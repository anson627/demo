# KWOK_REPO="kubernetes-sigs/kwok"
# KWOK_RELEASE="v0.7.0"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/kwok.yaml"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/stage-fast.yaml"

# kubectl delete configmap kwok -n kube-system --ignore-not-found=true
# kubectl create configmap kwok -n kube-system --from-file=config/kwok.yaml

# kubectl patch deployment kwok-controller -n kube-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"agentpool":"user"}}}}}'
# kubectl apply -f config/device-class.yaml

~/go/src/github.com/anson627/kwok/bin/darwin/arm64/kwokctl create cluster \
    --etcd-image "registry.k8s.io/etcd:v3.6.0" \
    --kube-apiserver-image "registry.k8s.io/kube-apiserver:v1.34.0" \
    --kube-controller-manager-image "registry.k8s.io/kube-controller-manager:v1.34.0" \
    --kube-scheduler-image "registry.k8s.io/kube-scheduler:v1.34.0" \
    --kwok-controller-image registry.k8s.io/kwok/kwok:v0.7.0 \
    -c config/kwokctl.yaml \
    --runtime kind \
    --kube-scheduler-config config/kube-scheduler.yaml
