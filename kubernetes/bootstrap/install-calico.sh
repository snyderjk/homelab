#!/bin/bash
set -e

echo "=== Downloading Calico manifest ==="
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml

echo ""
echo "=== Installing Calico CNI ==="
kubectl apply -f calico.yaml

echo ""
echo "=== Waiting for Calico pods to be ready ==="
echo "This may take 1-2 minutes..."

kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s

echo ""
echo "=== Verify control plane is Ready ==="
kubectl get nodes

echo ""
echo "Calico installed successfully!"
