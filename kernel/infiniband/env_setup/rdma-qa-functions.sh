#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   rdma-qa-functions.sh of /kernel/infiniband/env_setup
#   Description: prepare RDMA cluster test environment
#   Author: Afom Michael <tmichael@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
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
#
#
###                                                           ###
# This script contains many of the common functions, variables, #
# and constants infiniband-qe uses for test cases.  It can be   #
# used in supplment with /kernel/infiniband/env_setup.          #
#                                                               #
# WARNING: do *not* source this script in .bashrc.  This script #
#          will source .bashrc itself, so sourcing it from      #
#          .bashrc will cause a circular dependency.            #
###                                                           ###

##
# Prepend time-stamp to execution log
##
PS4='$(date +"+ [%y-%m-%d %H:%M:%S]") '

source /root/fsdp_setup/rdma-functions.sh

## functions #################################################################

##
# This function is to install a package(s) if it isn't already installed
# Arguments: package name or a list of package names
# Example: RQA_pkg_install nfs-utils
#          RQA_pkg_install nfs-utils nfsometer
##
function RQA_pkg_install {
    PKG_LIST=""
    for p in "$@";
    do
        rpm -q "$p" || PKG_LIST="${PKG_LIST} ${p}"
    done

    if [ ! -z "$PKG_LIST" ]; then
        $PKGINSTALL $PKG_LIST
    fi
}

##
# Identify between systemctl or service based on RHEL version
# and take the stated action
# Arguments: service name and service action (order independent)
# Example: RQA_sys_service restart opensm
##
function RQA_sys_service {
    SERVICE_RETURN=1
    if [ $# -ne 2 ]; then
        echo "Pass two arguments - service_name & service action"
        return 1
    fi
    while test ${#} -gt 0; do
        case $1 in
            start|status|restart|stop|enable|disable|is-active|is-enabled)
                action=$1
                ;;
            *)
                serv=$1
                ;;
        esac
        shift
    done
    if [ $(RQA_get_rhel_major) -ge 7 ]; then
        /usr/bin/systemctl $action $serv
        SERVICE_RETURN=$?
    else
        serv=$(echo $serv | awk -F '.' '{print $1}')

        case "$action" in
            "enable")
                # enable a service using chkconfig on
                /sbin/chkconfig $serv on
                ;;
            "disable")
                # disable a service using chkconfig off
                /sbin/chkconfig $serv off
                ;;
            "is-active")
                # similar to systemctl is-active, service status will
                # return 0 for an active service and 3 for inactive
                /sbin/service $serv status
                ;;
            "is-enabled")
                # to simulate systemctl is-enabled, use chkconfig to
                # check if the service is enabled at runlevel 3
                /sbin/chkconfig --list | grep $serv | grep "3:on"
                ;;
            *)
                # all other actions (start, status, restart, stop)
                # can be used directly by the service command
                /sbin/service $serv $action
                ;;
        esac
        SERVICE_RETURN=$?
    fi
    return $SERVICE_RETURN
}

##
# Returns the RHEL or Fedora release the host is provisioned to
# Arguments: none
##
function RQA_get_rhel_release {
    grep -o '[0-9]*\.*[0-9]*' /etc/redhat-release
}

##
# Returns the RHEL major release the host is provisioned to.  For Fedora,
# the return value will be equivalent to RQA_get_rhel_release's.
# Arguments: none
##
function RQA_get_rhel_major {
    echo $(RQA_get_rhel_release) | awk -F "." '{print $1}'
}

##
# Returns the RHEL minor release the host is provisioned to.  For Fedora,
# the return value will be empty.
# Arguments: none
##
function RQA_get_rhel_minor {
    echo $(RQA_get_rhel_release) | awk -F "." '{print $2}'
}

#
# This function can be utilized as a best-attempt to get the IB/iWARP/RoCE/OPA
# network of the calling device up and running.  For OPA devices, this will
# install opa-fm and start the opafm service.  For any other device, this will
# install opensm and only start the opensm service if the network is down
# initially.  If the network is still down after this, the default device
# for this host will be flipped down and back up.  If even after this step the
# network appears down, we assume there is a dhcpd issue, set up the ifcfg's
# to use static IP's, and flip the devices down and up again.  An optional
# prefix argument can be supplied to this function to override the default
# device for which this function attempts to bring up.
# Arguments: 1 = network, 2 = driver
# Example: RQA_bring_up_network ib0 mlx5
##
function RQA_bring_up_network {
    if [ $# -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <network> <driver>"
        return 1
    fi
    local _RDMA_NETWORK=$1
    local _RDMA_DRIVER=$2

    if [[ ! -z $CLIENTS ]] && [[ ! -z $SERVERS ]]; then
        # if the SERVERS and CLIENTS variables are set, and we can ping
        # both, then there is no need to try to bring up the network
        local alias_server="${_RDMA_NETWORK}-${SERVERS}"
        IP_SERVER=$(cat /etc/hosts | grep $alias_server | awk -F ' ' '{print $1}')
        local alias_client="${_RDMA_NETWORK}-${CLIENTS}"
        IP_CLIENT=$(cat /etc/hosts | grep $alias_client | awk -F ' ' '{print $1}')
        local __bad=0
        ping -c3 $IP_SERVER
        ((__bad+=$?))
        ping -c3 $IP_CLIENT
        ((__bad+=$?))
        if [ $__bad -eq 0 ]; then
            # return since the network is working as expected
            return 0
        fi
    else
        # this is a singlehost case, so ensure we can loopback ping
        local alias_server="${_RDMA_NETWORK}-${s_hostname}"
        IP_SERVER=$(cat /etc/hosts | grep $alias_server | awk -F ' ' '{print $1}')
        ping -c3 $IP_SERVER
        if [ $? -eq 0 ]; then
            # return since the network is working as expected
            return 0
        fi
    fi

    # if we got here - network isn't working.  We'll try:
    #   1) ensuring the appropriate modules are loaded and
    #   2) starting the subnet manager
    modprobe $(RQA_get_driver_modules)
    if [[ "$_RDMA_NETWORK" == *"opa"* ]]; then
        RQA_pkg_install opa-fm
        mkdir -p /var/usr/lib/opa-fm/ # temporary opa-fm bug
        RQA_sys_service enable opafm
        RQA_sys_service restart opafm
        sleep 5
        RQA_sys_service status opafm
        # try bringing the device down and up immediately
        ifdown $DEVICE_ID
        sleep 3
        ifup $DEVICE_ID
        if [ $? -ne 0 ]; then
            # sometimes it takes a while for OPA devices to go ACTIVE after the
            # opa-fm has started; try again in 5 minutes
            sleep 300
            ifdown $DEVICE_ID
            sleep 3
            ifup $DEVICE_ID
        fi
    else
        RQA_pkg_install opensm
        RQA_sys_service enable opensm
        RQA_sys_service restart opensm
        sleep 3
        # some interfaces (e.g. mlx4_ib1) require ib_ipoib module reload
        modprobe -r ib_ipoib
        sleep 3
        modprobe ib_ipoib
        sleep 3
        RQA_sys_service status opensm
        if [ $? -ne 0 ]; then
            # if opensm is not started, restart the network
            if [ $(RQA_get_rhel_major) -ge 7 ]; then
                RQA_sys_service restart NetworkManager.service
            else
                RQA_sys_service restart network
            fi
        else
            # otherwise, flip the device down/up
            ifdown $DEVICE_ID
            sleep 3
            ifup $DEVICE_ID
        fi
    fi

    # check the network once more -
    # if there are still failures, our last ditch effort is assuming there is
    # an issue with dhcpd on build-00, and thus will use static IPs
    local __bad=0
    ping -c3 $IP_SERVER
    ((__bad+=$?))
    if [[ ! -z $CLIENTS ]] && [[ ! -z $SERVERS ]]; then
        ping -c3 $IP_CLIENT
        ((__bad+=$?))
    fi
}

##
# Per bz1537600: if using RHEL-7.5+, CONNECTED_MODE=yes in an mlx5/ib0 ifcfg
# will cause the interface to fail to bring up, unless we otherwise reload the
# ib_ipoib module with ipoib_enhanced=0.  We will simply disable connected mode
# as the drivers no longer support it, and we want to test ipoib_enhanced in
# future releases as well.
#
# This workaround should only be temporary and a permanent solution implemented
# by the rdma-setup.sh script.
##
function RQA_fix_mlx5_ib_connected_mode {
    # only apply to 7.5+ or 8.y+
    if [[ $(RQA_get_rhel_major) -ge 7 && $(RQA_get_rhel_minor) -ge 5 ]] || \
        [[ $(RQA_get_rhel_major) -gt 7 ]]; then
        for mlx_ifcfg in $(ls /etc/sysconfig/network-scripts/ | grep mlx5 | grep ib | grep -v '~'); do
            # some ifcfgs (like ib1) do not define CONNECTED_MODE; since it defaults to 'no',
            # search only for CONNECTED_MODE=yes
            if ! grep "CONNECTED_MODE=yes" /etc/sysconfig/network-scripts/${mlx_ifcfg} 1>/dev/null 2>&1; then
                continue
            fi
            local mlx_intf=$(echo ${mlx_ifcfg//ifcfg-})
            echo "rdma-qa-functions.sh: disabling CONNECTED_MODE on ${mlx_intf}"
            sed -i 's/CONNECTED_MODE.*/CONNECTED_MODE=no/' /etc/sysconfig/network-scripts/${mlx_ifcfg}
            ifdown $mlx_intf
            sleep 3
            ifup $mlx_intf
        done
    fi
}

##
# if nothing is up, as a last act, try this function to assign IPs
# Arguments: none
##
function RQA_force_start_network {
    local net_devs=$(ibdev2netdev | awk '/(Up)/ {print $(NF-1)}')
    for d in $net_devs; do
        ip a s $d | grep "172.31."
        if [[ $? -ne 0 ]]; then
            ifup $d
        fi
    done

    if [[ ! -e /root/fsdp_setup/rdma-setup.sh ]]; then
        curl -L --retry 20 --remote-time -o /root/fsdp_setup/rdma-setup.sh \
            ${RDMA_LOOKASIDE}/rdma-testing/rdma-setup.sh
    fi

    if [[ ! -e /root/fsdp_setup/rdma-setup.log ]]; then
        /root/fsdp_setup/rdma-setup.sh 2>&1 > /root/fsdp_setup/rdma-setup.log
    fi

    local __mod_list=$(RQA_get_rdma_modules)
    for module in ${__mod_list}; do
        # module=$(ethtool -i $d | awk '/driver/ {print $2}' | awk -F "[" '{print $1}')

	dep_mod=$(RQA_get_driver_modules "${module}")

        for mod in $dep_mod; do
            sleep 3
            modprobe -r $mod
        done

        local rev_dep_mod=$(echo $dep_mod | tr ' ' '\n'|tac|tr '\n' ' ')

        for mod in $rev_dep_mod; do
            sleep 3
            modprobe $mod
        done
    done

    local net_config="/etc/sysconfig/network-scripts"

    local ib_dev=$(ibdev2netdev | awk '/(Up)/ {print $5}' | tr "\n"  " ")
    for d in ${ib_dev}; do
        net_n_vlan=$(ls ${net_config}/ifcfg-${d}* | awk -F "-" '{print $(NF)}')
        for netd in $net_n_vlan; do
            ifdown $netd
            sleep 5
            ifup $netd
        done
    done
}

##
# Decide if we're running on RHTS or in developer mode.  If running in developer mode
# (manually), then ensure that a test log is saved in /mnt/testarea and that the
# env_setup task was successfully run before this task
# Arguments: 1 = 'single' for singlehost, 'multi' for multihost
#            2 = 'env' iff you are calling it from env_setup, to avoid env_setup
#                making a call to RQA_check_env_setup
# Example: rhts_or_dev_mode multi
##
function RQA_rhts_or_dev_mode {
    export RUN_NUMBER=0

    if test -z $JOBID ; then
        echo "Variable JOBID not set, assuming developer mode"
        RQA_log_test_run
        if [ "$(basename $(pwd))" == "nfsordma_sh" ]; then
            export UNIQ_ID=$(shuf -i 10000-99999 -n 1)
        fi
        if [ -z ${REBOOTCOUNT+x} ]; then REBOOTCOUNT=0; fi
        if [[ -z "$2" || "$2" != "env" ]]; then
            RQA_check_env_setup
            TEST_NAME=$(echo $TEST | sed -r 's/\/kernel\/infiniband\///; \
		    s/ofa-fsdp\///; s/\/server//; s/\/client//; s/\/standalone//')
            # sub '/' by '_'
            export TNAME=$(echo $TEST_NAME | sed 's/\//_/g')
        else
            export TNAME=$(basename $(pwd))
        fi

        export RUN_NUMBER_LOG="/mnt/testarea/${TNAME}-run_number.log"

        if [[ *"${s_hostname}"* == "${SERVERS}" ]]; then
            # start with clean $RUN_NUMBER_LOG in case there was an old one
            rm -f $RUN_NUMBER_LOG
        fi

        if [[ $1 == *"multi"* ]]; then
            RQA_number_of_run
        fi
    else
        echo "Variable JOBID set, we're running on RHTS"
        if [ "$(basename $(pwd))" == "nfsordma_sh" ]; then
            export UNIQ_ID=$TASKID
        fi
        # Save STDOUT and STDERR, and redirect everything to a file
        exec 5>&1 6>&2
        exec >> "${OUTPUTFILE}" 2>&1
    fi

    if [ "$1" == "multi" ]; then
        echo "Clients: $CLIENTS"
        echo "Servers: $SERVERS"
    fi
}

##
# Log a test run by spawning a child process that will both print to STDOUT
# and to a log file in /mnt/testarea
# Arguments: none
##
function RQA_log_test_run {
    # only execute this as the parent, not child process spawned by this function
    if [ "$RUN_AS_CHILD" != "1" ]; then
        # initialize a log file in /mnt/testarea
        mkdir -p /mnt/testarea
        local TEST_LOG="/mnt/testarea/$(basename \
		$(pwd))-${s_hostname}-$(date +%Y_%m_%d_%H_%M_%S).log"
        # create a named pipe for logging the child process output
        local PIPE="pipe_$(date +%Y_%m_%d_%H_%M_%S).fifo"
        mkfifo $PIPE
        # launch the child process
        RUN_AS_CHILD=1 bash -x $0 $* 1>$PIPE 2>&1 <&0 &
        local LOG_PID=$!
        # use tee in a separate process to capture the child output
        tee $TEST_LOG <$PIPE &
        # parent process no longer needs reference to this pipe
        rm $PIPE
        # wait for the child to exit, then exit the parent (since the child has now
        # run the entire test script)
        wait $LOG_PID
        exit $?
    fi
    # this is where the child will get - return immediately
    return 0
}

##
# Set SERVERS & CLIENTS variables in ${HOME}/.bashrc"
# this removes the requirement that one has to define the variables for manual runs
##
function RQA_set_servers_clients {
    s_server_name=$(echo $SERVERS | awk -F "." '{ print $1}')
    s_client_name=$(echo $CLIENTS | awk -F "." '{ print $1}')
    if ! grep "export SERVERS=" $BASHRC_FILE; then
        echo "export SERVERS=\"$s_server_name\"" >> $BASHRC_FILE
    fi

    if ! grep "export CLIENTS=" $BASHRC_FILE; then
        echo "export CLIENTS=\"$s_client_name\"" >> $BASHRC_FILE
    fi

    source $BASHRC_FILE
}

##
# Creates a test result file for the currently executing test.
# Arguments: none
##
function __RQA_create_test_result_file {
    # create a new temporary file to record test results
    local rdma_version=$(rpm -q --queryformat "%{NAME}-%{VERSION}-%{RELEASE}" rdma-core)
    TEST_NAME=$(echo $TEST | sed -r "s/\/kernel\/infiniband\///; s/\/server//; \
	    s/\/client//; s/\/standalone//; s/\//_/")
    # if TEST_NAME has '/', substitute it with '-', i.e. 'mpi/openmpi' would be 'mpi-openmpi'
    local result_filename=$(echo "results_${TEST_NAME}_${RUN_NUMBER}.txt" | sed 's/\//-/g')
    TEST_RESULT_FILE="$(mktemp -d)/${result_filename}"
    {
        echo "Test results for ${TEST_NAME} on ${s_hostname}:"
        echo "$(uname -r), ${rdma_version}, ${RDMA_DRIVER}, ${RDMA_NETWORK}, & ${HCA_ID}"
        echo "    Result | Status | Test"
        echo "  ---------+--------+------------------------------------"
    } >> "$TEST_RESULT_FILE"
    # write this to /etc/environment to use it as a system-wide variable
    sed -i '/TEST_RESULT_FILE/d' /etc/environment
    echo "TEST_RESULT_FILE=$TEST_RESULT_FILE" >> /etc/environment
    source /etc/environment
}

##
# Removes the test result file to allow a new test to execute.
# Arguments: none
##
function __RQA_unset_test_result_file {
    # first 'cat' the file for easy reading in the complete test log
    cat $TEST_RESULT_FILE
    # remove the variable from /etc/environment and unset it
    export TEST_RESULT_FILE=""
    unset TEST_RESULT_FILE
    sed -i '/TEST_RESULT_FILE/d' /etc/environment
    echo "TEST_RESULT_FILE=\"\"" >> /etc/environment
    source /etc/environment
}

##
# Determine PASS or FAIL status based on return code of the test.
# Arguments: '-r <return code>' and '-t "test string"' [and sometimes '-c "command"]'
# Example: RQA_check_result -r $? -t "$_T_NFSORDMA_MOUNT"
#          RQA_check_result -r $? -t "$_T_NFSORDMA_MOUNT" -c "rcopy"
##
function RQA_check_result {
    local test_pass=0
    local test_skip=777

    # parse arguments for the return code and test string
    while test ${#} -gt 0; do
        case $1 in
            -r|-R|--value|--return)
                local rc=$2
                shift
                ;;
            -t|-T|--test|--message)
                local msg="$2"
                shift
                ;;
            -c|-C|--cmd|--CMD)
                local remote_cmnd="$2"
                shift
                ;;
            *)
                echo "Bad argument - allowed args are -v return_value and -r reason" >&2
                shift
                ;;
        esac
        shift
    done

    # ensure both return code and test string were provided
    if [ -z "$rc" -o -z "$msg" ]; then
        echo "Usage: ${FUNCNAME[0]} -r <return_value> -t <test_string>"
        return 1
    fi

    # check to see if a test result file is created; if not, create one now
    [ -z "$TEST_RESULT_FILE" ] && source /etc/environment
    if [ -z "$TEST_RESULT_FILE" ]; then
        __RQA_create_test_result_file
    fi

    # assuming a 0 exit code is PASS, set the overall "result" to FAIL as soon as
    # a single test fails, and save the result just for this test as "test_result"
    if [ $rc -eq $test_pass ]; then
        local test_result="PASS"
    elif [ $rc -eq $test_skip ]; then
        local test_result="SKIP"
    else
        local test_result="FAIL"
        export result="FAIL"
        # If command has FAILed, kill the corresponding command on the remote host
        # so it can move on without waiting to timeout
        if [[ ! -z $remote_cmnd ]]; then
            ssh $REMOTE_HOST "pkill $remote_cmnd"
        fi
    fi

    # save the test result to the test result file
    printf "%10s | %6s | %s\n" "$test_result" "$rc" "$msg" >> $TEST_RESULT_FILE

    # print the result to the test log (with set +x to avoid double-echo)
    (
     set +x
     echo "---"
     echo "- TEST RESULT FOR $(basename $(pwd))"
     echo "-   Test:   $msg"
     echo "-   Result: $test_result"
     echo "-   Return: $rc"
     echo "---"
    )
}

##
# To be used after a test finishes execution and has logged results with RQA_check_result,
# this function will parse through the overall results and the known-issue list to
# determine whether the test run should be deemed PASS or FAIL.
# Note: this function should only be called in a file (e.g. runtest.sh) that sources
#       the /usr/bin/rhts_environment.sh script, as it makes calls to report_result
# Arguments: none
##
function RQA_overall_result {
    # ensure the RQA_KNOWN_ISSUES dict is populated and TEST_RESULT_FILE is set
    [ -z $TEST_RESULT_FILE ] && source /etc/environment

    # if there is still no TEST_RESULT_FILE, then no tests were recorded/finished;
    # this may happen for example on Server hosts that set up for the client to run tests
    # but do not record any test results themselves
    if [ -z $TEST_RESULT_FILE ]; then
        echo "No test results recorded - automatically marking PASS."
        report_result "${TEST}" "PASS" 0
        return 0
    fi

    # set the overall result to PASS until we find a true failure
    local overall_result="PASS"
    echo >> $TEST_RESULT_FILE
    echo "Checking for failures and known issues:" >> $TEST_RESULT_FILE

    # if no failures in the test result file, overall result is PASS
    if ! grep "FAIL" $TEST_RESULT_FILE; then
        echo "  no test failures" >> $TEST_RESULT_FILE
        # report the overall result to Beaker
        report_result "${TEST}" "${overall_result}" 0
        rhts-submit-log -l $TEST_RESULT_FILE
        # unset the test result file variable so future tests will use a new /tmp file
        __RQA_unset_test_result_file
        return 0
    else
        overall_result="FAIL"
    fi

    # some tests may define a variable $ON_FAIL that dictates whether or not to mark
    # a test case as SKIP if it fails; if we see it is set and == SKIP, mark it so
    if [[ ! -z "$ON_FAIL" && "$ON_FAIL" == "SKIP" ]]; then
        echo "  User explicitly requested test failures be SKIPPED - please review manually" >> $TEST_RESULT_FILE
        overall_result="SKIP"
        report_result "${TEST}" "${overall_result}" 0
        rhts-submit-log -l $TEST_RESULT_FILE
        # unset the test result file variable so future tests will use a new /tmp file
        __RQA_unset_test_result_file
        return 0
    fi

    # if no failures, print a message to the test result file
    if [[ $overall_result == "PASS" ]]; then
        echo "  no new test failures" >> $TEST_RESULT_FILE
    fi

    # report the overall result to Beaker
    report_result "${TEST}" "${overall_result}" 0
    rhts-submit-log -l $TEST_RESULT_FILE
    # unset the test result file variable so future tests will use a new /tmp file
    rm $test_fail_file
    __RQA_unset_test_result_file
    return 0
}

##
# Prints the IPv4 address of the specified device
# Arguments: 1 = device
# Example: RQA_get_my_ipv4 qib_ib0
##
function RQA_get_my_ipv4 {
    local IPv4=""

    if [ $# -ne 1 ]; then
        echo "Usage: RQA_get_my_ipv4 <device>"
        return 1
    fi
    IPv4=$(ip addr show dev $1 | sed -e's/^.*inet \([^ ]*\)\/.*$/\1/;t;d')

    if [[ $IPv4 == "" ]]; then
        return 1
    else
        echo "$IPv4"
    fi

    return 0
}

##
# Prints the IPv6 address of the specified device
# Arguments: 1 = device
# Example: RQA_get_my_ipv6 qib_ib0
##
function RQA_get_my_ipv6 {
    if [ $# -ne 1 ]; then
        echo "Usage: RQA_get_my_ipv6 <device>"
        return 1
    fi
    ip addr show dev $1 | sed -e's/^.*inet6 \([^ ]*\)\/.*$/\1/;t;d'
}

##
# Prints a list of driver modules that should be found in the host
# Arguments: none
##
function RQA_get_driver_modules {
    case ${RDMA_DRIVER} in
        ocrdma) echo "ocrdma";
	;;
        mlx4)   echo "mlx4_ib mlx4_en mlx4_core";
	;;
        mlx5)   echo "mlx5_ib mlx5_core";
	;;
        qib)    echo "ib_qib";
	;;
        cxgb3)  echo "iw_cxgb3 cxgb3";
	;;
        cxgb4)  echo "iw_cxgb4 cxgb4";
	;;
        hfi1)   echo "hfi1";
	;;
        i40*)   echo "i40iw i40e";
	;;
        qed*)   echo "qedr qede qed";
	;;
        bnxt)   echo "bnxt_re bnxt_en";
	;;
        irdma)  # Need to check this for e810
                echo "irdma ice";
	;;
        *)      echo "";
	;;
    esac
}

##
# Prints the single main driver module that is used in json file
# Arguments: 1 = driver_name
# Example: RQA_get_driver_name bnxt_en
##
function RQA_get_driver_name {
    local __mod_name=$1
    case ${__mod_name} in
        *ocrdma*) echo "ocrdma";
	;;
        *mlx4*)   echo "mlx4";
	;;
        *mlx5*)   echo "mlx5";
	;;
        *qib*)    echo "qib";
	;;
        *cxgb3*)  echo "cxgb3";
	;;
        *cxgb4*)  echo "cxgb4";
	;;
        *hfi1*)   echo "hfi1";
	;;
        *i40*)    echo "i40iw";
	;;
        *qed*)    echo "qedr";
	;;
        *bnxt*)   echo "bnxt";
	;;
        *irdma*)   echo "irdma";
	;;
        *)        echo "";
	;;
    esac
}

##
# Checks to see if /kernel/infiniband/env_setup was run on this machine.
# Only to be used when doing manual testing, as this function will prompt
# for user interaction
# Arguments: none
##
function RQA_check_env_setup {
    source ${HOME}/.bashrc 1>/dev/null 2>&1
    source /etc/environment 1>/dev/null 2>&1
    if ! [ -z $RDMA_NETWORK ]; then
        # env_setup has run - return immediately
        return
    fi
    (
        set +x
        echo
        echo "###################################################################"
        echo "##                                                               ##"
        echo "## This test case requires /kernel/infiniband/env_setup ##"
        echo "## to run first, but it appears it has not run on this           ##"
        echo "## host yet.  Please enter a driver and network to test          ##"
        echo "## over (or leave blank for default values).                     ##"
        echo "##                                                               ##"
        echo "###################################################################"
        echo
    )

    # get user specified driver and network, then run env_setup
    read -p "Enter a driver to test over (blank for default): " _driver
    read -p "Enter a network to test over (blank for default): " _network

    RQA_pkg_install kernel-kernel-infiniband-env_setup
    cd /mnt/tests/kernel/infiniband/env_setup
    ENV_DRIVER="$_driver" ENV_NETWORK="$_network" make run
    cd - >/dev/null
}

##
# When in developer (manual) mode, a test might be executed
# multiple times. And sometimes, rhts_sync_[set,block] don't sync up as
# expected, causing test to run out of sync & fail.
# This is to always sync test's state between server/client
# Arguments: none
##
function RQA_number_of_run {

    rnum_log=$(echo $RUN_NUMBER_LOG | awk -F "/" '{print $(NF)}' | sed 's/.log//g')
    if [[ *"${s_hostname}"* == *"${SERVERS}"* ]]; then
        crnt_run_num=$(grep -m 1 "TEST_NAME=${TEST_NAME}" /mnt/testarea/*.log | wc -l)
        echo "export RUN_NUMBER=${crnt_run_num}" > ${RUN_NUMBER_LOG}
        sleep 3
        scp $RUN_NUMBER_LOG ${CLIENTS}:${RUN_NUMBER_LOG}
        if [[ $? -ne 0 ]]; then
            echo "Failed to scp $RUN_NUMBER_LOG"
            echo "Can't continue...exiting"
            exit 1
        fi

        source $RUN_NUMBER_LOG
        blk_msg="client-set-${rnum_log}-${RUN_NUMBER}"
        RQA_wait_until $CLIENTS $RUN_NUMBER_LOG $blk_msg
    elif [[ *"${s_hostname}"* == *"${CLIENTS}"* ]]; then
        # Wait for server to send client $RUN_NUMBER_LOG file
        RQA_wait_until $SERVERS $RUN_NUMBER_LOG

        source $RUN_NUMBER_LOG
        # Remove $RUN_NUMBER_LOG to avoid conflict with sync'ing
        time_extension=$(date +%H%M-%m%d%Y)
        mv $RUN_NUMBER_LOG ${RUN_NUMBER_LOG}.${time_extension}
        rhts_sync_set -s "client-set-${rnum_log}-${RUN_NUMBER}"
    fi
}

##
# Wait to get a file from the other/remote host
# Arguments: 1 = hostname of remote machine
#            2 = filename, including full path, of what is the calling host is waiting
#            3 = if called from server. rhts_sync_block_message
# Example:
#     RQA_wait_until $SERVERS /mnt/testarea/sanity_all_hca-run_number.log
#     or
#     RQA_wait_until $SERVERS /mnt/testarea/sanity_all_hca-run_number.log rhts_sync_block_message
##
function RQA_wait_until {
    local remote_host=$1
    local file_to_wait=$2
    local wait_secs=0

    if [[ ! -z $3 ]]; then
        block_msg=$3
    fi

    if [[ *"${s_hostname}"* == *"${SERVERS}"* ]]; then
        # help sync'ing since restraint just runs through if state was previously executed
        # ensure server doesn't pass this point until both client and server are in sync
        local srv_clnt_sync=1
        until (($srv_clnt_sync == 0));
        do
            ssh $CLIENTS "grep \"${block_msg}\" /var/lib/restraint/rstrnt_events"
            srv_clnt_sync=$?
            if [[ $srv_clnt_sync == 0 ]]; then
                break
            fi
            sleep 30s
            wait_secs=$((wait_secs + 30))
            # scopy $RUN_NUMBER_LOG every 2 minutes until client/server sync
            if (( $(($wait_secs % 120)) == 0 )); then
                echo "Again scopying $file_to_wait..."
                scp $file_to_wait ${CLIENTS}:${file_to_wait}
                sleep 15s
            fi
        done
    elif [[ *"${s_hostname}"* == *"${CLIENTS}"* ]]; then
        while [[ ! -f $file_to_wait ]]; do
            sleep 5
            wait_secs=$((wait_secs + 5))
            # print waiting msg every 3 minutes
            if (( $(($wait_secs % 180)) == 0 )); then
                echo "Waiting for ${remote_host} to send ${file_to_wait}. Waited for ${wait_secs} secs..."
            fi
        done

        # just to be certain that client received the correct expected file,
        # get it from server and compare
        sleep 10
        local tmp_cnt=0
        local diff_files=1
        tmp_run_log=$(mktemp)

        until (($diff_files == 0));
        do
            scp ${remote_host}:${file_to_wait} $tmp_run_log
            sleep 3s
            diff $file_to_wait $tmp_run_log
            diff_files=$?
            if [[ $diff_files == 0 ]]; then
                break
            fi
            sleep 30
            tmp_cnt=$((tmp_cnt +1))
            # Don't know but waiting for ~2hrs before exiting sounds reasonable
            if ((tmp_cnt >= 240)); then
                echo "Failed to get the correct $file_to_wait from $remote_host"
                echo "Exiting..."
                exit 1
            fi
        done
    fi
}


##
# Find the appropriate Python interpreter to use and export it as PYEXEC.
# This function is needed to support cross-compatibility of test infrastructure
# between RHEL-6/7 (python 2 distributions) and RHEL-8 (python 3 distribution
# with unusual python paths)
# Arguments :none
##
function RQA_set_pyexec {
    PYEXEC=''

    # first check if we have a python interpreter on the PATH
    if which python 1>/dev/null 2>&1; then
        export PYEXEC='python'
        return 0
    fi

    # if not, check for a python3 interpreter on the PATH
    if which python3 1>/dev/null 2>&1; then
        export PYEXEC='python3'
        return 0
    fi

    # if not, RHEL-8+ defaults to /usr/libexec/platform-python as the
    # default location for a python interpreter
    if which /usr/libexec/platform-python 1>/dev/null 2>&1; then
        export PYEXEC='/usr/libexec/platform-python'
        return 0
    fi

    # if we get here, python may not be installed; try installing various
    # pythons and searching again for a python interpreter on the PATH
    $PKGINSTALL --quiet --skip-broken python3 python2 python
    if which /usr/libexec/platform-python 1>/dev/null 2>&1; then
        PYEXEC='/usr/libexec/platform-python'
    elif which python3 1>/dev/null 2>&1; then
        PYEXEC='python3'
    elif which python2 1>/dev/null 2>&1; then
        PYEXEC='python2'
    elif which python 1>/dev/null 2>&1; then
        PYEXEC='python'
    fi

    if [ ! -z "$PYEXEC" ]; then
        # we found a python interpreter - use it
        export PYEXEC
    else
        # no python found in this distribution!
        echo "### WARNING: NO PYTHON INTERPRETER AVAILABLE ###"
        return 1
    fi
}

# determine whether to use yum or dnf
if [[ $(grep -i fedora /etc/redhat-release >/dev/null) || $(RQA_get_rhel_major) -ge 8 ]]; then
    export PKGINSTALL="dnf install -y --setopt=strict=0 --nogpgcheck"
    export PKGREMOVE="dnf remove --noautoremove -y"
else
    export PKGINSTALL="yum install -y --skip-broken --nogpgcheck"
    export PKGREMOVE="yum remove -y"
fi
