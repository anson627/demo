#!/bin/bash

set -eo pipefail

NAMESPACE_COUNT=2
DEPLOYMENTS_PER_NAMESPACE=3
REPLICAS_PER_DEPLOYMENT=20

for i in $(seq 1 $NAMESPACE_COUNT); do
  namespace="test-$i"
  if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
    kubectl create namespace "$namespace"
  fi

  for j in $(seq 1 $DEPLOYMENTS_PER_NAMESPACE); do
    deployment="test-$j"

    template=$(cat deployment.yaml)
    template=$(echo "$template" | sed "s/<NAMESPACE>/$namespace/g")
    template=$(echo "$template" | sed "s/<DEPLOYMENT>/$deployment/g")
    template=$(echo "$template" | sed "s/<REPLICAS>/$REPLICAS_PER_DEPLOYMENT/g")

    tmp_file="/tmp/kwok/deployment-$i-$j.yaml"
    echo "$template" > $tmp_file
    kubectl apply -f $tmp_file
    rm $tmp_file
  done
done
