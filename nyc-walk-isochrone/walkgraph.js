// Pedestrian graph + search. No DOM, no map: runs in the browser or in node.
//
// Graph layout is CSR (compressed sparse rows): node i's neighbours live in
// adj[off[i] .. off[i+1]) with edge lengths (metres) in len[] at the same index.

const R_EARTH = 6371008.8;
const RAD = Math.PI / 180;

export function haversine(lon1, lat1, lon2, lat2) {
  const dLat = (lat2 - lat1) * RAD;
  const dLon = (lon2 - lon1) * RAD;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * RAD) * Math.cos(lat2 * RAD) * Math.sin(dLon / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(a)));
}

// Point `dist` metres from (lon, lat) along compass bearing `deg`.
export function destination(lon, lat, deg, dist) {
  const d = dist / R_EARTH, b = deg * RAD;
  const p1 = lat * RAD, l1 = lon * RAD;
  const p2 = Math.asin(Math.sin(p1) * Math.cos(d) + Math.cos(p1) * Math.sin(d) * Math.cos(b));
  const l2 = l1 + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(p1),
    Math.cos(d) - Math.sin(p1) * Math.sin(p2));
  return [l2 / RAD, p2 / RAD];
}

export function bearing(lon1, lat1, lon2, lat2) {
  const p1 = lat1 * RAD, p2 = lat2 * RAD, dl = (lon2 - lon1) * RAD;
  const y = Math.sin(dl) * Math.cos(p2);
  const x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
  return (Math.atan2(y, x) / RAD + 360) % 360;
}

// Build a CSR graph from an Overpass `out skel` JSON response.
export function buildGraph(osm) {
  const idx = new Map();
  const lon = [], lat = [];
  for (const el of osm.elements) {
    if (el.type !== 'node') continue;
    idx.set(el.id, lon.length);
    lon.push(el.lon);
    lat.push(el.lat);
  }
  const n = lon.length;
  const deg = new Uint32Array(n);
  const pairs = [];
  for (const el of osm.elements) {
    if (el.type !== 'way' || !el.nodes) continue;
    for (let k = 1; k < el.nodes.length; k++) {
      const a = idx.get(el.nodes[k - 1]), b = idx.get(el.nodes[k]);
      if (a === undefined || b === undefined || a === b) continue;
      pairs.push(a, b);
      deg[a]++; deg[b]++;
    }
  }
  const off = new Uint32Array(n + 1);
  for (let i = 0; i < n; i++) off[i + 1] = off[i] + deg[i];
  const adj = new Uint32Array(off[n]);
  const len = new Float32Array(off[n]);
  const fill = off.slice(0, n);
  for (let k = 0; k < pairs.length; k += 2) {
    const a = pairs[k], b = pairs[k + 1];
    const d = haversine(lon[a], lat[a], lon[b], lat[b]);
    adj[fill[a]] = b; len[fill[a]++] = d;
    adj[fill[b]] = a; len[fill[b]++] = d;
  }
  return { n, lon: Float64Array.from(lon), lat: Float64Array.from(lat), off, adj, len };
}

// Minimal binary min-heap keyed by float priority.
class Heap {
  constructor() { this.k = []; this.v = []; }
  get size() { return this.k.length; }
  push(key, val) {
    const k = this.k, v = this.v;
    let i = k.length;
    k.push(key); v.push(val);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (k[p] <= key) break;
      k[i] = k[p]; v[i] = v[p]; i = p;
    }
    k[i] = key; v[i] = val;
  }
  pop() {
    const k = this.k, v = this.v;
    const top = v[0];
    const lk = k.pop(), lv = v.pop();
    const n = k.length;
    if (n) {
      let i = 0;
      for (;;) {
        let c = 2 * i + 1;
        if (c >= n) break;
        if (c + 1 < n && k[c + 1] < k[c]) c++;
        if (k[c] >= lk) break;
        k[i] = k[c]; v[i] = v[c]; i = c;
      }
      k[i] = lk; v[i] = lv;
    }
    return top;
  }
}

// A* from src to dst. Costs are metres; the heuristic is great-circle distance,
// which never overestimates a walk, so the returned path is optimal.
// Returns { path: [nodeIdx...], dist, expanded } or null if unreachable.
export function astar(g, src, dst, maxDist = Infinity) {
  const { lon, lat, off, adj, len } = g;
  const gScore = new Float64Array(g.n).fill(Infinity);
  const prev = new Int32Array(g.n).fill(-1);
  const closed = new Uint8Array(g.n);
  const tx = lon[dst], ty = lat[dst];
  const h = (i) => haversine(lon[i], lat[i], tx, ty);
  const open = new Heap();
  gScore[src] = 0;
  open.push(h(src), src);
  let expanded = 0;
  while (open.size) {
    const u = open.pop();
    if (closed[u]) continue;
    closed[u] = 1;
    expanded++;
    if (u === dst) {
      const path = [];
      for (let v = dst; v !== -1; v = prev[v]) path.push(v);
      return { path: path.reverse(), dist: gScore[dst], expanded };
    }
    const gu = gScore[u];
    for (let e = off[u]; e < off[u + 1]; e++) {
      const v = adj[e];
      const gv = gu + len[e];
      if (gv < gScore[v] && gv <= maxDist) {
        gScore[v] = gv;
        prev[v] = u;
        open.push(gv + h(v), v);
      }
    }
  }
  return null;
}

// Every node within `maxDist` metres of walking from src (A* with h = 0,
// i.e. Dijkstra, since an isochrone has no single goal to aim at).
export function reach(g, src, maxDist) {
  const { off, adj, len } = g;
  const dist = new Float64Array(g.n).fill(Infinity);
  const open = new Heap();
  dist[src] = 0;
  open.push(0, src);
  while (open.size) {
    const u = open.pop();
    const du = dist[u];
    for (let e = off[u]; e < off[u + 1]; e++) {
      const v = adj[e];
      const dv = du + len[e];
      if (dv < dist[v] && dv <= maxDist) {
        dist[v] = dv;
        open.push(dv, v);
      }
    }
  }
  return dist;
}

// Uniform grid for nearest-node lookups.
export function buildIndex(g, cell = 0.002) {
  const cells = new Map();
  for (let i = 0; i < g.n; i++) {
    const key = Math.floor(g.lon[i] / cell) + ',' + Math.floor(g.lat[i] / cell);
    let c = cells.get(key);
    if (!c) cells.set(key, c = []);
    c.push(i);
  }
  return { cell, cells };
}

// Nearest node, optionally restricted to nodes where accept(i) is true.
export function nearest(g, index, lon, lat, accept = null, maxRing = 6) {
  const { cell, cells } = index;
  const cx = Math.floor(lon / cell), cy = Math.floor(lat / cell);
  let best = -1, bestD = Infinity, foundAt = -1;
  for (let r = 0; r <= maxRing; r++) {
    for (let dx = -r; dx <= r; dx++) {
      for (let dy = -r; dy <= r; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        const c = cells.get((cx + dx) + ',' + (cy + dy));
        if (!c) continue;
        for (const i of c) {
          if (accept && !accept(i)) continue;
          const d = haversine(lon, lat, g.lon[i], g.lat[i]);
          if (d < bestD) { bestD = d; best = i; }
        }
      }
    }
    // Search one ring past the first hit: a corner of ring r can be farther
    // than an edge cell of ring r+1.
    if (best !== -1 && foundAt === -1) foundAt = r;
    if (foundAt !== -1 && r > foundAt) break;
  }
  return best === -1 ? null : { node: best, dist: bestD };
}
