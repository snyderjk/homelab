# Prometheus Monitoring Stack

Complete monitoring solution using kube-prometheus-stack, deployed via GitOps with Flux.

## Components

- **Prometheus** - Metrics collection and storage
- **Alertmanager** - Alert routing and management
- **Grafana** - Visualization and dashboards
- **Node Exporter** - Host-level metrics from all cluster nodes
- **Kube State Metrics** - Kubernetes object metrics

## Version

- **Chart:** kube-prometheus-stack v80.0.0
- **Repository:** https://prometheus-community.github.io/helm-charts

## Storage

All components use persistent storage backed by NFS CSI driver:

| Component | Storage Class | Size | Reclaim Policy |
|-----------|--------------|------|----------------|
| Prometheus | nfs-csi-retain | 10Gi | Retain |
| Alertmanager | nfs-csi-retain | 2Gi | Retain |
| Grafana | nfs-csi-retain | 5Gi | Retain |

**Retention:** Prometheus stores 7 days of metrics data.

## Access

**Grafana Dashboard:**
- URL: http://grafana.snyder.home
- Routed via: Traefik Gateway API (HTTPRoute)
- Credentials: Stored in `grafana-admin` secret (not in Git)

**Prometheus:**
- Internal: http://kube-prometheus-stack-prometheus.monitoring:9090
- Not exposed externally

**Alertmanager:**
- Internal: http://kube-prometheus-stack-alertmanager.monitoring:9093
- Not exposed externally

## Secrets Management

Credentials are stored in Kubernetes Secrets (not committed to Git):

**grafana-admin** - Grafana admin credentials
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: monitoring
stringData:
  admin-user: "admin"
  admin-password: ""
```

**alertmanager-config** - Alertmanager configuration with email settings
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: ''
      smtp_auth_username: ''
      smtp_auth_password: ''
      smtp_require_tls: true
    # ... rest of config
```

**To apply secrets:**
```bash
kubectl apply -f secrets.yaml
```

**Note:** `secrets.yaml` is in `.gitignore` to prevent committing credentials.

## Resources

**Prometheus:**
- Requests: 200m CPU, 512Mi memory
- Limits: 1000m CPU, 2Gi memory

**Alertmanager:**
- Requests: 100m CPU, 128Mi memory
- Limits: 200m CPU, 256Mi memory

**Grafana:**
- Requests: 100m CPU, 256Mi memory
- Limits: 500m CPU, 512Mi memory

## Alerting

**Email Alerts Configured:**
- SMTP: Gmail (smtp.gmail.com:587)
- Requires Gmail App Password (not regular password)
- Alerts sent for critical cluster issues

**Alert Routing:**
- Group by: alertname, cluster, service
- Group wait: 30s
- Group interval: 5m
- Repeat interval: 12h

## Verification

**Check deployment status:**
```bash
# Flux status
flux get helmreleases -n monitoring

# Pod status
kubectl get pods -n monitoring

# PVC status
kubectl get pvc -n monitoring

# HTTPRoute status
kubectl get httproute -n monitoring
```

**Expected pods:**
- alertmanager-kube-prometheus-stack-alertmanager-0
- kube-prometheus-stack-grafana-xxxxx
- kube-prometheus-stack-kube-state-metrics-xxxxx
- kube-prometheus-stack-operator-xxxxx
- kube-prometheus-stack-prometheus-node-exporter-xxxxx (one per node)
- prometheus-kube-prometheus-stack-prometheus-0

## Configuration Notes

**NFS Compatibility:**
- `initChownData.enabled: false` for Grafana
- NFS doesn't support chown operations from containers
- Permissions handled by NFS server settings

**Grafana Sidecars:**
- Dashboard sidecar automatically loads dashboards from ConfigMaps
- Datasource sidecar automatically configures Prometheus datasource
- Both require admin credentials from secret

## Files

```
prometheus/
├── namespace.yaml           # monitoring namespace
├── helmrepository.yaml      # Prometheus Community Helm repo
├── helmrelease.yaml         # kube-prometheus-stack deployment
├── httproute.yaml          # Grafana HTTPRoute (*.snyder.home)
├── kustomization.yaml      # Kustomize resource list
├── secrets.yaml            # NOT IN GIT - local only
└── README.md               # This file
```

## Updating

To update the stack:

1. Edit `helmrelease.yaml` (change version or values)
2. Commit and push to Git
3. Flux automatically reconciles within 10 minutes
4. Or force immediate update:
   ```bash
   flux reconcile kustomization monitoring --with-source
   ```

## Troubleshooting

**Grafana not accessible:**
```bash
# Check pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Check HTTPRoute
kubectl get httproute grafana -n monitoring

# Check if service exists
kubectl get svc -n monitoring | grep grafana
```

**Prometheus not collecting metrics:**
```bash
# Check Prometheus pod logs
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus

# Check ServiceMonitors
kubectl get servicemonitors -n monitoring
```

**Alerts not sending:**
```bash
# Check Alertmanager logs
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0

# Verify secret
kubectl get secret alertmanager-config -n monitoring
```

## Future Enhancements

- [ ] Add SOPS or External Secrets Operator for secret encryption
- [ ] Configure additional alert receivers (Slack, Discord)
- [ ] Add custom Prometheus rules for application-specific alerts
- [ ] Implement Thanos for long-term metric storage
- [ ] Add custom Grafana dashboards for specific workloads

