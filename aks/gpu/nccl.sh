#!/bin/bash

set -eo pipefail

kubectl apply --server-side -k "https://github.com/kubeflow/mpi-operator/manifests/overlays/standalone?ref=v0.7.0"

kubectl wait --for=condition=available deployment/mpi-operator -n mpi-operator --timeout=300s