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
    echo "Managed cluster already exists."
else
    # --custom-configuration ./custom-config.json \
    echo "Managed cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --kubernetes-version 1.33.3 \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin none \
        --outbound-type managedNATGateway \
        --nat-gateway-managed-outbound-ip-count 5 \
        --aks-custom-headers OverrideControlplaneResources=W3siY29udGFpbmVyTmFtZSI6Imt1YmUtYXBpc2VydmVyIiwiY3B1TGltaXQiOiIzMCIsImNwdVJlcXVlc3QiOiIyNyIsIm1lbW9yeUxpbWl0IjoiNjRHaSIsIm1lbW9yeVJlcXVlc3QiOiI2NEdpIiwiZ29tYXhwcm9jcyI6MzB9XSAg,ControlPlaneUnderlay=hcp-underlay-eastus2-cx-382,AKSHTTPCustomFeatures=OverrideControlplaneResources,AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=$IMAGE_SUB_ID,OSImageResourceGroup=$IMAGE_RG,OSImageGallery=$IMAGE_GALLERY,OSImageName=$IMAGE_NAME,OSImageVersion=$IMAGE_VERSION
fi


for i in $(seq 1 ${USER_POOL_COUNT}); do
    USER_POOL_NAME=user${i}
    if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} &>/dev/null; then
        echo "User pool ${i} already exists. Deleting ..."
        # az aks nodepool delete \
        #     --resource-group ${RESOURCE_GROUP} \
        #     --cluster-name ${CLUSTER_NAME} \
        #     --name ${USER_POOL_NAME}
    else
        echo "User pool ${i} does not exist. Creating ..."
        az aks nodepool add \
            --resource-group ${RESOURCE_GROUP} \
            --cluster-name ${CLUSTER_NAME} \
            --name ${USER_POOL_NAME} \
            --node-vm-size ${USER_VM_SIZE} \
            --node-count ${USER_POOL_SIZE} \
            --aks-custom-headers AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=$IMAGE_SUB_ID,OSImageResourceGroup=$IMAGE_RG,OSImageGallery=$IMAGE_GALLERY,OSImageName=$IMAGE_NAME,OSImageVersion=$IMAGE_VERSION
    fi
done

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing
