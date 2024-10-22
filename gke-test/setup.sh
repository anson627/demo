gcloud config set project phrasal-bond-380604
gcloud container clusters create retina-test --zone us-west1-a
gcloud container clusters get-credentials retina-test --zone us-west1-a