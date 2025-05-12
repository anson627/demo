#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}

az aks delete \
    --resource-group ${RESOURCE_GROUP} \
    --name ${CLUSTER_NAME} \
    --yes