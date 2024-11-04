#!/bin/bash

set -eo pipefail

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
    && helm repo update

helm install --wait \
    --generate-name \
    -n network-operator \
    --create-namespace \
    nvidia/network-operator \
    --version v23.4.0 \
    -f ./values.yaml

helm install --wait \
    --generate-name \
    -n gpu-operator \
    --create-namespace \
    nvidia/gpu-operator \
    --set driver.rdma.enabled=true
