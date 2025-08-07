#!/bin/bash

set -eo pipefail

PROVIDER="aks"

clusterloader2 --provider=$PROVIDER --v=2 \
  --kubeconfig=/Users/ansonqian/.kube/config \
  --testconfig=config.yaml \
  --testoverrides=overrides.yaml \
  --report-dir $PROVIDER-$(date +%Y%m%d-%H%M%S)
