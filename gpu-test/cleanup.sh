#!/bin/bash

set -eo pipefail

SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
LOCATION=eastus
RESOURCE_GROUP=gpu-test
CLUSTER_NAME=operator-test

az account set -s $SUBSCRIPTION
az group delete -n $RESOURCE_GROUP --yes --no-wait