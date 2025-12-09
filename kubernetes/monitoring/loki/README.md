# Loki Logging Stack

Log aggregation solution using Loki and Grafana Alloy, deployed via GitOps with Flux.

## Components

- **Loki** - Log aggregation and storage backend
- **Grafana Alloy** - Modern log collector (replaces deprecated Promtail)
- **Loki Gateway** - API gateway for Loki endpoints

## Version

- **Loki Chart:** v6.46.0
- **Alloy Chart:** v1.5.0
- **Repository:** https://grafana.github.io/helm-charts

## Architecture

```
Pod Logs (/var/log/pods/*)
    ↓
Alloy DaemonSet (collects from all nodes)
    ↓
Loki Gateway (http://loki-gateway)
    ↓
Loki Single Binary (aggregation + storage)
    ↓
NFS Persistent Storage (10Gi)
```

## Deployment Mode

**Single Binary Mode:**
- All Loki components in one process
- Suitable for small-to-medium scale (homelab perfect)
- Simpler to operate and troubleshoot
- Can scale to distributed mode later if needed

## Storage

**Loki:**
- Storage Class: `nfs-csi-retain`
- Size: 10Gi
- Reclaim Policy: Retain
- Backend: Synology DS423+ NAS via NFS

**Storage Type:** Filesystem (local to Loki pod)
- Schema: v13 (TSDB)
- Index: 24h period
- Alternative: S3-compatible storage for production scale

## Log Collection

**Grafana Alloy:**
- Deployment: DaemonSet (one pod per node)
- Total Pods: 5 (one per cluster node)
- Collection Method: Direct file reading from `/var/log/pods/`
- Processing: CRI log format parsing

**Why Alloy over Promtail:**
- Promtail is EOL March 2026
- Alloy is the modern replacement (Grafana's unified agent)
- Better configuration language
- More powerful processing capabilities
- Future-proof choice

## Labels Collected

Alloy automatically extracts and applies these labels to all logs:

- `namespace` - Kubernetes namespace
- `pod` - Pod name
- `container` - Container name
- `node` - Node name
- `app` - Application name (from labels)

## Access

**Loki API:**
- Internal: `http://loki-gateway.monitoring.svc.cluster.local`
- Short name (within namespace): `http://loki-gateway`
- Port: 80
- Not exposed externally

**Query via Grafana:**
- URL: http://grafana.snyder.home
- Datasource: "Loki" (auto-configured)
- Interface: Explore tab

## Grafana Integration

Loki is automatically added as a datasource to Grafana via ConfigMap:
- ConfigMap: `grafana-loki-datasource`
- Label: `grafana_datasource: "1"` (triggers auto-loading)
- URL: `http://loki-gateway`
- Max Lines: 1000 (default query limit)

## Resources

**Loki:**
- Requests: 100m CPU, 256Mi memory
- Limits: 500m CPU, 512Mi memory

**Alloy (per DaemonSet pod):**
- Requests: 100m CPU, 128Mi memory
- Limits: 200m CPU, 256Mi memory

## Common LogQL Queries

**All logs from a namespace:**
```logql
{namespace="monitoring"}
```

**Logs from specific pod:**
```logql
{pod="loki-0"}
```

**Search for errors:**
```logql
{namespace=~".+"} |~ "(?i)error|exception|fatal"
```

**Search for warnings:**
```logql
{namespace=~".+"} |~ "(?i)warn|warning"
```

**Count errors by pod (last 5 minutes):**
```logql
sum by (pod, namespace) (count_over_time({namespace=~".+"} |~ "(?i)error" [5m]))
```

**Top 10 pods with most errors (last hour):**
```logql
topk(10, sum by (pod, namespace) (count_over_time({namespace=~".+"} |~ "(?i)error" [1h])))
```

**Exclude noise:**
```logql
{namespace="monitoring"} 
  |~ "(?i)error" 
  != "context canceled"
  != "connection reset"
```

## Verification

**Check deployment status:**
```bash
# Flux status
flux get helmreleases -n monitoring | grep loki

# Loki pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# Alloy DaemonSet
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy

# Loki service
kubectl get svc -n monitoring loki-gateway
```

**Expected pods:**
- `loki-0` - Loki single binary
- `loki-gateway-xxxxx` - API gateway
- `loki-chunks-cache-0` - Cache for chunks
- `loki-results-cache-0` - Cache for query results
- `loki-canary-xxxxx` - Health check canaries (one per node)
- `alloy-xxxxx` - Log collectors (one per node, 5 total)

**Test Loki API:**
```bash
# From within cluster
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- \
  curl -s http://loki-gateway/loki/api/v1/labels

# Should return JSON with label names
```

**Test log ingestion:**
```bash
# Check Alloy is sending logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=50

# Should see log processing, no connection errors
```

## Configuration

**Loki Configuration:**
- Auth: Disabled (single-tenant)
- Replication Factor: 1 (single instance)
- Retention: Indefinite (limited by storage size)
- Compaction: Enabled

**Alloy Configuration:**
- Discovery: Kubernetes pod role
- Relabeling: Automatic label extraction
- Processing: CRI format parsing
- Batching: Default (improves efficiency)

## Files

```
loki/
├── helmrepository.yaml     # Grafana Helm repo
├── helmrelease.yaml        # Loki deployment
├── alloy-helmrelease.yaml  # Alloy log collector
├── kustomization.yaml      # Kustomize resource list
└── README.md              # This file
```

## Updating

To update the stack:

1. Edit `helmrelease.yaml` or `alloy-helmrelease.yaml` (change version or values)
2. Commit and push to Git
3. Flux automatically reconciles within 10 minutes
4. Or force immediate update:
   ```bash
   flux reconcile kustomization monitoring --with-source
   ```

## Troubleshooting

**Loki not receiving logs:**
```bash
# Check Alloy logs for errors
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100

# Common issues:
# - Connection refused: Check loki-gateway service exists
# - Permission denied: Check Alloy RBAC and service account
# - No logs appearing: Check discovery.kubernetes is finding pods
```

**Alloy pod not starting:**
```bash
# Check pod status
kubectl describe pod -n monitoring -l app.kubernetes.io/name=alloy

# Check config syntax
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy -c config-reloader
```

**Grafana can't query Loki:**
```bash
# Verify datasource exists
kubectl get configmap -n monitoring grafana-loki-datasource

# Check if Grafana loaded it
# In Grafana: Connections → Data sources → look for "Loki"

# Test connection from Grafana pod
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- \
  curl -s http://loki-gateway/loki/api/v1/labels
```

**High memory usage:**
```bash
# Check Loki memory
kubectl top pod -n monitoring loki-0

# Consider:
# - Reducing log retention (add retention period in Loki config)
# - Increasing memory limits
# - Implementing log filtering in Alloy to reduce volume
```

**Slow queries:**
```bash
# Check query performance in Grafana
# - Reduce time range
# - Add more specific label filters
# - Use stream selectors instead of line filters when possible

# Example:
# Slow:   {namespace=~".+"} |~ "error"
# Fast:   {namespace="monitoring", pod="loki-0"} |~ "error"
```

## Alloy Configuration Language

Alloy uses a River configuration language (not YAML). Key concepts:

**Components:** Building blocks (discovery, relabel, process, write)
**Pipelines:** Components connected with `forward_to`
**Receivers:** Input for components (`.receiver`)

Example pipeline:
```
discovery.kubernetes → discovery.relabel → loki.source.kubernetes → loki.process → loki.write
```

## Performance Tips

**Optimize log volume:**
- Filter noisy pods at Alloy level
- Use label matchers in queries (faster than regex on content)
- Limit time range in queries

**Reduce storage:**
- Implement retention policies
- Compress old logs
- Filter debug-level logs

**Scale up:**
- Move to distributed mode when single binary maxes out
- Add more replicas for high availability
- Use object storage (S3) for unlimited retention

## Future Enhancements

- [ ] Implement log retention policies (auto-delete old logs)
- [ ] Add structured log parsing for JSON logs
- [ ] Create pre-built Grafana dashboards for common queries
- [ ] Set up alerts for log error rates
- [ ] Configure log filtering to reduce noise
- [ ] Migrate to distributed Loki mode if scale demands
- [ ] Add S3-compatible storage for long-term retention
- [ ] Implement log sampling for high-volume applications

## Notes

**Log retention:**
- Currently unlimited (constrained by 10Gi storage)
- Monitor storage usage: `kubectl exec -n monitoring loki-0 -- df -h`
- Implement retention when storage fills

