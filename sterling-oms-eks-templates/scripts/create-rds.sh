#!/bin/bash
source rds.properties


# Variables
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Retrieve VPC ID and Subnet IDs from the EKS cluster
echo "Retrieving VPC ID and Subnet IDs from the EKS cluster..."
VPC_ID=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --query "cluster.resourcesVpcConfig.vpcId" --output text)
if [ -z "$VPC_ID" ]; then
    echo "Failed to retrieve VPC ID. Exiting..."
    exit 1
fi

SUBNET_IDS=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --query "cluster.resourcesVpcConfig.subnetIds" --output text)
if [ -z "$SUBNET_IDS" ]; then
    echo "Failed to retrieve Subnet IDs. Exiting..."
    exit 1
fi

# Retrieve Security Group ID of EKS nodes
echo "Retrieving Security Group ID for EKS nodes..."
EKS_SECURITY_GROUP=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --query "cluster.resourcesVpcConfig.securityGroupIds[0]" --output text)
if [ -z "$EKS_SECURITY_GROUP" ]; then
    echo "Failed to retrieve Security Group ID for EKS nodes. Exiting..."
    exit 1
fi

# Check if RDS instance already exists
echo "Checking if RDS instance ${RDS_INSTANCE_IDENTIFIER} already exists..."
if aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE_IDENTIFIER} > /dev/null 2>&1; then
    echo "RDS instance ${RDS_INSTANCE_IDENTIFIER} already exists. Exiting..."
    exit 0
fi

# Check if Security Group for RDS already exists
echo "Checking if Security Group ${RDS_SECURITY_GROUP_NAME} already exists..."
RDS_SECURITY_GROUP=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${RDS_SECURITY_GROUP_NAME} --query "SecurityGroups[0].GroupId" --output text)
if [ "$RDS_SECURITY_GROUP" == "None" ] || [ -z "$RDS_SECURITY_GROUP" ]; then
    # Create Security Group for RDS in the EKS VPC
    echo "Creating Security Group ${RDS_SECURITY_GROUP_NAME} for RDS..."
    RDS_SECURITY_GROUP=$(aws ec2 create-security-group --group-name ${RDS_SECURITY_GROUP_NAME} --description "RDS security group" --vpc-id ${VPC_ID} --query 'GroupId' --output text)
    if [ -z "$RDS_SECURITY_GROUP" ]; then
        echo "Failed to create Security Group. Exiting..."
        exit 1
    fi

    # Add tags to the Security Group
    echo "Tagging Security Group ${RDS_SECURITY_GROUP_NAME}..."
    aws ec2 create-tags --resources ${RDS_SECURITY_GROUP} --tags ${TAGS}
    if [ $? -ne 0 ]; then
        echo "Failed to tag Security Group. Exiting..."
        exit 1
    fi

    # Authorize inbound traffic on port 5432 (PostgreSQL default port)
    echo "Authorizing inbound traffic on port 5432 for Security Group ${RDS_SECURITY_GROUP_NAME}..."
    aws ec2 authorize-security-group-ingress --group-id ${RDS_SECURITY_GROUP} --protocol tcp --port 5432 --source-group ${EKS_SECURITY_GROUP}
    if [ $? -ne 0 ]; then
        echo "Failed to authorize inbound traffic. Exiting..."
        exit 1
    fi
else
    echo "Security Group ${RDS_SECURITY_GROUP_NAME} already exists."
fi

# Check if Subnet Group already exists
echo "Checking if DB Subnet Group ${DB_SUBNET_GROUP_NAME} already exists..."
if aws rds describe-db-subnet-groups --db-subnet-group-name ${DB_SUBNET_GROUP_NAME} > /dev/null 2>&1; then
    echo "DB Subnet Group ${DB_SUBNET_GROUP_NAME} already exists."

else
    # Create Subnet Group for RDS using the EKS Subnets
    echo "Creating Subnet Group ${DB_SUBNET_GROUP_NAME} for RDS..."
    aws rds create-db-subnet-group \
        --db-subnet-group-name ${DB_SUBNET_GROUP_NAME} \
        --db-subnet-group-description "RDS Subnet Group" \
        --subnet-ids ${SUBNET_IDS}
    echo "Subnet group ${DB_SUBNET_GROUP_NAME} for RDS is created"
    if [ $? -ne 0 ]; then
        echo "Failed to create DB Subnet Group. Exiting..."
        exit 1
    fi


fi

echo "RDS_INSTANCE_IDENTIFIER=${RDS_INSTANCE_IDENTIFIER},MASTER_USERNAME=${MASTER_USERNAME}, MASTER_PASSWORD=${MASTER_PASSWORD}, RDS_SECURITY_GROUP=${RDS_SECURITY_GROUP},DB_SUBNET_GROUP_NAME=${DB_SUBNET_GROUP_NAME}, ENGINE_VERSION=${ENGINE_VERSION}"

# Create the RDS instance
echo "Creating RDS instance ${RDS_INSTANCE_IDENTIFIER}..."
aws rds create-db-instance \
    --db-instance-identifier ${RDS_INSTANCE_IDENTIFIER} \
    --db-instance-class db.t3.medium \
    --engine postgres \
    --allocated-storage 50 \
    --master-username ${MASTER_USERNAME} \
    --master-user-password ${MASTER_PASSWORD} \
    --vpc-security-group-ids ${RDS_SECURITY_GROUP} \
    --db-subnet-group-name ${DB_SUBNET_GROUP_NAME} \
    --backup-retention-period 7 \
    --multi-az \
    --storage-type gp2 \
    --no-auto-minor-version-upgrade \
    --engine-version ${ENGINE_VERSION} \
    --storage-encrypted

if [ $? -ne 0 ]; then
    echo "Failed to create RDS instance. Exiting..."
    exit 1
fi


# Wait until the RDS instance is available
echo "Waiting for the RDS instance to become available..."
aws rds wait db-instance-available --db-instance-identifier ${RDS_INSTANCE_IDENTIFIER}

if [ $? -ne 0 ]; then
    echo "Error: RDS instance ${RDS_INSTANCE_IDENTIFIER} is not available. Exiting..."
    exit 1
fi

echo "RDS instance ${RDS_INSTANCE_IDENTIFIER} is now available."

# Get the RDS security group ID to update it to enable traffic from the EKS node group on port 5432
RDS_SG_ID=$(aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_IDENTIFIER" --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)

if [ -z "$RDS_SG_ID" ]; then
    echo "ERROR: Unable to retrieve the RDS security group ID."
    exit 1
fi

echo "INFO: Retrieved RDS security group ID: $RDS_SG_ID"

# Get the security group ID associated with the EKS worker nodes
EKS_NODE_SG_ID=$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)

if [ -z "$EKS_NODE_SG_ID" ]; then
    echo "ERROR: Unable to retrieve the EKS node security group ID."
    exit 1
fi

echo "INFO: Retrieved EKS node security group ID: $EKS_NODE_SG_ID"

# Add inbound rule to RDS security group to allow traffic from EKS security group
echo "INFO: Adding inbound rule to allow traffic on port 5432 from EKS node security group..."
aws ec2 authorize-security-group-ingress \
    --group-id "$RDS_SG_ID" \
    --protocol tcp \
    --port 5432 \
    --source-group "$EKS_NODE_SG_ID"

if [ $? -eq 0 ]; then
    echo "INFO: Successfully added inbound rule to RDS security group."
else
    echo "ERROR: Failed to add inbound rule to RDS security group."
    exit 1
fi

# Verification
echo "INFO: Verifying the new inbound rule..."
aws ec2 describe-security-groups --group-ids "$RDS_SG_ID" --query "SecurityGroups[0].IpPermissions" --output json


# Retrieve the RDS endpoint
echo "Retrieving RDS endpoint..."
RDS_HOST=$(aws rds describe-db-instances --db-instance-identifier ${RDS_INSTANCE_IDENTIFIER} --query "DBInstances[0].Endpoint.Address" --output text)
if [ -z "$RDS_HOST" ]; then
    echo "Failed to retrieve RDS endpoint. Exiting..."
    exit 1
fi

echo "RDS host is ${RDS_HOST}"
echo "Updating RDS host in the rds.properties file"
echo "export RDS_HOST="$RDS_HOST >> ./rds.properties
echo $env
