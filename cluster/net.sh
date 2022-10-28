#!/bin/bash
set -eo pipefail

source var.sh

az account set -s ${SUB}
az configure --defaults group=${RESOURCE_GROUP}

az network public-ip create -g ${RESOURCE_GROUP} -n ${IP_NAME} -l ${LOCATION} --sku Standard
az network nat gateway create -g ${RESOURCE_GROUP} -n ${GATEWAY_NAME} -l ${LOCATION} --public-ip-addresses /subscriptions/${SUB}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/publicIPAddresses/${IP_NAME}

az network vnet create -g ${RESOURCE_GROUP} -n ${VNET} -l ${LOCATION} --address-prefixes $VNET_CIDR
az network vnet subnet create -g ${RESOURCE_GROUP} --vnet-name ${VNET} --name nodes --address-prefixes ${VNET_NODES_CIDR} --nat-gateway /subscriptions/${SUB}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/natGateways/${GATEWAY_NAME}
az network vnet subnet create -g ${RESOURCE_GROUP} --vnet-name ${VNET} -n pods --address-prefixes $VNET_PODS_CIDR --nat-gateway /subscriptions/${SUB}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/natGateways/${GATEWAY_NAME}
