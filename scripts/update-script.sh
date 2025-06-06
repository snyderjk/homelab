#!/bin/bash

read -p 'What is the Kubernetes minor version you are updating to: ' minor_version

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.${minor_version}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.${minor_version}/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

apt update && apt upgrade -y
apt-cache madison kubeadm

read -p 'What version are you updating to: ' full_version

apt-mark unhold kubeadm
apt-get update && apt-get install -y "kubeadm=${full_version}"
apt-mark hold kubeadm

if [ "$HOSTNAME" = "k8-cp-01" ]; then
  base_version="${full_version%%-*}"
  kubeadm upgrade plan
  kubeadm upgrade apply v"${base_version}"
fi

kubectl drain "{$HOSTNAME}" --ignore-daemonsets

apt-mark unhold kubelet kubectl
apt-get update && sudo apt-get install -y "kubelet=${full_version}" "kubectl=${full_version}"
apt-mark hold kubelet kubectl

if [ "$HOSTNAME" != "k8-cp-01" ]; then
  kubeadm upgrade node
fi

systemctl daemon-reload
systemctl restart kubelet

kubectl uncordon "${HOSTNAME}"
