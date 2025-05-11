#!/bin/bash

kubectl get deployments --all-namespaces --watch --no-headers \
  -o custom-columns=\
"NAMESPACE:.metadata.namespace,"\
"NAME:.metadata.name,"\
"READY:.status.readyReplicas,"\
"DESIRED:.spec.replicas,"\
"AVAILABLE:.status.availableReplicas,"\
"AGE:.metadata.creationTimestamp"
