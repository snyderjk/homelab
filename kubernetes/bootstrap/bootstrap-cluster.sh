#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Kubernetes Homelab Cluster Bootstrap"
echo "=========================================="
echo ""

# Step 1: Initialize control plane
echo "Step 1/4: Initializing control plane..."
./init-cluster.sh

echo ""
read -p "Control plane initialized. Press Enter to install CNI..."

# Extract join command
# need to correct the join-command.txt to only have the non --contral plan flag
# and move command onto a single line
K8S_JOIN_CMD=$(grep "kubeadm join" join-command.txt | sed 's/^[[:space:]]*//')

# Step 2: Install Calico
echo ""
echo "Step 2/4: Installing Calico CNI..."
./install-calico.sh

echo ""
read -p "Calico installed. Press Enter to join workers..."

# Step 3: Join workers
echo ""
echo "Step 3/4: Joining worker nodes..."
cd ../../ansible

echo "Join command: $JOIN_CMD"
echo ""

ansible-playbook playbooks/04-join-workers.yml -e "kubeadm_join_command='$K8S_JOIN_CMD'" -k -K

cd ../kubernetes/bootstrap

echo ""
echo "Step 4/4: Labeling nodes..."
sleep 10

kubectl label node k8s-worker01 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-worker02 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-worker03 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-gpu01 node-role.kubernetes.io/gpu-worker=gpu-worker --overwrite
kubectl label node k8s-gpu01 workload=ai --overwrite

echo ""
echo "=========================================="
echo "Cluster Bootstrap Complete!"
echo "=========================================="
echo ""
kubectl get nodes -o wide

echo ""
echo "Next steps:"
echo "1. Verify all nodes are Ready"
echo "2. Check pods: kubectl get pods -A"
echo "3. Proceed to Phase 5 (MetalLB, ingress, etc.)"
