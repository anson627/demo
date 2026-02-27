#!/bin/bash

set -eo pipefail

if ! kubectl get deployment mpi-operator -n mpi-operator &>/dev/null; then
  kubectl apply --server-side -k "https://github.com/kubeflow/mpi-operator/manifests/overlays/standalone?ref=v0.7.0"
  kubectl wait --for=condition=available deployment/mpi-operator -n mpi-operator --timeout=300s
fi

kubectl apply -f nccl/device-class.yaml
kubectl apply -f nccl/resource-claim-template.yaml
kubectl get ResourceClaimTemplate gpu-nic-aligned -o yaml

kubectl delete mpijob nccl-test-dra --ignore-not-found
kubectl wait --for=delete pod -l training.kubeflow.org/job-name=nccl-test-dra --timeout=120s 2>/dev/null || true

kubectl apply -f nccl/mpi-job.yaml
sleep 5

kubectl wait --for=condition=ready pod -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=worker --timeout=300s

kubectl wait --for=condition=ready pod -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=launcher --timeout=300s

launcher=$(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=launcher -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f "${launcher}"

