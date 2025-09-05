LOCATION="westus3"
RESOURCE_GROUP="aksvhdtestbuildrg"
DISK_NAME="2404gen2arm64gb200containerd-1.1.206"
GALLERY_IMAGE_REFERENCE="/subscriptions/c4c3550e-a965-4993-a50c-628fd38cd3e1/resourceGroups/aksvhdtestbuildrg/providers/Microsoft.Compute/galleries/PackerSigGalleryEastUS/images/2404gen2arm64gb200containerd/versions/1.1.206"
OS_TYPE="Linux"

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

az account set -s $SUBSCRIPTION

az disk create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DISK_NAME" \
  --location "$LOCATION" \
  --gallery-image-reference "$GALLERY_IMAGE_REFERENCE" \
  --os-type "$OS_TYPE" \
  --query id -o tsv

echo "Granting access to $disk_resource_id for 1 hour"
# shellcheck disable=SC2102
sas=$(az disk grant-access --ids $disk_resource_id --duration-in-seconds 3600 --query [accessSas] -o tsv)
if [ "$sas" = "None" ]; then
echo "sas token empty. Trying alternative query string"
# shellcheck disable=SC2102
sas=$(az disk grant-access --ids $disk_resource_id --duration-in-seconds 3600 --query [accessSAS] -o tsv)
