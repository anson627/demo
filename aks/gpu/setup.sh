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
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin azure
fi


if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name user &>/dev/null; then
    echo "User pool already exists."
else
    echo "User pool does not exist. Creating ..."
    # --tags "TipNode.SessionId=${TIP_SESSION_ID}" \
    # --aks-custom-headers "AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=${IMAGE_SUB_ID},OSImageResourceGroup=${IMAGE_RG},OSImageGallery=${IMAGE_GALLERY},OSImageName=${IMAGE_NAME},OSImageVersion=${IMAGE_VERSION}" \
     az aks nodepool add \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --name user \
        --node-vm-size ${USER_VM_SIZE} \
        --node-count ${USER_POOL_SIZE} \
        --gpu-driver none
fi

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing


# helm upgrade gpu-operator nvidia/gpu-operator --reuse-values --set devicePlugin.enabled=false -n gpu-operator

# helm install dra-driver nvidia/nvidia-dra-driver-gpu \
#     --version=25.8.0 \
#     --create-namespace \
#     --namespace dra-driver \
#     -f dra/values.yaml