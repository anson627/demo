#!/bin/bash

set -eo pipefail

source variables.sh

az account set -s $SUBSCRIPTION
az group delete -n $RESOURCE_GROUP --yes