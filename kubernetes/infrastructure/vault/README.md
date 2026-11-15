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

### 5. Personal admin login, then revoke root
All doable in the UI (signed in with the root token):
1. Policies → Create ACL policy `admin`:
   `path "*" { capabilities = ["create","read","update","patch","delete","list","sudo"] }`
2. Access → Auth methods → enable **userpass** → create your user → Edit user →
   Tokens → **Generated Token's Policies**: `admin`.
3. Sign out, sign in as yourself (Method: Username) and confirm you can open Policies.
4. Signed in as root, open the web console (`>_`) and run `write -force auth/token/revoke-self`.
   Remove the root token from the password manager; **keep the recovery keys**.

Need root again (locked out of userpass, etc.): `vault operator generate-root` with 3 of 5 recovery keys.

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
## Backups → S3
`config/backup.yaml`: CronJob `vault-backup`, nightly 03:00 America/Chicago. Raft snapshot
(everything: secrets, policies, auth config) → `s3://vault-homelab-vault-backups-840296800572/snapshots/`.
It logs in with its own Kubernetes-auth role; the only thing it can do in Vault is take a snapshot.

One-time Vault setup (admin token — your userpass login — with the `v` helper from step 3):
```bash
printf 'path "sys/storage/raft/snapshot" { capabilities = ["read"] }\n' | v policy write vault-backup -
v write auth/kubernetes/role/vault-backup \
  bound_service_account_names=vault-backup bound_service_account_namespaces=vault \
  policies=vault-backup ttl=15m
```
Run one now instead of waiting for 03:00:
```bash
kubectl -n vault create job --from=cronjob/vault-backup vault-backup-manual-$(date +%s)
kubectl -n vault logs -f job/<that job> --all-containers
```
**Retention** — S3 lifecycle rule on the bucket (console → bucket → Management → Create
lifecycle rule, prefix `snapshots/`): expire current versions after 30 days, permanently
delete noncurrent versions after 7 days.

**Restore** (new or existing cluster, same KMS key): deploy Vault, init it (throwaway),
then with that temporary root token:
```bash
kubectl -n vault cp vault-YYYYmmdd-HHMMSS.snap vault-0:/tmp/restore.snap
kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=… vault operator raft snapshot restore -force /tmp/restore.snap
```
After restore the old cluster's recovery keys + root token apply again.
