#!/bin/bash
set -e

echo "=== Initializing Kubernetes Control Plane ==="

# Copy config to control plane
scp kubeadm-config.yaml jason@k8s-cp01.snyder.home:~/

# Run kubeadm init
ssh -tt jason@k8s-cp01.snyder.home 'sudo kubeadm init --config=kubeadm-config.yaml --upload-certs' | tee init-output.log

# Extract join command
grep -A 2 "kubeadm join" init-output.log >join-command.txt

echo ""
echo "=== Setup kubeconfig on control plane ==="
ssh -tt jason@k8s-cp01.snyder.home 'mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config'

echo ""
echo "=== Copy kubeconfig to workstation ==="
mkdir -p ~/.kube
scp jason@k8s-cp01.snyder.home:.kube/config ~/.kube/config

echo ""
echo "=== Verify control plane ==="
kubectl get nodes

echo ""
echo "Control plane initialized successfully!"
echo "Join command saved to: join-command.txt"
