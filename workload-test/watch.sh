#!/bin/bash

echo "Watching deployments across all test namespaces..."

# Count the test namespaces
TEST_NAMESPACES=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | grep "^test-" | sort)
NAMESPACE_COUNT=$(echo "$TEST_NAMESPACES" | wc -l)

echo "Found $NAMESPACE_COUNT test namespaces"
echo "Starting watch - press Ctrl+C to exit"
echo ""

# Watch the deployments with custom columns to show relevant information
kubectl get deployments --all-namespaces --watch --no-headers \
  -o custom-columns=\
"NAMESPACE:.metadata.namespace,"\
"NAME:.metadata.name,"\
"READY:.status.readyReplicas,"\
"DESIRED:.spec.replicas,"\
"AVAILABLE:.status.availableReplicas,"\
"AGE:.metadata.creationTimestamp" | grep "test-"

# Note: The above watch command will run until interrupted with Ctrl+C
