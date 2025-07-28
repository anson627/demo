#!/bin/bash

# Delete RayJobs with label perf-test=rayjob-pytorch-mnist
kubectl get rayjob -A -l perf-test=rayjob-pytorch-mnist -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name --no-headers | while read ns name; do
  echo "Deleting RayJob $name in namespace $ns"
  kubectl delete rayjob $name -n $ns --ignore-not-found
done

# Delete namespaces matching pattern test-i31sf6-1
for ns in $(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | grep '^test-[^-]*-[0-9]\+$'); do
    echo "Deleting namespace $ns"
    kubectl delete ns $ns --ignore-not-found
done

echo "Cleanup complete!"