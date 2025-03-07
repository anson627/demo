gcloud config set project phrasal-bond-380604

if gcloud compute networks describe cni-test &>/dev/null; then
    echo "Network cni-test already exists."
else
    gcloud compute networks create cni-test --mtu=8896
fi

if gcloud container clusters describe cni-test --zone=us-west1-a &>/dev/null; then
    echo "Cluster cni-test already exists."
else
    gcloud container clusters create cni-test --zone=us-west1-a --network=cni-test
fi

gcloud container clusters get-credentials cni-test --zone us-west1-a
