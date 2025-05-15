Kubernetes Homelab — Self-Hosted Cloud Infrastructure
Welcome! This repo documents my personal Kubernetes homelab—a hands-on project to deepen my skills in DevOps, cloud-native infrastructure, and system administration. This environment emulates a small-scale production setup and is used to deploy, manage, and monitor real-world applications.

⚙️ Architecture Overview
Control Plane:

Host: Dell laptop with NVIDIA RTX 3060 Mobile GPU

OS: Ubuntu Server

Installed via: kubeadm

Purpose: API server, scheduler, controller manager, GPU inference workloads (e.g., Mistral 7B)

Worker Nodes (3 total):

CPU: 4 cores each

RAM: 16 GB each

Storage: 256 GB HDD

OS: Ubuntu Server

Managed via kubeadm join

CNI Plugin: Calico

Load Balancer: MetalLB

Ingress: NGINX

Networking: VLAN segmentation via pfSense and UniFi gear

VLANs for home network, homelab, IoT, security devices, and work access

🚀 Deployed Applications
Linkding — Self-hosted bookmark manager (externally accessible)

Homepage — Personal dashboard with service health and quick links

UniFi Admin Controller — Network controller running in-cluster

Monitoring Stack (in progress) — Prometheus + Grafana + node-exporter

🔍 Key Features
GitOps-ready: Declarative YAML deployments and Git-based config tracking

Self-Hosted LLM Inference: Mistral 7B running with llama-cpp-python, GPU accelerated

Public Access: Select services exposed using secure ingress with Let's Encrypt

Security Best Practices: Role-based access control (RBAC), namespace isolation, and VLAN-based network segmentation

Automation: Plans to integrate Ansible for repeatable provisioning and CI/CD with GitHub Actions

🎯 Goals
Prepare for CKA and AWS Solutions Architect – Associate certifications

Master Linux system administration (LFCS in progress)

Build expertise in DevOps and cloud-native technologies

Transition from software engineering to infrastructure and platform engineering

🛠️ Roadmap
 Add CI/CD pipeline for automated deployment

 Expand monitoring stack with alerts and dashboards

 Integrate SSO for web services

 Migrate homelab secrets to HashiCorp Vault or AWS Secrets Manager

 Publish blog tutorials based on homelab setup

💼 About Me
I'm a senior software engineer with 20+ years of experience, currently transitioning into DevOps and cloud infrastructure. This homelab serves as my proving ground for mastering modern tools and practices, and showcases my ability to design, build, and operate production-like systems.

