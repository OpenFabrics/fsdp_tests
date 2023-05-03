#!/bin/bash -x
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   env_setup_functions.sh of /kernel/infiniband/env_setup
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

trap "rm -f /mnt/testarea/env_setup-run_number.log; exit 1" SIGHUP SIGINT SIGQUIT SIGTERM

# install wget
which wget || yum -y install wget

# Source the common test script helpers
source /usr/bin/rhts_environment.sh
source rdma-qa-functions.sh

RQA_pkg_install dmidecode lshw environment-modules

##
# get ssh key from other nodes and append it to authorized_keys
##
function get_ssh_pubkey {
    local __passed_host=$1
    for m in ${__passed_host}; do
        pushd /root/.ssh
        if ! grep $m authorized_keys; then
            echo "Adding ssh key for ${m}..."
            tftp -4 $m -c get ${m}.pub
            cat ${m}.pub >> authorized_keys
            rm -f ${m}.pub
        fi
        if ! grep $m known_hosts; then
            ssh-keyscan -t ecdsa $m >> known_hosts
        fi
        popd
    done
}

##
# get ssh key from other nodes and append it to authorized_keys
##
function tftp_service_sync {
    local __local_hst=$1
    local __remote_hst=$2

    # this function is expected to be run early in env_setup where RUN_NUMBER is not yet defined
    # so let's use a 999 as temp workaround
    local __RUN_NUMBER=999

    grep -q "$__remote_hst" /root/.ssh/authorized_keys
    if [[ $? -eq 0 ]]; then
        return
    else
        # start tftp service
        # but wont stop it since that will require sync'ing between machines
        local tftpservice="tftp.service"
        RQA_sys_service enable $tftpservice
        RQA_sys_service restart $tftpservice
    fi

    # Share ssh key
    if [[ $__local_hst == ${CLIENTS%%} ]]; then
        rhts_sync_block -s "tftp_service-server-ready-${__RUN_NUMBER}" ${SERVERS}
        rhts_sync_set -s "tftp_service-client-ready-${__RUN_NUMBER}"
    elif [[ $__local_hst == ${SERVERS%%} ]]; then
        rhts_sync_set -s "tftp_service-server-ready-${__RUN_NUMBER}"
        rhts_sync_block -s "tftp_service-client-ready-${__RUN_NUMBER}" ${CLIENTS}
    fi

    get_ssh_pubkey "${__remote_hst}"
}

##
# This function gets IB/HFI device HCA ID
# by converting input MAC in GID notation to
# IB default GID. The IB interface MAC is of
# the following format:
# 1. default GID - 0011:2233:4455:6677:8899:aabb:ccdd:eeff [ x - all 0s ]
# 2. INTF MAC    - 80:00:00:xx:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff [ from above default GID ]
# MAC in GID notation : 0011:2233:4455:6677:8899:aabb:ccdd:eeff
# Input - MAC without ":"
# Output - HCA_ID of IB device
##
function get_ib_HCA_ID_from_MAC() {
	local _dev_mac=$1
	local _hca_id=""

	# truncate the first 4 bytes from the MAC to be of
	# default gid form
	_dev_mac=${_dev_mac:8}
	local _mac_in_gid_form=$(get_mac_in_gid_form $_dev_mac)

	# get the output of "ibstatus" which info matches last 16 bytes
	# of IB INTF MAC
	local _dev_info=$(ibstatus | grep -B1 -A7 "${_mac_in_gid_form}")

	# if no matching device info found from the "ibstatus" output
	# just return
	if [[ -n $_dev_info ]]; then
		# extract out the "default gid"
		_defgid=$(echo $_dev_info | awk 'match($0, /default gid: ([a-z0-9:]+)/, arr) {print arr[1]}')
		# extract the HCA ID from the matched "ibstatus" output
		_hca_id=$(echo $_dev_info | awk 'match($0, /^Infiniband device ([\'a-z0-9']+) port [0-9] status:/, arr) {print arr[1], "\n"}' | sed -e "s/'//g;s/ //g")
	fi
	echo "$_hca_id,$_defgid"
	return
}

##
# This function gets IWARP device HCA ID
# by converting input MAC in GID notation to
# IWARP default GID. The IWARP interface MAC is of
# the following format:
# 1. default GID - 0011:2233:4455:xxxx:xxxx:xxxx:xxxx:xxxx [ x - all 0s ]
# 2. INTF MAC    - 00:11:22:33:44:55 [ from above default GID ]
# MAC in GID notation : 0011:2233:4455
# Input - MAC without ":"
# Output - HCA_ID of IWARP device
##
function get_iw_HCA_ID_from_MAC() {
	local _dev_mac=$1
	local _hca_id=""

	# extend the mac with 0s for the size of default gid
	_dev_mac+="00000000000000000000"
	local _mac_in_gid_form=$(get_mac_in_gid_form $_dev_mac)

	# get the output of "ibstatus" which info matches first 6 bytes
	# of IW INTF MAC
	local _dev_info=$(ibstatus | grep -B1 -A7 "${_mac_in_gid_form}")

	# if no matching device info found from the "ibstatus" output
	# just return
	if [[ -n $_dev_info ]]; then
		# extract out the "default gid"
		_defgid=$(echo $_dev_info | awk 'match($0, /default gid: ([a-z0-9:]+)/, arr) {print arr[1]}' | sed -e "s/://g")
		defgid_tmp=$(echo $_dev_info | awk 'match($0, /default gid: ([a-z0-9:]+)/, arr) {print arr[1]}')

		# extract the HCA ID from the matched "ibstatus" output
		_hca_id=$(echo $_dev_info | awk 'match($0, /^Infiniband device ([\'a-z0-9']+) port [0-9] status:/, arr) {print arr[1], "\n"}' | sed -e "s/'//g;s/ //g")
	fi

	echo "${_hca_id},${defgid_tmp}"
	return
}

##
# This function gets ROCE device HCA ID
# by converting input MAC in GID notation to
# ROCE default GID. The ROCE interface MAC is of
# the following format:
# 1. default GID - FE80:2233:4455:6677:8899:aaFF:EEdd:eeff
# 2. INTF MAC    - 00:99:aa:dd:ee:ff [ from above default GID ]
# MAC in GID notation : 0099:aadd:eeff
# Input - MAC without ":"
# Output - HCA_ID of ROCE device
##
function get_roce_HCA_ID_from_MAC() {
	local _hca_id=""
	local _dev_mac=$1
	local _mac_in_gid_form=$(get_mac_in_gid_form $_dev_mac)

	##
	# get the output of "ibstatus" which info matches the last 3 bytes
	# of ROCE INTF MAC
	# on rdma-perf-00, the last 3 bytes are the same for IB & RoCE devices
	# so trying a hack with additional charactes
	# but not sure if ff:fe is a standard in RoCE
	##
	# local _dev_info=$(ibstatus | grep -B1 -A7 "${_mac_in_gid_form:(-7)}")
	local _dev_info=$(ibstatus | grep -B1 -A7 "${_mac_in_gid_form:(-12):5}ff:fe${_mac_in_gid_form:(-7)}")

	# if no matching device info found from the "ibstatus" output
	# just return
	if [[ -n $_dev_info ]]; then
		# extract out the "default gid" without the ":"
		# _dev_mac is also MAC without ":"
		_defgid=$(echo $_dev_info | awk 'match($0, /default gid: ([a-z0-9:]+)/, arr) {print arr[1]}' | sed -e "s/://g")
		defgid_tmp=$(echo $_dev_info | awk 'match($0, /default gid: ([a-z0-9:]+)/, arr) {print arr[1]}')

		# make sure the first 3 bytes of INTF MAC also are included in
		# the "default gid"
		local _pos=2
		local _len=4
		[[ "${_dev_mac:_pos:_len}" != "${_defgid:(-14):(-10)}" ]] && return

		# extract the HCA ID from the matched "ibstatus" output
		local _hca_id=$(echo $_dev_info | awk 'match($0, /^Infiniband device ([\'a-z0-9']+) port [0-9] status:/, arr) {print arr[1], "\n"}' | sed -e "s/'//g;s/ //g")
		_hca_id=$(ibstatus | grep -B1 $defgid_tmp | awk '/Infiniband device/ {print $3}'| sed -e "s/'//g;s/ //g")
	fi

	echo "$_hca_id,$defgid_tmp"
	return
}

##
# This function converts MAC to GID notation
# ":" in every two bytes
# input:
#   MAC without any ":"
# output:
#   MAC in GID notation with ":" in every two-bytes
##
function get_mac_in_gid_form() {
	local _mac=$1
	local _pos=0
	local _item_sz=4
	local _mac_str_len=${#_mac}

	_mac_in_gid_form=""
	while ((_pos < $_mac_str_len )); do
		_mac_in_gid_form+="${_mac:_pos:_item_sz}:"
		_pos=$(( _pos + _item_sz ))
	done
	echo ${_mac_in_gid_form%:}
}

##
# This function would derive the RDMA device of
# DUT/UUT (device under test). It used the MAC
# of the interface MAC from the host's JSON file
# based on ENV_NETWORK and ENV_DRIVER - out of
# host_data_parser.py
# This function should be invoked after host_data_parser.py
##
function get_HCA_ID_from_MAC() {
	local _hca_id=""
	local _dev_mac=$(echo $DEVICE_MAC | sed -e "s/://g")

	if [[ $RDMA_NETWORK == "roce"* ]]; then
		_hca_id=$(get_roce_HCA_ID_from_MAC "${_dev_mac}")
	elif [[ $RDMA_NETWORK == "iw" ]]; then
		_hca_id=$(get_iw_HCA_ID_from_MAC "${_dev_mac}")
	else
		_hca_id=$(get_ib_HCA_ID_from_MAC "${_dev_mac}")
	fi
	echo $_hca_id
	return
}

##
# This function populate_json is to dynamically populate host's json file
# with host & RDMA HCA relevant information
# two arguments:
#     argument #1 is network device name
#     argument #2 is a temporary json file per HCA
##
function populate_json {

	local passed_dev="$1"
	local temp_json="$2"
	local all_netdev=""
	local filtered_netdevs=""

	if [[ "${passed_dev}" == *"roce"* ]]; then
		passed_dev=$(echo $passed_dev | sed -e 's/.45//g;s/.43//g')
	fi

	filtered_netdevs=$(ip addr | \
		          # sed -r -n 's/^[[:digit:]]+\:\s+([a-z0-9_.]+@?.*)\:\s+.*LOWER_UP.*\s+state UP.*/\1/p' | \
		           sed -r -n 's/^[[:digit:]]+\:\s+([a-z0-9_.]+@?.*)\:\s+.*UP.*\s+state .*/\1/p' | \
			   grep $passed_dev | \
			   sed -r -n 's/^([a-z0-9_.]+)@?.*/\1/p')
	for netdev in $filtered_netdevs; do
            [[ -n $(ip addr show dev $netdev | grep "172.31.") ]] && all_netdev+="$netdev "
        done

	# For BNXT ROCE ethernet based SIW, no sub/vlan interfaces will be allowed
	if [[ $passed_dev == *"roce"* && $ENV_DRIVER == "siw" ]]; then
		all_netdev=$(echo $all_netdev | awk -F ' ' '{print $1}')
	fi

	dev_count=$(echo ${all_netdev}| wc -w)
	i=$dev_count

	for n in ${all_netdev};
	do
		# Sometimes, devices are in mlx5_bond_roce, mlx5_bond_ro.43, & mlx5_bond_ro.45
		# and we need to convert 'bond' to 'roce' for net_type
		# otherwise, the _middle_ string can be used as type
		if [[ $n == *"bond_ro"* || $n == *"team_ro"* ]]; then
			net_type=$(echo $n | cut -d"_" -f2| sed 's/bond/roce/g;s/team/roce/g')
		elif [[ $n == "lom_2" ]]; then
			# Case for LOM RXE / SIW
			[[ $ENV_NETWORK != "eth" ]] && continue
			net_type="eth"
		elif [[ $ENV_DRIVER == "siw" ]]; then
			# Case for CXGB4 or BNXT SIW
			net_type="iw"
		else
			net_type=$(echo $n | cut -d"_" -f2)
		fi
		mac_address=$(ip address show $n | awk '/link\// {print $2}')
		vlan_dev=$(echo $n | awk -F "." '{print $2}')
		if [[ ! -z $vlan_dev ]]; then
			if [[ $net_type != *"roce"* && $net_type != *"iw"* ]]; then
				vlan_sub_id=$(echo ${vlan_dev} | sed 's/^[0-9]0*//')
				net_type=$(echo $net_type | cut -d"." -f1)
				net_type="${net_type}.${vlan_sub_id}"
			elif [[ $net_type == *"roce"* && ($n == *"bond_ro"* || $n == *"team_ro"* ||  "${n}" == *"bnxt"*) ]]; then
				net_type="${net_type}.${vlan_dev}"
			fi
		fi
		(
		if [[ $i -eq $dev_count ]]; then
			printf "\n\t\t\"networks\": [\n"
			printf "\t\t{"
		fi
		printf "\n\t\t\t\"net\" : \"%s\",\n" "$net_type"
		printf "\t\t\t\"device_id\": \"%s\"\n" "$n"
		if [[ $i -gt 1 ]]; then
			printf "\t\t\t}, \n\t\t\t{"
		else
			printf "\t\t}\n"
			printf "\t\t],\n"
			printf "\t\t\"mac\" : \"%s\"" "$mac_address"
		fi
		) >> ${temp_json}
		i=$((i-1))
	done
}

##
# This function makes sure all Active HCAs are configured with IPs"
##
function rdma_hcas_network_up {
	local _netcfg_devs=$(ls /etc/sysconfig/network-scripts/ifcfg-* | \
		awk -F "-" '/_ib*/ || /_roce*/ || /_opa*/ || /_iw*/ {print $(NF)}')
	for dev in $_netcfg_devs; do
		ipv4=$(ip address show $dev | awk '/inet / {print $2}' | sed 's/\/.*//g')
		# if device doesn't have IP address
		if [[ -z $ipv4 ]]; then
			# Eventually use RQA_bring_up_network <network> <driver>
			# but for now, just try to bring it up
			ifup $dev
			sleep 4
		fi
	done
}

##
# This function adds siw device
##
function eth_nic_siw_setup {

    echo "Setting up for SoftiWARP for Ethernet NIC"
    lsmod | grep "iw_*"
    modprobe siw
    sleep 3

    if lsmod | grep iw_cxgb4 > /dev/null; then
      echo "removing iw_cxgb4 for siw"
      rmmod iw_cxgb4
      sleep 3
    fi
    rdma link add siw-lom type siw netdev lom_2
    if ip addr show lom_2 | grep "inet " >/dev/null; then
        echo "lom_2 ip adress found"
    else
        ip addr add $siw_netwk_addr.$siw_host_addr dev $siw_intf
        echo "configuring $siw_intf ip address $siw_netwk_addr.$siw_host_addr "
    fi
    ibv_devices
    ibv_devinfo
}

##
# This function adds siw device on bnxt_re device
##
function bnxt_siw_setup {
    echo "Setting up for SoftiWARP for BNXT client"
    modprobe siw
    rmmod bnxt_re
    rdma link add siw-bnxt type siw netdev bnxt_roce
    ibv_devices
    ibv_devinfo
}

##
# This function adds siw device on Chelsio
##
function chelsio_siw_setup {
    echo "Setting up for SoftiWARP for Chelsio client"
    modprobe siw
    rmmod iw_cxgb4
    rdma link add siw-cxgb4 type siw netdev cxgb4_iw
    ibv_devices
    ibv_devinfo
}

##
# This function is to run rdma-setup.sh when
# /var/lib/tftpboot/(hostname -s).pub doesn't exist
##
function run_rdma_setup {
    # rdma-setup.sh executes Setup_Ssh & it creates ssh pub key
    # this function is to be called when this key doesn't exist
    # so execute it & reboot
    if [[ ! -e /root/fsdp_setup/rdma-setup.sh ]]; then
        cd /root/
        git clone https://github.com/OpenFabrics/fsdp_setup.git
        chmod +x /root/fsdp_setup/rdma-setup.sh
    fi

    bash /root/fsdp_setup/rdma-setup.sh 2>&1 > /root/fsdp_setup/rdma-setup.log
    /usr/bin/rhts-reboot
}
