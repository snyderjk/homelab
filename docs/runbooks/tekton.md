At this point there is not an officially supported way to install with flux. Best path right now is to install like below 

# Pipelins
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Dashboard
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml
