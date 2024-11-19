#!/bin/bash

#set -e
source common.sh
source rds.properties
source oms.properties


if [[ -z $OUTPUT_DIR ]]; then
    if [[ -z $AWS_SCRIPTS_PATH_OUTPUT_DIRECTORY ]]; then
        export OUTPUT_DIR="/opt/oms/scriptoutput"
    else
        export OUTPUT_DIR=$AWS_SCRIPTS_PATH_OUTPUT_DIRECTORY
    fi
fi
export OUTPUT_FILE="oms-script-output-$(date -u +'%Y-%m-%d-%H%M%S').log"
log-info "Script started"


# Check required parameters
if [[ -z $IBM_ENTITLEMENT_KEY ]]; then log-error "IBM_ENTITLEMENT_KEY not defined"; exit 1; fi
if [[ -z $ADMIN_PASSWORD ]]; then log-error "ADMIN_PASSWORD not defined"; exit 1; fi
#if [[ -z $RDS_HOST ]]; then log-error "RDS_HOST not defined"; exit 1; fi
#if [[ -z $TRUSTSTORE_PASSWORD ]]; then log-error "TRUSTSTORE_PASSWORD not defined"; exit 1; fi
if [[ -z $DOMAIN_NAME ]]; then log-error "DOMAIN_NAME is not defined"; fi



if [[ -z $TMP_DIR ]]; then TMP_DIR="$(pwd)"; fi
if [[ -z $WORKSPACE_DIR ]]; then WORKSPACE_DIR="$TMP_DIR"; fi
if [[ -z $BIN_DIR ]]; then BIN_DIR="/usr/local/bin"; fi
if [[ -z $OMS_CATALOG ]]; then OMS_CATALOG="cp.icr.io/cpopen/ibm-oms-ent-case-catalog:v1.0.13-10.0.2403.0"; fi
if [[ -z $OPERATOR_NAMESPACE ]]; then OPERATOR_NAMESPACE="ibm-operators"; fi
if [[ -z $OPERATOR_CHANNEL ]]; then OPERATOR_CHANNEL="1.0"; fi
if [[ -z $VERSION ]]; then VERSION="10.0.2403.0"; fi
if [[ -z $SUBSCRIPTION_NAME ]]; then SUBSCRIPTION_NAME="oms-subscription"; fi
if [[ -z $OMS_NAMESPACE ]]; then OMS_NAMESPACE="oms"; fi
if [[ -z $OMS_INSTANCE_NAME ]]; then OMS_INSTANCE_NAME="oms"; fi
if [[ -z $SC_NAME ]]; then SC_NAME="efs-sc"; fi
if [[ -z $PVC_NAME ]]; then PVC_NAME="oms-pvc"; fi
if [[ -z $LICENSE ]]; then LICENSE="decline"; fi
if [[ -z $CERT_MANAGER_VERSION ]]; then CERT_MANAGER_VERSION="v1.14.3"; fi
if [[ -z $PVC_SIZE ]]; then PVC_SIZE="100Gi"; fi
if [[ -z $PSQL_POD_NAME ]]; then export PSQL_POD_NAME="psql-client"; fi
if [[ -z $PSQL_IMAGE ]]; then export PSQL_IMAGE="postgres:13"; fi
if [[ -z $DB_NAME ]]; then export DB_NAME="oms"; fi
if [[ -z $SCHEMA_NAME ]]; then export SCHEMA_NAME="oms"; fi
if [[ -z $ADMIN_USER ]]; then ADMIN_USER="admin"; fi
if [[ -z $PROFESSIONAL_REPO ]]; then PROFESSIONAL_REPO="cp.icr.io/cp/ibm-oms-professional"; fi
if [[ -z $ENTERPRISE_REPO ]]; then ENTERPRISE_REPO="cp.icr.io/cp/ibm-oms-enterprise"; fi
if [[ -z $HELM_URL ]]; then HELM_URL="https://get.helm.sh/helm-v3.14.3-linux-amd64.tar.gz"; fi



# Default secrets
if [[ -z $CONSOLEADMINPW ]]; then export CONSOLEADMINPW="$ADMIN_PASSWORD"; fi
if [[ -z $CONSOLENONADMINPW ]]; then export CONSOLENONADMINPW="$ADMIN_PASSWORD"; fi
if [[ -z $DBPASSWORD ]]; then export DBPASSWORD="$ADMIN_PASSWORD"; fi
if [[ -z $TLSSTOREPW ]]; then export TLSSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $TRUSTSTOREPW ]]; then export TRUSTSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $KEYSTOREPW ]]; then export KEYSTOREPW="$ADMIN_PASSWORD"; fi
if [[ -z $CASSANDRA_USERNAME ]]; then export CASSANDRA_USERNAME="admin"; fi
if [[ -z $CASSANDRA_PASSWORD ]]; then export CASSANDRA_PASSWORD="$ADMIN_PASSWORD"; fi
if [[ -z $ES_USERNAME ]]; then export ES_USERNAME="admin"; fi
if [[ -z $ES_PASSWORD ]]; then export ES_PASSWORD="$ADMIN_PASSWORD"; fi


# Set edition specific parameters
if [[ ${OMS_CATALOG} == *"-pro-"* ]]; then
    export EDITION="Professional"
    export OPERATOR_NAME="ibm-oms-pro"
    export OPERATOR_CSV="ibm-oms-pro.v${OPERATOR_CHANNEL}"
    export CATALOG_NAME="ibm-oms-pro-catalog"
    export REPOSITORY="${PROFESSIONAL_REPO}"
    export TAG="${VERSION}-amd64"
else
    export EDITION="Enterprise"
    export OPERATOR_NAME="ibm-oms-ent"
    export OPERATOR_CSV="ibm-oms-ent.v${OPERATOR_CHANNEL}"
    export CATALOG_NAME="ibm-oms-ent-catalog"
    export REPOSITORY="${ENTERPRISE_REPO}"
    export TAG="${VERSION}-amd64"
fi



##Debug purpose
echo "OMS_INSTANCE_NAME: ${OMS_INSTANCE_NAME}"
echo "OMS_NAMESPACE: ${OMS_NAMESPACE}"
echo "HOSTNAME: ${HOSTNAME}"
echo "RDS_HOST: ${RDS_HOST}"
echo "DB_NAME: ${DB_NAME}"
echo "SCHEMA_NAME: ${SCHEMA_NAME}"
echo "MASTER_USERNAME: ${MASTER_USERNAME}"
echo "SC_NAME: ${SC_NAME}"
echo "VERSION: ${VERSION}"
echo "TAG: ${TAG}"
echo "REPOSITORY: ${REPOSITORY}"



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


# Install the operatorSDK if not already
if [[ -z $(which operator-sdk) ]]; then
    log-info "Installing the Operator-SDK CLI tool"
    export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    export OS=$(uname | awk '{print tolower($0)}')
    export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.32.0

    curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}

    if [[ $(whoami) == "root" ]]; then
        chmod +x operator-sdk_${OS}_${ARCH} && mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    else
        chmod +x operator-sdk_${OS}_${ARCH} && sudo mv operator-sdk_${OS}_${ARCH} ${BIN_DIR}/operator-sdk
    fi
else
    log-info "The Operator-SDK CLI tool is already installed"
fi


# Install the helm cli
if [[ -z $(which helm) ]]; then
    # Check if Helm URL is reachable
    curl --head --silent --fail "$HELM_URL" > /dev/null
    if (( $? != 0 )); then
        log-error "Unable to locate Helm CLI at $HELM_URL"
        exit 1
    else
        log-info "Downloading the Helm CLI"
        curl --silent --output "${TMP_DIR}/helm.tgz" "$HELM_URL"

        # Extract the downloaded file
        tar xaf "${TMP_DIR}/helm.tgz" -C "${TMP_DIR}"
        if (( $? != 0 )); then
            log-error "Unable to untar file ${TMP_DIR}/helm.tgz"
            exit 1
        fi
        
        # Move helm to bin directory
        mv "${TMP_DIR}/linux-amd64/helm" "${BIN_DIR}/helm"
        if (( $? != 0 )); then
            log-error "Unable to copy helm to bin directory"
            exit 1
        else
            log-info "Successfully installed helm"
        fi
    fi
else
    log-info "Helm CLI already installed"
fi


# Log into the EKS cluster
if [[ -z $AWS_PROFILE ]]; then
  log-info "AWS profile not set, using default profile"
fi

log-info "Logging into EKS Cluster ${EKS_CLUSTER_NAME} in region ${AWS_REGION}"
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME



# Add OLM to the cluster
if ! kubectl get pods -n olm | grep -q olm-operator; then
    log-info "Installing OperatorSDK OLM"
    operator-sdk olm install
else
    log-info "OperatorSDK OLM already installed"
fi



# Add OLM to the cluster
#kubectl get pods -n olm | grep olm-operator 2>&1
#if (( $? != 0 )); then
#    log-info "Installing OperatorSDK OLM"
#    operator-sdk olm install
#else
#    log-info "OperatorSDK OLM already installed"
#fi



# Create the operator namespace
if [[ -z $(kubectl get ns ${OPERATOR_NAMESPACE} 2> /dev/null ) ]]; then
    log-info "Creating namespace ${OPERATOR_NAMESPACE}"
    kubectl create namespace ${OPERATOR_NAMESPACE}
    if (( $? != 0 )); then
        log-error "Unable to create namespace $OPERATOR_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $OPERATOR_NAMESPACE"
    fi
else
    log-info "Namespace ${OPERATOR_NAMESPACE} already exists"
fi

# Create the OMS catalog source
if [[ -z $(kubectl get catalogsource -n ${OPERATOR_NAMESPACE} ${CATALOG_NAME} 2> /dev/null) ]]; then
    log-info "Creating Catalog Source for ${CATALOG_NAME}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${CATALOG_NAME}
  namespace: ${OPERATOR_NAMESPACE}
spec:
  displayName: IBM OMS Operator Catalog
  image: '${OMS_CATALOG}'
  publisher: IBM
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 10m0s
EOF
    if (( $? != 0 )); then
        log-error "Unable to create catalog source for ${CATALOG_NAME}"
        exit 1
    else
        log-info "Created catalog source for ${CATALOG_NAME}"
    fi
else
    log-info "Catalog source for ${CATALOG_NAME} already exists"
fi


# Wait for catalog source to be ready
wait_for_catalog ${OPERATOR_NAMESPACE} ${CATALOG_NAME} 15
log-info "Catalog source ${CATALOG_NAME} in namespace ${OPERATOR_NAMESPACE} is ready"


# Create the operator group
if [[ -z $(kubectl get operatorgroup -n ${OPERATOR_NAMESPACE} oms-operator-global 2> /dev/null) ]]; then
    log-info "Creating operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
 name: oms-operator-global
 namespace: ${OPERATOR_NAMESPACE}
spec: {}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created operator group oms-operator-global in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Operator group oms-operator-global already exists in namespace ${OPERATOR_NAMESPACE}"
fi



# Create the OMS operator
if [[ -z $(kubectl get subscription -n ${OPERATOR_NAMESPACE} ${SUBSCRIPTION_NAME} 2> /dev/null) ]]; then
    log-info "Creating subscription ${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
    cat << EOF | kubectl create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${SUBSCRIPTION_NAME}
  namespace: ${OPERATOR_NAMESPACE}
spec:
  channel: v${OPERATOR_CHANNEL}
  installPlanApproval: Automatic
  name: ${OPERATOR_NAME}
  source: ${CATALOG_NAME}
  sourceNamespace: ${OPERATOR_NAMESPACE}
EOF
    if (( $? != 0 )); then
        log-error "Unable to create subscription ${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
        exit 1
    else
        log-info "Created subscription${SUBSCRIPTION_NAME} in namespace ${OPERATOR_NAMESPACE}"
    fi
else
    log-info "Subscription ${SUBSCRIPTION_NAME} already exists in namespace ${OPERATOR_NAMESPACE}"
fi


# Wait for operator to be ready
wait_for_subscription ${OPERATOR_NAMESPACE} ${SUBSCRIPTION_NAME}
log-info "${SUBSCRIPTION_NAME} subscription ready"

# Create the operand namespace
if [[ -z $(kubectl get namespace ${OMS_NAMESPACE} 2> /dev/null) ]]; then
    log-info "Creating namespace ${OMS_NAMESPACE}"
    kubectl create namespace $OMS_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create namespace $OMS_NAMESPACE"
        exit 1
    else
        log-info "Successfully created namespace $OMS_NAMESPACE"
    fi
else
    log-info "Namespace $OMS_NAMESPACE already exists"
fi

# Create the certificate manager CRD
if [[ -z $(kubectl get crd certificates.cert-manager.io 2> /dev/null) ]]; then
    log-info "Installing the certificate manager operator"
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml
    if (( $? != 0 )); then
        log-error "Unable to install certificate manager operator"
        exit 1
    else
        while [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager " | grep "1/1") ]] \
            && [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager-cainjector" | grep "1/1") ]] \
            && [[ -z $(kubectl get deployments -n cert-manager | grep "cert-manager-webhook" | grep "1/1") ]]; do
            log-info "Waiting for certificate manager to initialize"
            i=$(( $i + 1))
            if (( $i > 10 )); then
                log-error "Timeout waiting for certificate manager to initialize"
                exit 1
            fi
            sleep 30
        done
        log-info "Certificate manager installed and running"
    fi
else
    log-info "Certificate Manager custom resource definition already exists"
fi

# Create the image pull secrets
if [[ -z $(kubectl get secrets -n $OMS_NAMESPACE | grep ibm-entitlement-key) ]]; then
    log-info "Creating image pull secret ibm-entitlement-key in namespace $OMS_NAMESPACE"
    kubectl create secret docker-registry ibm-entitlement-key --docker-server=cp.icr.io --docker-username=cp --docker-password=$IBM_ENTITLEMENT_KEY -n $OMS_NAMESPACE
    if (( $? != 0 )); then
        log-error "Unable to create image pull secret for ibm-entitlement-key in namespace $OMS_NAMESPACE"
        exit 1
    else
        log-info "Created image pull secret for ibm-entitlement-key in namespace $OMS_NAMESPACE"
    fi
else
    log-info "Image pull secret for ibm-entitlement-key already exists in namespace $OMS_NAMESPACE"
fi



# Create OMS secret with default passwords
if [[ -z $(kubectl get secrets -n $OMS_NAMESPACE oms-secret 2> /dev/null) ]]; then
    log-info "Creating OMS Secret"
    cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
   name: oms-secret
   namespace: $OMS_NAMESPACE
type: Opaque
stringData:
  consoleAdminPassword: $CONSOLEADMINPW
  consoleNonAdminPassword: $CONSOLENONADMINPW
  dbPassword: $DBPASSWORD
  tlskeystorepassword: $TLSSTOREPW
  trustStorePassword: $TRUSTSTOREPW
  keyStorePassword: $KEYSTOREPW
  cassandra_username: $CASSANDRA_USERNAME
  cassandra_password: $CASSANDRA_PASSWORD
  es_username: $ES_USERNAME
  es_password: $ES_PASSWORD
EOF
    if (( $? == 0 )) ; then
        log-info "Successfully created OMS secret"
    else
        log-error "Unable to create OMS secret"
        exit 1
    fi
else
    log-info "OMS Secret already exists"
fi


# Create the nginx ingress controller
if ! helm status ingress-nginx --namespace ingress-nginx > /dev/null 2>&1; then
    log-info "Installing NGINX ingress controller"
    helm upgrade --install ingress-nginx ingress-nginx \
        --repo https://kubernetes.github.io/ingress-nginx \
        --namespace ingress-nginx --create-namespace
    if (( $? != 0 )); then
        log-error "Unable to install ingress controller"
        exit 1
    else
        log-info "Successfully installed ingress controller"
    fi
else
    log-info "NGINX ingress controller already deployed"
fi




# Add the Helm repository for the AWS EFS CSI driver if not already added
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# Check if the AWS EBS CSI driver is already installed
if [[ -z $(helm list --namespace kube-system | grep aws-efs-csi-driver) ]]; then
    # Install the AWS EFS CSI driver
    helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver  --namespace kube-system

    if (( $? != 0 )); then
        log-error "Unable to install AWS EFS CSI driver"
        exit 1
    else
        log-info "Successfully installed AWS EFS CSI driver"
    fi
else
    log-info "AWS EFS CSI driver already deployed"
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


# Deploy OMS instance
if [[ -z $(kubectl get omenvironment -n $OMS_NAMESPACE $OMS_INSTANCE_NAME 2> /dev/null) ]]; then
    if [[ $LICENSE == "accept" ]]; then

    HOSTNAME="oms-service-${OMS_NAMESPACE}.${DOMAIN_NAME}"

        # Create the persistant volume
        if [[ -z $(kubectl get pvc -n $OMS_NAMESPACE $PVC_NAME 2> /dev/null) ]]; then
            log-info "Creating the persistent volume $PVC_NAME in namespace $OMS_NAMESPACE"
            cat << EOF | kubectl create -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: $PVC_NAME
  namespace: $OMS_NAMESPACE
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $SC_NAME
EOF
            if (( $? != 0 )); then
                log-error "Unable to create PVC $PVC_NAME in namespace $OMS_NAMESPACE"
                exit 1
            else
                log-info "Created PVC $PVC_NAME in namespace $OMS_NAMESPACE"
            fi

            log-info "Running job to mount volume and force PV creation"
            # Remove any existing job
            if [[ $(kubectl get jobs -n $OMS_NAMESPACE volume-pod 2> /dev/null ) ]]; then
                log-info "Deleting existing volume-pod job in namespace $OMS_NAMESPACE"
                kubectl delete job -n $OMS_NAMESPACE volume-pod
                if (( $? != 0 )); then
                    log-error "Unable to delete volume-pod job in namespace $OMS_NAMESPACE"
                    exit 1
                else
                    log-info "Deleted volume-pod job in namespace $OMS_NAMESPACE"
                fi
            fi
            cat << EOF | kubectl create -f -
kind: Job
apiVersion: batch/v1
metadata:
  name: volume-pod
  namespace: $OMS_NAMESPACE
spec:
  template:
    spec:
      volumes:
        - name: sip-volume
          persistentVolumeClaim:
            claimName: $PVC_NAME
      containers:
        - name: nginx
          image: nginx:latest
          command: [ "/bin/bash", "-c", "--" ]
          args: [ "echo done" ]
          volumeMounts:
            - name: sip-volume
              mountPath: /mnt
      restartPolicy: OnFailure
  backoffLimit: 4
EOF
            if (( $? != 0 )); then
                log-error "Unable to create batch job to mount volume"
                exit 1
            else
                while [[ -z $(kubectl get job volume-pod -n $OMS_NAMESPACE | grep "1/1") ]]; do
                    log-info "Waiting for volume-pod job in namespace $OMS_NAMESPACE to complete"
                    i=$(( $i + 1 ))
                    if (( $i > 10 )); then
                        log-error "Timeout waiting for volume-pod job in namespace $OMS_NAMESPACE to complete"
                        exit 1
                    fi
                    sleep 30
                done
                log-info "Job volume-pod completed in namespace $OMS_NAMESPACE"
            fi
        else
            log-info "PVC $PVC_NAME already exists in namespace $OMS_NAMESPACE"
        fi

        log-info "Creating OMS instance in namespace $OMS_NAMESPACE"
        cat << EOF | kubectl apply -f -
apiVersion: apps.oms.ibm.com/v1beta1
kind: OMEnvironment
metadata:
  name: ${OMS_INSTANCE_NAME}
  namespace: ${OMS_NAMESPACE}
  annotations:
    apps.oms.ibm.com/activemq-install-driver: 'yes'
    apps.oms.ibm.com/activemq-driver-url: "https://repo1.maven.org/maven2/org/apache/activemq/activemq-all/5.16.0/activemq-all-5.16.0.jar"
spec:
  license:
    accept: true
    acceptCallCenterStore: true
  common:
    ingress:
      host: "${HOSTNAME}"
      ssl:
        enabled: false
  callCenter:
    bindingAppServerName: smcfs
    base:
      replicaCount: 1
      profile: ProfileMedium
    extn:
      replicaCount: 1
      profile: ProfileMedium
  database:
    db2:
      dataSourceName: jdbc/OMDS
      host: ${DB_HOST}
      name: ${DB_NAME}
      port: ${DB_PORT}
      schema: ${DB_SCHEMA}
      secure: false
      user: ${DB_USERNAME}
      password: ${DB_PASSWORD}
  dataManagement:
    mode: create
  storage:
    name: oms-pvc
  secret: oms-secret
  healthMonitor:
    profile: ProfileSmall
    replicaCount: 1
  orderHub:
    bindingAppServerName: smcfs
    base:
      profile: ProfileSmall
      replicaCount: 1
    extn:
      profile: ProfileSmall
      replicaCount: 1
  orderService:
    cassandra:
      createDevInstance:
        profile: ProfileColossal
        storage:
          accessMode: ReadWriteMany
          capacity: 20Gi
          name: oms-pvc-ordserv
          storageClassName: ${SC_NAME}
      keyspace: cassandra_keyspace
    configuration:
      additionalConfig:
        enable_graphql_introspection: 'true'
        log_level: DEBUG
        order_archive_additional_part_name: ordRel
        service_auth_disable: 'true'
        ssl_vertx_disable: 'false'
      jwt_ignore_expiration: false
    elasticsearch:
      createDevInstance:
        profile: ProfileLarge
    orderServiceVersion: ${VERSION}
    profile: ProfileLarge
    replicaCount: 1
  image:
    oms:
      tag: ${TAG}
      repository: ${REPOSITORY}
    orderHub:
      base:
        tag: ${TAG}
        repository: ${REPOSITORY}
      extn:
        tag: ${TAG}
        repository: ${REPOSITORY}
    orderService:
      imageName: orderservice
      repository: ${REPOSITORY}
      tag: ${TAG}
    callCenter:
      base:
        repository: ${REPOSITORY}
        tag: ${TAG}
      extn:
        repository: ${REPOSITORY}
        tag: ${TAG}
    imagePullSecrets:
      - name: ibm-entitlement-key
  networkPolicy:
    ingress: []
    podSelector:
      matchLabels:
        release: oms
        role: appserver
    policyTypes:
      - Ingress
  serverProfiles:
    - name: ProfileSmall
      resources:
        limits:
          cpu: 1000m
          memory: 1Gi
        requests:
          cpu: 200m
          memory: 512Mi
    - name: ProfileMedium
      resources:
        limits:
          cpu: 2000m
          memory: 2Gi
        requests:
          cpu: 500m
          memory: 1Gi
    - name: ProfileLarge
      resources:
        limits:
          cpu: 4000m
          memory: 4Gi
        requests:
          cpu: 500m
          memory: 2Gi
    - name: ProfileHuge
      resources:
        limits:
          cpu: 4000m
          memory: 8Gi
        requests:
          cpu: 500m
          memory: 4Gi
    - name: ProfileColossal
      resources:
        limits:
          cpu: 4000m
          memory: 16Gi
        requests:
          cpu: 500m
          memory: 4Gi
  servers:
    - name: smcfs
      replicaCount: 1
      profile: ProfileHuge
      appServer:
        dataSource:
          minPoolSize: 10
          maxPoolSize: 25
        ingress:
          contextRoots: [smcfs, sbc, sma, isccs, wsc, isf, icc]
        threads:
          min: 10
          max: 25
        vendor: websphere
  serviceAccount: default
  upgradeStrategy: RollingUpdate
  serverProperties:
    customerOverrides:
        - groupName: BaseProperties
          propertyList:
            yfs.yfs.ssi.enabled: N
            yfs.api.security.enabled: Y
            yfs.api.security.token.enabled: Y


EOF
        if (( $? != 0 )); then
            log-error "Unable to create OMS instance ${OMS_INSTANCE_NAME} in namespace $OMS_NAMESPACE"
            exit 1
        else
            # Wait for instance to finish creation            #######TODO

            ###########
            log-info "Successfully created OMS instance ${OMS_INSTANCE_NAME} in namespace $OMS_NAMESPACE"
        fi

        # Wait for instance to be created
        count=0
        while [[ $(kubectl get OMEnvironment -n ${OMS_NAMESPACE} ${OMS_INSTANCE_NAME} -o json | jq -r '.status.conditions[] | select(.type=="OMEnvironmentAvailable").status') != "True" ]]; do
            current_status=$(kubectl get OMEnvironment -n ${OMS_NAMESPACE} ${OMS_INSTANCE_NAME} -o json | jq -r '.status.conditions[].reason')
            log-info "Waiting for OMEnvironment instance to be ready. Status = $current_status"
            log-info "Info: Waited $count minutes. Will wait up to 90 minutes. "
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 90)); then    # Timeout set to 90 minutes
                log-error "Timout waiting for ${OMS_INSTANCE_NAME} to be ready"
                exit 1
            fi
        done

        # Sleep to allow pods to finish starting up
        log-info "Sleeping for 3 minutes to allow pods to finish starting"
        sleep 180


    else
        log-info "License not accepted. Instance not created"
    fi
else
    log-info "OMS instance ${OMS_INSTANCE_NAME} already exists in namespace $OMS_NAMESPACE"
fi


log-info "Script completed"
echo $env
