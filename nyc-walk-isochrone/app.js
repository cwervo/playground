import {
  haversine, destination, bearing, buildGraph, buildIndex, nearest, astar, reach,
} from './walkgraph.js';

const CROW = '#1010ff';
const WALK = '#ff4f1f';
const SPOKES = 72;
// Rough NYC bounds; clicks outside are ignored.
const NYC = [[-74.2591, 40.4774], [-73.7004, 40.9176]];
const OVERPASS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

const $ = (id) => document.getElementById(id);
const ui = {
  crowMin: $('crow-min'), walkMin: $('walk-min'), speed: $('speed'),
  crowMinOut: $('crow-min-out'), walkMinOut: $('walk-min-out'), speedOut: $('speed-out'),
  status: $('status'), stats: $('stats'), hover: $('hover'),
};

const state = {
  origin: null,         // [lon, lat]
  graph: null, index: null, bbox: null,
  src: -1, dist: null,  // walking metres from src to every node
  fetchSeq: 0,
};

const settings = () => {
  const speed = +ui.speed.value * 1000 / 60;        // metres per minute
  return {
    speed,
    crowM: +ui.crowMin.value * speed,
    walkM: +ui.walkMin.value * speed,
  };
};

const empty = { type: 'FeatureCollection', features: [] };
const fc = (features) => ({ type: 'FeatureCollection', features });
const line = (coords, props = {}) => ({
  type: 'Feature', properties: props, geometry: { type: 'LineString', coordinates: coords },
});

const map = new maplibregl.Map({
  container: 'map',
  style: 'https://tiles.openfreemap.org/styles/positron',
  bounds: NYC,
  fitBoundsOptions: { padding: 20 },
  attributionControl: { compact: true },
});
map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-right');

map.on('load', () => {
  const src = (id) => map.addSource(id, { type: 'geojson', data: empty });
  ['crow-area', 'crow-spokes', 'walk-net', 'walk-trails', 'hover-crow', 'hover-walk', 'origin']
    .forEach(src);

  map.addLayer({ id: 'crow-area-fill', type: 'fill', source: 'crow-area',
    paint: { 'fill-color': CROW, 'fill-opacity': 0.04 } });
  map.addLayer({ id: 'crow-area-line', type: 'line', source: 'crow-area',
    paint: { 'line-color': CROW, 'line-width': 2 } });
  map.addLayer({ id: 'crow-spokes', type: 'line', source: 'crow-spokes',
    paint: { 'line-color': CROW, 'line-width': 1.25, 'line-opacity': 0.8 } });

  // Every street segment reachable on foot, faded by how long it takes to get there.
  map.addLayer({ id: 'walk-net', type: 'line', source: 'walk-net',
    layout: { 'line-cap': 'round' },
    paint: {
      'line-color': WALK,
      'line-width': ['interpolate', ['linear'], ['zoom'], 11, 0.8, 15, 2.5],
      'line-opacity': ['interpolate', ['linear'], ['get', 't'], 0, 0.75, 1, 0.25],
    } });
  // A* trails to the farthest reachable point in each spoke direction.
  map.addLayer({ id: 'walk-trails', type: 'line', source: 'walk-trails',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': WALK, 'line-width': 2.25 } });

  map.addLayer({ id: 'hover-crow', type: 'line', source: 'hover-crow',
    paint: { 'line-color': CROW, 'line-width': 3, 'line-dasharray': [2, 1.5] } });
  map.addLayer({ id: 'hover-walk-casing', type: 'line', source: 'hover-walk',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#fff', 'line-width': 7 } });
  map.addLayer({ id: 'hover-walk', type: 'line', source: 'hover-walk',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#111', 'line-width': 3.5 } });

  map.addLayer({ id: 'origin', type: 'circle', source: 'origin',
    paint: { 'circle-radius': 7, 'circle-color': '#111',
      'circle-stroke-color': '#fff', 'circle-stroke-width': 3 } });

  const fromHash = location.hash.slice(1).split(',').map(Number);
  const origin = fromHash.length === 2 && fromHash.every(Number.isFinite)
    ? fromHash : [-73.9973, 40.7308];   // Washington Square Park
  const r = settings().crowM * 1.1;
  map.fitBounds([destination(...origin, 225, r * Math.SQRT2), destination(...origin, 45, r * Math.SQRT2)],
    { padding: 20, animate: false });
  setOrigin(origin);
});

map.on('click', (e) => {
  const { lng, lat } = e.lngLat;
  if (lng < NYC[0][0] || lng > NYC[1][0] || lat < NYC[0][1] || lat > NYC[1][1]) {
    setStatus('That’s outside NYC — click somewhere in the five boroughs.');
    return;
  }
  setOrigin([lng, lat]);
});

let hoverFrame = 0;
map.on('mousemove', (e) => {
  cancelAnimationFrame(hoverFrame);
  hoverFrame = requestAnimationFrame(() => hover([e.lngLat.lng, e.lngLat.lat]));
});
map.getCanvasContainer().addEventListener('mouseleave', clearHover);

for (const input of [ui.crowMin, ui.walkMin, ui.speed]) {
  input.addEventListener('input', () => { renderLabels(); recompute(); });
}
renderLabels();

function renderLabels() {
  ui.crowMinOut.textContent = ui.crowMin.value;
  ui.walkMinOut.textContent = ui.walkMin.value;
  ui.speedOut.textContent = (+ui.speed.value).toFixed(1);
}

function setStatus(msg) { ui.status.textContent = msg; }
function set(id, data) { map.getSource(id).setData(data); }

async function setOrigin(origin) {
  state.origin = origin;
  history.replaceState(null, '', '#' + origin.map((v) => v.toFixed(5)).join(','));
  set('origin', fc([{ type: 'Feature', properties: {},
    geometry: { type: 'Point', coordinates: origin } }]));
  clearHover();
  drawCrow();
  set('walk-net', empty);
  set('walk-trails', empty);
  ui.stats.innerHTML = '';
  await ensureGraph();
  recompute();
}

// Overpass bbox around the origin that covers both radii plus some slack.
function wantedBbox() {
  const { crowM, walkM } = settings();
  const r = Math.max(crowM, walkM) + 250;
  const [lon, lat] = state.origin;
  return {
    s: destination(lon, lat, 180, r)[1], n: destination(lon, lat, 0, r)[1],
    w: destination(lon, lat, 270, r)[0], e: destination(lon, lat, 90, r)[0],
  };
}

const covers = (a, b) => a && a.s <= b.s && a.n >= b.n && a.w <= b.w && a.e >= b.e;

async function ensureGraph() {
  const want = wantedBbox();
  if (covers(state.bbox, want)) return;
  const seq = ++state.fetchSeq;
  // Everything a person can legally walk on: streets, sidewalks, paths,
  // stairs, footbridges. Highways and private roads are out.
  const q = `[out:json][timeout:90];
way["highway"]["highway"!~"^(motorway|motorway_link|trunk|trunk_link|construction|proposed|raceway|bus_guideway|busway|elevator|platform)$"]["foot"!~"^(no|private)$"]["access"!~"^(no|private)$"]["area"!="yes"](${want.s},${want.w},${want.n},${want.e});
(._;>;);
out skel qt;`;
  setStatus('Loading NYC walking network from OpenStreetMap…');
  let osm = null, lastErr = null;
  for (const url of OVERPASS) {
    try {
      const res = await fetch(url, { method: 'POST', body: 'data=' + encodeURIComponent(q) });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      osm = await res.json();
      break;
    } catch (err) { lastErr = err; }
  }
  if (seq !== state.fetchSeq) return;   // a newer click superseded this one
  if (!osm) {
    setStatus(`Couldn’t load walking network (${lastErr}). Showing crow-flies only.`);
    state.graph = null;
    return;
  }
  const t0 = performance.now();
  state.graph = buildGraph(osm);
  state.index = buildIndex(state.graph);
  state.bbox = want;
  setStatus(`${state.graph.n.toLocaleString()} walkable OSM nodes loaded ` +
    `(${Math.round(performance.now() - t0)} ms to build graph).`);
}

async function recompute() {
  if (!state.origin || !map.isStyleLoaded()) return;
  drawCrow();
  await ensureGraph();
  const g = state.graph;
  if (!g) return;
  const { walkM, crowM, speed } = settings();
  const [olon, olat] = state.origin;

  const start = nearest(g, state.index, olon, olat);
  if (!start || start.dist > 300) {
    setStatus('No walkable street near that point (water?). Try clicking on land.');
    set('walk-net', empty); set('walk-trails', empty);
    return;
  }
  // Walking from the click to the nearest street node spends part of the budget.
  const budget = walkM - start.dist;
  state.src = start.node;
  state.dist = reach(g, start.node, Math.max(0, budget));
  const dist = state.dist;

  // Reachable street segments, clipping the ones that run out of time midway.
  const net = [];
  let streetM = 0;
  for (let u = 0; u < g.n; u++) {
    const du = dist[u];
    if (du > budget) continue;
    for (let e = g.off[u]; e < g.off[u + 1]; e++) {
      const v = g.adj[e], dv = dist[v], L = g.len[e];
      const a = [g.lon[u], g.lat[u]], b = [g.lon[v], g.lat[v]];
      if (dv <= budget) {
        if (u < v) { net.push(line([a, b], { t: Math.min(du, dv) / budget })); streetM += L; }
      } else if (du + L > budget) {
        const f = (budget - du) / L;
        net.push(line([a, [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]], { t: 1 }));
        streetM += L * f;
      }
    }
  }
  set('walk-net', fc(net));

  // For each spoke direction, the reachable node farthest from the origin as
  // the crow flies, then an A* walk to it.
  const far = new Int32Array(SPOKES).fill(-1);
  const farD = new Float64Array(SPOKES);
  for (let i = 0; i < g.n; i++) {
    if (dist[i] > budget) continue;
    const d = haversine(olon, olat, g.lon[i], g.lat[i]);
    const bin = Math.floor(bearing(olon, olat, g.lon[i], g.lat[i]) / (360 / SPOKES)) % SPOKES;
    if (d > farD[bin]) { farD[bin] = d; far[bin] = i; }
  }
  const trails = [];
  let expanded = 0, runs = 0;
  const t0 = performance.now();
  for (let k = 0; k < SPOKES; k++) {
    if (far[k] < 0) continue;
    const r = astar(g, start.node, far[k], budget);
    if (!r) continue;
    runs++;
    expanded += r.expanded;
    trails.push(line([state.origin, ...r.path.map((i) => [g.lon[i], g.lat[i]])],
      { minutes: (r.dist + start.dist) / speed }));
  }
  const astarMs = performance.now() - t0;
  set('walk-trails', fc(trails));

  const reached = farD.reduce((s, d) => s + d, 0) / SPOKES;
  const reachedNodes = dist.reduce((s, d) => s + (d <= budget), 0);
  ui.stats.innerHTML = `
    <div><b style="color:${CROW}">Crow flies, ${ui.crowMin.value} min:</b> ${(crowM / 1000).toFixed(2)} km radius</div>
    <div><b style="color:${WALK}">Walking, ${ui.walkMin.value} min:</b> reaches on average
      <b>${(reached / 1000).toFixed(2)} km</b> out (${Math.round(100 * reached / crowM)}% of the crow radius)</div>
    <div class="dim">${reachedNodes.toLocaleString()} intersections · ${(streetM / 1000).toFixed(1)} km of path reachable ·
      ${runs} A* trails in ${Math.round(astarMs)} ms (${expanded.toLocaleString()} nodes expanded)</div>`;
}

function drawCrow() {
  if (!state.origin) return;
  const { crowM } = settings();
  const [lon, lat] = state.origin;
  const ring = [];
  for (let i = 0; i <= 180; i++) ring.push(destination(lon, lat, i * 2, crowM));
  set('crow-area', fc([{ type: 'Feature', properties: {},
    geometry: { type: 'Polygon', coordinates: [ring] } }]));
  const spokes = [];
  for (let k = 0; k < SPOKES; k++) {
    // Centre each spoke in its bin so it lines up with the walking trail for that bin.
    spokes.push(line([state.origin, destination(lon, lat, (k + 0.5) * 360 / SPOKES, crowM)]));
  }
  set('crow-spokes', fc(spokes));
}

function hover([lon, lat]) {
  const g = state.graph;
  if (!g || !state.dist || !state.origin) return;
  const { speed, walkM } = settings();
  const [olon, olat] = state.origin;
  const crowD = haversine(olon, olat, lon, lat);
  set('hover-crow', fc([line([state.origin, [lon, lat]])]));

  const hit = nearest(g, state.index, lon, lat);
  const crowTxt = `<span style="color:${CROW}">crow flies ${(crowD / 1000).toFixed(2)} km · ${Math.round(crowD / speed)} min</span>`;
  if (!hit || hit.dist > 250) {
    set('hover-walk', empty);
    ui.hover.innerHTML = crowTxt + '<br><span class="dim">no walkable street here</span>';
    return;
  }
  const startGap = haversine(olon, olat, g.lon[state.src], g.lat[state.src]);
  const r = astar(g, state.src, hit.node);
  if (!r) {
    set('hover-walk', empty);
    ui.hover.innerHTML = crowTxt + '<br><span class="dim">not reachable on foot in loaded area</span>';
    return;
  }
  const walkD = r.dist + startGap + hit.dist;
  const coords = [state.origin, ...r.path.map((i) => [g.lon[i], g.lat[i]]), [lon, lat]];
  set('hover-walk', fc([line(coords)]));
  const mins = walkD / speed;
  const ok = walkD <= walkM;
  ui.hover.innerHTML = `${crowTxt}<br>
    <span style="color:${WALK}">A* walk ${(walkD / 1000).toFixed(2)} km · ${Math.round(mins)} min</span>
    ${ok ? '✓' : '✗'} <span class="dim">· detour ×${(walkD / Math.max(crowD, 1)).toFixed(2)} · ${r.expanded.toLocaleString()} expanded</span>`;
}

function clearHover() {
  if (!map.getSource('hover-walk')) return;
  set('hover-walk', empty);
  set('hover-crow', empty);
  ui.hover.innerHTML = '<span class="dim">Hover the map to A* a walk from the pin.</span>';
}
