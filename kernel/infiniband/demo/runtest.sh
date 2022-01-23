#!/bin/bash -x

overall_result=0
RUN_NUMBER=1

source ${HOME}/.bashrc
source /usr/bin/rhts_environment.sh

if hostname -A | grep ${CLIENTS%%.*} > /dev/null; then
    rhts_sync_block -s "server-ready-${RUN_NUMBER}" ${SERVERS}
    rhts_sync_set -s "client-ready-${RUN_NUMBER}"
    rpm -q infiniband-diags
    if [ $? -eq 0 ]; then
        ibstatus
    else
        overall_result=$((overall_result + 1))
        echo "infiniband-diags not installed"
    fi

    rpm -q iproute
    if [ $? -eq 0 ]; then
        rdma dev
        rdma link
    else
        overall_result=$((overall_result + 1))
        echo "iproute not installed"
    fi
    rhts_sync_set -s "client-done-${RUN_NUMBER}"
elif hostname -A | grep ${SERVERS%%.*} > /dev/null; then
    rhts_sync_set -s "server-ready-${RUN_NUMBER}"
    rhts_sync_block -s "client-ready-${RUN_NUMBER}" ${CLIENTS}
    rpm -q infiniband-diags
    if [ $? -eq 0 ]; then
        ibstatus
    else
        overall_result=$((overall_result + 1))
        echo "infiniband-diags not installed"
    fi

    rpm -q iproute
    if [ $? -eq 0 ]; then
        rdma dev
        rdma link
    else
        overall_result=$((overall_result + 1))
        echo "iproute not installed"
    fi
    rhts_sync_block -s "client-done-${RUN_NUMBER}" ${CLIENTS}
fi

# report the overall result to Beaker
# report_result "${TEST}" "PASS" 0
report_result "${TEST}" "${overall_result}" 0
rhts-submit-log -l $OUTPUTFILE

exit $overall_result