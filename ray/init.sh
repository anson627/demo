helm upgrade --install kuberay-operator $HOME/go/src/github.com/anson627/kuberay/helm-chart/kuberay-operator -f config/values.yaml
kubectl patch deploy kuberay-operator --type=json -p='[{"op":"add","path":"/spec/template/spec/nodeName","value":"kwok-kwok-control-plane"}]'

kubectl apply -f config/coredns.yaml
kubectl patch deployment coredns -n kube-system --type=json -p='[{"op":"add","path":"/spec/template/spec/nodeName","value":"kwok-kwok-control-plane"}]'

kubectl apply -f config/deployment.yaml
kubectl apply -f config/service.yaml