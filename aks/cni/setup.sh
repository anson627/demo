#!/bin/bash

set -euo pipefail

source variables.sh

if az group show -n "${RESOURCE_GROUP}" &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l "${LOCATION}" -n "${RESOURCE_GROUP}" --tags SkipAKSCluster=1 SkipASB_Audit=true
fi

if az aks show -g "${RESOURCE_GROUP}" -n "${CLUSTER_NAME}" &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    az aks create -l "${LOCATION}" \
        -g "${RESOURCE_GROUP}" \
        -n "${CLUSTER_NAME}" \
        --tier standard \
        --kubernetes-version 1.34.0 \
        --network-plugin none \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --vm-set-type "VirtualMachines" \
        --node-vm-size "${SYSTEM_VM_SIZE}" \
        --node-count "${SYSTEM_POOL_SIZE}"
fi

az aks get-credentials --resource-group "${RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --overwrite-existing
    
python3 ipvlan.py \
  --resource-group "${RESOURCE_GROUP}" \
  --cluster-name "${CLUSTER_NAME}" \
  --ipvlan-prefix-length "${IPVLAN_PREFIX_LENGTH}" \
  --boostrap-cni-config
    
# helm repo add spiderpool https://spidernet-io.github.io/spiderpool
# helm repo update spiderpool
# helm install spiderpool spiderpool/spiderpool --namespace kube-system --set ipam.enableStatefulSet=false --set multus.multusCNI.defaultCniCRName="ipvlan-eth0"
