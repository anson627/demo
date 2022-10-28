#!/bin/bash
set -eo pipefail

source var.sh

az account set -s ${SUB}
az configure --defaults group=${RESOURCE_GROUP}

VNET_SUBNET_ID=$(az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET --name nodes | jq -r '.id')
POD_SUBNET_ID=$(az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET --name pods | jq -r '.id')

echo $VNET_SUBNET_ID
echo $POD_SUBNET_ID

for i in {1..5}
do
  USER_POOL_NAME=$NODE_POOL_PREFIX$i
  if az aks nodepool show -n $USER_POOL_NAME -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME &> /dev/null ; then
    echo "node pool $USER_POOL_NAME already existed"
  else
    az aks nodepool add -n $USER_POOL_NAME -g $RESOURCE_GROUP --cluster-name $CLUSTER_NAME -c $USER_POOL_SIZE --max-pods $MAX_PODS -s $USER_VM_SIZE --vnet-subnet-id $VNET_SUBNET_ID --pod-subnet-id $POD_SUBNET_ID
    sleep 5m
  fi 
done
