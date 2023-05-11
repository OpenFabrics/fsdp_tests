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
    #   iWARP: cxgb4, qedr, and irdma devices need to use rdma_cm QP's
    #   RoCE/IB/OPA: not always guaranteed the correct GID index will be specified
    #                on the client/server, so we can either use '-x 0' or '-R' (RedHat Bugzilla 1468589),
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
# per RedHat Bugzilla 1028906 Comment #c1
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
if [[ $RELEASE -ge 8 ]]; then
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

    # pkey 0x8080 and vlan 81 creation/deletion test (RHEL-7.7/RHEL-8.0+: see RedHat Bugzilla 1659075)
    if [[ $RELEASE -ge 8 || ( $RELEASE -eq 7 && $RELEASE_MIN -ge 7 ) ]]; then
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
        # not supported on iWARP (RedHat Bugzilla 752570)
        /usr/sbin/ibstat
        RQA_check_result -r $? -t "/usr/sbin/ibstat"
    fi

    /usr/sbin/ibstatus
    RQA_check_result -r $? -t "/usr/sbin/ibstatus"

    # ibutils tests (removed in RHEL-8+)
    if [ $RELEASE -lt 8 ]; then
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

    # pmix (greater than pmix2.1) test for release >= 8.3
    if [[ $RELEASE -gt 8 || ( $RELEASE -gt 7 && $RELEASE_MIN -gt 2 ) ]]; then
      [[ -d /user/share/pmix/test ]] || $PKGINSTALL pmix
      PMIX_TEST_FLAGS="-n 104 -nb --ns-dist 8:8:8:8:8:8:8:8:8:8:8:8:8 --test-internal 100"
      PMIX_TEST_FLAGS+=" --job-fence --test-publish --test-spawn --test-connect --test-resolve-peers"
      /usr/share/pmix/test/pmix_test $PMIX_TEST_FLAGS
      RQA_check_result -r $? -t "/usr/share/pmix/test/pmix_test"
    fi
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

    # openmpi tests
    source ${HOME}/.bashrc 1>/dev/null 2>&1
    rhts_sync_set -s "mpi_ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
    rhts_sync_block -s "mpi_done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}

    # set up iperf server
    route add -net 224.0.0.0 netmask 240.0.0.0 dev $DEVICE_ID
    if [ $RELEASE -ge 8 ]; then
        # RHEL-8 only supports iperf3, which does not support multicast.
        # instead, do multicast sanity checking
        ip maddr show dev $DEVICE_ID
        RQA_check_result -r $? -t "ip multicast addr"
    else
        iperf -u -s -B 224.1.2.3 -i 0.5 &
        rhts_sync_set -s "iperf-up_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
        rhts_sync_block -s "iperf-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
        pkill -9 iperf
    fi

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

    # execute perftests tests read, send, and write BW over RC connection
    for prog in ib_read_bw ib_send_bw ib_write_bw; do
        if [ $(which ${prog}) ]; then
            rhts_sync_set -s "${prog}-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
            timeout 3m ${prog} ${PERFTEST_FLAGS}
            RQA_check_result -r $? -t "${prog}" -c "${prog}"
            rhts_sync_block -s "${prog}-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
        fi
    done

    # iSER test
    if [[ $RELEASE -ge 7 ]]; then
        # iser login, discover, & write
        server_block_dev=$(RQA_get_block_dev_xfs $SERVER_IPV4)
        umount ${server_block_dev}
        targetcli /backstores/block create vol1 ${server_block_dev}
        targetcli /iscsi create ${target_name}
        targetcli /iscsi/${target_name}/tpg1/portals/ delete  0.0.0.0 3260
        targetcli /iscsi/${target_name}/tpg1/portals/ create ${SERVER_IPV4}
        targetcli /iscsi/${target_name}/tpg1/portals/${SERVER_IPV4}:3260 enable_iser true
        targetcli /iscsi/${target_name}/tpg1/luns create /backstores/block/vol1
        targetcli /iscsi/${target_name}/tpg1/ set attribute authentication=0 demo_mode_write_protect=0 generate_node_acls=1 cache_dynamic_acls=1
        targetcli ls
        targetcli saveconfig
        rhts_sync_set -s "iser-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"

        # iser cleanup
        rhts_sync_block -s "iser-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${CLIENTS}
        targetcli clearconfig confirm=true
        targetcli ls
        mount ${server_block_dev}
        server_block_dir=$(df -h | grep $server_block_dev | awk '{print $NF}')
        [ -d "${server_block_dir}" ] && rm -f ${server_block_dir}/*
        df -h
    fi

    # NFSoRDMA test
    local nfs_dir="/srv/nfs"

    nfs_rdma_mod="rpcrdma"
    if (($RELEASE <= 7)); then
        nfs_rdma_mod="svcrdma"
    fi

    lsmod | grep "$nfs_rdma_mod"
    if [[ $? -eq 0 ]]; then
        modprobe $nfs_rdma_mod
    fi

    for fs_type in XFS_EXT RAMDISK; do
        local ramdisk_mnt=1
        local l_nfs_start=1
        local l_nfs_stop=1

        [ ! -d $nfs_dir ] && mkdir -p $nfs_dir
        if [[ $fs_type == "RAMDISK" ]]; then
            RQA_create_ramdisk $nfs_dir
            ramdisk_mnt=$?
            if [[ $ramdisk_mnt != 0 ]]; then
                continue
            fi
        fi
        echo "${nfs_dir} *(fsid=0,rw,async,insecure,no_root_squash)" > /etc/exports
        exportfs -a
        if (($RELEASE >= 8)); then
            nfsconf --set nfsd rdma 20049
            RQA_sys_service nfs-server restart
            l_nfs_start=$?
        else
            RQA_sys_service nfs restart
            l_nfs_start=$?
            RQA_sys_service nfs-server restart
            l_nfs_start=$((l_nfs_start + $?))
            echo "rdma 20049" > /proc/fs/nfsd/portlist
        fi
        cat /proc/fs/nfsd/portlist | grep "rdma"

        if [[ $fs_type == "RAMDISK" ]]; then
            local l_mnt_n_srv=$((ramdisk_mnt + l_nfs_start))
            RQA_check_result -r $l_mnt_n_srv -t "nfsordma - server nfs started - $fs_type created"
        else
            RQA_check_result -r $l_nfs_start -t "nfsordma - server nfs started - $fs_type"
        fi

        rhts_sync_set -s "nfsordma-server-ready_${TNAME}-${RDMA_NETWORK}-${fs_type}_${RUN_NUMBER}"
        rhts_sync_block -s "nfsordma-client-done_${TNAME}-${RDMA_NETWORK}-${fs_type}_${RUN_NUMBER}" ${CLIENTS}

        RQA_sys_service nfs-server status
        if [[ $? -eq 0 ]]; then
            RQA_sys_service nfs-server stop
            l_nfs_stop=$?
        fi

        if (($RELEASE <= 7)); then
            RQA_sys_service nfs status
            if [[ $? -eq 0 ]]; then
                RQA_sys_service nfs stop
                l_nfs_stop=$((l_nfs_stop + $?))
            fi
        fi

        if [[ $fs_type == "RAMDISK" ]]; then
            if [[ $ramdisk_mnt = 0 ]]; then
                RQA_del_ramdisk "$nfs_dir"
                local l_del_ramdisk=$?
            fi
            local l_mnt_srv_stp=$((l_del_ramdisk + l_nfs_stop))
            RQA_check_result -r $l_mnt_srv_stp -t "nfsordma - server nfs stopped - $fs_type deleted"
        else
            RQA_check_result -r $l_nfs_stop -t "nfsordma - server nfs stopped - $fs_type"
        fi

        # NFSoRDMA cleanup
        rm -rf /srv/nfs /etc/exports
        touch /etc/exports
        exportfs -r
    done

    RQA_sys_service nfs-server status
    if [[ $? -eq 0 ]]; then
        RQA_sys_service nfs-server stop
    fi

    if (($RELEASE <= 7)); then
        RQA_sys_service nfs status
        if [[ $? -eq 0 ]]; then
            RQA_sys_service nfs stop
        fi
    fi

    lsmod | grep "$nfs_rdma_mod"
    if [[ $? -eq 0 ]]; then
        modprobe --remove $nfs_rdma_mod
    fi
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

    # run openmpi tests - one core, one network, one benchmark in MPI1, IO, EXT, and OSU
    source ${HOME}/.bashrc 1>/dev/null 2>&1
    MPIPATH=/usr/lib64/openmpi/bin
    export HFILES="/root/hfile_all_cores /root/hfile_one_core"
    if [[ $MPI_PKG == "openmpi3" ]]; then
        MPIPATH=/usr/lib64/openmpi3/bin
    fi
    mpirun_flags="--allow-run-as-root --map-by node $(MPI_get_openmpi_mca_param)"
    ucx_flags=$(ucx_mpi_flags "$mpirun_flags")
    mpirun_flags="$ucx_flags"
    hfiles=( $(echo $HFILES) )
    hfile=${hfiles[0]}
    if [ ! -z $hfile ]; then
        rhts_sync_block -s "mpi_ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
        NLINES=$(cat ${hfile} | wc -l)
        for app in "mpitests-IMB-MPI1 PingPong" "mpitests-IMB-IO S_Read_indv" \
            "mpitests-IMB-EXT Window" "mpitests-osu_get_bw"; do
            timeout 3m $MPIPATH/mpirun $mpirun_flags -hostfile ${hfile} -np ${NLINES} $MPIPATH/${app}
            mpi_return=$?
            RQA_check_result -r ${mpi_return} -t "$MPI_PKG $app"
        done
    fi
    rhts_sync_set -s "mpi_done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"

    # iperf test
    route add -net 224.0.0.0 netmask 240.0.0.0 dev $DEVICE_ID
    if [ $RELEASE -ge 8 ]; then
        # RHEL-8 only supports iperf3, which does not support multicast.
        # instead, do multicast sanity checking
        ip maddr show dev $DEVICE_ID
        RQA_check_result -r $? -t "ip multicast addr"
    else
        rhts_sync_block -s "iperf-up_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
        iperf -u -c 224.1.2.3 -i 0.5 -t 30
        RQA_check_result -r $? -t "multicast iperf"
        rhts_sync_set -s "iperf-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
    fi

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

    # execute perftests tests read, send, and write BW over RC connection
    for prog in ib_read_bw ib_send_bw ib_write_bw; do
        if [ $(which ${prog}) ]; then
            rhts_sync_block -s "${prog}-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
            sleep 5
            timeout 3m ${prog} ${PERFTEST_FLAGS} ${SERVER_IPV4}
            RQA_check_result -r $? -t "${prog}" -c "${prog}"
            rhts_sync_set -s "${prog}-DONE_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
        fi
    done

    # iSER tests
    if [[ $RELEASE -ge 7 ]]; then
        rhts_sync_block -s "iser-ready_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}" ${SERVERS}
        timeout 2m iscsiadm -m discovery -t sendtargets -p $SERVER_IPV4 -I iser
        timeout 2m iscsiadm -m node -p $SERVER_IPV4 -T $target_name \
            --op update -n node.transport_name -v iser
        timeout 3m iscsiadm -m node -p $SERVER_IPV4 -T $target_name --login
        local is_logged_in=$?
        RQA_check_result -r $is_logged_in -t "iser login"
        sleep 5
        if [ $is_logged_in -eq 0 ]; then
            mkdir -p /iser
            client_block_dev=$(lsscsi | grep vol1 | awk '{print $NF}')
            timeout 3m mount ${client_block_dev} /iser
            mnt_iser=$?
            RQA_check_result -r $mnt_iser -t "mount ${client_block_dev} /iser"
            sleep 5
            if (( mnt_iser == 0 )); then
                for size in 1K 1M 1G; do
                    rm -f /iser/${size}.dd
                    timeout 3m dd if=/dev/zero of=/iser/test-${size}.dd bs=${size} count=5 iflag=fullblock
                    RQA_check_result -r $? -t "iser write ${size}"
                    rm -f /iser/test-${size}.dd
                done
            else
                echo "Failed in 'mount ${client_block_dev} /iser"
            fi
            timeout 1m umount /iser
            rm -rf /iser
            timeout 2m iscsiadm -m node -p $SERVER_IPV4 -T $target_name --logout
        fi
        rhts_sync_set -s "iser-done_${TNAME}-${RDMA_NETWORK}-${RUN_NUMBER}"
    fi

    # NFSoRDMA tests
    local nfsordma_mnt_pt="/srv/nfs"
    local nfs_dir="/srv/nfs"
    local ramdisk_mnt=1

    nfs_rdma_mod="rpcrdma"
    if (($RELEASE <= 7)); then
        nfs_rdma_mod="xprtrdma"
    fi

    lsmod | grep "$nfs_rdma_mod"
    if [[ $? -eq 0 ]]; then
        modprobe $nfs_rdma_mod
    fi

    for fs_type in XFS_EXT RAMDISK; do
        [ -d ${nfsordma_mnt_pt} ] || mkdir -p ${nfsordma_mnt_pt}
        rhts_sync_block -s "nfsordma-server-ready_${TNAME}-${RDMA_NETWORK}-${fs_type}_${RUN_NUMBER}" ${SERVERS}
        RQA_sys_service nfs-client.target enable
        showmount -e ${SERVER_IPV4}
        timeout 3m mount -v -o rdma,port=20049 ${SERVER_IPV4}:${nfs_dir} ${nfsordma_mnt_pt}
        sleep 5
        grep "proto=rdma" /proc/mounts
        local is_mounted=$?
        RQA_check_result -r $is_mounted -t "nfsordma mount - $fs_type"
        if (( is_mounted == 0 )); then
            local cnt=5
            local dd_return=0
            for bs in K M G; do
                rm -f ${nfsordma_mnt_pt}/test-${cnt}${bs}.dd
                timeout 3m dd if=/dev/zero of=${nfsordma_mnt_pt}/test-${cnt}${bs}.dd bs=1${bs} count=${cnt} iflag=fullblock
                dd_return=$((dd_return + $?))
                sync
                rm -f ${nfsordma_mnt_pt}/test-${cnt}${bs}.dd
            done
            echo "nfsordma IO [${cnt}KB, ${cnt}MB, ${cnt}GB in 1KB, 1MB, 1GB blocksize]"
            RQA_check_result -r $dd_return -t "nfsordma - wrote [${cnt}KB, ${cnt}MB, ${cnt}GB in 1KB, 1MB, 1GB bs]"
        fi
        timeout 1m umount ${nfsordma_mnt_pt}
        umounted=$?
        RQA_check_result -r $umounted -t "nfsordma umount - $fs_type"
        if ((umounted == 0)); then
            rm -rf ${nfsordma_mnt_pt}
        fi
        rhts_sync_set -s "nfsordma-client-done_${TNAME}-${RDMA_NETWORK}-${fs_type}_${RUN_NUMBER}"
    done

    RQA_sys_service nfs-client.target status
    if [[ $? -eq 0 ]]; then
        RQA_sys_service nfs-client.target stop
    fi

    lsmod | grep "$nfs_rdma_mod"
    if [[ $? -eq 0 ]]; then
        modprobe --remove $nfs_rdma_mod
    fi
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
