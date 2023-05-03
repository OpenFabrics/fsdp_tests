#!/bin/bash -x
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /kernel/infiniband/env_setup
#   Description: assists in generating hcas json files for  RDMA cluster
#                test environment
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

source ./rdma-qa-functions.sh

which jq > /dev/null || yum install -y jq
which python3 > /dev/null || yum install -y python3
which dmidecode  > /dev/null || yum install -y dmidecode

hca_json=""
# hca_keys=(hca_id port port_guid transport mac driver networks)

hca_ids=$(ibstatus | awk 'match($0, /^Infiniband device ([\'a-z0-9']+) port [0-9] status:/, arr) {print arr[1], "\n"}' | sed -e "s/'//g; s/ //g; /^$/d" | uniq)

json_dir=$(mktemp -d)
hostname_fqdn=$(hostname)
host_name=$(hostname -s)
host_arch=$(uname -i)
host_vendor=$(dmidecode | awk -F ":" '/Vendor:/ {print $2}')
host_model=$(dmidecode | awk -F ":" '/Product Name: / {print $2}' | head -1)
lshw_network="$json_dir/${host_name}-lshw.log"
h_head_added=0

lshw -class network | sed "/capabilities:/d; /configuration:/d; /resources:/d; \
       /capacity:/d; /width:/d; /clock:/d; /version:/d; /physical id:/d; \
       /size:/d" > $lshw_network

(printf "{"
printf "  \"full_hostname\": \"%s\"," "$hostname_fqdn"
printf "  \"arch\": \"%s\"," "$host_arch"
printf "  \"vendor\": \"%s\"," "$host_vendor"
printf "  \"model\": \"%s\"," "$host_model"
printf "  \"hcas\": [")> "${json_dir}/${host_name}.json"

##
# This function is to populate json heading for passed HCA
# Argument: 2
# Example: hca_header_info hca_id eth_name
##
function hca_header_info {
    local _hca_header=$1
    local _eth_name="${2}"
    local _pci_bus=""

    pci_bus=$(grep -B1 "logical name: ${_eth_name}$" $lshw_network \
        | tr "\n" " " | awk '{print $3}' | sed 's/pci@//')

    if [[ -z ${pci_bus} ]]; then
        mac_w_cln=$(ip address show $_eth_name \
	    | awk '/link\/infiniband/ || /link\/ether/ {print $2}')
        pci_bus=$(grep -B6 -A5 "${mac_w_cln}" $lshw_network \
	    | awk -F "@" '/bus info:/{print $2}' | head -1)
    fi
    pci_bus=$(echo $pci_bus | awk -F ":" '{print $2":"$3}')

    if [[ ! -z $pci_bus ]]; then
        hca_desc=$(lspci -s $pci_bus | awk -F ":" '{print $(NF)}' | cut -c2-)
        dev_module=$(lspci -nv -s $pci_bus \
	    | awk -F ":" '/Kernel driver in use:/ {print $2}' | tr -d " ")
        dev_module=$(RQA_get_driver_name $dev_module)
    fi

    if [[ $hca_desc == *"Connect"* ]] || [[ $hca_desc == *"connect"* ]]; then
        hca_abrv=$(echo $hca_desc | awk -F "[" '{print $2}' | sed 's/]//')
    elif [[ $hca_desc == *"BCM"* ]]; then
        hca_abrv=$(echo $hca_desc | cut -d' ' -f5)
        if [[ $ENV_DRIVER == "rxe" || $ENV_DRIVER == "siw" ]]; then
            [[ $ENV_NETWORK == "eth" ]] && hca_abrv="lom"
            if [[ $transport == "iwarp" ]]; then
                dev_module="siw"
            elif [[ $transport == "roce" ]]; then
                dev_module="rxe"
            fi
        fi
    elif [[ $hca_desc == *"Chelsio"* ]]; then
        hca_abrv=$(echo $hca_desc | cut -d ' ' -f4)
        # for cxbg4 based SIW, set the json info for driver to siw
        [[ $ENV_DRIVER == "siw" ]] && dev_module="siw"
    elif [[ $hca_desc == *"QLogic"* ]]; then
        hca_abrv=$(echo $hca_desc | cut -d' ' -f4)
    elif [[ $hca_desc == *"HFI"* ]]; then
        hca_abrv=$(echo $hca_desc | cut -d' ' -f3)
    fi

    if [[ ! -e "${json_dir}/${_hca_header}.log" ]]; then
        (printf "  {"
        printf "\"name\": \"%s\"," "$hca_desc"
        printf "\"name_short\": \"%s\"," "$hca_abrv"
        printf "\"pci_slot\": \"%s\"," "$pci_bus"
        printf "\"driver\": \"%s\"," "$dev_module"
        printf "\"devices\": [") > "${json_dir}/${_hca_header}.log"
    fi
}

##
# This function is to populate HCA specific info for JSON file
# Argument: 5
# Example: add_to_json "mlx5_0" "1" "fe80:0000:0000:0000:bace:f6ff:fe09:66fb" "b8:ce:f6:09:66:fb" "roce"
##
function add_to_json {
    local _hca_json=""
    local _hca_id="$1"
    local _port="$2"
    local _gid="$3"
    local _mac="$4"
    local _transp="$5"
    local _per_netdevice=0
    local _bus=""

    for m in ${_mac};
    do
        local _net_dev=$(ip a s | grep -B1 $m | awk '/mtu/ {print $2}' \
		| sed 's/:$//g;s/\@.*//g' | uniq | awk '{print $1}')
        local _hca_rate=$(grep -A6 "port ${_port}" ${json_dir}/${d}-ibstatus.log \
		| awk '/rate:/ {print $2}')
        for _eth in $_net_dev;
        do
            _net_name="${_eth#*_}"
            _vlan=$(echo $_net_name | awk -F "." '{print $2}')
            if [[ ! -z "$_vlan" ]]; then
                local f=$(echo "${_net_name:${#_net_name}<2?0: -2}")
                local s=$(echo "${_net_name:${#_net_name}<1?0: -1}")
                if [[ $(echo $((f - s ))) -eq 0 ]]; then
                    local _xtra_net_name="$s"
                else
                    local _xtra_net_name="${f}"
                fi
                _net_name=$(echo $_net_name | sed "s/[.].*$/.${_xtra_net_name}/g")
            fi

            local _ip_add=$(grep "${_net_name}-${host_name}" /etc/hosts | awk '{print $1}')
            if [[ $_per_netdevice == 0 ]]; then
	        if [[ $_port -eq 1 ]]; then
                    hca_header_info "$_hca_id" "$_eth"
		fi
                _hca_json="{\"hca_id\":\"${_hca_id}\", \"port\":\"${_port}\",\
		       \"hca_rate\":\"${_hca_rate}\", \"port_guid\":\"${_gid}\",\
		       \"transport\":\"${_transp}\", \"mac\":\"${_mac}\",\
		       \"networks\" : [ {\"net\":\"${_net_name}\",\
		       \"ip\":\"${_ip_add}\",\
		       \"device_id\":\"${_eth}\"}"
	        _net_part=""
            else
		if [[ ! -z ${_net_part} ]]; then
                    _net_part="${_net_part},{\"net\":\"${_net_name}\",\
		           \"ip\":\"${_ip_add}\",\
			   \"device_id\":\"${_eth}\"}"
		else
                    _net_part=",{\"net\":\"${_net_name}\",\
		           \"ip\":\"${_ip_add}\",\
	                   \"device_id\":\"${_eth}\"}"
		fi
            fi
            _per_netdevice=$((_per_netdevice + 1))
        done
        echo ${_hca_json} ${_net_part} >> ${json_dir}/${_hca_id}.log
	_num_hca_mport=$(rdma link | grep "$_hca_id/" | wc -l)
	if [[ $_port -eq $_num_hca_mport ]]; then
	    printf "]}]\n}," >> ${json_dir}/${_hca_id}.log
	    cat ${json_dir}/${_hca_id}.log >> ${json_dir}/${host_name}.json
	else
            printf "]\n}," >> ${json_dir}/${_hca_id}.log
	fi
    done
}

for d in ${hca_ids};
do
    ibstatus $d > ${json_dir}/${d}-ibstatus.log
    hca_link_layer=$(awk '/link_layer/ {print $2}' ${json_dir}/${d}-ibstatus.log \
	    | sed 's/ //g')
    hca_gid=$(awk '/default gid/ {print $3}' ${json_dir}/${d}-ibstatus.log)
    for gid in ${hca_gid}; do
        hca_port=$(grep -B1 "$gid" ${json_dir}/${d}-ibstatus.log \
		| awk -F "'" '/port / {print $3}' | awk '{print $2}')
        _gid2mac=$(echo $gid | sed 's/://g;s/.\{2\}/&:/g;s/:$//')
        if [[ $hca_link_layer == *"InfiniBand"* ]]; then
            transp="infiniband"
            mac=${_gid2mac}
	    if [[ $d == *"opa"* || $d == *"hfi"* ]]; then
                transp="opa"
	    fi
        elif [[ $hca_link_layer == *"Ethernet"* ]]; then
            transport=$(ibv_devinfo -d $d | awk -F ":" '/transport/ {print $2}')
            if [[ $transport == *"InfiniBand"* ]]; then
		transp="roce"
                mac1=$(echo $_gid2mac \
			| awk -F ":" '{print $10 ":" $11 ":" $14 ":" $15 ":" $16}')
            elif [[ $transport == *"iWARP"* ]]; then
		transp="iw"
                _gid_tmp=$(echo $gid | sed 's/:0000//g;s/ff:fe//g;s/://g')
                _gid_len=${#_gid_tmp}
                _gid2mac=$(echo $_gid_tmp | sed 's/.\{2\}/&:/g;s/:$//')
                if ((_gid_len == 16)); then
                    mac1=$(echo $_gid2mac \
			   | awk -F ":" '{print "00:" $4 ":" $5 ":" $6 ":" $7 ":" $8}')
                elif ((_gid_len == 12)); then
                    mac1=${_gid2mac}
                fi
            fi
            mac=$(ip a s | grep $mac1 | awk '{print $2}' | uniq)
        fi

        add_to_json "$d" "$hca_port" "$gid" "${mac}" "${transp}"
    done
done

# for last HCA in the list, remove ","  from last line & append closing brackets
sed -i '$ s/,/\n\t]\n}/g' ${json_dir}/${host_name}.json

[[ ! -d ./json ]] && mkdir -p ./json
jq '.' ${json_dir}/${host_name}.json > ./json/${host_name}.json
__json_status=$?
RQA_check_result -r $__json_status -t "Generated JSON"

rm -fr "${json_dir}"

exit $__json_status
