#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}

for i in $(seq 1 ${USER_POOL_COUNT}); do
    USER_POOL_NAME=user${i}
    NODE_COUNT=$(az aks nodepool show --resource-group ${RESOURCE_GROUP} --cluster-name ${CLUSTER_NAME} --name ${USER_POOL_NAME} --query count -o tsv)
    if [ "$NODE_COUNT" -gt 0 ]; then
        echo "User pool ${i} already exists. Scaling down ..."
        az aks nodepool scale \
            --resource-group ${RESOURCE_GROUP} \
            --cluster-name ${CLUSTER_NAME} \
            --name ${USER_POOL_NAME} \
            --node-count 0
    else
        echo "User pool ${i} already scaled down"
    fi
done

az aks delete \
    --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --yes