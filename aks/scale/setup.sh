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
    MY_USER_ID=$(az ad signed-in-user show --query id -o tsv)
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
        --aad-admin-group-object-ids "$MY_USER_ID" \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin none \
        --outbound-type managedNATGateway \
        --nat-gateway-managed-outbound-ip-count 5
fi

if az network vnet show -g ${RESOURCE_GROUP} -n ${USER_POOL_VNET_NAME} &>/dev/null; then
    echo "User pool VNet already exists."
else
    echo "Creating user pool VNet ..."
    az network vnet create \
        -g ${RESOURCE_GROUP} \
        -n ${USER_POOL_VNET_NAME} \
        --address-prefix 10.1.0.0/16 \
        --subnet-name ${USER_POOL_SUBNET_NAME} \
        --subnet-prefix 10.1.0.0/24
fi

if az network nsg show -g ${RESOURCE_GROUP} -n ${USER_POOL_NSG_NAME} &>/dev/null; then
    echo "User pool NSG already exists."
else
    echo "Creating user pool NSG ..."
    az network nsg create \
        -g ${RESOURCE_GROUP} \
        -n ${USER_POOL_NSG_NAME}
    az network nsg rule create \
        -g ${RESOURCE_GROUP} \
        --nsg-name ${USER_POOL_NSG_NAME} \
        -n AllowSSH \
        --priority 1000 \
        --access Allow \
        --direction Inbound \
        --protocol Tcp \
        --destination-port-ranges 22
fi

az network vnet subnet update \
    -g ${RESOURCE_GROUP} \
    --vnet-name ${USER_POOL_VNET_NAME} \
    -n ${USER_POOL_SUBNET_NAME} \
    --network-security-group ${USER_POOL_NSG_NAME}

if az identity show -g ${RESOURCE_GROUP} -n ${USER_POOL_MI_NAME} &>/dev/null; then
    echo "User pool managed identity already exists."
else
    echo "Creating user pool managed identity ..."
    az identity create \
        -g ${RESOURCE_GROUP} \
        -n ${USER_POOL_MI_NAME} \
        -l ${LOCATION}
fi

USER_POOL_MI_ID=$(az identity show \
    -g ${RESOURCE_GROUP} \
    -n ${USER_POOL_MI_NAME} \
    --query id -o tsv)

if az vmss show -g ${RESOURCE_GROUP} -n ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool VMSS already exists."
else
    echo "Creating user pool VMSS ..."
    USER_POOL_SUBNET_ID=$(az network vnet subnet show \
        -g ${RESOURCE_GROUP} \
        --vnet-name ${USER_POOL_VNET_NAME} \
        -n ${USER_POOL_SUBNET_NAME} \
        --query id -o tsv)
    az vmss create \
        -g ${RESOURCE_GROUP} \
        -n ${USER_POOL_NAME} \
        --image ${USER_POOL_IMAGE} \
        --vm-sku ${USER_VM_SIZE} \
        --instance-count ${USER_POOL_SIZE} \
        --admin-username ${USER_POOL_ADMIN_USERNAME} \
        --ssh-key-values ${USER_POOL_SSH_KEY_PATH} \
        --assign-identity ${USER_POOL_MI_ID} \
        --authentication-type ssh \
        --orchestration-mode Uniform \
        --platform-fault-domain-count 1 \
        --public-ip-per-vm \
        --load-balancer ""
fi

# Peer AKS VNet (in managed resource group) with user pool VNet
AKS_MC_RG=$(az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} --query nodeResourceGroup -o tsv)
AKS_VNET_NAME=$(az network vnet list -g ${AKS_MC_RG} --query '[0].name' -o tsv)
AKS_VNET_ID=$(az network vnet show -g ${AKS_MC_RG} -n ${AKS_VNET_NAME} --query id -o tsv)
USER_VNET_ID=$(az network vnet show -g ${RESOURCE_GROUP} -n ${USER_POOL_VNET_NAME} --query id -o tsv)

if az network vnet peering show -g ${AKS_MC_RG} --vnet-name ${AKS_VNET_NAME} -n aks-to-user &>/dev/null; then
    echo "AKS-to-user VNet peering already exists."
else
    echo "Creating AKS-to-user VNet peering ..."
    az network vnet peering create \
        -g ${AKS_MC_RG} \
        --vnet-name ${AKS_VNET_NAME} \
        -n aks-to-user \
        --remote-vnet ${USER_VNET_ID} \
        --allow-vnet-access
fi

if az network vnet peering show -g ${RESOURCE_GROUP} --vnet-name ${USER_POOL_VNET_NAME} -n user-to-aks &>/dev/null; then
    echo "User-to-AKS VNet peering already exists."
else
    echo "Creating user-to-AKS VNet peering ..."
    az network vnet peering create \
        -g ${RESOURCE_GROUP} \
        --vnet-name ${USER_POOL_VNET_NAME} \
        -n user-to-aks \
        --remote-vnet ${AKS_VNET_ID} \
        --allow-vnet-access
fi


AKS_RESOURCE_ID=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "id" \
  --output tsv)

TENANT_ID=$(az account show \
  --query "tenantId" \
  --output tsv)
  
MI_PRINCIPAL_ID=$(az identity show \
  -g "$RESOURCE_GROUP" \
  -n "$USER_POOL_MI_NAME" \
  --query "principalId" \
  --output tsv)

MI_CLIENT_ID=$(az identity show \
  -g "$RESOURCE_GROUP" \
  -n "$USER_POOL_MI_NAME" \
  --query "clientId" \
  --output tsv)

az role assignment create \
    --assignee-object-id "$MI_PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Owner" \
    --scope "$AKS_RESOURCE_ID"

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --admin \
    --overwrite-existing

export TENANT_ID MI_PRINCIPAL_ID MI_CLIENT_ID SUBSCRIPTION LOCATION AKS_RESOURCE_ID

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aks-flex-node-bootstrapper
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-bootstrapper
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $MI_PRINCIPAL_ID
EOF

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aks-flex-node-csr-approval
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $MI_PRINCIPAL_ID
EOF

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: aks-flex-node-role
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:nodes
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $MI_PRINCIPAL_ID
EOF

envsubst < config.template.json > config.json
