cat > kubernetes/bootstrap/README.md <<'EOF'
# Kubernetes Cluster Bootstrap

This directory contains the configuration and scripts to bootstrap the homelab Kubernetes cluster.

## Prerequisites

- All nodes have been prepared with Ansible (playbooks 00-04)
- containerd is running on all nodes
- Swap is disabled on all nodes
- Kubernetes tools (kubeadm, kubelet, kubectl) are installed

## Files

- `kubeadm-config.yaml` - Cluster initialization configuration
- `init-cluster.sh` - Initialize control plane
- `install-calico.sh` - Install Calico CNI
- `bootstrap-cluster.sh` - Complete bootstrap process (runs all steps)

## Usage

### Full Bootstrap (Recommended)
```bash
cd kubernetes/bootstrap
./bootstrap-cluster.sh
```

This will:
1. Initialize the control plane
2. Install Calico CNI
3. Join all worker nodes
4. Label nodes appropriately

### Manual Step-by-Step
```bash
# 1. Initialize control plane
./init-cluster.sh

# 2. Install Calico
./install-calico.sh

# 3. Join workers (from ansible directory)
cd ../../ansible
JOIN_CMD=$(grep "kubeadm join" ../kubernetes/bootstrap/join-command.txt)
ansible-playbook playbooks/10-join-workers.yml -e "kubeadm_join_command='$JOIN_CMD'"

# 4. Label nodes
kubectl label node k8s-worker01 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker02 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker03 node-role.kubernetes.io/worker=worker
kubectl label node k8s-gpu01 node-role.kubernetes.io/gpu-worker=gpu-worker
kubectl label node k8s-gpu01 workload=ai
```

## Verification
```bash
# Check all nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check node details
kubectl get nodes -o wide
```

## Troubleshooting

### Node won't join
```bash
# On the problem node
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes /var/lib/kubelet
sudo systemctl restart containerd

# Rejoin
sudo kubeadm join 10.77.1.10:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

### Generate new join token
```bash
ssh jason@k8s-cp01.snyder.home "kubeadm token create --print-join-command"
```
EOF
