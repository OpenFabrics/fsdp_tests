#!/bin/bash
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   clean_env.sh of /kernel/infiniband/env_setup
#   Description: prepare RDMA cluster test environment
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
trap 'exit 1' SIGHUP SIGINT SIGQUIT SIGTERM

###########################################################################
# In the case where the user is running this manually, (s)he may wish     #
# to run the env_setup again with a new driver and/or network variable    #
# set.  In order to do so however, the user must first clean the previous #
# environment set by this task.  Simply sourcing this script will do so.  #
#                                                                         #
#                               IMPORTANT                                 #
# You must *SOURCE*, not *RUN* this script to clean your environment!!!   #
# The reason for this is because running the script as `./clean_env.sh`   #
# will start a child process to unset all environment variables; once it  #
# returns control to your parent shell, the environment variables will    #
# still be set.  Executing `source clean_env.sh` however will run the     #
# commands in your parent shell and do exactly as the script is intended  #
# to do.  As a result, this script intentionally has no executable        #
# permission bits set to remind you that you must source it to clean the  #
# environment variables.
###########################################################################

BASHRC_FILE="${HOME}/.bashrc"

# make sure the user isn't accidentally running this
while true; do
    read -p "Are you sure you want to clean env_setup's previous run [y/n]? " yn
    case $yn in
        [Yy]*)
            # user wants to run the cleanup, so proceed
            break;;
        [Nn]*)
            # user decided not to run the cleanup - exit immediately
            return 0
            break;;
        *) echo "Please answer yes or no [y/n]: ";;
    esac
done

# create a backup
echo "Creating bashrc backup at ${BASHRC_FILE}.bak ..."
cp ${BASHRC_FILE} ${BASHRC_FILE}.bak
echo "... complete." && echo

# remove all env_setup .bashrc entries
echo "Wiping env_setup entries from ${BASHRC_FILE} ..."
sed -i '/env_setup variables/d' $BASHRC_FILE
sed -i '/export RDMA_DRIVER/d' $BASHRC_FILE
sed -i '/export RDMA_NETWORK/d' $BASHRC_FILE
sed -i '/export HCA_ID/d' $BASHRC_FILE
sed -i '/export HCA_RATE/d' $BASHRC_FILE
sed -i '/export HCA_ABRV/d' $BASHRC_FILE
sed -i '/export DEVICE_ID/d' $BASHRC_FILE
sed -i '/export DEVICE_MAC/d' $BASHRC_FILE
sed -i '/export DEVICE_PORT/d' $BASHRC_FILE
sed -i '/export PORT_GUID/d' $BASHRC_FILE
sed -i '/export RDMA_IPV4/d' $BASHRC_FILE
sed -i '/export RDMA_IPV6/d' $BASHRC_FILE
sed -i '/export CLIENT_DRIVER/d' $BASHRC_FILE
sed -i '/export CLIENT_NETWORK/d' $BASHRC_FILE
sed -i '/export CLIENT_HCA_ID/d' $BASHRC_FILE
sed -i '/export CLIENT_HCA_RATE/d' $BASHRC_FILE
sed -i '/export CLIENT_HCA_ABRV/d' $BASHRC_FILE
sed -i '/export CLIENT_DEVICE_ID/d' $BASHRC_FILE
sed -i '/export CLIENT_DEVICE_MAC/d' $BASHRC_FILE
sed -i '/export CLIENT_DEVICE_PORT/d' $BASHRC_FILE
sed -i '/export CLIENT_PORT_GUID/d' $BASHRC_FILE
sed -i '/export CLIENT_IPV4/d' $BASHRC_FILE
sed -i '/export CLIENT_IPV6/d' $BASHRC_FILE
sed -i '/export SERVER_DRIVER/d' $BASHRC_FILE
sed -i '/export SERVER_NETWORK=/d' $BASHRC_FILE
sed -i '/export SERVER_HCA_ID/d' $BASHRC_FILE
sed -i '/export SERVER_HCA_RATE/d' $BASHRC_FILE
sed -i '/export SERVER_HCA_ABRV/d' $BASHRC_FILE
sed -i '/export SERVER_DEVICE_ID/d' $BASHRC_FILE
sed -i '/export SERVER_DEVICE_MAC=/d' $BASHRC_FILE
sed -i '/export SERVER_DEVICE_PORT/d' $BASHRC_FILE
sed -i '/export SERVER_PORT_GUID/d' $BASHRC_FILE
sed -i '/export SERVER_IPV4/d' $BASHRC_FILE
sed -i '/export SERVER_IPV6/d' $BASHRC_FILE
sed -i '/export REMOTE_HOST/d' $BASHRC_FILE
echo "... complete." && echo

# source the updated .bashrc
echo "Sourcing the clean ${BASHRC_FILE} ..."
source $BASHRC_FILE
echo "... complete." && echo

# unset all env_setup variables
echo "Unsetting all env_setup variables ..."
unset RDMA_DRIVER RDMA_NETWORK HCA_ID HCA_RATE HCA_ABRV DEVICE_ID DEVICE_MAC DEVICE_PORT
unset RDMA_IPV4 RDMA_IPV6 CLIENT_DRIVER CLIENT_NETWORK CLIENT_HCA_ID
unset CLIENT_HCA_ABRV CLIENT_DEVICE_ID CLIENT_DEVICE_MAC CLIENT_DEVICE_PORT
unset CLIENT_IPV4 CLIENT_IPV6 SERVER_DRIVER SERVER_NETWORK
unset SERVER_HCA_ID SERVER_HCA_ABRV SERVER_DEVICE_ID SERVER_DEVICE_MAC SERVER_HCA_RATE
unset SERVER_DEVICE_PORT SERVER_IPV4 SERVER_IPV6 REMOTE_HOST
echo "... complete." && echo
