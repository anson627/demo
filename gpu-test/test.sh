#!/bin/bash

set -eo pipefail

echo "Creating the server pod ..."
kubectl apply -f server-pod.yaml

echo "Creating the client pod ..."
kubectl apply -f client-pod.yaml

echo "Waiting for the server pod to be ready ..."
kubectl wait --for=condition=Ready pod/server-pod

server_pod_ip=$(kubectl get pod server-pod -o jsonpath='{.status.podIP}')
echo "Server pod IP: $server_pod_ip"
