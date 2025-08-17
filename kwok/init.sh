# KWOK_REPO="kubernetes-sigs/kwok"
# KWOK_RELEASE="v0.7.0"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/kwok.yaml"
# kubectl apply -f "https://github.com/${KWOK_REPO}/releases/download/${KWOK_RELEASE}/stage-fast.yaml"

# kubectl delete configmap kwok -n kube-system --ignore-not-found=true
# kubectl create configmap kwok -n kube-system --from-file=config/kwok.yaml

# kubectl patch deployment kwok-controller -n kube-system -p '{"spec":{"template":{"spec":{"nodeSelector":{"agentpool":"user"}}}}}'
# kubectl apply -f config/device-class.yaml

kwokctl create cluster -c config/kwokctl.yaml --kube-scheduler-config config/kube-scheduler.yaml