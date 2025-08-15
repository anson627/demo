#!/bin/bash

set -eo pipefail

PROVIDER="eks"

clusterloader2 --provider=$PROVIDER \
  --kubeconfig=/Users/ansonqian/.kube/config \
  --testconfig=ray/config.yaml \
  --report-dir /tmp/$PROVIDER-$(date +%Y%m%d-%H%M%S)
