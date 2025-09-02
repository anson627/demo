# KWOK_REPO="kubernetes-sigs/kwok"
# KWOK_RELEASE="v0.7.0"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/kwok.yaml"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/stage-fast.yaml"

# kubectl delete configmap kwok -n kube-system --ignore-not-found=true
# kubectl create configmap kwok -n kube-system --from-file=config/kwok.yaml

# kubectl patch deployment kwok-controller -n kube-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"agentpool":"user"}}}}}'
# kubectl apply -f config/device-class.yaml

#    --runtime kind \
kwokctl create cluster \
    --etcd-image "registry.k8s.io/etcd:v3.6.0" \
    --kube-apiserver-image "registry.k8s.io/kube-apiserver:v1.34.0" \
    --kube-controller-manager-image "registry.k8s.io/kube-controller-manager:v1.34.0" \
    --kube-scheduler-image "registry.k8s.io/kube-scheduler:v1.34.0" \
    --kwok-controller-image registry.k8s.io/kwok/kwok:v0.7.0 \
    -c config/kwokctl.yaml \
    --kube-scheduler-config config/kube-scheduler.yaml

docker run -d --name=grafana -p 3000:3000 docker.io/grafana/grafana:9.4.7