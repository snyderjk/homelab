#!/bin/bash
set -e

script_dir="$(cd "$(dirname "${bash_source[0]}")" && pwd)"

# Setup Work
cd ../../ansible
ansible-playbook playbooks/00-bootstrap.yml -k -K
ansible-playbook playbooks/01-k8s-prereqs.yml -k -K
ansible-playbook playbooks/02-gpu-setup.yml -k -K
ansible-playbook playbooks/03-containerd-CRI-fix.yml -k -K

echo "=========================================="
echo "kubernetes homelab cluster bootstrap"
echo "=========================================="
echo ""

cd "$script_dir"

# step 1: initialize control plane
echo "step 1/4: initializing control plane..."
./init-cluster.sh

echo ""
read -p "control plane initialized. press enter to install cni..."

# clean up extra newlines in join-command
sed -i 's/\r$//' join-command.txt

# extract join command
k8s_join_cmd=$(awk '
/^kubeadm join/ {
  cmd=$0
  while (getline && $0 !~ /^--$/ && $0 !~ /^$/) {
    cmd = cmd " " $0
  }
  if (cmd !~ /--control-plane/) {
    gsub(/\\[[:space:]]*/, "", cmd)  # remove backslashes
    print cmd
  }
}' join-command.txt)

# step 2: install calico
echo ""
echo "step 2/4: installing calico cni..."
./install-calico.sh

echo ""
read -p "calico installed. press enter to join workers..."

# step 3: join workers
echo ""
echo "step 3/4: joining worker nodes..."
cd ../../ansible

echo "join command: $k8s_join_cmd"
echo ""

ansible-playbook playbooks/04-join-workers.yml -e "kubeadm_join_command='$k8s_join_cmd'" -k -K

cd ../kubernetes/bootstrap

echo ""
echo "step 4/4: labeling nodes..."
sleep 10

kubectl label node k8s-worker01 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-worker02 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-worker03 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-gpu01 node-role.kubernetes.io/gpu-worker=gpu-worker --overwrite
kubectl label node k8s-gpu01 workload=ai --overwrite

echo ""
echo "=========================================="
echo "cluster bootstrap complete!"
echo "=========================================="
echo ""
kubectl get nodes -o wide
