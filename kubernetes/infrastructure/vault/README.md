# Vault HA - Kubernetes Deployment

Production-grade HashiCorp Vault HA cluster with AWS KMS auto-unseal running on homelab Kubernetes.

## Architecture
```
Homelab K8s Cluster (3-node Vault HA + Raft)
         ↓
   AWS KMS (auto-unseal)
         ↓
   S3 Bucket (backups - planned)
```

**Hybrid approach:** Compute runs in homelab (free), AWS provides trust anchor for auto-unseal (~$1-2/month).

## What's Deployed

- **Vault:** 3 replicas with Raft integrated storage
- **Storage:** NFS-CSI persistent volumes (10Gi each, retain policy)
- **Auto-Unseal:** AWS KMS integration (no manual unseal needed)
- **Access:** HTTPS via Traefik Gateway API at `vault.snyderhomelab.com`
- **TLS:** Let's Encrypt via cert-manager
- **Network:** Internal homelab only (not public)

## Prerequisites

- AWS infrastructure deployed (see `../../terraform/vault-aws/README.md`)
- AWS credentials saved from Terraform outputs
- Flux CD managing this cluster
- Traefik Gateway API controller
- cert-manager
- NFS-CSI provisioner

## Deployment Steps

### 1. Create Kubernetes Secret (One-Time Bootstrap)

This is **"secret zero"** - the one manual step:
```bash
kubectl create namespace vault

kubectl create secret generic vault-aws-creds -n vault \
  --from-literal=AWS_ACCESS_KEY_ID=<from-terraform-output> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<from-terraform-output> \
  --from-literal=AWS_REGION=us-east-1
```

**⚠️ Note:** This secret is NOT in Git. Must be recreated on cluster rebuilds.

### 2. Deploy via Flux

Flux automatically deploys from Git:
```bash
flux reconcile kustomization flux-system --with-source
kubectl get pods -n vault -w
```

### 3. Initialize Vault (One-Time)

When pods are running but not ready:
```bash
kubectl exec -it -n vault vault-0 -- vault operator init
```

**⚠️ CRITICAL:** Save the recovery keys and root token to your password manager immediately!

### 4. Join Raft Cluster

**TODO:** Automate this with retry_join config. For now, manual:
```bash
kubectl exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
```

### 5. Verify

- Access UI: `https://vault.snyderhomelab.com`
- Login with root token
- Check Monitoring → Raft Storage (should show 3 nodes)

## Test Auto-Unseal
```bash
# Delete a standby pod
kubectl delete pod vault-1 -n vault

# Watch it restart and auto-unseal (no manual intervention!)
kubectl get pods -n vault -w
```

## Test Leader Failover
```bash
# Delete the leader
kubectl delete pod vault-0 -n vault

# Watch new leader election in UI
# vault-0 rejoins as standby automatically
```

## Key Configuration

**Vault Config:**
- 3 replicas (HA with Raft quorum)
- KMS key ID: `e65746b3-f625-4554-8ad5-3b7e254b5f02`
- Storage: `/vault/data` on NFS PVCs
- Resources: 256Mi-512Mi memory, 250m-500m CPU

**Network:**
- Service: `vault-active` (points to leader)
- HTTPRoute via Traefik Gateway API
- TLS cert: `vault-tls` (Let's Encrypt)

## Common Commands
```bash
# Check cluster status
kubectl get pods -n vault
kubectl exec -n vault vault-0 -- vault status

# List Raft peers
kubectl exec -n vault vault-0 -- vault operator raft list-peers

# View logs
kubectl logs -n vault vault-0

# Restart all pods
kubectl rollout restart statefulset vault -n vault
```

## Disaster Recovery

**Scenario: Complete cluster loss**

1. Recreate AWS credentials secret (step 1 above)
2. Flux redeploys Vault
3. Restore from S3 backup:
```bash
   kubectl exec -n vault vault-0 -- vault operator raft snapshot restore /tmp/backup.snap
```

**Scenario: AWS credentials compromised**

1. Deactivate key in AWS console
2. Generate new access key
3. Update K8s secret and restart pods

## TODO

- [ ] Automate Raft join with retry_join config
- [ ] Create CronJob for daily snapshots to S3
- [ ] Enable Kubernetes auth method
- [ ] Set up Prometheus monitoring
- [ ] Deploy External Secrets Operator integration
- [ ] Disable root token after creating admin policies

## Files
```
vault/
├── namespace.yaml          # Vault namespace
├── helmrepository.yaml     # HashiCorp Helm repo
├── helmrelease.yaml        # Vault deployment config
├── httproute.yaml          # Traefik Gateway API route
├── certificate.yaml        # Let's Encrypt TLS cert
└── kustomization.yaml      # Flux resources
```

## Related Docs

- AWS Infrastructure: `../../terraform/vault-aws/README.md`
- Vault Documentation: https://developer.hashicorp.com/vault/docs
- Helm Chart: https://github.com/hashicorp/vault-helm

---

**Status:** ✅ Deployed and operational
