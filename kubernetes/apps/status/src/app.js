"use strict";
// Polls /api/stats and renders with DOM APIs only (no innerHTML), so the strict CSP holds.

const REFRESH_MS = 5000;
let lastOk = 0;

const $ = (id) => document.getElementById(id);
function el(tag, attrs = {}, ...children) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v;
    else n.setAttribute(k, v);
  }
  for (const c of children) if (c != null) n.append(c);
  return n;
}

const fmtCores = (c) => (c == null ? "–" : c < 1 ? `${Math.round(c * 1000)}m` : c.toFixed(c < 10 ? 2 : 1));
function fmtBytes(b) {
  if (b == null) return "–";
  const u = ["B", "KiB", "MiB", "GiB", "TiB"];
  let i = 0;
  while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
  return `${b.toFixed(b < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
}
function fmtDuration(s) {
  if (s == null) return "–";
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
}
const pct = (u, t) => (u == null || !t ? null : Math.min(100, (u / t) * 100));

function meter(name, used, total, fmt, kind) {
  const p = pct(used, total);
  const bar = el("div", { class: `bar ${kind}${p >= 90 ? " crit" : p >= 75 ? " hot" : ""}` }, el("span"));
  bar.firstChild.style.width = `${p ?? 0}%`;
  bar.setAttribute("role", "meter");
  bar.setAttribute("aria-label", name);
  bar.setAttribute("aria-valuenow", p == null ? "0" : p.toFixed(0));
  bar.setAttribute("aria-valuemin", "0");
  bar.setAttribute("aria-valuemax", "100");
  const figs = p == null ? `– / ${fmt(total)}` : `${fmt(used)} / ${fmt(total)} · ${p.toFixed(0)}%`;
  return el("div", { class: "meter" },
    el("div", { class: "top" }, el("span", { class: "name" }, name), el("span", { class: "figs" }, figs)),
    bar);
}

function setTile(id, text, cls) {
  const n = $(id);
  n.textContent = text;
  n.className = `value ${cls || ""}`;
}

function render(d) {
  const c = d.cluster;
  const running = d.pods.phases.Running || 0;
  const notOk = (d.pods.phases.Pending || 0) + (d.pods.phases.Failed || 0) + (d.pods.phases.Unknown || 0);

  setTile("t-nodes", `${c.nodesReady}/${c.nodes}`, c.nodesReady === c.nodes ? "ok" : "bad");
  setTile("t-pods", String(running), notOk ? "warn" : "ok");
  setTile("t-argo", `${d.argo.healthy}/${d.argo.total}`,
    d.argo.total && d.argo.healthy === d.argo.total && d.argo.synced === d.argo.total ? "ok" : "warn");
  setTile("t-warn", String(d.warningsLastHour), d.warningsLastHour ? "warn" : "ok");

  $("m-cpu").replaceWith(Object.assign(meter("CPU", c.cpu.used, c.cpu.total, fmtCores, "cpu"), { id: "m-cpu" }));
  $("m-mem").replaceWith(Object.assign(meter("Memory", c.mem.used, c.mem.total, fmtBytes, "mem"), { id: "m-mem" }));
  $("metrics-note").hidden = d.metricsAvailable;

  $("nodes").replaceChildren(...d.nodes.map((n) => {
    const meta = [n.role, `${n.pods} pods`, n.ready ? `up ${fmtDuration(n.readySeconds)}` : null,
      n.gpu ? `${n.gpu}× GPU` : null].filter(Boolean);
    return el("div", { class: "node" },
      el("div", { class: "head" },
        el("span", { class: "nm" }, n.name),
        el("span", { class: `badge ${n.ready ? "ok" : "bad"}` }, n.ready ? "Ready" : "NotReady")),
      el("div", { class: "meta" }, ...meta.map((m) => el("span", {}, m))),
      meter("CPU", n.cpu.used, n.cpu.total, fmtCores, "cpu small"),
      meter("Memory", n.mem.used, n.mem.total, fmtBytes, "mem small"));
  }));

  $("ns").tBodies[0].replaceChildren(...(d.topNamespaces.length ? d.topNamespaces.map((ns) =>
    el("tr", {},
      el("td", { class: "mono" }, ns.namespace),
      el("td", { class: "num" }, String(ns.pods)),
      el("td", { class: "num" }, fmtCores(ns.cpu)),
      el("td", { class: "num" }, fmtBytes(ns.mem)))
  ) : [el("tr", {}, el("td", { colspan: "4", class: "note" }, "Waiting for metrics…"))]));

  const w = d.workloads;
  const kv = (pairs) => pairs.flatMap(([k, v]) => [el("dt", {}, k), el("dd", {}, v)]);
  $("workloads").replaceChildren(...kv([
    ["Namespaces", String(c.namespaces)],
    ["Deployments", `${w.deployments.ready}/${w.deployments.total} ready`],
    ["DaemonSets", `${w.daemonsets.ready}/${w.daemonsets.total} ready`],
    ["StatefulSets", `${w.statefulsets.ready}/${w.statefulsets.total} ready`],
    ["Containers", String(d.pods.containers)],
    ["Container restarts", String(d.pods.restarts)],
  ]));
  $("phases").replaceChildren(...kv(Object.entries(d.pods.phases).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, String(v)])));

  $("argo-summary").textContent =
    `${d.argo.synced}/${d.argo.total} synced · ${d.argo.healthy}/${d.argo.total} healthy`;
  $("argo-problems").replaceChildren(...(d.argo.problems.length
    ? d.argo.problems.map((p) => el("li", {},
        el("span", { class: "mono" }, p.name),
        el("span", { class: "st" }, `${p.sync || "?"} · ${p.health || "?"}`)))
    : [el("li", {}, el("span", {}, "Everything is in sync with git."))]));

  $("certs").tBodies[0].replaceChildren(...d.certificates.map((ct) => {
    const days = ct.daysLeft;
    const cls = !ct.ready ? "bad" : days == null ? "" : days < 14 ? "bad" : days < 30 ? "warn" : "ok";
    return el("tr", {},
      el("td", { class: "mono" }, ct.name),
      el("td", {}, ct.issuer || "–"),
      el("td", { class: `num ${cls}` }, !ct.ready ? "not ready" : days == null ? "–" : days > 730 ? `${(days / 365).toFixed(0)} years` : `${days} days`));
  }));

  const os = d.nodes[0]?.os, rt = d.nodes[0]?.runtime;
  $("footer").textContent = [`Kubernetes ${d.kubernetes || "?"}`, os, rt, "refreshes every 5 seconds"].filter(Boolean).join(" · ");
}

function tickLabel() {
  const live = $("live");
  if (!lastOk) return;
  const age = Math.round((Date.now() - lastOk) / 1000);
  $("updated").textContent = age <= 1 ? "live" : `updated ${age}s ago`;
  live.className = `live ${age > 20 ? "stale" : "ok"}`;
}

async function refresh() {
  try {
    const r = await fetch("/api/stats", { cache: "no-store" });
    if (!r.ok) throw new Error(r.status);
    render(await r.json());
    lastOk = Date.now();
  } catch (e) {
    if (!lastOk) $("updated").textContent = "unavailable";
  }
  tickLabel();
}

refresh();
setInterval(() => { if (!document.hidden) refresh(); }, REFRESH_MS);
setInterval(tickLabel, 1000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
