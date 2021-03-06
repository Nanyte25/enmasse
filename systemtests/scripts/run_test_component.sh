#!/bin/bash
CURDIR=`readlink -f \`dirname $0\``
source ${CURDIR}/test_func.sh

ENMASSE_DIR=$1
KUBEADM=$2
TEST_PROFILE=${3}
TESTCASE=${4:-"io.enmasse.**"}

failure=0

SANITIZED_PROJECT=$OPENSHIFT_PROJECT
SANITIZED_PROJECT=${SANITIZED_PROJECT//_/-}
SANITIZED_PROJECT=${SANITIZED_PROJECT//\//-}
export OPENSHIFT_PROJECT=$SANITIZED_PROJECT

setup_test ${ENMASSE_DIR} ${KUBEADM}
if [ $? -ne 0 ]; then
    echo "DEPLOYMENT FAILED - tests won't be executed."
    exit 1
fi

#environment info before tests
LOG_DIR="${ARTIFACTS_DIR}/openshift-info/"
mkdir -p ${LOG_DIR}
get_kubernetes_info ${LOG_DIR} services default "-before"
get_kubernetes_info ${LOG_DIR} pods default "-before"

#start system resources logging
${CURDIR}/system-stats.sh > ${ARTIFACTS_DIR}/system-resources.log &
STATS_PID=$!
echo "process for checking system resources is running with PID: ${STATS_PID}"

#start docker logging
DOCKER_LOG_DIR="${ARTIFACTS_DIR}/docker-logs"
${CURDIR}/docker-logs.sh ${DOCKER_LOG_DIR} > /dev/null 2> /dev/null &
LOGS_PID=$!
echo "process for syncing docker logs is running with PID: ${LOGS_PID}"

#run tests
if [[ "${TEST_PROFILE}" = "systemtests-pr" ]]; then
    run_test ${TESTCASE} systemtests-shared-pr || failure=$(($failure + 1))
    run_test ${TESTCASE} systemtests-isolated-pr || failure=$(($failure + 1))
elif [[ "${TEST_PROFILE}" = "systemtests-marathon" ]]; then
    run_test ${TESTCASE} ${TEST_PROFILE} || failure=$(($failure + 1))
else
    run_test ${TESTCASE} systemtests-shared || failure=$(($failure + 1))
    run_test ${TESTCASE} systemtests-isolated || failure=$(($failure + 1))
fi

#stop system resources logging
echo "process for checking system resources with PID: ${STATS_PID} will be killed"
kill ${STATS_PID}

#stop docker logging
echo "process for syncing docker logs with PID: ${LOGS_PID} will be killed"
kill ${LOGS_PID}
categorize_dockerlogs "${DOCKER_LOG_DIR}"

if [ $failure -gt 0 ]
then
    echo "Systemtests failed"
    exit 1
else
    teardown_test ${OPENSHIFT_PROJECT}
fi
