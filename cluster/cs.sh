#!/bin/bash
set -eo pipefail

source var.sh

az account set -s ${SUB}
az configure --defaults group=${RESOURCE_GROUP}

VNET_SUBNET_ID=$(az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET --name nodes | jq -r '.id')
POD_SUBNET_ID=$(az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET --name pods | jq -r '.id')

echo $VNET_SUBNET_ID
echo $POD_SUBNET_ID

SYSTEM_POOL_NAME=${NODE_POOL_PREFIX}0

if az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME ; then
  echo "cluster $CLUSTER_NAME already existed"
  az aks update -g $RESOURCE_GROUP \
    -n $CLUSTER_NAME \
    --aks-custom-headers ControlPlaneUnderlay=hcp-underlay-intv2-eastus-cx-1 \
    --load-balancer-backend-pool-type nodeIP \
    --yes 
else 
# --load-balancer-backend-pool-type=nodeIP \
#    --aks-custom-headers ControlPlaneUnderlay=hcp-underlay-intv2-eastus-cx-1 \
#    --service-principal 91658ced-1b74-419e-a33f-081cc3152a19 \
#    --client-secret s5p8Q~IGLCuBUyaSZRvnaI5o33F3HjUTNUMYzcLF \
  az aks create -l $LOCATION \
    -g $RESOURCE_GROUP \
    -n $CLUSTER_NAME \
    -c $SYSTEM_POOL_SIZE \
    -s $SYSTEM_VM_SIZE \
    --nodepool-name $SYSTEM_POOL_NAME \
    --max-pods $MAX_PODS \
    --network-plugin $NETWORK_PLUGIN \
    --vnet-subnet-id $VNET_SUBNET_ID \
    --pod-subnet-id $POD_SUBNET_ID \
    --service-cidr $SERVICE_CIDR \
    --dns-service-ip $DNS_SERVICE_IP \
    --outbound-type userAssignedNATGateway \
    --uptime-sla \
    --yes
fi
