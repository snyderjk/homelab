# Homelab Talos cluster

4x Minisforum MS-A2 · Talos v1.14.5 · Kubernetes v1.37.2 · Cilium 1.19.10 (kube-proxy replacement)

| Node     | IP          | Role                       |
|----------|-------------|----------------------------|
| VIP      | 10.77.1.5   | API endpoint (Talos L2 VIP) |
| k8s-cp01 | 10.77.1.10  | control plane (schedulable) |
| k8s-cp02 | 10.77.1.11  | control plane (schedulable) |
| k8s-cp03 | 10.77.1.12  | control plane (schedulable) |
| k8s-wk01 | 10.77.1.13  | worker                      |

## Layout

- `talconfig.yaml` — talhelper config (nodes, schematic, versions)
- `talsecret.sops.yaml` — cluster secrets (SOPS/age)
- `patches/all.yaml` — kubelet nodeIP subnet + reserved resources
- `patches/sysctls.yaml` — forwarding / rp_filter sysctls
- `patches/cilium.yaml` — removes Flannel, disables kube-proxy (Talos 1.14 doc format)
- `patches/controlplane.yaml` — etcd advertised subnet, allow CPs as LB backends
- Cilium Helm values live in `../kubernetes/infrastructure/cilium/values.yaml` (managed by Argo CD)
- `clusterconfig/` — generated, gitignored (contains secrets)
- `legacy/` — pre-talhelper patch, kept for reference only

## Image

Schematic `adfc9752363635b8d09393a061edc65afad49f8da4d7e5d8c1a4381923019a53`
(amd-ucode, realtek-firmware, iscsi-tools, util-linux-tools)

```bash
talhelper genurl image      # ISO
talhelper genurl installer  # installer image (talhelper puts this in the machine config)
curl -LO https://factory.talos.dev/image/adfc9752363635b8d09393a061edc65afad49f8da4d7e5d8c1a4381923019a53/v1.14.5/metal-amd64.iso
sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## Bring up a node

```bash
# 0. Client tools must match: talosctl v1.14.5, kubectl v1.36+ (brew upgrade siderolabs/tap/talosctl kubectl)

# 1. Boot the ISO (UEFI, Secure Boot off). Node comes up in maintenance mode with a DHCP address.
#    Confirm the NIC MAC on VLAN 77 and the install disk, then update talconfig.yaml if they differ:
talosctl get links --insecure -n <dhcp-ip>
talosctl get disks --insecure -n <dhcp-ip>

# 2. Generate configs (needs your age key, e.g. SOPS_AGE_KEY_FILE=~/path/to/keys.txt)
talhelper genconfig
talosctl validate --mode metal -c clusterconfig/homelab-k8s-cp01.yaml
export TALOSCONFIG=$PWD/clusterconfig/talosconfig

# 3. Apply
talosctl apply-config --insecure -n <dhcp-ip> -f clusterconfig/homelab-k8s-cp01.yaml

# 4. Bootstrap etcd — ONCE, on cp01 only, never on cp02/cp03
talosctl bootstrap -n 10.77.1.10 -e 10.77.1.10

# 5. Kubeconfig (server will be the VIP https://10.77.1.5:6443)
talosctl kubeconfig -n 10.77.1.10 -e 10.77.1.10

# 6. Cilium (node stays NotReady until this is in). Only on a fresh cluster — Argo CD manages it after bootstrap
helm repo add cilium https://helm.cilium.io && helm repo update
helm install cilium cilium/cilium --version 1.19.10 -n kube-system -f ../kubernetes/infrastructure/cilium/values.yaml
kubectl get nodes -o wide
talosctl health -n 10.77.1.10 -e 10.77.1.10
```

Adding cp02/cp03/wk01: uncomment the node in `talconfig.yaml`, fill in its MAC,
`talhelper genconfig`, then step 3 with that node's file. No bootstrap.

## Notes

- talhelper 3.1.17 is the final release (repo archived). It warns that v1.14.5
  "might not be compatible" but generates valid 1.14 multi-doc configs.
- talhelper envsubsts patches: write `$$patch: delete` to get `$patch: delete`.
- hostDNS `forwardKubeDNSToHost` is on — if you turn on Cilium `bpf.masquerade`,
  also set `bpf.hostLegacyRouting: true`.
- No DHCP on VLAN 77? Add a kernel arg to the schematic for maintenance mode:
  `ip=10.77.1.10::10.77.1.1:255.255.255.0:k8s-cp01:<iface>:off`.
- Your workstation is on 10.17.1.0/24: make sure the router allows 50000/tcp
  (talos apid) and 6443/tcp to VLAN 77.
