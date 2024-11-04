#!/bin/bash

set -eo pipefail

# ACS Test with H100
SUBSCRIPTION=8ecadfc9-d1a3-4ea4-b844-0d9f87e4d7c8

# Dataplane Developer with A100
# SUBSCRIPTION=8643025a-c059-4a48-85d0-d76f51d63a74

RESOURCE_GROUP=gpu-test

az account set -s $SUBSCRIPTION
az group delete -n $RESOURCE_GROUP --yes