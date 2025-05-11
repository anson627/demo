#!/bin/bash

set -eo pipefail

NAMESPACE_COUNT=2
DEPLOYMENTS_PER_NAMESPACE=2
REPLICAS_PER_DEPLOYMENT=30

for i in $(seq 1 $NAMESPACE_COUNT); do
  NAMESPACE="test-$i"
  kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

  for j in $(seq 1 $DEPLOYMENTS_PER_NAMESPACE); do
    DEPLOYMENT_NAME="test-$j"

    tmp_file="/tmp/kwok/pods-$i-$j.yaml"
    cat > $tmp_file << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
spec:
  replicas: $REPLICAS_PER_DEPLOYMENT
  selector:
    matchLabels:
      app: fake-pod
  template:
    metadata:
      labels:
        app: fake-pod
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: type
                operator: In
                values:
                - kwok
      tolerations:
      - key: "kwok.x-k8s.io/node"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: fake-container
        image: fake-image
        resources:
          requests:
            cpu: 3
EOF

    kubectl apply -f $tmp_file
    rm $tmp_file
  done
done
