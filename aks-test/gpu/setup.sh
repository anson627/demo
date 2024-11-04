#!/bin/bash

set -eo pipefail

ACS Test with H100
SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
LOCATION=centraluseuap
USER_VM_SIZE=Standard_ND96isr_H100_v5

# Dataplane Developer with A100
# SUBSCRIPTION=8643025a-c059-4a48-85d0-d76f51d63a74
# LOCATION=southcentralus
# USER_VM_SIZE=Standard_ND96amsr_A100_v4


RESOURCE_GROUP=gpu-test
CLUSTER_NAME=gpu-test
SYSTEM_POOL_NAME=system
SYSTEM_VM_SIZE=Standard_D16s_v5
SYSTEM_POOL_SIZE=3
USER_POOL_NAME=gpu
USER_POOL_SIZE=1

az account set -s $SUBSCRIPTION
if az group show -n $RESOURCE_GROUP &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l $LOCATION -n $RESOURCE_GROUP
fi

if az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    az aks create -l $LOCATION \
        -g $RESOURCE_GROUP \
        -n $CLUSTER_NAME \
        --tier standard \
        --nodepool-name $SYSTEM_POOL_NAME \
        --node-vm-size $SYSTEM_VM_SIZE \
        --node-count $SYSTEM_POOL_SIZE \
        --yes
fi

if az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name $USER_POOL_NAME &>/dev/null; then
    echo "User pool already exists."
else
    echo "User pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $CLUSTER_NAME \
        --name $USER_POOL_NAME \
        --node-vm-size $USER_VM_SIZE \
        --node-count $USER_POOL_SIZE \
        --node-taints nvidia.com/gpu=present:NoSchedule \
        --skip-gpu-driver-install
fi

az aks get-credentials --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --overwrite-existing
