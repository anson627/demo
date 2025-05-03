#!/bin/bash

set -eo pipefail

echo "Starting cleanup of test namespaces..."

# Get all namespaces that match our pattern
TEST_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^test-[0-9]*$')

# Count namespaces to be deleted
NAMESPACE_COUNT=$(echo "$TEST_NAMESPACES" | wc -w)

echo "Found $NAMESPACE_COUNT test namespaces to delete"

if [ "$NAMESPACE_COUNT" -eq 0 ]; then
  echo "No namespaces to delete. Exiting."
  exit 0
fi

# Ask for confirmation
read -p "Are you sure you want to delete these namespaces? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup canceled."
  exit 1
fi

# Counter for tracking progress
COUNT=0

# Delete each namespace
for NAMESPACE in $TEST_NAMESPACES; do
  COUNT=$((COUNT+1))
  echo "[$COUNT/$NAMESPACE_COUNT] Deleting namespace $NAMESPACE..."

  # Delete the namespace
  kubectl delete namespace $NAMESPACE --wait=false
done

echo "Deletion commands issued for all $COUNT namespaces."
echo "Note: Namespaces may take some time to fully terminate."
echo "To check status: kubectl get namespaces | grep test-"
