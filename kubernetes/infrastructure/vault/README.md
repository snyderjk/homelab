# Vault (HA Raft, AWS KMS auto-unseal) + External Secrets

- **Vault 2.2.1**, 3 Raft voters (`vault-0..2`), data on `nas-iscsi` (10Gi) + audit (5Gi)
- **Auto-unseal**: AWS KMS key `alias/vault-homelab-vault-unseal` (us-east-1), IAM user
  `vault-homelab-vault-kms-user` — infra from `~/Repos/homelab-archive/terraform/vault-aws`
- **TLS everywhere**: `vault-tls` (homelab-ca) for API 8200 and Raft 8201; joins are automatic (`retry_join`)
- **UI/API**: https://vault.snyderhomelab.com (LAN + WireGuard only — no Pangolin resource)
- **In-cluster**: `https://vault-active.vault.svc:8200` (trust `homelab-ca`)
- **External Secrets**: `ClusterSecretStore/vault` → KV v2 at `secret/`, Kubernetes auth role `external-secrets`

## Bootstrap (once per cluster build)

### 1. AWS credentials — "secret zero" (never in git)
Use a **fresh access key** for `vault-homelab-vault-kms-user` (IAM → Users → Security
credentials), and deactivate the old cluster's key.
```bash
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
printf 'AWS access key id: '; read -r AKID
printf 'AWS secret access key: '; stty -echo; read -r SAK; stty echo; echo
# strip pasted CR/whitespace (a copied \r broke signing once: InvalidSignatureException)
AKID=$(printf %s "$AKID" | tr -d '\r[:space:]'); SAK=$(printf %s "$SAK" | tr -d '\r[:space:]')
echo "lengths: ${#AKID} ${#SAK}   (want: 20 40)"
kubectl -n vault create secret generic vault-aws-creds \
  --from-literal=AWS_ACCESS_KEY_ID="$AKID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$SAK" \
  --from-literal=AWS_REGION=us-east-1
unset SAK
```

### 2. Initialize (one time — prints the recovery keys + root token)
Pods run but stay `0/1` (sealed/uninitialized) until this:
```bash
kubectl -n vault exec -it vault-0 -- vault operator init -recovery-shares=5 -recovery-threshold=3
```
**Store the 5 recovery keys and the root token in your password manager.** With KMS
auto-unseal, recovery keys are not needed to unseal — they are for root token
regeneration and recovery operations. Losing them all is unrecoverable for those ops.
`vault-1`/`vault-2` join automatically; all three should go `1/1` within a minute.

### 3. Configure KV, Kubernetes auth, External Secrets access
```bash
printf 'Vault root token: '; stty -echo; read -r VT; stty echo; echo
v() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$VT" vault "$@"; }

v secrets enable -path=secret kv-v2
v auth enable kubernetes
v write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc
printf 'path "secret/data/*" { capabilities = ["read"] }\npath "secret/metadata/*" { capabilities = ["read", "list"] }\n' \
  | v policy write external-secrets -
v write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets ttl=1h
v audit enable file file_path=/vault/audit/vault_audit.log
v operator raft list-peers
unset VT
```

### 4. Verify External Secrets
```bash
kubectl get clustersecretstore vault   # READY=True, "store validated"
```

## Using it from an app
```bash
# write (vault CLI as above, or the UI)
v kv put secret/n8n/db password='…'
```
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: {name: n8n-db, namespace: n8n}
spec:
  refreshInterval: 1h
  secretStoreRef: {kind: ClusterSecretStore, name: vault}
  target: {name: n8n-db}
  data:
    - secretKey: password
      remoteRef: {key: n8n/db, property: password}   # secret/data/n8n/db
```

## Operations
```bash
kubectl -n vault exec vault-0 -- vault status
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=… vault operator raft list-peers
kubectl -n vault delete pod vault-1   # comes back and auto-unseals via KMS
```
Backups (Raft snapshots → S3 bucket `vault-homelab-vault-backups-840296800572`): next step.
