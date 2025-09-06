SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
LOCATION="centraluseuap"
RESOURCE_GROUP="gb200-kp-centraluseuap"
CLUSTER_NAME=aks-gb200-20250814-01-kp
NP_NAME=gb200np02
GPU_VM_SKU=Standard_ND128isr_NDR_GB200_v6
IMAGE_SUB_ID=c4c3550e-a965-4993-a50c-628fd38cd3e1
IMAGE_RG=aksvhdtestbuildrg
IMAGE_GALLERY=PackerSigGalleryEastUS
IMAGE_NAME=2404gen2arm64gb200containerd
IMAGE_VERSION=1.1755173711.9536
TIP_SESSION_ID=66c2bc2c-142e-4807-b0dd-a4a79a7d046a

az account set -s ${SUBSCRIPTION}
if az group show -n ${RESOURCE_GROUP} &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l ${LOCATION} -n ${RESOURCE_GROUP}
fi

if az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} &>/dev/null; then
    echo "Cluster already exists."
else
    echo "Cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --kubernetes-version 1.33.2 \
        --nodepool-name system \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin azure \
        --network-plugin-mode overlay
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool already exists."
else
  az aks nodepool add \
    --resource-group ${RESOURCE_GROUP} \
    --cluster-name $CLUSTER_NAME \
    --name user \
    --node-vm-size $GPU_VM_SKU \
    --node-count 0 \
    --tags TipNode.SessionId=$TIP_SESSION_ID \
    --aks-custom-headers AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=$IMAGE_SUB_ID,OSImageResourceGroup=$IMAGE_RG,OSImageGallery=$IMAGE_GALLERY,OSImageName=$IMAGE_NAME,OSImageVersion=$IMAGE_VERSION
 fi