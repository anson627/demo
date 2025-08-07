#!/bin/bash

for ns in $(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | grep '^test-[0-9]\+$'); do
    echo "Deleting namespace $ns"
    kubectl delete ns $ns --ignore-not-found
done

echo "Cleanup complete!"