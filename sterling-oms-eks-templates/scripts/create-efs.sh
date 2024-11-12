#!/bin/bash
source efs.properties
source common.sh

# Retrieve the VPC ID from the EKS cluster
VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text --region $REGION)
if [[ -z "$VPC_ID" ]]; then
    log-error "Unable to retrieve VPC ID for EKS cluster $EKS_CLUSTER_NAME"
    exit 1
fi
log-info "Retrieved VPC ID: $VPC_ID"

# Check if the EFS file system already exists
EFS_FILE_SYSTEM_ID=$(aws efs describe-file-systems --query "FileSystems[?Name=='$EFS_FILE_SYSTEM_NAME'].FileSystemId" --output text --region $REGION)

if [[ -z "$EFS_FILE_SYSTEM_ID" || "$EFS_FILE_SYSTEM_ID" == "None" ]]; then
    # Create the EFS file system
    if [[ -n "$KMS_KEY_ID" ]]; then
        # Create EFS with custom KMS key for encryption
        EFS_FILE_SYSTEM_ID=$(aws efs create-file-system --creation-token $EFS_FILE_SYSTEM_NAME --performance-mode generalPurpose --encrypted --kms-key-id $KMS_KEY_ID --region $REGION --query "FileSystemId" --output text)
    else
        # Create EFS with default encryption
        EFS_FILE_SYSTEM_ID=$(aws efs create-file-system --creation-token $EFS_FILE_SYSTEM_NAME --performance-mode generalPurpose --encrypted --region $REGION --query "FileSystemId" --output text)
    fi

    # Check if creation failed due to file system already existing
    if [[ $? -ne 0 ]]; then
        # Retrieve the file system ID if creation failed due to existing file system
        EFS_FILE_SYSTEM_ID=$(aws efs describe-file-systems --query "FileSystems[?CreationToken=='$EFS_FILE_SYSTEM_NAME'].FileSystemId" --output text --region $REGION)
        if [[ -z "$EFS_FILE_SYSTEM_ID" || "$EFS_FILE_SYSTEM_ID" == "None" ]]; then
            log-error "Unable to create or find existing EFS file system"
            exit 1
        fi
    fi

    log-info "Using existing EFS file system with ID: $EFS_FILE_SYSTEM_ID"
else
    log-info "EFS file system already exists with ID: $EFS_FILE_SYSTEM_ID"
fi

# Tag the EFS file system
aws efs tag-resource --resource-id $EFS_FILE_SYSTEM_ID --tags Key=$TAG_KEY,Value=$TAG_VALUE Key=Name,Value=$EFS_FILE_SYSTEM_NAME --region $REGION
if [[ $? -ne 0 ]]; then
    log-error "Unable to tag EFS file system with ID $EFS_FILE_SYSTEM_ID"
    exit 1
fi
log-info "Tagged EFS file system with ID $EFS_FILE_SYSTEM_ID"

# Wait for the EFS file system to become available
MAX_ATTEMPTS=30
ATTEMPT=0
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    FILE_SYSTEM_STATE=$(aws efs describe-file-systems --file-system-id $EFS_FILE_SYSTEM_ID --region $REGION --query "FileSystems[*].LifeCycleState" --output text)
    if [[ "$FILE_SYSTEM_STATE" == "available" ]]; then
        log-info "EFS file system is available"
        break
    else
        log-info "Waiting for EFS file system to become available. Current state: $FILE_SYSTEM_STATE"
        sleep 10
        ((ATTEMPT++))
    fi
done

if [[ "$FILE_SYSTEM_STATE" != "available" ]]; then
    log-error "EFS file system did not become available in time"
    exit 1
fi

# Check if the mount targets already exist
MOUNT_TARGETS_EXIST=false
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text --region $REGION)
echo $SUBNET_IDS
for SUBNET_ID in $SUBNET_IDS; do
    echo selected $SUBNET_ID
    MOUNT_TARGET_ID=$(aws efs describe-mount-targets --file-system-id $EFS_FILE_SYSTEM_ID --query "MountTargets[?SubnetId=='$SUBNET_ID'].MountTargetId" --output text --region $REGION)
    echo checking mount target id: $MOUNT_TARGET_ID
    if [[ -n "$MOUNT_TARGET_ID" && "$MOUNT_TARGET_ID" != "None" ]]; then
        log-info "Mount target already exists in subnet $SUBNET_ID with ID: $MOUNT_TARGET_ID"
        MOUNT_TARGETS_EXIST=true
    fi
done

# Create mount targets if they don't already exist
if [[ "$MOUNT_TARGETS_EXIST" == false ]]; then
    for SUBNET_ID in $SUBNET_IDS; do
        aws efs create-mount-target --file-system-id $EFS_FILE_SYSTEM_ID --subnet-id $SUBNET_ID --region $REGION
        if [[ $? -ne 0 ]]; then
            log-error "Unable to create mount target in subnet $SUBNET_ID"
            exit 1
        fi
    done
    log-info "Created EFS mount targets in subnets: $SUBNET_IDS"
else
    log-info "EFS mount targets already exist in the VPC"
fi

## here write a code to allow port 2049 from all IP in EFS security group
# Get the mount targets for the given EFS file system ID
MOUNT_TARGET_ID=$(aws efs describe-mount-targets --file-system-id "$EFS_FILE_SYSTEM_ID" --query 'MountTargets[0].MountTargetId' --output text)

# Check if the command was successful
if [ $? -ne 0 ]; then
    echo "Failed to describe mount targets for file system ID: $EFS_FILE_SYSTEM_ID"
    exit 1
fi

# Retrieve the security group associated with the EFS
SECURITY_GROUP_ID=$(aws efs describe-mount-target-security-groups --mount-target-id "$MOUNT_TARGET_ID" --query 'SecurityGroups' --output text)

if [ "$SECURITY_GROUP_ID" == "None" ]; then
  echo "No security group found for EFS File System ID: $EFS_FILE_SYSTEM_ID"
  exit 1
fi

echo "Found Security Group ID: $SECURITY_GROUP_ID"

# Allow port 2049 (NFS) from all IPs (0.0.0.0/0)
echo "Adding rule to allow port 2049 from all IPs (0.0.0.0/0)..."
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 2049 --cidr 0.0.0.0/0

if [ $? -eq 0 ]; then
  echo "Successfully updated security group to allow port 2049."
else
  echo "Failed to update security group."
  exit 1
fi


# Install the kubectl CLI tools if not installed
if [[ -z $(which kubectl) ]]; then
    log-info "Installing kubectl CLI tool"

    curl -Lo kubectl https://dl.k8s.io/release/$(curl -L https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    if (( $? != 0 )); then
        log-error "Unable to install kubectl"
        exit 1
    fi
else
    log-info "kubectl CLI tool already installed"
fi

# EFS StorageClass
if [[ -z $(kubectl get storageclass $SC_NAME 2> /dev/null) ]]; then
    log-info "Creating the EFS StorageClass $SC_NAME"
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $SC_NAME
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $EFS_FILE_SYSTEM_ID
  directoryPerms: "700" # Adjust permissions as needed
  gidRangeStart: "1000" # Group ID range start
  gidRangeEnd: "2000" # Group ID range end
  basePath: "/"
reclaimPolicy: Retain
volumeBindingMode: Immediate
EOF

if [[ $? -ne 0 ]]; then
        log-error "Unable to create StorageClass $SC_NAME"
        exit 1
    fi
else
    log-info "StorageClass $SC_NAME already exists"
fi

echo "Adding EFS_ID variable to the oms.properties"
echo "export EFS_ID=${EFS_FILE_SYSTEM_ID}" >> oms.properties
echo $env
