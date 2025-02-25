#!/bin/bash

set -eo pipefail

SUBSCRIPTION=137f0351-8235-42a6-ac7a-6b46be2d21c7
RESOURCE_GROUP=cni-test
LOCATION=eastus2
CLUSTER_NAME=cni-test
SYSTEM_POOL_NAME=system
SYSTEM_VM_SIZE=Standard_D8ds_v5
SYSTEM_POOL_SIZE=3
USER_POOL_NAME=user
USER_VM_SIZE=Standard_D8ds_v5
USER_POOL_SIZE=1
VNET_CIDR="10.0.0.0/8"
VNET_NODES_CIDR="10.1.0.0/16"
VNET_PODS_CIDR="10.4.0.0/14"

az account set -s ${SUBSCRIPTION}
if az group show -n ${RESOURCE_GROUP} &>/dev/null; then
    echo "Resource group already exists."
else
    echo "Resource group does not exist. Creating ..."
    az group create -l ${LOCATION} -n ${RESOURCE_GROUP}
fi

IP_NAME=${CLUSTER_NAME}-ip
if az network public-ip show -g ${RESOURCE_GROUP} -n ${IP_NAME} &>/dev/null; then
    echo "Public IP already exists."
else
    echo "Public IP does not exist. Creating ..."
    az network public-ip create -g ${RESOURCE_GROUP} \
        -n ${IP_NAME} \
        --sku Standard
fi
PUBLIC_IP_ID=$(az network public-ip show -g ${RESOURCE_GROUP} -n ${IP_NAME} | jq -r '.id')

GATEWAY_NAME=${CLUSTER_NAME}-gateway
if az network nat gateway show -g ${RESOURCE_GROUP} -n ${GATEWAY_NAME} &>/dev/null; then
    echo "NAT gateway already exists."
else
    echo "NAT gateway does not exist. Creating ..."
    az network nat gateway create -g ${RESOURCE_GROUP} \
        -n ${GATEWAY_NAME} \
        --public-ip-addresses ${PUBLIC_IP_ID}
fi
NAT_GATEWAY_ID=$(az network nat gateway show -g ${RESOURCE_GROUP} -n ${GATEWAY_NAME} | jq -r '.id')

VNET_NAME=${CLUSTER_NAME}-net
if az network vnet show -g ${RESOURCE_GROUP} -n ${VNET_NAME} &>/dev/null; then
    echo "VNET already exists."
else
    echo "VNET does not exist. Creating ..."
    az network vnet create -g ${RESOURCE_GROUP} \
        -n ${VNET_NAME} \
        --address-prefixes ${VNET_CIDR}
fi

if az network vnet subnet show -g ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name nodes &>/dev/null; then
    echo "Nodes subnet already exists."
else
    echo "Nodes subnet does not exist. Creating ..."
    az network vnet subnet create -g ${RESOURCE_GROUP} \
        --vnet-name ${VNET_NAME} \
        --name nodes \
        --address-prefixes ${VNET_NODES_CIDR} \
        --nat-gateway ${NAT_GATEWAY_ID}
fi
NODE_SUBNET_ID=$(az network vnet subnet show -g ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name nodes | jq -r '.id')

if az network vnet subnet show -g ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name pods &>/dev/null; then
    echo "Pods subnet already exists."
else
    echo "Pods subnet does not exist. Creating ..."
    az network vnet subnet create -g ${RESOURCE_GROUP} \
        --vnet-name ${VNET_NAME} \
        --name pods \
        --address-prefixes ${VNET_PODS_CIDR} \
        --nat-gateway ${NAT_GATEWAY_ID}
fi
POD_SUBNET_ID=$(az network vnet subnet show -g ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name pods | jq -r '.id')

if az aks show -g ${RESOURCE_GROUP} -n ${CLUSTER_NAME} &>/dev/null; then
    echo "Managed cluster already exists."
else
    echo "Managed cluster does not exist. Creating ..."
    az aks create -l ${LOCATION} \
        -g ${RESOURCE_GROUP} \
        -n ${CLUSTER_NAME} \
        --tier standard \
        --nodepool-name ${SYSTEM_POOL_NAME} \
        --node-vm-size ${SYSTEM_VM_SIZE} \
        --node-count ${SYSTEM_POOL_SIZE} \
        --network-plugin azure \
        --outbound-type userAssignedNATGateway \
        --vnet-subnet-id ${NODE_SUBNET_ID} \
        --pod-subnet-id ${POD_SUBNET_ID} \
        --pod-ip-allocation-mode StaticBlock
fi

if az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} &>/dev/null; then
    echo "User pool already exists."
else
    echo "User pool does not exist. Creating ..."
    az aks nodepool add \
        --resource-group ${RESOURCE_GROUP} \
        --cluster-name ${CLUSTER_NAME} \
        --name ${USER_POOL_NAME} \
        --node-vm-size ${USER_VM_SIZE} \
        --node-count ${USER_POOL_SIZE} \
        --vnet-subnet-id ${NODE_SUBNET_ID} \
        --pod-subnet-id ${POD_SUBNET_ID} \
        --pod-ip-allocation-mode StaticBlock
fi

az aks get-credentials --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --overwrite-existing
