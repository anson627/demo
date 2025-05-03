#!/bin/bash

# Configuration
NAMESPACE_COUNT=100
DEPLOYMENTS_PER_NAMESPACE=10
REPLICAS_PER_DEPLOYMENT=200

# Create a temporary deployment file
TEMP_FILE=$(mktemp)

# Loop to create namespaces
for i in $(seq 1 $NAMESPACE_COUNT); do
  NAMESPACE="test-$i"

  # Create namespace if it doesn't exist
  kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

  # Create multiple deployments in each namespace
  for j in $(seq 1 $DEPLOYMENTS_PER_NAMESPACE); do
    DEPLOYMENT_NAME="test-$j"

    # Create deployment manifest with the current namespace
    cat > $TEMP_FILE << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: test
    deployment-id: "$j"
spec:
  replicas: $REPLICAS_PER_DEPLOYMENT
  selector:
    matchLabels:
      app: test
      deployment-id: "$j"
  template:
    metadata:
      labels:
        app: test
        deployment-id: "$j"
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: test
            deployment-id: "$j"
      containers:
      - name: test
        image: mcr.microsoft.com/oss/mirror/docker.io/library/ubuntu:20.04
        command: ["sh", "-c", "while true; do sleep 3600; done"]
EOF

    # Apply the deployment to the namespace
    kubectl apply -f $TEMP_FILE

    echo "Created deployment $DEPLOYMENT_NAME in namespace $NAMESPACE ($i/$NAMESPACE_COUNT, $j/$DEPLOYMENTS_PER_NAMESPACE)"
  done
done

# Clean up temporary file
rm $TEMP_FILE

TOTAL_PODS=$((NAMESPACE_COUNT * DEPLOYMENTS_PER_NAMESPACE * REPLICAS_PER_DEPLOYMENT))
echo "Completed! Created:"
echo "- $NAMESPACE_COUNT namespaces"
echo "- $DEPLOYMENTS_PER_NAMESPACE deployments per namespace (total: $((NAMESPACE_COUNT * DEPLOYMENTS_PER_NAMESPACE)) deployments)"
echo "- $REPLICAS_PER_DEPLOYMENT replicas per deployment"
echo "- $TOTAL_PODS total pods"
