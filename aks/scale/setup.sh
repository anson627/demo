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
    echo "Managed cluster already exists."
else
    echo "Managed cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --kubernetes-version 1.34.2 \
        --disable-disk-driver \
        --disable-file-driver \
        --nodepool-name system \
        --enable-aad \
        --aad-admin-group-object-ids "8a5603a8-2c60-49ab-bc28-a989b91e187d" \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin none \
        --outbound-type managedNATGateway \
        --nat-gateway-managed-outbound-ip-count 5
fi

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --admin \
    --overwrite-existing

AKS_RESOURCE_ID=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "id" \
  --output tsv)

TENANT_ID=$(az account show \
  --query "tenantId" \
  --output tsv)

# Generate bootstrap token
TOKEN_ID=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
BOOTSTRAP_TOKEN="${TOKEN_ID}.${TOKEN_SECRET}"
EXPIRATION=$(date -u -v+24H +"%Y-%m-%dT%H:%M:%SZ")

SERVER_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT_DATA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Create bootstrap token secret and RBAC bindings
export TOKEN_ID TOKEN_SECRET EXPIRATION
envsubst < config/bootstrap-token-secret.template.yaml | kubectl apply -f -
kubectl apply -f config/node-bootstrapper-binding.yaml
kubectl apply -f config/node-auto-approve-csr.yaml

# Generate cloud-init script
export TENANT_ID SUBSCRIPTION LOCATION AKS_RESOURCE_ID BOOTSTRAP_TOKEN SERVER_URL CA_CERT_DATA
envsubst < cloud-init.template.sh > cloud-init.sh

# Create VMSS with cloud-init custom data
if az vmss show -g ${RESOURCE_GROUP} -n ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool VMSS already exists."
else
    echo "Creating user pool VMSS ..."
    az vmss create \
        -g ${RESOURCE_GROUP} \
        -n ${USER_POOL_NAME} \
        --image ${USER_POOL_IMAGE} \
        --vm-sku ${USER_VM_SIZE} \
        --instance-count ${USER_POOL_SIZE} \
        --admin-username ${USER_POOL_ADMIN_USERNAME} \
        --ssh-key-values ${USER_POOL_SSH_KEY_PATH} \
        --custom-data cloud-init.sh \
        --authentication-type ssh \
        --orchestration-mode Uniform \
        --platform-fault-domain-count 1 \
        --public-ip-per-vm \
        --load-balancer ""
fi
