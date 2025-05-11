#!/bin/bash

set -eo pipefail

TEST_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^test-[0-9]*$')
NAMESPACE_COUNT=$(echo "$TEST_NAMESPACES" | wc -w)

if [ "$NAMESPACE_COUNT" -eq 0 ]; then
  echo "No namespaces to delete. Exiting."
  exit 0
fi

for namespace in $TEST_NAMESPACES; do
  kubectl delete namespace $namespace --wait=false
done

