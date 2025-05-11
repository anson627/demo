#!/bin/bash

set -e

NODE_ARRAY=$(kubectl get nodes -l type=kwok -o name)
if [ -z "$NODE_ARRAY" ]; then
    echo "No nodes to delete."
    exit 0
fi

for NODE in $NODE_ARRAY; do
    kubectl delete $NODE --wait=false
done