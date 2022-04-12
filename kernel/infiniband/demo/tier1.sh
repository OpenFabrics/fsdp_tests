#!/bin/bash -x
trap 'exit 1' SIGHUP SIGINT SIGQUIT SIGTERM

source ${HOME}/rdma-qa-functions.sh

###### FUNCTIONS AND SETUP #########################################################

##
# Exports the PERFTEST_FLAGS variable set depending on the network/driver
# under test.
# Arguments: none
##
function RQA_set_perftest_flags {
    # -R / -x 0:
    #   iWARP: cxgb3, cxgb4, and i40iw devices need to use rdma_cm QP's
    #   RoCE/IB/OPA: not always guaranteed the correct GID index will be specified
    #                on the client/server, so we can either use '-x 0' or '-R' (bz1468589),
    #                where -R is more desirable
    # -F:
    #   suppress CPU frequency warnings when cpu-freq is not max
    # -d $HCA_ID:
    #   all tests should specify the device to avoid incorrect one being selected
    # -p $DEVICE_PORT:
    #   all tests should specify the port to avoid incorrect one being selected
    PERFTEST_FLAGS="-d $HCA_ID -i $DEVICE_PORT -F"
    if [[ "$RDMA_DRIVER" == "mlx4" && "$RDMA_NETWORK" == "roce" ]]; then
        # mlx4/RoCE interfaces give "wr_id 0 syndrom 0x81" with rdmacm; use ethernet exchange
        PERFTEST_FLAGS="$PERFTEST_FLAGS -x 0"
    else
        PERFTEST_FLAGS="$PERFTEST_FLAGS -R"
    fi
    export PERFTEST_FLAGS
}

##
# If using a non-mlx4 machine, disables the inline default feature as
# per bz1028906#c1
# Arguments: none
##
function RQA_set_inline_default {
    if [[ "$RDMA_DRIVER" != *"mlx4"* ]]; then
        mkdir -p /etc/rdma/rsocket
        echo 0 > /etc/rdma/rsocket/inline_default
    fi
}


# mlx4 support inline feature
RQA_set_inline_default

# perftest setup
RQA_set_perftest_flags

# iperf setup
if [[ $(RQA_get_rhel_major) -ge 8 ]]; then
    RQA_pkg_install iperf3
else
    RQA_pkg_install iperf
fi

# route will not be installed by default with check-install
RQA_pkg_install net-tools

###### TESTS #######################################################################

function common_tests {
    # ensure appropriate ib/iw/en/opa drivers are available in this kernel
    driver_modules=$(RQA_get_driver_modules)
    for module in $driver_modules; do
        lsmod | grep -i "^${module} "
        RQA_check_result -r $? -t "load module ${module}"
    done

    if [[ "$RDMA_NETWORK" == *"opa"* ]]; then
        # opa-fm sanity check
        which opa-fm || $PKGINSTALL opa-fm
        mkdir -p /var/usr/lib/opa-fm/ # temporary opa-fm bug

        # To do:
        # Since opafm service for OPA fabric should be running in rdma-master, we
        # should try to see if we can enable it with different priority than that
        # of rdma-master
        RQA_sys_service opafm enable
        RQA_check_result -r $? -t "enable opafm"

        RQA_sys_service opafm restart
        local __opafm_start=$?
        RQA_check_result -r $__opafm_start -t "restart opafm"
        if [[ $__opafm_start -eq 0 ]]; then
            RQA_sys_service opafm stop
            RQA_check_result -r $? -t "stop opafm"
            sleep 3
            RQA_sys_service opafm disable
            RQA_check_result -r $? -t "disable opafm"
        fi

    elif [[ "$RDMA_NETWORK" == *"ib"* ]]; then
        # opensm sanity check
        which opensm || $PKGINSTALL opensm
        RQA_sys_service opensm enable
        RQA_check_result -r $? -t "enable opensm"

        RQA_sys_service opensm restart
        local __opensm_start=$?
        RQA_check_result -r $__opensm_start -t "restart opensm"
        if [[ $__opensm_start -eq 0 ]]; then
            RQA_sys_service opensm stop
            RQA_check_result -r $? -t "stop opensm"
	    sleep 3
            RQA_sys_service opensm disable
            RQA_check_result -r $? -t "disable opensm"
        fi
    fi

    # pkey 0x8080 and vlan 81 creation/deletion test (RHEL-7.7/RHEL-8.0+: see bz1659075)
    if [[ $(RQA_get_rhel_major) -ge 8 || \
        ( $(RQA_get_rhel_major) -eq 7 && $(RQA_get_rhel_minor) -ge 7 ) ]]; then
        if [[ "$RDMA_NETWORK" == "ib0" || "$RDMA_NETWORK" == "ib1" || "$RDMA_NETWORK" == "opa0" ]]; then
            pkey_fail=0
            ip link add link "$DEVICE_ID" name "${DEVICE_ID}.8080" type ipoib pkey 0x8080
            ((pkey_fail+=$?))
            ip --details link show "${DEVICE_ID}.8080"
            ((pkey_fail+=$?))
            ip link delete "${DEVICE_ID}.8080"
            ((pkey_fail+=$?))
            RQA_check_result -r "$pkey_fail" -t "pkey ${DEVICE_ID}.8080 create/delete"
        elif [[ "$RDMA_NETWORK" == "roce" || "$RDMA_NETWORK" == "iw" ]]; then
            vlan_fail=0
            # it will be failed if the name's length > 15, so truncate it
            DEVICE_ID_TMP=$DEVICE_ID
            if [ ${#DEVICE_ID} -gt 12 ]; then
                DEVICE_ID_TMP=${DEVICE_ID:0:12}
            fi
            ip link add link "$DEVICE_ID" name "${DEVICE_ID_TMP}.81" type vlan id 81
            ((vlan_fail+=$?))
            ip --details link show "${DEVICE_ID_TMP}.81"
            ((vlan_fail+=$?))
            ip link delete "${DEVICE_ID_TMP}.81"
            ((vlan_fail+=$?))
            RQA_check_result -r "$vlan_fail" -t "vlan ${DEVICE_ID_TMP}.81 create/delete"
        fi
    fi

    # simple infiniband-diags cases to run on both server and client
    if [[ "$RDMA_NETWORK" != *"iw"* ]]; then
        # not supported on iWARP (bz752570)
        /usr/sbin/ibstat
        RQA_check_result -r $? -t "/usr/sbin/ibstat"
    fi

    /usr/sbin/ibstatus
    RQA_check_result -r $? -t "/usr/sbin/ibstatus"

    # ibutils tests (removed in RHEL-8+)
    if [ $(RQA_get_rhel_major) -lt 8 ]; then
        RQA_pkg_install ibutils
        if ! grep -i fedora /etc/redhat-release; then # not available in Fedora - see PURPOSE
            /usr/bin/ibdev2netdev
            RQA_check_result -r $? -t "/usr/bin/ibdev2netdev"
        fi
        if [[ "$RDMA_NETWORK" == *"ib"* ]]; then
            # can only run on IB networks
            /usr/bin/ibdiagnet
            RQA_check_result -r $? -t "/usr/bin/ibdiagnet"
        fi
    fi

    # ping self ipv4 test
    timeout 3m ping -i 0.2 -c 10 $RDMA_IPV4
    RQA_check_result -r $? -t "ping self - $RDMA_IPV4"

    # ping6 self ipv6 test
    timeout 3m ping6 -i 0.2 -c 10 "${RDMA_IPV6}%${DEVICE_ID}"
    RQA_check_result -r $? -t "ping6 self - ${RDMA_IPV6}%${DEVICE_ID}"
}

function server_tests {
    # ping client. If it fails, the following multi-host tests would fail.
    if [[ -z $CLIENT_IPV4 ]]; then
        echo "CLIENT_IPV4 is empty..."
        echo "Can't continue...returning from client_tests"
        return
    else
        timeout 3m ping -i 0.2 -c 10 $CLIENT_IPV4
        RQA_check_result -r $? -t "ping client - $CLIENT_IPV4"
    fi

    # ping6 client IPV6
    timeout 3m ping6 -i 0.2 -c 10 "${CLIENT_IPV6}%${DEVICE_ID}"
    RQA_check_result -r $? -t "ping6 client - ${CLIENT_IPV6}%${DEVICE_ID}"

    # from librdmacm-utils, run rping and rcopy (not supported by Chelsio)
    if [[ ! "$RDMA_DRIVER" == *"cxgb"* ]]; then
            rhts_sync_set -s "rping-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
            timeout 3m rping -s -a ${SERVER_IPV4} -v -C 50
            RQA_check_result -r $? -t "rping" -c "rping"
            rhts_sync_block -s "rping-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}

            rm -f /tmp/123
            rhts_sync_set -s "rcopy-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
            timeout 3m rcopy
            grep -w 123 /tmp/123
            RQA_check_result -r $? -t "rcopy" -c "rcopy"
            rhts_sync_block -s "rcopy-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
    fi

    # execute a few basic perftests to test read, send, and write BW over RC connection
        for prog in ib_read_bw ib_send_bw ib_write_bw; do
            if [ $(which ${prog}) ]; then
                rhts_sync_set -s "${prog}-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
                timeout 3m ${prog} ${PERFTEST_FLAGS}
                RQA_check_result -r $? -t "${prog}" -c "${prog}"
                rhts_sync_block -s "${prog}-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
            fi
        done
}

function client_tests {
    # ping server. If it fails, the following multi-host tests would fail.
    if [[ -z $SERVER_IPV4 ]]; then
        echo "SERVER_IPV4 is empty..."
        echo "Can't continue...returning from client_tests"
        return
    else
        timeout 3m ping -i 0.2 -c 10 $SERVER_IPV4
        RQA_check_result -r $? -t "ping server - $SERVER_IPV4"
    fi

    # ping6 server test
    timeout 3m ping6 -i 0.2 -c 10 "${SERVER_IPV6}%${DEVICE_ID}"
    RQA_check_result -r $? -t "ping6 server - ${SERVER_IPV6}%${DEVICE_ID}"

    # from librdmacm-utils, run rping and rcopy (not supported by Chelsio)
    if [[ ! "$RDMA_DRIVER" == *"cxgb"* ]]; then
            rhts_sync_block -s "rping-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
            sleep 5
            timeout 3m rping -c -a ${SERVER_IPV4} -v -C 50
            RQA_check_result -r $? -t "rping" -c "rping"
            rhts_sync_set -s "rping-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"

            rhts_sync_block -s "rcopy-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
            echo 123 > /tmp/123
            sleep 5
            timeout 3m rcopy /tmp/123 ${SERVER_IPV4}
            RQA_check_result -r $? -t "rcopy" -c "rcopy"
	    timeout 3m ssh ${SERVERS} "pkill -9 rcopy"
            rhts_sync_set -s "rcopy-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
    fi

    # execute a few basic perftests to test read, send, and write BW over RC connection
        for prog in ib_read_bw ib_send_bw ib_write_bw; do
            if [ $(which ${prog}) ]; then
                rhts_sync_block -s "${prog}-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
                sleep 5
                timeout 3m ${prog} ${PERFTEST_FLAGS} ${SERVER_IPV4}
                RQA_check_result -r $? -t "${prog}" -c "${prog}"
                rhts_sync_set -s "${prog}-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
            fi
        done
}

# begin client/server specific tests
#if hostname -A | grep ${SERVERS%%.*} >/dev/null ; then
if [[ "$1" == "common" ]]; then
    common_tests
elif [[ "$1" == "server" ]]; then
    server_tests
elif [[ "$1" == "client" ]]; then
    client_tests
fi
