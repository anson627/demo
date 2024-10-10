#!/bin/bash

set -eo pipefail

SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
LOCATION=centraluseuap
RESOURCE_GROUP=gpu-test
CLUSTER_NAME=gpu-test
SYSTEM_POOL_NAME=system
SYSTEM_VM_SIZE=Standard_D8s_v5
SYSTEM_POOL_SIZE=3
USER_POOL_NAME=gpu
USER_POOL_SIZE=2
USER_VM_SIZE=Standard_ND96isr_H100_v5

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
        --nodepool-name $SYSTEM_POOL_NAME \
        --node-vm-size Standard_D8s_v5 \
        --node-count 3 \
        --tier standard \
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
        --node-taints nvidia.com/gpu=present:NoSchedule
        --skip-gpu-driver-install
fi

az aks get-credentials --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --overwrite-existing
