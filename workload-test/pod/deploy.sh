#!/bin/bash

NAMESPACE_COUNT=100
DEPLOYMENTS_PER_NAMESPACE=10
REPLICAS_PER_DEPLOYMENT=200

TEMP_FILE=$(mktemp)

for i in $(seq 1 $NAMESPACE_COUNT); do
  NAMESPACE="test-$i"
  kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

  for j in $(seq 1 $DEPLOYMENTS_PER_NAMESPACE); do
    DEPLOYMENT_NAME="test-$j"

    cat > $TEMP_FILE << EOF
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
      # A taints was added to an automatically created Node.
      # You can remove taints of Node or add this tolerations.
      tolerations:
      - key: "kwok.x-k8s.io/node"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: fake-container
        image: fake-image
EOF

    kubectl apply -f $TEMP_FILE
    echo "Created deployment $DEPLOYMENT_NAME in namespace $NAMESPACE ($i/$NAMESPACE_COUNT, $j/$DEPLOYMENTS_PER_NAMESPACE)"
  done
done

rm $TEMP_FILE

TOTAL_PODS=$((NAMESPACE_COUNT * DEPLOYMENTS_PER_NAMESPACE * REPLICAS_PER_DEPLOYMENT))
echo "Completed! Created:"
echo "- $NAMESPACE_COUNT namespaces"
echo "- $DEPLOYMENTS_PER_NAMESPACE deployments per namespace (total: $((NAMESPACE_COUNT * DEPLOYMENTS_PER_NAMESPACE)) deployments)"
echo "- $REPLICAS_PER_DEPLOYMENT replicas per deployment"
echo "- $TOTAL_PODS total pods"
