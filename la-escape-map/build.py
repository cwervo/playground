#!/usr/bin/env python3
"""Build index.html: a self-contained drive-time choropleth from downtown LA.

Pipeline
  1. Load boundaries (California, LA County from us-atlas; LA city outline).
  2. Build the highway graph from network.py, densify edges to ~3 km, run
     Dijkstra from downtown LA.
  3. Lay a grid over California (0.1 deg statewide, 0.025 deg inside LA County),
     estimate minutes for each cell = nearest graph node time + off-network
     access at city speed.
  4. Find where the routed graph crosses each boundary (city / county / state)
     and report the fastest crossings.
  5. Inline everything into template.html -> index.html.

Optional overrides (drop the file in data/ and rebuild):
  data/la_city.geojson    exact city limits (LA GeoHub "City Boundary")
  data/osrm_times.json    real routed minutes exported from the page's
                          "Load live OSRM times" button
"""
import json
import math
import os
import sys

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, mapping, shape
from shapely.geometry.polygon import orient

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import network as N  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

CITY_MPH = 30.0          # off-network access speed
CITY_SINUOSITY = 1.35    # straight-line -> street distance
DENSIFY_KM = 3.0
COARSE = 0.10            # deg, statewide cells
FINE = 0.025             # deg, cells inside the LA County bbox
KM_PER_DEG_LAT = 111.32
MI_PER_KM = 0.621371


def load_geojson(name):
    with open(os.path.join(DATA, name)) as f:
        return json.load(f)


def mainland(geom):
    """Largest polygon of a (Multi)Polygon."""
    if geom.geom_type == "Polygon":
        return geom
    return max(geom.geoms, key=lambda p: p.area)


def km_xy(lon, lat, lat0):
    """Local equirectangular projection in km around lat0."""
    return (lon * KM_PER_DEG_LAT * math.cos(math.radians(lat0)), lat * KM_PER_DEG_LAT)


def haversine_km(lon1, lat1, lon2, lat2):
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ---------------------------------------------------------------------------
# 1. boundaries
# ---------------------------------------------------------------------------
ca_gj = load_geojson("ca_state.geojson")
county_gj = load_geojson("la_county.geojson")
city_path = "la_city.geojson" if os.path.exists(os.path.join(DATA, "la_city.geojson")) else "la_city_approx.geojson"
city_gj = load_geojson(city_path)
city_is_approx = city_path.endswith("approx.geojson")
neighbors_gj = load_geojson("neighbor_states.geojson")
county_mesh_gj = load_geojson("ca_county_mesh.geojson")

ca_geom = shape(ca_gj["geometry"])
county_geom = shape(county_gj["geometry"])
city_geom = shape(city_gj["geometry"])
# d3-geo wants clockwise exterior rings and counter-clockwise holes (the
# opposite of RFC 7946); hand-drawn files may be wound either way.
city_geom = orient(city_geom, sign=-1.0) if city_geom.geom_type == "Polygon" else city_geom.__class__([orient(g, sign=-1.0) for g in city_geom.geoms])
city_gj["geometry"] = mapping(city_geom)
ca_main = mainland(ca_geom)
county_main = mainland(county_geom)
city_main = mainland(city_geom)

# ---------------------------------------------------------------------------
# 2. graph
# ---------------------------------------------------------------------------
node_index = {}
node_xy = []       # (lon, lat)
edges = []         # (u, v, minutes, route_name)


def node_id(key, lon, lat):
    if key not in node_index:
        node_index[key] = len(node_xy)
        node_xy.append((lon, lat))
    return node_index[key]


for name, cls, wps in N.ROUTES:
    mph, sinuosity = N.SPEEDS[cls]
    pts = [N.resolve(w) for w in wps]
    for (lon1, lat1, k1), (lon2, lat2, k2) in zip(pts, pts[1:]):
        d_km = haversine_km(lon1, lat1, lon2, lat2) * sinuosity
        n_seg = max(1, int(math.ceil(d_km / DENSIFY_KM)))
        prev = node_id(k1, lon1, lat1)
        for i in range(1, n_seg + 1):
            f = i / n_seg
            lon, lat = lon1 + (lon2 - lon1) * f, lat1 + (lat2 - lat1) * f
            key = k2 if i == n_seg else "%s|%s|%d" % (k1, k2, i)
            cur = node_id(key, lon, lat)
            minutes = (d_km / n_seg) * MI_PER_KM / mph * 60.0
            edges.append((prev, cur, minutes, name))
            prev = cur

n_nodes = len(node_xy)
rows = [e[0] for e in edges] + [e[1] for e in edges]
cols = [e[1] for e in edges] + [e[0] for e in edges]
vals = [e[2] for e in edges] * 2
graph = coo_matrix((vals, (rows, cols)), shape=(n_nodes, n_nodes)).tocsr()
origin = node_index[N.ORIGIN]
node_t, preds = dijkstra(graph, directed=False, indices=origin, return_predecessors=True)
print("graph: %d nodes, %d edges, max %.0f min" % (n_nodes, len(edges), node_t[np.isfinite(node_t)].max()))
unreach = np.sum(~np.isfinite(node_t))
if unreach:
    print("WARNING: %d unreachable nodes" % unreach)

# ---------------------------------------------------------------------------
# 3. grid
# ---------------------------------------------------------------------------
lat0 = 37.0
node_km = np.array([km_xy(lon, lat, lat0) for lon, lat in node_xy])
tree = cKDTree(node_km)


def estimate_minutes(lon, lat):
    d, idx = tree.query(km_xy(lon, lat, lat0), k=4)
    best = math.inf
    for dist_km, i in zip(d, idx):
        access = dist_km * CITY_SINUOSITY * MI_PER_KM / CITY_MPH * 60.0
        best = min(best, node_t[i] + access)
    return best


minx, miny, maxx, maxy = ca_main.bounds
cminx, cminy, cmaxx, cmaxy = county_main.bounds
cells = []


def add_cell(lon, lat, size):
    cx, cy = lon + size / 2, lat + size / 2
    if not ca_main.contains(Point(cx, cy)):
        return
    cells.append((round(lon, 4), round(lat, 4), size, round(estimate_minutes(cx, cy), 1)))


lon = math.floor(minx / COARSE) * COARSE
while lon < maxx:
    lat = math.floor(miny / COARSE) * COARSE
    while lat < maxy:
        in_county_box = (lon + COARSE > cminx and lon < cmaxx and lat + COARSE > cminy and lat < cmaxy)
        if in_county_box:
            k = int(round(COARSE / FINE))
            for i in range(k):
                for j in range(k):
                    add_cell(lon + i * FINE, lat + j * FINE, FINE)
        else:
            add_cell(lon, lat, COARSE)
        lat += COARSE
    lon += COARSE

minutes = np.array([c[3] for c in cells])
print("cells: %d, minutes range %.0f..%.0f" % (len(cells), minutes.min(), minutes.max()))

# ---------------------------------------------------------------------------
# 4. boundary crossings
# ---------------------------------------------------------------------------
node_pts = [Point(lon, lat) for lon, lat in node_xy]


neighbor_geoms = [shape(f["geometry"]) for f in neighbors_gj["features"]]


def in_mexico(p):
    # south of the CA/Baja border line (Tijuana to Yuma), with a small margin
    if p.x < -117.15 or p.x > -114.70:
        return False
    border_lat = 32.534 + (p.x + 117.12) * (32.720 - 32.534) / (117.12 - 114.72)
    return p.y < border_lat + 0.01


def outside_state_ok(p):
    return in_mexico(p) or any(g.contains(p) for g in neighbor_geoms)


def crossings(poly, label, outside_ok):
    """Graph edges that leave `poly`; the far node must satisfy outside_ok so
    coastal segments drawn through the ocean do not count as exits."""
    inside = [poly.contains(p) for p in node_pts]
    boundary = poly.boundary
    found = []
    for u, v, minutes_uv, name in edges:
        if inside[u] == inside[v]:
            continue
        a, b = (u, v) if inside[u] else (v, u)
        if not np.isfinite(node_t[a]) or not outside_ok(node_pts[b]):
            continue
        seg = LineString([node_xy[a], node_xy[b]])
        x = seg.intersection(boundary)
        if x.is_empty:
            continue
        if x.geom_type != "Point":
            x = min(x.geoms, key=lambda g: g.distance(Point(node_xy[a]))) if hasattr(x, "geoms") else x
            if x.geom_type != "Point":
                x = x.representative_point()
        frac = seg.project(x) / seg.length if seg.length else 0.0
        t = node_t[a] + frac * minutes_uv
        found.append({"minutes": round(float(t), 1), "lon": round(x.x, 4), "lat": round(x.y, 4),
                      "route": name})
    found.sort(key=lambda c: c["minutes"])
    # keep the fastest crossing per route (dedupe repeated densified hits)
    seen, out = set(), []
    for c in found:
        if c["route"] in seen:
            continue
        seen.add(c["route"])
        out.append(c)
    print("%s exit: %s" % (label, ", ".join("%s %.0f min" % (c["route"], c["minutes"]) for c in out[:5])))
    return out


exits = {
    "city": crossings(city_geom, "city", lambda p: county_main.contains(p)),
    "county": crossings(county_geom, "county", lambda p: ca_main.contains(p)),
    "state": crossings(ca_geom, "state", outside_state_ok),
}

# All boundary-crossing candidates get a short human label for the state exits.
STATE_LABELS = {
    "sanysidro": "San Ysidro → Tijuana, MX", "calexico": "Calexico → Mexicali, MX",
    "az_i8": "Yuma, AZ", "az_i10": "Blythe → Ehrenberg, AZ", "parker_az": "Parker, AZ",
    "topock": "Needles → Topock, AZ", "us95_nv": "Cal-Nev-Ari, NV", "primm": "Primm, NV",
    "nv_sr127": "Death Valley Jn → Amargosa, NV", "nv_us6": "Benton → Montgomery Pass, NV",
    "nv_us395_topaz": "Topaz Lake, NV", "nv_sr88": "Woodfords → Minden, NV",
    "nv_us50": "Stateline, NV", "nv_i80": "Verdi, NV", "nv_us395_reno": "Bordertown, NV",
    "nv_sr299": "Cedarville → Vya, NV", "or_us395": "Lakeview, OR", "or_sr139": "Tulelake → Klamath Falls, OR",
    "or_us97": "Dorris → Klamath Falls, OR", "or_i5": "Siskiyou Summit, OR", "or_us199": "O'Brien, OR",
    "or_us101": "Brookings, OR",
}
place_pts = {k: Point(v) for k, v in N.PLACES.items() if k in STATE_LABELS}
for c in exits["state"]:
    p = Point(c["lon"], c["lat"])
    k = min(place_pts, key=lambda k: place_pts[k].distance(p))
    c["label"] = STATE_LABELS[k]

# ---------------------------------------------------------------------------
# 5. optional live OSRM override
# ---------------------------------------------------------------------------
osrm_path = os.path.join(DATA, "osrm_times.json")
osrm = None
if os.path.exists(osrm_path):
    with open(osrm_path) as f:
        osrm = json.load(f)
    print("using data/osrm_times.json (%d cells)" % len(osrm.get("cells", [])))

# ---------------------------------------------------------------------------
# 6. emit
# ---------------------------------------------------------------------------
route_lines = []
for name, cls, wps in N.ROUTES:
    route_lines.append({"name": name, "cls": cls,
                        "pts": [[round(N.resolve(w)[0], 3), round(N.resolve(w)[1], 3)] for w in wps]})

payload = {
    "origin": {"lon": N.PLACES[N.ORIGIN][0], "lat": N.PLACES[N.ORIGIN][1], "name": "Downtown Los Angeles"},
    "cells": cells,
    "exits": exits,
    "cityIsApprox": city_is_approx,
    "routes": route_lines,
    "osrm": osrm,
    "model": {"cityMph": CITY_MPH, "citySinuosity": CITY_SINUOSITY, "speeds": N.SPEEDS},
}

with open(os.path.join(HERE, "template.html")) as f:
    tpl = f.read()


def js(obj):
    return json.dumps(obj, separators=(",", ":")).replace("</", "<\\/")


with open(os.path.join(HERE, "vendor", "d3.min.js")) as f:
    d3_src = f.read()

html = (tpl.replace("/*__D3__*/", d3_src)
        .replace("/*__DATA__*/", "const DATA=" + js(payload) + ";")
        .replace("/*__GEO__*/", "const GEO=" + js({
            "ca": ca_gj, "county": county_gj, "city": city_gj,
            "neighbors": neighbors_gj, "countyMesh": county_mesh_gj}) + ";"))
out = os.path.join(HERE, "index.html")
with open(out, "w") as f:
    f.write(html)
print("wrote %s (%.1f KB)" % (out, len(html) / 1024))
