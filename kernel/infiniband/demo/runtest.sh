#!/bin/bash -x
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/infiniband/sanity
#   Description: runs a few basic IB tests for fast tier0/1 verification
#   Author: Michael Stowell <mstowell@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2016 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
trap "rm -f /mnt/testarea/sanity-run_number.log; exit 1" SIGHUP SIGINT SIGQUIT SIGTERM

# Source the common test script helpers
source /usr/bin/rhts_environment.sh
source /usr/bin/rhts_environment.sh
source ../env_setup/rdma-qa-functions.sh

# decide if we're running on RHTS or in developer mode
RQA_rhts_or_dev_mode multi

function client {
    echo "--- wait for server to get ready - ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ---"
    rhts_sync_block -s "server-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
    rhts_sync_set -s "client-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"

    # do the sanity test
    bash -x ./tier1.sh client

    # Report the result
    echo "--- client finished - ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ---"
    rhts_sync_set -s "client-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
}

function server {
    # server get ready
    echo "--- server is ready - ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ---"
    rhts_sync_set -s "server-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
    rhts_sync_block -s "client-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}

    # do the sanity test
    bash -x ./tier1.sh server

    # Report the result
    echo "--- server finishes - ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ---"
    rhts_sync_block -s "client-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
}

#--- Start test ------------------------------------------------------

bash -x ./tier1.sh common

if hostname -A | grep ${CLIENTS%%.*} >/dev/null ; then
    echo "******** client test start ********"
    echo "**** ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ***"
    client
    TEST=${TEST}/sanity/client
elif hostname -A | grep ${SERVERS%%.*} >/dev/null ; then
    echo "******** server test start ********"
    echo "******** ${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER} ********"
    server
    TEST=${TEST}/sanity/server
fi

# Report the result and submit the test log
RQA_overall_result

# Clean after self
rm -f ${RUN_NUMBER_LOG} /mnt/testarea/sanity-run_number.log
unset RUN_NUMBER TNAME

echo " ------ end of runtest.sh."
exit 0
