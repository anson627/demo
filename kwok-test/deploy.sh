#!/bin/bash

set -eo pipefail

NODE_COUNT=5000
NAMESPACE_COUNT=150
PODS_PER_NAMESPACE=1000

if helm list -q | grep "^node$" > /dev/null 2>&1; then
  echo "node release already exists, skipping..."
else
  helm upgrade --install node node \
    --set "nodeCount=$NODE_COUNT"
fi

for i in $(seq 1 $NAMESPACE_COUNT); do
  namespace="kwok-$i"
  if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
    kubectl create namespace "$namespace"
  fi

  if helm list -q -n "$namespace" | grep "^pod$" > /dev/null 2>&1; then
    echo " pod release already exists in $namespace, skipping..."
  else
    helm upgrade --install pod pod \
      --namespace "$namespace" \
      --set "podCount=$PODS_PER_NAMESPACE"
  fi
done
