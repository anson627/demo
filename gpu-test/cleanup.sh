#!/bin/bash

set -eo pipefail

SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8
RESOURCE_GROUP=gpu-test

az account set -s $SUBSCRIPTION
az group delete -n $RESOURCE_GROUP --yes