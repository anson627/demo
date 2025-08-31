#!/bin/bash

set -eo pipefail

PROVIDER="kind"

clusterloader2 --provider=$PROVIDER --v=2 \
  --enable-exec-service=False \
  --kubeconfig=$HOME/.kube/config \
  --testconfig=config.yaml \
  --report-dir $PROVIDER-$(date +%Y%m%d-%H%M%S)
