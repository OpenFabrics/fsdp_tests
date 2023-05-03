#!/usr/bin/env python
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   host_data_parser.py of /kernel/infiniband/env_setup
#   Description: Read in JSON configuration files for hosts in the
#                OFA FSDP RDMA cluster and provide the following
#                details regarding the executing host:
#                HCA_ID, HCA_RATE, HCA_ABRV, DEVICE_ID, DEVICE_MAC, DEVICE_PORT,
#                RDMA_DRIVER, RDMA_NETWORK
#   Author: Mike Stowell <mstowell@redhat.com>
#           Afom Michael <tmichael@redhat.com>
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

import sys
import json

# variables to be written by this parser
HCA_ID = ''
HCA_RATE = ''
DEVICE_ID = ''
DEVICE_MAC = ''
DEVICE_PORT = ''

# main function
def main(argv):
    try:
        # gather arguments
        if len(argv) != 4:
            exit(1)
        json_file = str(argv[1]).strip()
        driver = str(argv[2]).strip()
        network = str(argv[3]).strip()

        # parse the data json
        with open(json_file) as data_file:
            data = json.load(data_file)
        all_hcas = data['hcas']

        # set up default dictionaries
        hca_dict = None
        device_dict = None
        net_dict = None

        # loop through the HCAs on this host to find a driver and network that pair up
        for _hca in all_hcas:

            if driver and _hca['driver'] != driver:
                # user specified a driver to test over and this is not a match - skip it
                continue

            if not network:
                # user did not specify network to test over, and we either have
                # a matching driver or user did not specify driver either
                hca_dict = _hca
                driver = driver if driver else hca_dict['driver']
                device_dict = hca_dict['devices'][0]
                net_dict = device_dict['networks'][0]
                network = net_dict['net']
                break

            # the user has specified a network to test over; find a match
            for _device in _hca['devices']:
                for _net in _device['networks']:
                    if network == _net['net']:
                        # found a matching network
                        hca_dict = _hca
                        driver = driver if driver else hca_dict['driver']
                        device_dict = _device
                        net_dict = _net
                        break

        # ensure we found a valid hca, driver, device, and network
        if hca_dict is None or device_dict is None or net_dict is None or not driver or not network:
            raise ValueError('driver + network pair not found for this host')

        # gather the variables to be returned by this parser
        HCA_ABRV= hca_dict['name_short']
        HCA_ID = device_dict['hca_id']
        DEVICE_ID = net_dict['device_id']
        DEVICE_MAC = device_dict['mac']
        DEVICE_PORT = device_dict['port']
        PORT_GUID = device_dict['port_guid']

        try:
            HCA_RATE = device_dict['hca_rate']
        except KeyError:
            HCA_RATE = "Not Set"

        # give output bash can tee to a file and source
        print('export RDMA_DRIVER="' + str(driver) + '"')
        print('export RDMA_NETWORK="' + str(network) + '"')
        print('export HCA_ID="' + str(HCA_ID) + '"')
        print('export HCA_RATE="' + str(HCA_RATE) + '"')
        print('export HCA_ABRV="' + str(HCA_ABRV) + '"')
        print('export DEVICE_ID="' + str(DEVICE_ID) + '"')
        print('export DEVICE_MAC="' + str(DEVICE_MAC) + '"')
        print('export DEVICE_PORT="' + str(DEVICE_PORT) + '"')
        print('export PORT_GUID="' + str(PORT_GUID) + '"')

        exit(0)

    except ValueError as ve:
        print('Value Error caught: ')
        print(ve)
        exit(55)

    except Exception as excp:
        print(type(excp))
        print(excp)
        exit(120)

# Import safety: only invoke the main function if this script was run via the command line
# Arguments expected are:
#   1 = JSON file
#   2 = driver to test over (or empty string)
#   3 = network to test over (or empty string)
if __name__ == '__main__':
    sys.exit(main(sys.argv))
