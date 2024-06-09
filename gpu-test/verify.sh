#!/bin/bash

set -eo pipefail

echo "Checking the gpu nodes based on node feature discovery ..."
kubectl get nodes -o json | jq '.items[] | select(.metadata.labels | has("feature.node.kubernetes.io/pci-10de.present")) | .metadata.name'

echo "Check the status of nvidia operator ..."
kubectl logs -n gpu-operator ds/nvidia-operator-validator -c nvidia-operator-validator

echo "Check the status of the nvidia-cuda-validator ..."
kubectl logs -n gpu-operator -l app=nvidia-cuda-validator

echo "Check the status of the mellanox ofed and nvidia drivers, as well as nvidia-peermem module ..."
kubectl logs -n gpu-operator ds/nvidia-driver-daemonset -c nvidia-peermem-ctr