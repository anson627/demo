#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}
if az group show -n ${RESOURCE_GROUP} &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l ${LOCATION} -n ${RESOURCE_GROUP} --tags SkipAKSCluster=1 SkipASB_Audit=true SkipLinuxAzSecPack=true exempted_by_qi=36250079
fi

if az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --kubernetes-version 1.34.2 \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin azure
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name cpu &>/dev/null; then
    echo "CPU pool already exists."
else
    echo "CPU pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --name cpu \
        --node-vm-size Standard_D16_v3 \
        --node-count 0
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name gpu &>/dev/null; then
    echo "GPU pool already exists."
else
    # --aks-custom-headers "AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=${IMAGE_SUB_ID},OSImageResourceGroup=${IMAGE_RG},OSImageGallery=${IMAGE_GALLERY},OSImageName=${IMAGE_NAME},OSImageVersion=${IMAGE_VERSION}" \
    echo "GPU pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --name gpu \
        --node-vm-size ${USER_VM_SIZE} \
        --node-count 0 \
        --node-osdisk-type Managed \
        --os-sku Ubuntu2404 \
        --gpu-driver none
fi

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --admin \
    --overwrite-existing
