#!/bin/bash

set -eo pipefail

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
    && helm repo update

RELEASE_NAME=$(helm list -q -n gpu-operator)
if [[ -n "$RELEASE_NAME" ]]; then
    helm upgrade --wait \
        -n gpu-operator \
        $RELEASE_NAME \
        nvidia/gpu-operator \
        -f nfd-custom-values.yaml
else
    helm install --wait \
        --generate-name \
        -n gpu-operator \
        nvidia/gpu-operator \
        -f nfd-custom-values.yaml
fi



kubectl get nodes -o json | jq '.items[].metadata.labels | keys | any(startswith("feature.node.kubernetes.io/pci-10de.present"))'