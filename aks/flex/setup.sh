#!/bin/bash

set -euo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}
if az group show -n "${RESOURCE_GROUP}" &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l "${LOCATION}" -n "${RESOURCE_GROUP}" --tags SkipAKSCluster=1 SkipASB_Audit=true SkipLinuxAzSecPack=true
fi

if az aks show -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    MY_USER_ID=$(az ad signed-in-user show --query id -o tsv)
    #    --enable-azure-rbac \
    az aks create -l "${LOCATION}" \
        -g "${RESOURCE_GROUP}" \
        -n "${CLUSTER_NAME}" \
        --tier standard \
        --kubernetes-version 1.34.1 \
        --enable-aad \
        --aad-admin-group-object-ids "$MY_USER_ID" \
        --network-plugin none \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --vm-set-type "VirtualMachines" \
        --node-vm-size "${SYSTEM_VM_SIZE}" \
        --node-count "${SYSTEM_POOL_SIZE}"
fi

AKS_RESOURCE_ID=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "id" \
  --output tsv)

MY_SP=$(az ad sp create-for-rbac \
  --name "aks-owner-sp" \
  --role "Owner" \
  --scopes "$AKS_RESOURCE_ID")

MY_SP_ID=$(echo "$MY_SP" | jq -r '.appId')
MY_SP_SECRET=$(echo "$MY_SP" | jq -r '.password')
TENANT_ID=$(echo "$MY_SP" | jq -r '.tenant')
export MY_SP_ID MY_SP_SECRET TENANT_ID SUBSCRIPTION LOCATION AKS_RESOURCE_ID

envsubst < config.template.json > config.json

az aks get-credentials --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --admin \
    --overwrite-existing

envsubst < config/node-bootstrapper-binding.yaml | kubectl apply -f -
envsubst < config/node-role-binding.yaml | kubectl apply -f -
    
# python3 setup.py \
#   --resource-group "${RESOURCE_GROUP}" \
#   --cluster-name "${CLUSTER_NAME}" \
#   --ipvlan-prefix-length "${IPVLAN_PREFIX_LENGTH}" \
#   --dry-run
