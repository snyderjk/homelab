# Vault Backup and Restore Procedures

## Automated Backups

**Schedule:** Daily at 2 AM UTC
**Location:** `s3://vault-homelab-vault-backups-840296800572/snapshots/`
**Retention:** 30 days (automated via S3 lifecycle policy)
**Mechanism:** CronJob in vault namespace

## Verify Backups Are Running

### Check CronJob Status
```bash
kubectl get cronjob vault-backup -n vault
kubectl get jobs -n vault | grep vault-backup
```

### Check recent backup in S3
```bash
aws s3 ls s3://vault-homelab-vault-backups-840296800572/snapshots/ --recursive --human-readable
```

### Check last backup job logs
```bash
# Find the most recent backup job
kubectl get jobs -n vault -l job-name --sort-by=.metadata.creationTimestamp

# View logs
kubectl logs -n vault job/vault-backup-
```


## Manual Backup

[When and why to create manual backup]
[Step-by-step commands]

---

## Restore from Backup

### Prerequisites

- Root token available
- Access to S3 bucket
- kubectl access to vault namespace
- At least one Vault pod running

### Step 1: Download Snapshot from S3
```bash
# List available snapshots
aws s3 ls s3://vault-homelab-vault-backups-840296800572/snapshots/

# Download the desired snapshot (usually most recent)
aws s3 cp s3://vault-homelab-vault-backups-840296800572/snapshots/vault-snapshot-YYYYMMDD-HHMMSS.snap ./restore.snap
```

### Step 2: Verify Snapshot Integrity
```bash
# Copy snapshot to vault pod
kubectl cp ./restore.snap vault/vault-0:/tmp/restore.snap

# Exec into vault pod
kubectl exec -it -n vault vault-0 -- sh

# Set VAULT_TOKEN
export VAULT_TOKEN=<root-token>

# Inside pod: Inspect snapshot
vault operator raft snapshot inspect /tmp/restore.snap
```

**Expected output:**
- ID: bolt-snapshot
- Size: ~30KB (will vary)
- Index, Term, Version numbers
- List of keys and sizes

If inspection fails, the snapshot is corrupted. Try a different backup.

### Step 3: Restore Snapshot

**⚠️ WARNING:** This will overwrite current Vault data. Ensure this is what you want.
```bash
# Inside vault-0 pod
export VAULT_TOKEN=<root-token>

# Restore the snapshot
vault operator raft snapshot restore -force /tmp/restore.snap
```

**Expected output:**
```
Success! Restored snapshot
```

### Step 4: Verify Cluster Health
```bash
# Exit the pod
exit

# Check all pods are healthy
kubectl get pods -n vault

# Verify Raft cluster
kubectl exec -n vault vault-0 -- vault operator raft list-peers

# Test reading a known secret
kubectl exec -n vault vault-0 -- sh -c "export VAULT_TOKEN= && vault kv get secret/apps/demo-app"
```

---

## Manual Backup

To create an ad-hoc backup before major changes:
```bash
# Trigger a manual backup job
kubectl create job -n vault vault-backup-manual-$(date +%Y%m%d) --from=cronjob/vault-backup

# Watch the job
kubectl get jobs -n vault -w

# Verify backup was uploaded
aws s3 ls s3://vault-homelab-vault-backups-840296800572/snapshots/ | tail -5
```

---

## Disaster Recovery Scenarios

### Scenario: Complete Cluster Loss

**Situation:** All Vault pods lost, all PVCs deleted

**Recovery:**
1. Redeploy Vault via Flux (GitOps will recreate resources)
2. Wait for pods to start (they will be sealed and uninitialized)
3. Initialize vault-0: `kubectl exec -n vault vault-0 -- vault operator init`
4. Save new recovery keys and root token
5. Follow restore procedure above using latest S3 backup
6. Join vault-1 and vault-2 to cluster

**RTO:** ~30 minutes  
**RPO:** Last backup (max 24 hours with daily backups)

### Scenario: Single Bad Change

**Situation:** Someone deleted important secrets or policies

**Recovery:**
1. Determine when the bad change occurred
2. Find most recent backup before the change
3. Follow restore procedure with that specific snapshot
4. Verify data is correct

**RTO:** ~10 minutes  
**RPO:** Time since last backup before the change

### Scenario: AWS Credentials Compromised

**Situation:** vault-aws-creds secret leaked or credentials compromised

**Recovery:**
1. Immediately deactivate compromised access key in AWS console
2. Generate new access key via Terraform or AWS console
3. Update Kubernetes secret:
```bash
   kubectl delete secret vault-aws-creds -n vault
   kubectl create secret generic vault-aws-creds -n vault \
     --from-literal=AWS_ACCESS_KEY_ID= \
     --from-literal=AWS_SECRET_ACCESS_KEY= \
     --from-literal=AWS_REGION=us-east-1
```
4. Restart backup CronJob: `kubectl delete pod -n vault -l job-name=vault-backup-<latest>`
5. Restart Vault pods: `kubectl rollout restart statefulset vault -n vault`

**RTO:** ~5 minutes  
**RPO:** None (no data loss)

---

## Testing Restore Procedures

**Frequency:** Quarterly (every 3 months)

**Test Checklist:**
- [ ] Download latest backup from S3
- [ ] Verify snapshot integrity with `inspect`
- [ ] Restore to a test Vault instance (if available)
- [ ] Verify secrets are readable after restore
- [ ] Document any issues or procedure changes
- [ ] Update runbook if procedure changed

---

## Troubleshooting

### Backup Job Fails

**Check logs:**
```bash
kubectl logs -n vault job/vault-backup-
```

**Common issues:**
- AWS credentials expired → Rotate credentials
- S3 bucket permissions → Check IAM policy
- Vault authentication failed → Verify backup-role exists
- Network issues → Check cluster connectivity

### Restore Fails

**Error: "permission denied"**
- Ensure you're using root token or token with sufficient permissions

**Error: "snapshot verification failed"**
- Snapshot may be corrupted
- Try a different backup

**Error: "no leader elected"**
- Wait 30 seconds for leader election
- Check Raft cluster status: `vault operator raft list-peers`

---
