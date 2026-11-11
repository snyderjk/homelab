# NAS storage (Synology DS, DSM 7.2.2)

| StorageClass        | Backend                 | Access | On PVC delete | Use for                          |
|---------------------|-------------------------|--------|---------------|----------------------------------|
| `nas-iscsi` (default) | synology-csi, iSCSI LUN | RWO    | LUN **kept**  | anything with a database         |
| `nas-iscsi-delete`  | synology-csi, iSCSI LUN | RWO    | LUN deleted   | caches, scratch, tests           |
| `nas-nfs`           | csi-driver-nfs          | RWX    | folder deleted| shared files, media, bulk        |
| `nas-nfs-retain`    | csi-driver-nfs          | RWX    | folder kept   | shared data you'd hate to lose   |

NFS folders land at `/volume1/kubernetes-nfs/<namespace>/<pvc-name>`.
iSCSI LUNs show up in DSM → SAN Manager, named after the PV.

The cluster reaches the NAS as **`nas.snyderhomelab.com`** (pfSense DNS → 10.17.1.5,
routed from VLAN 77). To move storage traffic onto a direct VLAN 77 NAS port later,
repoint that one DNS record — volumes re-resolve it on their next mount.

## One-time setup

### 1. DSM service account
Control Panel → User & Group → Create `k8s-csi`:
- Group: **administrators** (the DSM API requires it to create LUNs/targets)
- Shared folder permissions: **No access** on everything
- Applications: deny all except what's required; strong random password

### 2. DSM certificate (homelab-ca, issued by cert-manager)
synology-csi ≥1.3.1 verifies DSM's TLS cert. DSM's default self-signed cert won't
verify, so DSM serves `nas-dsm` (Certificate in `config/nas-certificate.yaml`).

Export it (files contain a private key: delete them after importing):
```bash
d=$(mktemp -d)
kubectl -n synology-csi get secret nas-dsm-tls -o jsonpath='{.data.tls\.key}' | base64 -d > $d/nas.key
kubectl -n synology-csi get secret nas-dsm-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > $d/nas.crt
kubectl -n synology-csi get secret nas-dsm-tls -o jsonpath='{.data.ca\.crt}'  | base64 -d > $d/ca.crt
echo $d
```
DSM → Control Panel → Security → Certificate → **Add** → Add a new certificate →
Import certificate: Private key `nas.key`, Certificate `nas.crt`, Intermediate `ca.crt`.
Then **Settings** → set the **DSM** service (and System default) to the new cert.
Finally: `rm -rf $d`

Re-import before it expires (3-year cert; the status dashboard lists `nas-dsm`).
Optional: trust `homelab-ca` on your desktop and DSM in the browser stops warning.

### 3. Driver credentials Secret (never in git)
Prompts for the password without echoing it; JSON is valid YAML, so special
characters in the password need no escaping:
```bash
printf 'DSM username: '; read -r DSM_USER
printf 'DSM password: '; stty -echo; read -r DSM_PASS; stty echo; echo   # works in zsh and bash
CA=$(kubectl -n cert-manager get secret homelab-ca -o jsonpath='{.data.ca\.crt}' | base64 -d)
DSM_USER="$DSM_USER" DSM_PASS="$DSM_PASS" CA="$CA" python3 -c '
import json, os
print(json.dumps({"clients": [{
    "host": "nas.snyderhomelab.com", "port": 5001, "https": True,
    "username": os.environ["DSM_USER"], "password": os.environ["DSM_PASS"],
    "tlsCACert": os.environ["CA"]}]}))' |
  kubectl -n synology-csi create secret generic synology-csi-client-info --from-file=client-info.yaml=/dev/stdin
unset DSM_PASS
kubectl -n synology-csi rollout restart statefulset/synology-csi-controller daemonset/synology-csi-node
```

## Shrinking Talos EPHEMERAL for local storage
Planned before CNPG — see talos/README.md when it's done.
