SUBSCRIPTION=137f0351-8235-42a6-ac7a-6b46be2d21c7
LOCATION=eastus2
RESOURCE_GROUP=ipv6-test
CLUSTER_NAME=ipvlan
SYSTEM_VM_SIZE=Standard_D8ds_v5
SYSTEM_POOL_SIZE=2
USER_VM_SIZE=Standard_D8ds_v5
USER_POOL_SIZE=1

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
        --kubernetes-version 1.33.3 \
        --network-plugin none \
        --disable-disk-driver \
        --disable-file-driver \
        --ssh-key-value ~/.ssh/id_rsa.pub \
        --nodepool-name system \
        --vm-set-type "VirtualMachines" \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE}
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool already exists."
else
  az aks nodepool add \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name $CLUSTER_NAME \
    --name user \
    --vm-set-type "VirtualMachines" \
    --node-vm-size ${USER_VM_SIZE} \
    --node-count ${USER_POOL_SIZE}
 fi

 az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing
