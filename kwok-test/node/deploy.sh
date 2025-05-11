#!/bin/bash

set -e

NODE_COUNT=10
BATCH_SIZE=1

kubectl apply -f kwok.yaml
if [ $? -ne 0 ]; then
  echo "Failed to apply kwok.yaml"
  exit 1
fi

kubectl apply -f stage-fast.yaml
if [ $? -ne 0 ]; then
  echo "Failed to apply stage-fast"
  exit 1
fi

TOTAL_BATCHES=$((NODE_COUNT / BATCH_SIZE + (NODE_COUNT % BATCH_SIZE > 0)))
for i in $(seq 1 $TOTAL_BATCHES); do
  start_idx=$(( (i-1) * BATCH_SIZE + 1 ))
  end_idx=$((i * BATCH_SIZE))

  if [ $end_idx -gt $NODE_COUNT ]; then
    end_idx=$NODE_COUNT
  fi

  echo "Creating batch $i/$TOTAL_BATCHES (nodes $start_idx to $end_idx)"

  tmp_file="/tmp/kwok/nodes-$i.yaml"
  > $tmp_file

  for j in $(seq $start_idx $end_idx); do
    cat >> $tmp_file << EOF
---
apiVersion: v1
kind: Node
metadata:
  annotations:
    node.alpha.kubernetes.io/ttl: "0"
    kwok.x-k8s.io/node: fake
  labels:
    beta.kubernetes.io/arch: amd64
    beta.kubernetes.io/os: linux
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: test-$j
    kubernetes.io/os: linux
    kubernetes.io/role: agent
    node-role.kubernetes.io/agent: ""
    type: kwok
  name: test-$j
spec:
  providerID: kwok://test-$j
  taints:
  - effect: NoSchedule
    key: kwok.x-k8s.io/node
    value: fake
status:
  allocatable:
    cpu: 32
    memory: 256Gi
    pods: 110
  capacity:
    cpu: 32
    memory: 256Gi
    pods: 110
  nodeInfo:
    architecture: amd64
    bootID: ""
    containerRuntimeVersion: ""
    kernelVersion: ""
    kubeProxyVersion: fake
    kubeletVersion: fake
    machineID: ""
    operatingSystem: linux
    osImage: ""
    systemUUID: ""
  phase: Running
EOF
  done

  kubectl apply -f $tmp_file
  if [ $? -ne 0 ]; then
    echo "Failed to create nodes in batch $batch"
    exit 1
  fi

  rm $tmp_file
done
