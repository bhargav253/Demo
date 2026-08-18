"use strict";

const state = {
  layout: null,
  rows: new Map(),
  cycles: [],
  cycleIndex: 0,
  interval: 100,
  timer: null,
  selected: null,
  camera: null,
  drag: null,
  suppressClick: false
};

const $ = id => document.getElementById(id);
const nodeKey = n => `${n.kind}:${n.id}`;

function parseCSV(text) {
  const lines = text.trim().split(/\r?\n/);
  const header = lines.shift().split(",");
  return lines.filter(Boolean).map(line => {
    const values = line.split(",");
    const row = {};
    header.forEach((h, i) => row[h] = values[i]);
    ["cycle", "id", "port", "arrivals", "departures", "occupancy",
     "request_cycles", "grant_cycles", "allocator_loss_cycles",
     "contention_cycles", "credit_stall_cycles", "queue_wait_samples",
     "queue_wait_cycles", "residence_samples", "residence_cycles",
     "avg_queue_wait", "avg_residence", "avg_latency"]
      .forEach(k => row[k] = row[k] === undefined || row[k] === "" ? null : Number(row[k]));
    return row;
  });
}

async function loadBundled() {
  try {
    const selection = $("bundledTopology").value;
    const topology = selection.startsWith("noc16c") ? "noc16c" :
                     selection.startsWith("noc12") ? "noc12" : "noc16";
    const telemetry = `sample/${topology}_synthetic_telemetry.csv`;
    const layoutAsset = topology === "noc16" ?
      "sample/noc16_layout_v2.json" : `sample/${topology}_layout.json`;
    const [layoutResponse, csvResponse] = await Promise.all([
      fetch(layoutAsset, { cache: "no-store" }),
      fetch(telemetry, { cache: "no-store" })
    ]);
    if (!layoutResponse.ok || !csvResponse.ok) throw new Error("sample fetch failed");
    installData(await layoutResponse.json(), parseCSV(await csvResponse.text()));
  } catch (error) {
    $("status").textContent = "Bundled sample needs a local HTTP server; choose both files manually or use serve.sh.";
  }
}

function installData(layout, rows) {
  state.layout = layout;
  state.rows.clear();
  const cycleSet = new Set();
  for (const row of rows) {
    cycleSet.add(row.cycle);
    const suffix = row.kind === "port" ? `:${row.port}` : "";
    state.rows.set(`${row.cycle}|${row.kind}:${row.id}${suffix}`, row);
  }
  state.cycles = [...cycleSet].sort((a, b) => a - b);
  state.interval = state.cycles.length > 1 ? state.cycles[1] - state.cycles[0] : 1;
  state.cycleIndex = state.cycles.length > 1 ? 1 : 0;
  $("cycle").max = Math.max(0, state.cycles.length - 1);
  $("cycle").value = state.cycleIndex;
  $("subtitle").textContent = layout.name;
  $("status").textContent = `${layout.nodes.length} nodes, ${layout.links.length} visual links, ${state.cycles.length} cycles`;
  renderBase();
  update();
}

function svgEl(name, attributes = {}) {
  const el = document.createElementNS("http://www.w3.org/2000/svg", name);
  for (const [k, v] of Object.entries(attributes)) el.setAttribute(k, v);
  return el;
}

function renderBase() {
  const svg = $("topology");
  svg.replaceChildren();
  resetCamera();

  const nodeByKey = new Map(state.layout.nodes.map(n => [nodeKey(n), n]));
  for (const c of state.layout.clusters) {
    const width = c.box_width || 220, height = c.box_height || 165;
    const yOffset = c.box_y_offset === undefined ? -35 : c.box_y_offset;
    svg.appendChild(svgEl("rect", { x: c.x - width/2, y: c.y + yOffset,
      width, height, class: "cluster-box" }));
    const label = svgEl("text", { x: c.x - width/2 + 10,
      y: c.y + yOffset + 18, class: "cluster-label" });
    label.textContent = c.name;
    svg.appendChild(label);
  }

  for (const link of state.layout.links) {
    const a = nodeByKey.get(link.source), b = nodeByKey.get(link.target);
    if (!a || !b) continue;
    let edge;
    if (link.points && link.points.length >= 2) {
      edge = svgEl("polyline", { points: link.points.map(p => p.join(",")).join(" "),
        fill: "none" });
    } else if (link.kind === "L1-MESH" && a.y === b.y) {
      // East p2 to west p4. Anchor at the displayed logical-port markers.
      edge = svgEl("line", { x1: a.x + 52, y1: a.y,
        x2: b.x - 52, y2: b.y });
    } else if (link.kind === "L1-MESH") {
      // South p3 to north p1. Route outside the cluster box so the mesh link
      // does not visually pass through the local L2/shim/L3 hierarchy.
      const sx = a.x + 22, sy = a.y + 28;
      const tx = b.x, ty = b.y - 27;
      const aroundX = a.x + 122;
      edge = svgEl("path", { d: `M ${sx} ${sy} H ${aroundX} V ${ty} H ${tx}`,
        fill: "none" });
    } else {
      edge = svgEl("line", { x1: a.x, y1: a.y, x2: b.x, y2: b.y });
    }
    edge.setAttribute("class", `link ${link.kind === "L1-MESH" ? "mesh" : ""}`);
    edge.setAttribute("data-link", link.id);
    edge.addEventListener("click", () => showLink(link));
    svg.appendChild(edge);
  }

  for (const n of state.layout.nodes) {
    const group = svgEl("g", { "data-node": nodeKey(n), "data-level": n.level });
    let shape;
    if (n.level === "L1")
      shape = svgEl("rect", { x: n.x - 44, y: n.y - 19, width: 88, height: 38, rx: 7, class: "node" });
    else if (n.level === "L2")
      shape = svgEl("rect", { x: n.x - 37, y: n.y - 14, width: 74, height: 28, rx: 5, class: "node" });
    else
      shape = svgEl("circle", { cx: n.x, cy: n.y, r: n.level === "LLCH" ? 22 : 12, class: "node" });
    group.appendChild(shape);
    const label = svgEl("text", { x: n.x, y: n.y,
      class: `node-label ${n.level === "L1" ? "l1" : n.level === "L2" ? "l2" : "small"}` });
    label.textContent = n.level === "LLCH" ? n.name.replace("LLCH_", "M") :
      n.level === "SHIM" ? "S" : n.level === "L3" ? n.name.split("_").pop() : n.name;
    group.appendChild(label);
    group.addEventListener("click", () => showNode(n));
    svg.appendChild(group);
  }

  for (const p of state.layout.ports || []) {
    const group = svgEl("g", { "data-port": `${p.router_kind}:${p.router}:${p.port}`,
      "data-level": p.level, class: "port-group" });
    const marker = svgEl("circle", { cx: p.x, cy: p.y, r: 8, class: "port-marker" });
    const label = svgEl("text", { x: p.x, y: p.y, class: "port-label" });
    label.textContent = `p${p.port}`;
    group.appendChild(marker); group.appendChild(label);
    group.addEventListener("click", event => { event.stopPropagation(); showPort(p); });
    svg.appendChild(group);
  }
}

function applyCamera() {
  if (!state.camera) return;
  const c = state.camera;
  $("topology").setAttribute("viewBox", `${c.x} ${c.y} ${c.width} ${c.height}`);
  const scale = state.layout.viewBox.width / c.width;
  $("zoomLabel").textContent = `${Math.round(scale * 100)}%`;
}

function resetCamera() {
  if (!state.layout) return;
  state.camera = { x: 0, y: 0, width: state.layout.viewBox.width,
                   height: state.layout.viewBox.height };
  applyCamera();
}

function zoomAt(factor, svgX = null, svgY = null) {
  if (!state.camera) return;
  const c = state.camera;
  const full = state.layout.viewBox;
  const minimumWidth = full.width / 8;
  const maximumWidth = full.width * 1.35;
  let newWidth = Math.max(minimumWidth, Math.min(maximumWidth, c.width * factor));
  const actualFactor = newWidth / c.width;
  const newHeight = c.height * actualFactor;
  const focusX = svgX === null ? c.x + c.width / 2 : svgX;
  const focusY = svgY === null ? c.y + c.height / 2 : svgY;
  state.camera = {
    x: focusX - (focusX - c.x) * actualFactor,
    y: focusY - (focusY - c.y) * actualFactor,
    width: newWidth,
    height: newHeight
  };
  applyCamera();
}

function clientToSvg(clientX, clientY) {
  const matrix = $("topology").getScreenCTM();
  if (!matrix) return { x: state.camera.x, y: state.camera.y };
  const point = new DOMPoint(clientX, clientY).matrixTransform(matrix.inverse());
  return { x: point.x, y: point.y };
}

function metricValue(node, row) {
  if (!row) return null;
  switch ($("metric").value) {
    case "occupancy_ratio": return node.capacity ? row.occupancy / node.capacity : 0;
    case "throughput": return row.departures / state.interval;
    case "router_avg_queue_wait": return aggregatePortLatency(node, "queue");
    case "router_avg_residence": return aggregatePortLatency(node, "residence");
    case "credit_stall_cycles": return row.credit_stall_cycles;
    case "contention_cycles": return row.contention_cycles;
    default: return 0;
  }
}

function aggregatePortLatency(node, which) {
  if (node.kind !== "router") return null;
  const cycle = state.cycles[state.cycleIndex];
  let samples = 0, total = 0;
  for (const p of state.layout.ports || []) {
    if (p.router !== node.id) continue;
    const row = state.rows.get(`${cycle}|port:${p.router}:${p.port}`);
    if (!row) continue;
    if (which === "queue") {
      samples += row.queue_wait_samples || 0;
      total += row.queue_wait_cycles || 0;
    } else {
      samples += row.residence_samples || 0;
      total += row.residence_cycles || 0;
    }
  }
  return samples ? total / samples : null;
}

function isPortMetric(metric) {
  return ["port_throughput", "avg_queue_wait", "avg_residence",
          "port_credit_stalls", "allocator_loss_cycles"].includes(metric);
}

function portMetricValue(port, row) {
  if (!row) return null;
  switch ($("metric").value) {
    case "port_throughput": return row.departures / state.interval / port.max_rate;
    case "avg_queue_wait": return row.avg_queue_wait;
    case "avg_residence": return row.avg_residence;
    case "port_credit_stalls": return row.credit_stall_cycles;
    case "allocator_loss_cycles": return row.allocator_loss_cycles;
    default: return null;
  }
}

function color(t) {
  const stops = [[26,152,80], [145,207,96], [254,224,139], [252,141,89], [215,48,39]];
  t = Math.max(0, Math.min(1, t));
  const p = t * (stops.length - 1), i = Math.min(stops.length - 2, Math.floor(p));
  const f = p - i;
  const rgb = stops[i].map((v, j) => Math.round(v + (stops[i + 1][j] - v) * f));
  return `rgb(${rgb.join(",")})`;
}

function update() {
  if (!state.layout || !state.cycles.length) return;
  const cycle = state.cycles[state.cycleIndex];
  const level = $("level").value;
  const values = [];
  for (const n of state.layout.nodes) {
    const row = state.rows.get(`${cycle}|${nodeKey(n)}`);
    const v = metricValue(n, row);
    if (v !== null && (level === "ALL" || level === n.level)) values.push(v);
  }
  const metric = $("metric").value;
  const portMode = isPortMetric(metric);
  if (portMode) {
    values.length = 0;
    for (const p of state.layout.ports || []) {
      const row = state.rows.get(`${cycle}|port:${p.router}:${p.port}`);
      const visibleLevel = level === "ALL" ? (p.level === "L1" || p.level === "L2") : p.level === level;
      const v = portMetricValue(p, row);
      if (visibleLevel && v !== null) values.push(v);
    }
  }
  const fixedMax = metric === "occupancy_ratio" || metric === "port_throughput" ? 1 :
                   metric === "throughput" ? 1 : null;
  const requestedMax = Number($("scaleMax").value);
  const manualMax = requestedMax > 0 ? requestedMax : null;
  const max = manualMax || fixedMax || Math.max(1, ...values);

  document.querySelectorAll("[data-node]").forEach(group => {
    const n = state.layout.nodes.find(x => nodeKey(x) === group.dataset.node);
    const row = state.rows.get(`${cycle}|${group.dataset.node}`);
    const v = portMode ? null : metricValue(n, row);
    group.classList.toggle("filtered", level !== "ALL" && level !== n.level);
    group.querySelector(".node").style.fill = v === null ? "#303b50" : color(v / max);
  });
  document.querySelectorAll("[data-port]").forEach(group => {
    const [routerKind, router, portNumber] = group.dataset.port.split(":");
    const p = (state.layout.ports || []).find(x => x.router_kind === routerKind &&
      x.router === Number(router) && x.port === Number(portNumber));
    const visibleLevel = level === "ALL" ? (p.level === "L1" || p.level === "L2") : p.level === level;
    group.style.display = portMode && visibleLevel ? "block" : "none";
    if (portMode && visibleLevel) {
      const row = state.rows.get(`${cycle}|port:${p.router}:${p.port}`);
      const v = portMetricValue(p, row);
      group.querySelector(".port-marker").style.fill = v === null ? "#4b5568" : color(v / max);
    }
  });
  $("cycleLabel").value = cycle;
  $("cycleLabel").textContent = cycle;
  $("legend").innerHTML = `<span>0</span><span class="legend-bar"></span><span>${format(max)}</span>`;
  if (state.selected && state.selected.type === "node") showNode(state.selected.value, false);
  if (state.selected && state.selected.type === "port") showPort(state.selected.value, false);
}

function showPort(p, remember = true) {
  if (remember) state.selected = { type: "port", value: p };
  document.querySelectorAll(".port-marker.selected").forEach(x => x.classList.remove("selected"));
  const selected = document.querySelector(`[data-port="${p.router_kind}:${p.router}:${p.port}"] .port-marker`);
  if (selected) selected.classList.add("selected");
  const cycle = state.cycles[state.cycleIndex];
  const r = state.rows.get(`${cycle}|port:${p.router}:${p.port}`);
  const val = (field, suffix="") => r && r[field] !== null ? `${format(r[field])}${suffix}` : "n/a";
  $("details").innerHTML = `<h2>${p.router_name}.p${p.port}</h2>
    <p>${p.label}</p><div class="kv"><span>Level</span><b>${p.level}</b>
    <span>Cycle</span><b>${cycle}</b><span>Port capacity</span><b>${p.capacity}</b>
    <span>Maximum rate</span><b>${p.max_rate} pkt/cycle</b>
    <span>Arrivals/window</span><b>${val("arrivals")}</b>
    <span>Departures/window</span><b>${val("departures")}</b>
    <span>Throughput</span><b>${r ? format(r.departures/state.interval) : "n/a"} pkt/cycle</b>
    <span>Occupancy</span><b>${val("occupancy")}</b>
    <span>Request cycles</span><b>${val("request_cycles")}</b>
    <span>Grant cycles</span><b>${val("grant_cycles")}</b>
    <span>Allocator losses</span><b>${val("allocator_loss_cycles")}</b>
    <span>Credit stalls</span><b>${val("credit_stall_cycles")}</b>
    <span>Average queue wait</span><b>${val("avg_queue_wait", " cycles")}</b>
    <span>Average residence</span><b>${val("avg_residence", " cycles")}</b></div>
    <h3>Telemetry note</h3><p class="warning">The bundled synthetic datasets are illustrative; RR/weighted selections use real BookSim per-port telemetry.</p>`;
}

function format(value) {
  return Number.isFinite(value) ? (Math.abs(value) >= 10 ? value.toFixed(1) : value.toFixed(2)) : "n/a";
}

function showNode(n, remember = true) {
  if (remember) state.selected = { type: "node", value: n };
  document.querySelectorAll(".node.selected").forEach(x => x.classList.remove("selected"));
  const selected = document.querySelector(`[data-node="${nodeKey(n)}"] .node`);
  if (selected) selected.classList.add("selected");
  const cycle = state.cycles[state.cycleIndex];
  const r = state.rows.get(`${cycle}|${nodeKey(n)}`);
  $("details").innerHTML = `<h2>${n.name}</h2>
    <div class="kv"><span>Level</span><b>${n.level}</b><span>ID</span><b>${n.id}</b>
    <span>Cycle</span><b>${cycle}</b><span>Position</span><b>${n.x}, ${n.y}</b>
    <span>Capacity</span><b>${n.capacity}</b>
    <span>Arrivals/window</span><b>${r ? r.arrivals : "n/a"}</b>
    <span>Departures/window</span><b>${r ? r.departures : "n/a"}</b>
    <span>Output pkt/cycle</span><b>${r ? format(r.departures/state.interval) : "n/a"}</b>
    <span>Occupancy</span><b>${r ? r.occupancy : "n/a"}</b>
    <span>Occupancy ratio</span><b>${r ? format(100*r.occupancy/n.capacity)+"%" : "n/a"}</b>
    <span>Credit stalls</span><b>${r ? r.credit_stall_cycles : "n/a"}</b>
    <span>Contention</span><b>${r ? r.contention_cycles : "n/a"}</b>
    <span>Average latency</span><b>${r ? format(r.avg_latency) : "n/a"}</b></div>
    <h3>Prototype note</h3><p class="warning">These values are synthetic. Average latency is included only to review the UI.</p>`;
}

function showLink(link) {
  state.selected = { type: "link", value: link };
  $("details").innerHTML = `<h2>${link.id}</h2><div class="kv">
    <span>Type</span><b>${link.kind}</b><span>Source</span><b>${link.source}</b>
    <span>Target</span><b>${link.target}</b><span>Aggregated lanes</span><b>${link.lanes}</b>
    </div><p class="warning">Phase-1 visual links are static and aggregate lanes. Dynamic per-link coloring comes after the UI layout is accepted.</p>`;
}

function moveCycle(delta) {
  state.cycleIndex = Math.max(0, Math.min(state.cycles.length - 1, state.cycleIndex + delta));
  $("cycle").value = state.cycleIndex;
  update();
}

$("metric").addEventListener("change", update);
$("level").addEventListener("change", update);
$("cycle").addEventListener("input", e => { state.cycleIndex = Number(e.target.value); update(); });
$("first").addEventListener("click", () => { state.cycleIndex = 0; $("cycle").value=0; update(); });
$("last").addEventListener("click", () => { state.cycleIndex=state.cycles.length-1; $("cycle").value=state.cycleIndex; update(); });
$("previous").addEventListener("click", () => moveCycle(-1));
$("next").addEventListener("click", () => moveCycle(1));
$("zoomIn").addEventListener("click", () => zoomAt(0.8));
$("zoomOut").addEventListener("click", () => zoomAt(1.25));
$("zoomReset").addEventListener("click", resetCamera);

$("topology").addEventListener("wheel", event => {
  event.preventDefault();
  const point = clientToSvg(event.clientX, event.clientY);
  zoomAt(event.deltaY < 0 ? 0.82 : 1.22, point.x, point.y);
}, { passive: false });

$("topology").addEventListener("pointerdown", event => {
  if (event.button !== 0) return;
  state.drag = { clientX: event.clientX, clientY: event.clientY,
                 anchor: clientToSvg(event.clientX, event.clientY), moved: false };
  $("topology").setPointerCapture(event.pointerId);
  $("topology").classList.add("panning");
});

$("topology").addEventListener("pointermove", event => {
  if (!state.drag) return;
  if (Math.abs(event.clientX - state.drag.clientX) > 3 ||
      Math.abs(event.clientY - state.drag.clientY) > 3) state.drag.moved = true;
  const current = clientToSvg(event.clientX, event.clientY);
  state.camera.x += state.drag.anchor.x - current.x;
  state.camera.y += state.drag.anchor.y - current.y;
  applyCamera();
});

function finishPan(event) {
  if (!state.drag) return;
  state.suppressClick = state.drag.moved;
  try { $("topology").releasePointerCapture(event.pointerId); } catch (_) {}
  state.drag = null;
  $("topology").classList.remove("panning");
  if (state.suppressClick) setTimeout(() => { state.suppressClick = false; }, 0);
}
$("topology").addEventListener("pointerup", finishPan);
$("topology").addEventListener("pointercancel", finishPan);
$("topology").addEventListener("click", event => {
  if (!state.suppressClick) return;
  event.preventDefault();
  event.stopImmediatePropagation();
}, true);
$("play").addEventListener("click", () => {
  if (state.timer) { clearInterval(state.timer); state.timer=null; $("play").textContent="Play"; return; }
  $("play").textContent="Pause";
  state.timer=setInterval(() => {
    if (state.cycleIndex === state.cycles.length-1) state.cycleIndex=0;
    else state.cycleIndex++;
    $("cycle").value=state.cycleIndex; update();
  }, 800);
});
$("loadSample").addEventListener("click", loadBundled);
$("bundledTopology").addEventListener("change", loadBundled);
$("scaleMax").addEventListener("input", update);

$("layoutFile").addEventListener("change", async e => {
  state.layout = JSON.parse(await e.target.files[0].text());
  if (state.rows.size) installData(state.layout, [...state.rows.values()]);
});
$("telemetryFile").addEventListener("change", async e => {
  if (!state.layout) { $("status").textContent="Choose layout JSON first."; return; }
  installData(state.layout, parseCSV(await e.target.files[0].text()));
});

const requestedTopology = new URLSearchParams(window.location.search).get("topology");
if ([...$("bundledTopology").options].some(option => option.value === requestedTopology))
  $("bundledTopology").value = requestedTopology;
loadBundled();
