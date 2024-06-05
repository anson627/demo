#!/bin/bash

set -eo pipefail

SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
LOCATION=eastus
RESOURCE_GROUP=gpu-test
CLUSTER_NAME=operator-test
GPU_POOL_NAME=gpupool
GPU_POOL_SIZE=3
GPU_VM_SIZE=Standard_NC4as_T4_v3

az account set -s $SUBSCRIPTION
az configure --defaults group=$RESOURCE_GROUP
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
        --yes
fi

if az aks nodepool show --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER_NAME --name $GPU_POOL_NAME &>/dev/null; then
    echo "GPU pool already exists."
else
    echo "GPU pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $CLUSTER_NAME \
        --name $GPU_POOL_NAME \
        --node-taints nvidia.com/gpu=present:NoSchedule \
        --node-vm-size $GPU_VM_SIZE \
        --node-count $GPU_POOL_SIZE \
        --skip-gpu-driver-install
fi

az aks get-credentials --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --overwrite-existing
