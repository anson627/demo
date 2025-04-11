#!/bin/bash

set -eo pipefail

SUBSCRIPTION=137f0351-8235-42a6-ac7a-6b46be2d21c7

RESOURCE_GROUP=general-test

az account set -s ${SUBSCRIPTION}
az group delete -n ${RESOURCE_GROUP} --yes