#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}
if az group show -n ${RESOURCE_GROUP} &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l ${LOCATION} -n ${RESOURCE_GROUP} --tags SkipAKSCluster=1 SkipASB_Audit=true
fi

if az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --kubernetes-version 1.34.0 \
        --network-plugin none \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE}
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name user &>/dev/null; then
    echo "User pool already exists."
else
  # --localdns-config ./localdnsconfig.json \
  az aks nodepool add \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name $CLUSTER_NAME \
    --name user \
    --node-vm-size ${USER_VM_SIZE} \
    --node-count ${USER_POOL_SIZE}
 fi

 az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing
