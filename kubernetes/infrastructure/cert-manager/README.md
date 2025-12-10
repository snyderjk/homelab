# cert-manager

Automated TLS certificate management for Kubernetes using cert-manager with Let's Encrypt and self-signed issuers.

## Overview

cert-manager automates the creation, renewal, and management of TLS certificates in the homelab cluster. This eliminates manual certificate tracking, prevents expiration-related outages, and provides production-grade certificate lifecycle management.

**Key capabilities:**
- Automatic certificate issuance and renewal
- Let's Encrypt integration via DNS-01 challenge
- Self-signed certificates for internal-only services
- Integration with Traefik Gateway API for automatic TLS termination
- GitOps-managed deployment via Flux

## Architecture

### Certificate Issuers

Two ClusterIssuers are configured to support different certificate use cases:

**`letsencrypt-prod`** - Production Let's Encrypt certificates
- Uses DNS-01 challenge via Cloudflare API
- Issues trusted certificates for public domains
- Automatic 90-day renewal (30 days before expiry)
- Suitable for: External-facing services, services requiring browser trust

**`selfsigned-issuer`** - Self-signed certificates
- Generates self-signed certificates on demand
- No external dependencies or challenges required
- Suitable for: Internal-only services, development environments

### Certificate Strategy

**Wildcard Certificate**: `*.snyderhomelab.com`
- Single certificate covers all subdomains
- Reduces API calls to Let's Encrypt
- Simplifies certificate management
- Stored as secret: `snyderhomelab-wildcard-tls` in `traefik` namespace

**Individual Certificates**: Optional per-service certificates
- See `apps/test-app/certificate.yaml` (commented) for reference
- Useful when specific certificate requirements exist
- Not necessary when wildcard certificate covers the domain

### Integration with Gateway API

The Traefik Gateway references the wildcard certificate for HTTPS termination:

```yaml
# infrastructure/traefik/gateway.yaml
listeners:
  - name: https
    protocol: HTTPS
    port: 8443
    tls:
      mode: Terminate
      certificateRefs:
        - name: snyderhomelab-wildcard-tls
```

HTTPRoutes automatically inherit TLS configuration from the Gateway - no per-route certificate configuration needed.

### Split-Horizon DNS Architecture

The same domain names work both internally and externally:

**External DNS (Cloudflare)**:
- `*.snyderhomelab.com` → Pangolin VPS (66.63.163.124)
- TLS terminates at Pangolin with its own Let's Encrypt cert
- Traffic tunnels via WireGuard (Newt) to homelab

**Internal DNS (pfSense)**:
- `*.snyderhomelab.com` → Traefik LoadBalancer (10.77.1.201)
- TLS terminates at Gateway using cert-manager wildcard certificate
- Traffic stays local, never leaves network

This architecture provides:
- Trusted certificates everywhere (no self-signed CA import needed)
- Local traffic never hairpins through VPS
- Identical URLs work internally and externally
- Better performance for internal access

## Deployed Resources

### Namespace
- `cert-manager` - Isolated namespace for cert-manager components

### Helm Releases
- `cert-manager` (v1.19.1) - Core cert-manager controller and webhook
  - CRDs auto-installed via Helm
  - Gateway API support enabled

### ClusterIssuers
- `letsencrypt-prod` - Let's Encrypt production ACME issuer
  - Server: `https://acme-v02.api.letsencrypt.org/directory`
  - Challenge: DNS-01 via Cloudflare
  - Email: snyderjk@gmail.com
  
- `selfsigned-issuer` - Self-signed certificate issuer
  - No external dependencies
  - Instant certificate generation

### Certificates
- `snyderhomelab-wildcard-tls` - Wildcard certificate for `*.snyderhomelab.com`
  - Issuer: `letsencrypt-prod`
  - DNS Names: `*.snyderhomelab.com`, `snyderhomelab.com`
  - Namespace: `traefik`
  - Auto-renewal: 30 days before expiry
  - Valid for: 90 days (Let's Encrypt standard)

### Secrets
- `cloudflare-api-token` - Cloudflare API token for DNS-01 challenge
  - Namespace: `cert-manager`
  - Managed manually (not in Git)
  - Required for Let's Encrypt DNS validation

- `snyderhomelab-wildcard-tls` - TLS certificate and private key
  - Namespace: `traefik`
  - Auto-created and updated by cert-manager
  - Referenced by Gateway for HTTPS termination

## How to Request a Certificate

### Using the Wildcard Certificate (Recommended)

For any service under `snyderhomelab.com`, no action needed - the wildcard certificate is automatically used by the Gateway.

**Steps:**
1. Create HTTPRoute with hostname `subdomain.snyderhomelab.com`
2. Gateway automatically applies the wildcard certificate
3. Service is immediately accessible via HTTPS

**Example:**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-service
  namespace: my-app
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames:
    - myapp.snyderhomelab.com
  rules:
    - backendRefs:
        - name: my-service
          port: 80
```

No certificate configuration needed in the HTTPRoute - the Gateway handles TLS.

### Creating Individual Certificates (Advanced)

For services requiring dedicated certificates or using different domains:

**Example:** (see `apps/test-app/certificate.yaml`)
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: my-app
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - myapp.example.com
```

**When to use individual certificates:**
- Different domain not covered by wildcard
- Service needs certificate in specific namespace
- Specific certificate requirements (extended validation, etc.)

### Using Self-Signed Certificates

For internal-only services that don't require browser trust:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-service-tls
  namespace: my-app
spec:
  secretName: internal-service-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
    - internal.snyder.home
```

**Note**: Browsers will show security warnings unless you manually trust the CA certificate on each device.

## Certificate Lifecycle

### Automatic Renewal

cert-manager automatically renews certificates:
- **Let's Encrypt**: 30 days before expiry (60 days into 90-day lifetime)
- **Self-Signed**: Configurable renewal period

**Monitoring renewal:**
```bash
# Check certificate status
kubectl get certificate -A

# View certificate details including renewal time
kubectl describe certificate snyderhomelab-wildcard-tls -n traefik

# Check cert-manager logs for renewal activity
kubectl logs -n cert-manager -l app.kubernetes.io/component=controller
```

### Manual Certificate Refresh

To force certificate renewal (e.g., after configuration changes):

```bash
# Delete the certificate secret (cert-manager will recreate)
kubectl delete secret snyderhomelab-wildcard-tls -n traefik

# Or trigger renewal via annotation
kubectl annotate certificate snyderhomelab-wildcard-tls \
  -n traefik cert-manager.io/issue-temporary-certificate="true" \
  --overwrite
```

## Maintenance

### Updating cert-manager

cert-manager is managed via Flux HelmRelease:

```bash
# Update version in helmrelease.yaml
vim infrastructure/cert-manager/helmrelease.yaml

# Commit and push
git add infrastructure/cert-manager/helmrelease.yaml
git commit -m "Update cert-manager to vX.Y.Z"
git push

# Monitor rollout
kubectl get pods -n cert-manager -w
```

**Before upgrading:**
- Check release notes for breaking changes
- Verify CRD updates if upgrading across major versions
- Test in non-production first if possible

### Rotating Cloudflare API Token

If API token needs rotation:

1. Create new token in Cloudflare dashboard
2. Update secret:
   ```bash
   kubectl create secret generic cloudflare-api-token \
     --namespace cert-manager \
     --from-literal=api-token=NEW_TOKEN \
     --dry-run=client -o yaml | kubectl apply -f -
   ```
3. Restart cert-manager to pick up new token:
   ```bash
   kubectl rollout restart deployment cert-manager -n cert-manager
   ```

### Backup and Disaster Recovery

**Critical resources to backup:**
- ClusterIssuer configurations (in Git via GitOps)
- Certificate resources (in Git via GitOps)
- Cloudflare API token (secure password manager)

**Certificate secrets** are automatically recreated by cert-manager if lost - no backup needed.

**To restore after cluster rebuild:**
1. Redeploy cert-manager via GitOps (Flux applies from Git)
2. Recreate Cloudflare API token secret manually
3. cert-manager will automatically reissue certificates

## Security Considerations

### API Token Permissions

The Cloudflare API token has minimal required permissions:
- **Zone**: DNS Edit for `snyderhomelab.com` only
- No account-level permissions
- Limited to single zone

### Secret Management

**Current approach**: Manual secret creation (not in Git)

**Future improvements:**
- Implement SOPS for encrypted secrets in Git
- Or use External Secrets Operator (ESO) with cloud secrets manager
- Enables full GitOps including secrets

### Certificate Private Keys

- Stored in Kubernetes secrets (encrypted at rest if cluster encryption enabled)
- Never leave the cluster
- Rotated automatically with certificate renewal
- Access controlled via Kubernetes RBAC


## Portfolio Notes

This setup demonstrates:
- **Production-grade certificate management** - Automated lifecycle, no manual renewals
- **GitOps methodology** - Infrastructure as code, declarative configuration
- **Security best practices** - Minimal API permissions, encrypted secrets, automated rotation
- **Cloud-native patterns** - Kubernetes operators, CRDs, controller reconciliation loops
- **Hybrid architecture** - Split-horizon DNS, seamless internal/external access
- **Observability** - Certificate status monitoring, renewal tracking

**Skills showcased:**
- Kubernetes operators and custom resources
- TLS/PKI fundamentals and certificate lifecycle management
- DNS challenge types and domain validation
- API integration (Cloudflare)
- Gateway API and modern ingress patterns
- GitOps with Flux
- Troubleshooting distributed systems
