#!/bin/bash -x
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   host_data_parser.sh of /kernel/infiniband/env_setup
#   Description: Read in JSON configuration files for hosts in the
#                OFA FSDP RDMA cluster and provide the following
#                details regarding the executing host:
#                HCA_ID, HCA_RATE, HCA_ABRV, DEVICE_ID, DEVICE_MAC, DEVICE_PORT,
#                RDMA_DRIVER, RDMA_NETWORK
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

_tmp_dir="$(mktemp -d)"
_tmpof="${_tmp_dir}/output.json"

source rdma-qa-functions.sh

if [[ ! -z $2 && "$2" == *"DRIVER"* ]]; then
    ENV_DRIVER=$(echo $2 | awk -F "=" '{print $2}')
elif [[ ! -z $3 && "$3" == *"DRIVER"* ]]; then
    ENV_DRIVER=$(echo $3 | awk -F "=" '{print $2}')
fi

if [[ ! -z $2 && "$2" == *"NETWORK"* ]]; then
    ENV_NETWORK=$(echo $2 | awk -F "=" '{print $2}')
elif [[ ! -z $3 && "$3" == *"NETWORK"* ]]; then
    ENV_NETWORK=$(echo $3 | awk -F "=" '{print $2}')
fi

ENV_DRIVER=$(RQA_get_driver_name $ENV_DRIVER)
export ENV_DRIVER="$ENV_DRIVER"
export ENV_NETWORK="$ENV_NETWORK"

if [[ -z $host_json ]]; then
    test_base="$(pwd)"
    s_hostname=$(hostname -s)
    host_json="${test_base}/json/${s_hostname}.json"
fi

function export_vars {
    local _exp_vars="$1"
    local _psd_json="$_tmpof"
    jq -r ". | {${_exp_vars}} | to_entries | .[] | .key + \"=\" + (.value)" ${_psd_json}
}

function get_matched_dict {
    local _head_var="$1"
    local _json_sel="$2"

    if [[ $_head_var == "hcas" ]]; then
        _json_file=${host_json}
        if [[ $_ck_drvr_in_json == 1 ]]; then
            local _xtra_json_args=""
	    _ck_drvr_in_json=0
        else
            local _xtra_json_args="| select(.net==\"$ENV_NETWORK\")"
        fi
    else
        _json_file="${_tmpof}.in"
        local _xtra_json_args="| select(.net==\"$ENV_NETWORK\")"
	cp $_tmpof $_json_file
    fi


    local _json_len=$(jq -r ".${_head_var} | length" $_json_file)

    ((_json_len=_json_len -1))
    for i in $(seq 0 ${_json_len});
    do
        len=$(jq -r ".$_head_var[$i] | ${_json_sel} ${_xtra_json_args} | length" $_json_file)
        if [[ $len -gt 0 ]]; then
	    break
        elif [[ $i -eq ${_json_len} && $len -eq 0 ]]; then
	    exit 1
        fi
    done
    jq  -r ".$_head_var[$i]" $_json_file > $_tmpof
}

# The order of the following lines is important
# because of the way JSON files are structured
# get array of hcas, followed by devices, & then networks
_ck_drvr_in_json=1

# get hcas dictionary/array from host JSON file
# let's make sure desired ENV_DRIVER is in json. If not, exit
get_matched_dict "hcas" "select(.driver==\"$ENV_DRIVER\")" > ${_tmpof}.log

# for the given ENV_DRIVER + ENV_NETWORK, get hcas dictionary/array from host JSON file
get_matched_dict "hcas" "select(.driver==\"$ENV_DRIVER\") | .devices[] |.networks[]" >> ${_tmpof}.log
export_vars "driver, name_short" >> ${_tmpof}.log

# get devices dictionary/array
get_matched_dict "devices" ".networks[]" "${_tmpof}.in" >> ${_tmpof}.log
export_vars "hca_id, port, hca_rate, port_guid, mac" >> ${_tmpof}.log

# get networks dictionary/array
get_matched_dict "networks" "{net, device_id}" "${_tmpof}.in" >> ${_tmpof}.log
export_vars "net, ip, device_id" >> ${_tmpof}.log

sed -i "s/driver=/export RDMA_DRIVER=\"/g; \
	s/net=/export RDMA_NETWORK=\"/g; \
	s/hca_id=/export HCA_ID=\"/g; \
	s/hca_rate=/export HCA_RATE=\"/g; \
	s/name_short=/export HCA_ABRV=\"/g; \
	s/device_id=/export DEVICE_ID=\"/g; \
	s/mac=/export DEVICE_MAC=\"/g; \
	s/port=/export DEVICE_PORT=\"/g; \
	s/ip=/export RDMA_IPV4=\"/g; \
	s/port_guid=/export PORT_GUID=\"/g; s/$/\"/;" ${_tmpof}.log

cat ${_tmpof}.log

[[ ! -z ${_tmp_dir} ]] && rm -fr "${_tmp_dir}"

exit 0
