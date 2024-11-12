#!/bin/bash

function log-output() {
    MSG=${1}

    if [[ -z $OUTPUT_DIR ]]; then
        OUTPUT_DIR="/opt/oms/ocp/ocpscriptoutput"
    fi
    mkdir -p $OUTPUT_DIR

    if [[ -z $OUTPUT_FILE ]]; then
        OUTPUT_FILE="script-output.log"
    fi

    echo "$(date -u +"%Y-%m-%d %T") ${MSG}" >> ${OUTPUT_DIR}/${OUTPUT_FILE}
    echo ${MSG}
}

function log-info() {
    MSG=${1}
    log-output "INFO: $MSG"
}

function log-error() {
    MSG=${1}
    log-output "ERROR: $MSG"
    echo $MSG >&2
}

function oc-login() {
    API_SERVER=${1}
    TOKEN=${2}
    CA_CERT_PATH=${3}
    BIN_DIR=${4:-"/usr/local/bin"}

    if [[ -z $API_SERVER ]] || [[ -z $TOKEN ]] ; then
        log-error "Incorrect usage. Supply API server and token"
        exit 1
    fi

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-info "Logging into OpenShift cluster at $API_SERVER"

        count=0
        while ! ${BIN_DIR}/oc login --server=$API_SERVER --token=$TOKEN > /dev/null 2>&1; do
            log-info "Waiting to log into cluster. Waited $count minutes. Will wait up to 15 minutes."
            sleep 60
            count=$(( $count + 1 ))
            if (( $count > 15 )); then
                log-error "Timeout waiting to log into cluster"
                exit 1
            fi
        done
        log-info "Successfully logged into cluster"
    else
        log-info "Already logged into cluster."
    fi
}

function cli-download() {
    BIN_DIR=${1:-"/usr/local/bin"}
    TMP_DIR=${2:-"/tmp"}
    OC_VERSION=${3:-"stable-4.12"}

    log-info "Downloading and installing oc and kubectl"
    curl -sLo $TMP_DIR/openshift-client.tgz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OC_VERSION/openshift-client-linux.tar.gz

    if ! tar xzf ${TMP_DIR}/openshift-client.tgz -C ${TMP_DIR} oc kubectl ; then
        log-error "Unable to extract oc or kubectl from tar file"
        exit 1
    fi

    if ! mv ${TMP_DIR}/oc ${BIN_DIR}/oc ; then
        log-error "Unable to move oc to $BIN_DIR"
        exit 1
    fi

    if ! mv ${TMP_DIR}/kubectl ${BIN_DIR}/kubectl ; then
        log-error "Unable to move kubectl to $BIN_DIR"
        exit 1
    fi
}

function reset-output() {
    OUTPUT_DIR=${OUTPUT_DIR:-"/mnt/azscripts/azscriptoutput"}
    OUTPUT_FILE=${OUTPUT_FILE:-"script-output.log"}

    if [[ -f ${OUTPUT_DIR}/${OUTPUT_FILE} ]]; then
        cp ${OUTPUT_DIR}/${OUTPUT_FILE} ${OUTPUT_DIR}/${OUTPUT_FILE}-$(date -u +"%Y%m%d-%H%M%S").log
        rm ${OUTPUT_DIR}/${OUTPUT_FILE}
    fi
}

function wait_for_cluster_operators() {
    BIN_DIR=${1:-"/usr/local/bin"}

    log-info "Checking for cluster operator status"

    if ! ${BIN_DIR}/oc status 1> /dev/null 2> /dev/null; then
        log-error "Not logged into OpenShift cluster. Please log in first."
        exit 1
    fi

    count=0
    while ${BIN_DIR}/oc get clusteroperators | awk '{print $4}' | grep -q True; do
        log-info "Waiting on cluster operators to be available. Waited $count minutes. Will wait up to 30 minutes."
        sleep 60
        count=$(( $count + 1 ))
        if (( $count > 30 )); then
            log-error "Timeout waiting for cluster operators to be available"
            exit 1
        fi
    done
    log-info "Cluster operators are ready"
}


function cleanup_file() {
    FILE=${1}

    if [[ -f $FILE ]]; then
        rm $FILE
    fi
}

function catalog_status() {
    # Gets the status of a catalogsource
    # Usage:
    #      catalog_status CATALOG

    CATALOG=${1}

    CAT_STATUS="$(${BIN_DIR}/oc get catalogsource -n openshift-marketplace $CATALOG -o json | jq -r '.status.connectionState.lastObservedState')"
    echo $CAT_STATUS
}

function wait_for_catalog() {
    # Waits for a catalog source to be ready
    # Usage:
    #      wait_for_catalog CATALOG [TIMEOUT]

    CATALOG=${1}
    # Set default timeout of 15 minutes
    if [[ -z ${2} ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${2}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(catalog_status $CATALOG) != "READY" ]]; do
        log-info "Waiting for catalog source $CATALOG to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for catalog source $CATALOG to be ready"
            exit 1
        fi
    done
}




function subscription_status() {
    SUB_NAMESPACE=${1}
    SUBSCRIPTION=${2}

    CSV=$(${BIN_DIR}/oc get subscription -n ${SUB_NAMESPACE} ${SUBSCRIPTION} -o json | jq -r '.status.currentCSV')
    if [[ "$CSV" == "null" ]]; then
        STATUS="PendingCSV"
    else
        STATUS=$(${BIN_DIR}/oc get csv -n ${SUB_NAMESPACE} ${CSV} -o json | jq -r '.status.phase')
    fi
    echo $STATUS
}

function wait_for_subscription() {
    SUB_NAMESPACE=${1}
    export SUBSCRIPTION=${2}

    # Set default timeout of 15 minutes
    if [[ -z ${3} ]]; then
        TIMEOUT=15
    else
        TIMEOUT=${3}
    fi

    export TIMEOUT_COUNT=$(( $TIMEOUT * 60 / 30 ))

    count=0;
    while [[ $(subscription_status $SUB_NAMESPACE $SUBSCRIPTION) != "Succeeded" ]]; do
        log-info "Waiting for subscription $SUBSCRIPTION to be ready. Waited $(( $count * 30 )) seconds. Will wait up to $(( $TIMEOUT_COUNT * 30 )) seconds."
        sleep 30
        count=$(( $count + 1 ))
        if (( $count > $TIMEOUT_COUNT )); then
            log-error "Timeout exceeded waiting for subscription $SUBSCRIPTION to be ready"
            exit 1
        fi
    done
}
