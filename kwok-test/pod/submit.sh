#!/bin/bash

set -eo pipefail

NAMESPACE_COUNT=100
JOBS_PER_NAMESPACE=200
COMPLETIONS_PER_JOB=10

for i in $(seq 1 $NAMESPACE_COUNT); do
  namespace="test-$i"
  if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
    kubectl create namespace "$namespace"
  fi

  for j in $(seq 1 $JOBS_PER_NAMESPACE); do
    job="test-$j"

    template=$(cat job.yaml)
    template=$(echo "$template" | sed "s/<NAMESPACE>/$namespace/g")
    template=$(echo "$template" | sed "s/<JOB>/$job/g")
    template=$(echo "$template" | sed "s/<REPLICAS>/$COMPLETIONS_PER_JOB/g")

    mkdir -p /tmp/kwok
    tmp_file="/tmp/kwok/job-$i-$j.yaml"
    echo "$template" > $tmp_file
    kubectl apply -f $tmp_file
    rm $tmp_file
  done
done
