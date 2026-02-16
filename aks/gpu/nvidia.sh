#!/bin/bash

set -eo pipefail

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm upgrade --install network-operator nvidia/network-operator \
  --version=25.10.0 \
  --create-namespace \
  --namespace nvidia \
  -f nvidia/values_net.yaml \
  --wait

kubectl apply -f nvidia/nfd-network-rule.yaml

kubectl get nodes -l "feature.node.kubernetes.io/pci-15b3.present=true" -o wide

kubectl apply -f nvidia/nic-cluster-policy.yaml

echo "Verifying MOFED driver on user nodes ..."
while true; do
    mofed_pods_count="$(kubectl get pods \
        -n nvidia \
        -l nvidia.com/ofed-driver \
        --no-headers | wc -l)"

    nodes_with_mofed_wait_false="$(kubectl get nodes \
        -l "network.nvidia.com/operator.mofed.wait=false" \
        --no-headers | wc -l)"

    if [[ "${mofed_pods_count}" -gt 0 && "${mofed_pods_count}" -eq "${nodes_with_mofed_wait_false}" ]]; then
        echo "MOFED driver is successfully installed on all nodes."
        break
    fi

    [[ "${mofed_pods_count}" -eq 0 ]] && echo "⏳ Waiting for mofed pods to show up..."
    echo "⏳ Waiting for all nodes to be labeled 'network.nvidia.com/operator.mofed.wait=false' ..."
    sleep 10
done

helm upgrade --install gpu-operator nvidia/gpu-operator \
    --version=v25.10.1 \
    --create-namespace \
    --namespace nvidia \
    -f nvidia/values_gpu.yaml \
    --wait

kubectl wait --for=condition=ready pod -l app=nvidia-driver-daemonset -n nvidia --timeout=600s

for pod in $(kubectl get pods -n nvidia -l app=nvidia-driver-daemonset -o jsonpath='{.items[*].metadata.name}'); do
    node=$(kubectl get pod "${pod}" -n nvidia -o jsonpath='{.spec.nodeName}')
    echo "  ${node}:"
    kubectl exec -n nvidia "${pod}" -- nvidia-smi -L || echo "    ERROR: nvidia-smi failed on ${node}"
    
    kubectl exec -n nvidia "${pod}" -- ibstat || echo "    ERROR: ibstat failed on ${node}"
done

helm upgrade --install dra-driver nvidia/nvidia-dra-driver-gpu \
    --version=25.12.0 \
    --create-namespace \
    --namespace nvidia \
    -f nvidia/values_dra.yaml \
    --wait

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nvidia-dra-driver-gpu -n nvidia --timeout=300s

echo "Verifying GPU ResourceSlices have pcieRoot attributes..."
missing_pcie_root=0
for slice in $(kubectl get resourceslices --field-selector=spec.driver=gpu.nvidia.com -o jsonpath='{.items[*].metadata.name}'); do
    pcie_root=$(kubectl get resourceslice "${slice}" -o jsonpath='{.spec.devices[0].attributes.resource\.kubernetes\.io/pcieRoot.string}')
    if [[ -z "${pcie_root}" ]]; then
        echo "  WARNING: ResourceSlice ${slice} missing pcieRoot attribute"
        missing_pcie_root=$((missing_pcie_root + 1))
    else
        echo "  ResourceSlice ${slice} has pcieRoot: ${pcie_root}"
    fi
done

kubectl apply -f nvidia/dranet/

kubectl rollout status daemonset/dranet -n kube-system --timeout=300s

net_slice_count=$(kubectl get resourceslices --field-selector=spec.driver=dra.net --no-headers 2>/dev/null | wc -l)
if [[ "${net_slice_count}" -eq 0 ]]; then
    echo "ERROR: No dranet ResourceSlices found"
    exit 1
fi
echo "  Found ${net_slice_count} dranet ResourceSlice(s)"
kubectl get resourceslices --field-selector=spec.driver=dra.net

