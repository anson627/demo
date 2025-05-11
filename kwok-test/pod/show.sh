#!/bin/bash

set -eo pipefail

TEST_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^test-[0-9]*$')
NAMESPACE_COUNT=$(echo "$TEST_NAMESPACES" | wc -w)

if [ "$NAMESPACE_COUNT" -eq 0 ]; then
  echo "No namespaces to show. Exiting."
  exit 0
fi

total_running_pods=0
total_pending_pods=0
total_failed_pods=0
total_completed_pods=0

printf "%-20s | %8s | %8s | %8s | %8s \n" "NAMESPACE" "RUNNING" "PENDING" "FAILED" "COMPLETED"

for namespace in $TEST_NAMESPACES; do
  start_time=$(date +%s.%N)
  pod_data=$(kubectl get pods -n $namespace -o=custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,STATUS:.status.phase --no-headers)
  end_time=$(date +%s.%N)
  latency=$(echo "$end_time - $start_time" | bc)

  running_pods=0
  pending_pods=0
  failed_pods=0
  completed_pods=0
  while IFS= read -r line; do
    pod_status=$(echo "$line" | awk '{print $3}')
    case $pod_status in
      Running)
        ((running_pods++))
        ;;
      Pending)
        ((pending_pods++))
        ;;
      Failed)
        ((failed_pods++))
        ;;
      Succeeded)
        ((completed_pods++))
        ;;
    esac
  done <<< "$pod_data"

  total_running_pods=$((total_running_pods + running_pods))
  total_pending_pods=$((total_pending_pods + pending_pods))
  total_failed_pods=$((total_failed_pods + failed_pods))
  total_completed_pods=$((total_completed_pods + completed_pods))

  printf "%-20s | %8s | %8s | %8s | %8s | %8s\n" "$namespace" "$running_pods" "$pending_pods" "$failed_pods" "$completed_pods"
done

printf "%-20s | %8s | %8s | %8s | %8s | %8s\n" "total" "$total_running_pods" "$total_pending_pods" "$total_failed_pods" "$total_completed_pods"