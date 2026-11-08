# homelab

GitOps repo for the homelab Kubernetes cluster.

- **Talos v1.14.5**, **Kubernetes v1.37.2**: 3 schedulable control planes + 1 worker (Minisforum MS-A2)
- **Cilium 1.19.10**: CNI + kube-proxy replacement
- **Argo CD**: GitOps, app-of-apps for infrastructure + an ApplicationSet for apps

## Layout

```
talos/                          Talos machine config (talhelper + SOPS/age). See talos/README.md
kubernetes/
  bootstrap/root.yaml           root app-of-apps, applied once by hand
  argocd/                       what the root app syncs
    infrastructure/*.yaml       one Application per infra component (sync waves)
    apps.yaml                   ApplicationSet: every kubernetes/apps/<name>/ becomes an app
  infrastructure/<name>/        Helm values / manifests per infra component
  apps/<name>/                  one folder per app (kustomize), namespace = folder name
```

## Bootstrap (fresh cluster)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 10.15.0 -n argocd --create-namespace \
  -f kubernetes/infrastructure/argocd/values.yaml
kubectl apply -f kubernetes/bootstrap/root.yaml
```

Cilium has to exist before Argo can run (no CNI, no pods), so on a brand-new cluster
install it first with helm using `kubernetes/infrastructure/cilium/values.yaml`; Argo adopts it.

## Adding things

- **App:** create `kubernetes/apps/<name>/kustomization.yaml` and push. The ApplicationSet picks it up.
- **Infrastructure:** add `kubernetes/argocd/infrastructure/<name>.yaml` (Application, with a sync wave)
  and its values under `kubernetes/infrastructure/<name>/`.

## Argo CD UI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```
