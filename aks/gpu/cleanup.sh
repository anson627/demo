#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s ${SUBSCRIPTION}

echo "Deleting resource group ${RESOURCE_GROUP} ..."
az group delete -n ${RESOURCE_GROUP} --yes --no-wait
