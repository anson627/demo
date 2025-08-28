helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm install kuberay-operator kuberay/kuberay-operator --version 1.4.2 -n kube-system

kubectl patch deploy kuberay-operator --type=json -p='[{"op":"add","path":"/spec/template/spec/nodeName","value":"kwok-kwok-control-plane"}]'

kubectl get configmap coredns -n kube-system -o yaml > config/coredns.yaml
sed -i '' '/ready/a\
        rewrite name regex (.+)-head-svc\.(.+)\.svc\.cluster\.local mock-head.default.svc.cluster.local
' config/coredns.yaml

kubectl apply -f config/coredns.yaml
kubectl patch deployment coredns -n kube-system --type=json -p='[{"op":"add","path":"/spec/template/spec/nodeName","value":"kwok-kwok-control-plane"}]'

kubectl apply -f config/configmap.yaml
kubectl apply -f config/deployment.yaml
kubectl apply -f config/service.yaml