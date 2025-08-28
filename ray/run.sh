#!/bin/bash

set -eo pipefail

PROVIDER="kind"

clusterloader2 --provider=$PROVIDER \
  --enable-exec-service=False \
  --kubeconfig=$HOME/.kube/config \
  --testconfig=config.yaml \
  --report-dir $PROVIDER-$(date +%Y%m%d-%H%M%S)
