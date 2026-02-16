#!/bin/bash

set -eo pipefail

kubectl apply --server-side -k "https://github.com/kubeflow/mpi-operator/manifests/overlays/standalone?ref=v0.7.0"
kubectl wait --for=condition=available deployment/mpi-operator -n mpi-operator --timeout=300s

kubectl apply -f nccl/device-class.yaml
kubectl apply -f nccl/rct-h100.yaml
kubectl get ResourceClaimTemplate gpu-nic-aligned -o yaml

kubectl apply -f nccl/mpi-job.yaml

kubectl wait --for=condition=ready pod -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=worker --timeout=300s

kubectl wait --for=condition=ready pod -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=launcher --timeout=300s

launcher=$(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-dra,training.kubeflow.org/job-role=launcher -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f "${launcher}"

