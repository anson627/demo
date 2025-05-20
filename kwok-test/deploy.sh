#!/bin/bash

set -eo pipefail

NODE_COUNT=5000
NAMESPACE_COUNT=150
PODS_PER_NAMESPACE=1000

# helm upgrade --install node node \
#  --nodeCount "$NODE_COUNT"

for i in $(seq 1 $NAMESPACE_COUNT); do
  namespace="kwok-$i"
  if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
    kubectl create namespace "$namespace"
  fi

  helm upgrade --install pod pod \
    --namespace "$namespace" \
    --set "podCount=$PODS_PER_NAMESPACE"
done

echo "Waiting for all fake pods to be running..."
total_pods=$((NAMESPACE_COUNT * PODS_PER_NAMESPACE))
echo "Expected total pods: $total_pods"

while true; do
  echo "Pod status breakdown:"
  running_pods=0
  kubectl get pod -l app=fake-pod -A --no-headers | awk '{print $4}' | sort | uniq -c | while read count status; do
    echo "  $status: $count"
    if [ "$status" = "Running" ]; then
      running_pods=$((running_pods + count))
    fi
  done

  echo "  Running pods: $running_pods / $total_pods"
  done

  echo "Waiting for remaining pods to start..."
  sleep 10
done
