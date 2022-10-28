#!/bin/bash
set -eo pipefail

for i in {1..5}
do
  NAMESPACE=monitoring
  if kubectl get ns $NAMESPACE ; then
    kubectl delete ns $NAMESPACE --wait=false	
    kubectl proxy &
    kubectl get namespace $NAMESPACE -o json |jq '.spec = {"finalizers":[]}' >temp.json
    curl -k -H "Content-Type: application/json" -X PUT --data-binary @temp.json 127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
    sleep 1
  fi
done
