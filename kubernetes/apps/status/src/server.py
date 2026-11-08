"""Homelab status dashboard: read-only, aggregate cluster stats as JSON + a static page.

Stdlib only (runs on the stock python image). Talks to the Kubernetes API with its
ServiceAccount token. Stats are cached for CACHE_SECONDS, so the API load is fixed no
matter how much public traffic the page gets.

Deliberately public-safe: no IPs, no secrets, no pod names, no env/config, just counts,
usage and versions.
"""

import json
import os
import ssl
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API = "https://kubernetes.default.svc"
SA = "/var/run/secrets/kubernetes.io/serviceaccount"
STATIC = os.path.dirname(os.path.abspath(__file__))
CACHE_SECONDS = float(os.environ.get("CACHE_SECONDS", "5"))
PORT = int(os.environ.get("PORT", "8080"))

_ctx = ssl.create_default_context(cafile=f"{SA}/ca.crt")
_lock = threading.Lock()
_cache = {"at": 0.0, "data": None}


def k8s(path):
    """GET an API path; returns parsed JSON, or None if unavailable (e.g. metrics not ready)."""
    with open(f"{SA}/token") as f:  # re-read: projected tokens rotate
        token = f.read().strip()
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=5) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None


def items(path):
    data = k8s(path)
    return data.get("items", []) if data else []


_CPU = {"n": 1e-9, "u": 1e-6, "m": 1e-3}
_MEM = {"Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "Ti": 2**40,
        "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12}


def cpu_cores(q):
    q = str(q or "0")
    return float(q[:-1]) * _CPU[q[-1]] if q[-1] in _CPU else float(q)


def mem_bytes(q):
    q = str(q or "0")
    for suf in ("Ki", "Mi", "Gi", "Ti", "k", "M", "G", "T"):
        if q.endswith(suf):
            return float(q[: -len(suf)]) * _MEM[suf]
    return float(q)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def collect():
    now = datetime.now(timezone.utc)
    version = k8s("/version") or {}

    # --- nodes + live usage (metrics-server) ---
    usage = {m["metadata"]["name"]: m["usage"]
             for m in items("/apis/metrics.k8s.io/v1beta1/nodes")}
    pods = items("/api/v1/pods")
    pods_per_node = {}
    for p in pods:
        n = p["spec"].get("nodeName")
        if n and p["status"].get("phase") == "Running":
            pods_per_node[n] = pods_per_node.get(n, 0) + 1

    nodes = []
    for n in items("/api/v1/nodes"):
        name = n["metadata"]["name"]
        labels = n["metadata"].get("labels", {})
        ready = next((c for c in n["status"].get("conditions", []) if c["type"] == "Ready"), {})
        alloc = n["status"].get("allocatable", {})
        info = n["status"].get("nodeInfo", {})
        u = usage.get(name)
        since = ts(ready.get("lastTransitionTime"))
        nodes.append({
            "name": name,
            "role": "control-plane" if "node-role.kubernetes.io/control-plane" in labels else "worker",
            "ready": ready.get("status") == "True",
            "readySeconds": int((now - since).total_seconds()) if since else None,
            "os": info.get("osImage"),
            "kernel": info.get("kernelVersion"),
            "runtime": info.get("containerRuntimeVersion"),
            "pods": pods_per_node.get(name, 0),
            "podCapacity": int(alloc.get("pods", 0)),
            "cpu": {"used": cpu_cores(u["cpu"]) if u else None, "total": cpu_cores(alloc.get("cpu"))},
            "mem": {"used": mem_bytes(u["memory"]) if u else None, "total": mem_bytes(alloc.get("memory"))},
            "gpu": int(alloc.get("nvidia.com/gpu", 0)),
        })
    nodes.sort(key=lambda x: x["name"])

    def total(key, field):
        vals = [nd[key][field] for nd in nodes]
        return None if any(v is None for v in vals) else sum(vals)

    # --- pods ---
    phases, restarts, containers = {}, 0, 0
    for p in pods:
        ph = p["status"].get("phase", "Unknown")
        phases[ph] = phases.get(ph, 0) + 1
        for cs in p["status"].get("containerStatuses", []) or []:
            containers += 1
            restarts += cs.get("restartCount", 0)

    # --- usage by namespace (top consumers) ---
    by_ns = {}
    for m in items("/apis/metrics.k8s.io/v1beta1/pods"):
        ns = m["metadata"]["namespace"]
        agg = by_ns.setdefault(ns, {"namespace": ns, "cpu": 0.0, "mem": 0.0, "pods": 0})
        agg["pods"] += 1
        for c in m.get("containers", []):
            agg["cpu"] += cpu_cores(c["usage"].get("cpu"))
            agg["mem"] += mem_bytes(c["usage"].get("memory"))
    top_ns = sorted(by_ns.values(), key=lambda a: a["mem"], reverse=True)[:8]

    # --- workloads ---
    deploys = items("/apis/apps/v1/deployments")
    ds = items("/apis/apps/v1/daemonsets")
    sts = items("/apis/apps/v1/statefulsets")

    def ready_count(objs, want, have):
        return sum(1 for o in objs if (o.get("status", {}).get(have) or 0) >= (o.get("status", {}).get(want) or 0))

    # --- GitOps (Argo CD) ---
    apps = items("/apis/argoproj.io/v1alpha1/applications")
    argo = {"total": len(apps), "synced": 0, "healthy": 0, "problems": []}
    for a in apps:
        st = a.get("status", {})
        sync = st.get("sync", {}).get("status")
        health = st.get("health", {}).get("status")
        argo["synced"] += sync == "Synced"
        argo["healthy"] += health == "Healthy"
        if sync != "Synced" or health != "Healthy":
            argo["problems"].append({"name": a["metadata"]["name"], "sync": sync, "health": health})

    # --- certificates (cert-manager) ---
    certs = []
    for c in items("/apis/cert-manager.io/v1/certificates"):
        exp = ts(c.get("status", {}).get("notAfter"))
        ready = any(x["type"] == "Ready" and x["status"] == "True"
                    for x in c.get("status", {}).get("conditions", []))
        certs.append({"name": c["metadata"]["name"], "ready": ready,
                      "issuer": c["spec"].get("issuerRef", {}).get("name"),
                      "daysLeft": int((exp - now).total_seconds() // 86400) if exp else None})
    certs.sort(key=lambda c: (c["daysLeft"] is None, c["daysLeft"]))

    # --- warning events, last hour ---
    hour_ago = now.timestamp() - 3600
    warnings = 0
    for e in items("/api/v1/events?fieldSelector=type%3DWarning"):
        t = ts(e.get("lastTimestamp") or e.get("eventTime") or e["metadata"].get("creationTimestamp"))
        if t and t.timestamp() >= hour_ago:
            warnings += e.get("count", 1) or 1

    return {
        "generatedAt": now.isoformat(),
        "metricsAvailable": bool(usage),
        "kubernetes": version.get("gitVersion"),
        "nodes": nodes,
        "cluster": {
            "nodesReady": sum(n["ready"] for n in nodes), "nodes": len(nodes),
            "cpu": {"used": total("cpu", "used"), "total": total("cpu", "total")},
            "mem": {"used": total("mem", "used"), "total": total("mem", "total")},
            "namespaces": len(items("/api/v1/namespaces")),
            "gpus": sum(n["gpu"] for n in nodes),
        },
        "pods": {"total": len(pods), "phases": phases, "containers": containers, "restarts": restarts},
        "workloads": {
            "deployments": {"total": len(deploys), "ready": ready_count(deploys, "replicas", "readyReplicas")},
            "daemonsets": {"total": len(ds), "ready": ready_count(ds, "desiredNumberScheduled", "numberReady")},
            "statefulsets": {"total": len(sts), "ready": ready_count(sts, "replicas", "readyReplicas")},
        },
        "topNamespaces": top_ns,
        "argo": argo,
        "certificates": certs,
        "warningsLastHour": warnings,
    }


def stats():
    with _lock:  # one refresh at a time; everyone else gets the cached copy
        if _cache["data"] is None or time.monotonic() - _cache["at"] > CACHE_SECONDS:
            _cache["data"] = json.dumps(collect()).encode()
            _cache["at"] = time.monotonic()
        return _cache["data"]


FILES = {"/": ("index.html", "text/html; charset=utf-8"),
         "/app.js": ("app.js", "text/javascript; charset=utf-8"),
         "/style.css": ("style.css", "text/css; charset=utf-8")}

HEADERS = {
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; "
                               "connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
}


class Handler(BaseHTTPRequestHandler):
    server_version = "status"
    sys_version = ""

    def send(self, code, body, ctype, cache="no-store"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        for k, v in HEADERS.items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            return self.send(200, b"ok", "text/plain")
        if path == "/api/stats":
            try:
                return self.send(200, stats(), "application/json")
            except Exception as e:  # never leak a traceback publicly
                self.log_error("collect failed: %r", e)
                return self.send(503, b'{"error":"unavailable"}', "application/json")
        if path in FILES:
            name, ctype = FILES[path]
            with open(os.path.join(STATIC, name), "rb") as f:
                return self.send(200, f.read(), ctype, "public, max-age=60")
        self.send(404, b"not found", "text/plain")

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        if not self.path.startswith("/healthz"):
            super().log_message(fmt, *args)


if __name__ == "__main__":
    print(f"listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()
