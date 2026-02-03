# Homelab Kubernetes Platform

A production-grade Kubernetes homelab built with Infrastructure as Code (Ansible) and GitOps (Flux), demonstrating modern DevOps practices and cloud-native technologies.

## Overview

This homelab runs a 5-node Kubernetes cluster (v1.34.1) with automated infrastructure provisioning, GitOps-based application deployment, and enterprise-grade networking and storage solutions.

**Infrastructure:**
- 1x Control Plane (k8s-cp01)
- 3x Worker Nodes (k8s-worker01-03)
- 1x GPU Node (k8s-gpu01)

**Core Technologies:**
- Infrastructure as Code: Ansible for cluster provisioning and base infrastructure
- GitOps: Flux for continuous deployment from Git
- Networking: Calico CNI, MetalLB load balancing, Traefik Gateway API
- Storage: Synology NAS (NFS CSI driver) for persistent volumes
- Container Runtime: containerd 2.2.0

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Management Network (10.17.1.0/24)                           │
│ - Synology DS423+ NAS (10.17.1.5)                          │
│ - Management hosts                                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            │
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster Network (10.77.1.0/24)                   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Control Plane (10.77.1.10)                           │  │
│  │ - Kubernetes API Server                               │  │
│  │ - etcd, Controller Manager, Scheduler                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Worker Nodes (10.77.1.11-14)                         │  │
│  │ - Application workloads                               │  │
│  │ - Storage: NFS CSI → Synology NAS                    │  │
│  │ - Networking: Calico CNI                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ LoadBalancer Services (10.77.1.200-250)             │  │
│  │ - MetalLB IP Pool                                     │  │
│  │ - Traefik Gateway (10.77.1.201)                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Features

### Infrastructure as Code (Ansible)
- Automated cluster deployment - Complete cluster setup in minutes
- Idempotent operations - Safe to run repeatedly
- Modular design - Roles for storage, networking, GitOps
- Version controlled - All infrastructure defined in Git

### GitOps with Flux
- Declarative deployments - Kubernetes manifests in Git as source of truth
- Automatic reconciliation - Flux syncs cluster state with Git every 10 minutes
- Pull-based model - No CI/CD access to cluster credentials needed
- Multi-environment ready - Structured for future expansion

### Networking
- Calico CNI - Network policies and pod networking
- MetalLB - LoadBalancer service support on bare metal
- Traefik Gateway API - Modern ingress with Gateway API (not legacy Ingress)
- Layer 2 mode - ARP-based IP advertisement for home networks

### Storage
- Dynamic provisioning - Automatic PV creation from PVCs
- NFS CSI Driver - Kubernetes-native NFS integration
- Multiple storage classes - Delete and Retain policies
- Synology DS423+ backend - Enterprise NAS features at homelab scale

## Project Structure

```
homelab/
├── ansible/                    # Infrastructure provisioning
│   ├── inventory/             # Cluster inventory and variables
│   ├── playbooks/             # Cluster setup playbooks
│   └── roles/                 # Reusable Ansible roles
│       ├── nfs-provisioner/   # NFS CSI storage
│       ├── metallb/           # Load balancer
│       └── flux/              # GitOps bootstrap
│
└── kubernetes/                # GitOps-managed resources
    ├── clusters/
    │   └── homelab/          # Cluster-specific configs
    │       ├── infrastructure.yaml
    │       └── apps.yaml
    ├── infrastructure/        # Platform services
    │   └── traefik/          # Gateway API controller
    └── apps/                  # Applications
        └── test-app/         # Example application
```

## Quick Start

### Prerequisites
- 5 Ubuntu 24.04 LTS nodes with network connectivity
- Ansible 2.15+ on control machine
- kubectl configured
- Synology NAS with NFS enabled

### Deploy the Cluster

```bash
# Clone the repository
git clone https://github.com/snyderjk/homelab.git
cd homelab/ansible

# Review and update inventory
vim inventory/homelab.yml

# Deploy complete stack
ansible-playbook -i inventory/homelab.yml playbooks/site.yml
```

This will:
1. Bootstrap the Kubernetes cluster
2. Install Calico CNI
3. Configure NFS storage
4. Deploy MetalLB load balancer
5. Bootstrap Flux GitOps
6. Deploy Traefik Gateway API controller


## Technology Stack

| Component | Technology | Version | Purpose |
|-----------|-----------|---------|---------|
| OS | Ubuntu Server | 24.04 LTS | Base operating system |
| Container Runtime | containerd | 2.2.0 | Container execution |
| Kubernetes | Kubernetes | 1.34.1 | Container orchestration |
| CNI | Calico | Latest | Pod networking and network policies |
| Storage | NFS CSI Driver | Latest | Dynamic volume provisioning |
| Load Balancer | MetalLB | 0.15.3 | LoadBalancer service implementation |
| Gateway | Traefik | 37.4.0 | Ingress controller (Gateway API) |
| GitOps | Flux | 2.4.0 | Continuous deployment |
| IaC | Ansible | 2.15+ | Infrastructure provisioning |

## Network Configuration

- **Management VLAN:** 10.17.1.0/24
  - Synology NAS: 10.17.1.5
  - Administrative access
  
- **Cluster VLAN:** 10.77.1.0/24
  - Control Plane: 10.77.1.10
  - Worker Nodes: 10.77.1.11-14
  - Pod Network: 10.244.0.0/16 (Calico)
  - Service Network: 10.96.0.0/12
  
- **MetalLB Pool:** 10.77.1.200-250
  - 51 available IPs for LoadBalancer services
  - Currently assigned:
    - 10.77.1.201: Traefik Gateway

## Storage Configuration

**NFS Storage Classes:**
- `nfs-csi` - Delete reclaim policy (ephemeral data)
- `nfs-csi-retain` - Retain reclaim policy (persistent data)

**Backend:** Synology DS423+ NAS
- Share: `/volume1/kubernetes-nfs`
- Protocol: NFSv4.1
- Access: 10.77.1.0/24 subnet

## Contributing

This is a personal homelab project, but feel free to use it as a reference for your own setup. Issues and suggestions are welcome.

## License

MIT License - See [LICENSE](LICENSE) file for details.
