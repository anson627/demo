# Dataplane Developer with A100
SUBSCRIPTION=8643025a-c059-4a48-85d0-d76f51d63a74
LOCATION=eastus
USER_VM_SIZE=Standard_ND96asr_v4

# ACS Test with T4
# SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
# LOCATION=eastus2
# USER_VM_SIZE=Standard_NC8as_T4_v3

# ACS Test with H100
# SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
# LOCATION=centraluseuap
# USER_VM_SIZE=Standard_ND96isr_H100_v5

RESOURCE_GROUP=gpu-${LOCATION}
CLUSTER_NAME=gpu-aks
SYSTEM_VM_SIZE=Standard_NC8as_T4_v3
SYSTEM_POOL_SIZE=2
USER_POOL_SIZE=1

# SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
# CLUSTER_NAME=aks-gb200-20250814-01-kp
# NP_NAME=gb200np02
# GPU_VM_SKU=Standard_ND128isr_NDR_GB200_v6
# GROUP=gb200-kp-centraluseuap
# IMAGE_SUB_ID=c4c3550e-a965-4993-a50c-628fd38cd3e1
# IMAGE_RG=aksvhdtestbuildrg
# IMAGE_GALLERY=PackerSigGalleryEastUS
# IMAGE_NAME=2404gen2arm64gb200containerd
# IMAGE_VERSION=1.1755173711.9536
# TIP_SESSION_ID=66c2bc2c-142e-4807-b0dd-a4a79a7d046a


# az aks nodepool add \
#  --subscription $SUBSCRIPTION \
#  --cluster-name $CLUSTER_NAME \
#  --name $NP_NAME \
#  --resource-group $GROUP \
#  --node-vm-size $GPU_VM_SKU \
#  --node-count 0 \
#  --tags TipNode.SessionId=$TIP_SESSION_ID \
#  --aks-custom-headers AKSHTTPCustomFeatures=Microsoft.ContainerService/UseCustomizedOSImage,OSImageSubscriptionID=$IMAGE_SUB_ID,OSImageResourceGroup=$IMAGE_RG,OSImageGallery=$IMAGE_GALLERY,OSImageName=$IMAGE_NAME,OSImageVersion=$IMAGE_VERSION