#!/bin/bash

set -eo pipefail

SUBSCRIPTION=137f0351-8235-42a6-ac7a-6b46be2d21c7
RESOURCE_GROUP=cri-test
LOCATION=eastus2
CLUSTER_NAME=cri-test
SYSTEM_POOL_NAME=system
SYSTEM_VM_SIZE=Standard_D8ds_v5
SYSTEM_POOL_SIZE=3
USER_POOL_NAME=user
USER_VM_SIZE=Standard_D8ds_v5
USER_POOL_SIZE=1

az account set -s ${SUBSCRIPTION}
if az group show -n ${RESOURCE_GROUP} &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l ${LOCATION} -n ${RESOURCE_GROUP}
fi

if az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} &>/dev/null; then
    echo "Managed cluster already exists."
else
    echo "Managed cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --nodepool-name ${SYSTEM_POOL_NAME} \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --node-osdisk-type Ephemeral \
        --network-plugin azure \
        --network-plugin-mode overlay
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool already exists."
else
    echo "User pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --name ${USER_POOL_NAME} \
        --node-vm-size ${USER_VM_SIZE} \
        --node-count ${USER_POOL_SIZE} \
        --node-osdisk-type Ephemeral
fi

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing
