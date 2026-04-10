#!/bin/bash

set -eo pipefail

kubectl apply -f containerd/
kubectl rollout status daemonset/update-containerd -n kube-system --timeout=300s

sleep 10
for pod in $(kubectl get pods -n kube-system -l app=update-containerd -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod "${pod}" -n kube-system -o jsonpath='{.spec.nodeName}')
    max_retries=5
    retry=0
    version=""
    while (( retry < max_retries )); do
        version=$(kubectl exec -n kube-system "${pod}" -- chroot /host containerd -version 2>/dev/null || true)
        if [[ "${version}" == *"2.2.1"* ]]; then
            break
        fi
        retry=$((retry + 1))
        echo "  ${node}: retry ${retry}/${max_retries} (got: ${version})"
        sleep 5
    done
    echo "  ${node}: ${version}"
    if [[ "${version}" != *"2.2.1"* ]]; then
        echo "ERROR: ${node} has unexpected containerd version after ${max_retries} retries: ${version}"
        exit 1
    fi
done

kubectl apply -f amd/install-driver-configmap.yaml
kubectl apply -f amd/install-driver-daemonset.yaml
kubectl rollout status daemonset/install-amdgpu-driver -n kube-system --timeout=600s

echo "Verifying amdgpu driver on GPU nodes ..."
for pod in $(kubectl get pods -n kube-system -l app=install-amdgpu-driver -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod "${pod}" -n kube-system -o jsonpath='{.spec.nodeName}')
    max_retries=20
    retry=0
    while (( retry < max_retries )); do
        if kubectl exec -n kube-system "${pod}" -- chroot /host modinfo amdgpu &>/dev/null; then
            echo "  ${node}: amdgpu driver loaded"
            break
        fi
        retry=$((retry + 1))
        echo "  ${node}: waiting for driver (${retry}/${max_retries}) ..."
        sleep 30
    done
    if (( retry == max_retries )); then
        echo "ERROR: amdgpu driver not loaded on ${node} after ${max_retries} retries"
        exit 1
    fi
done

helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.15.1 \
  --set crds.enabled=true \
  --wait

helm repo add rocm https://rocm.github.io/gpu-operator
helm repo update

helm upgrade --install amd-gpu-operator rocm/gpu-operator-charts \
  --version=v1.4.1 \
  --create-namespace \
  --namespace kube-amd-gpu \
  -f amd/values_gpu.yaml \
  --wait

echo "Waiting for AMD GPU operator pods to be ready ..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gpu-operator -n kube-amd-gpu --timeout=300s

kubectl apply -f amd/deviceconfig.yaml

echo "Waiting for device plugin pods to be ready ..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=device-plugin -n kube-amd-gpu --timeout=600s

for pod in $(kubectl get pods -n kube-amd-gpu -l app.kubernetes.io/component=device-plugin -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod "${pod}" -n kube-amd-gpu -o jsonpath='{.spec.nodeName}')
    echo "  ${node}:"
    kubectl exec -n kube-amd-gpu "${pod}" -- amd-smi list || echo "    ERROR: amd-smi failed on ${node}"
done

echo "Verifying GPU allocatable resources on nodes ..."
kubectl get nodes -l "feature.node.kubernetes.io/amd-vgpu=true" \
  -o custom-columns='NODE:.metadata.name,GPU_ALLOCATABLE:.status.allocatable.amd\.com/gpu'
