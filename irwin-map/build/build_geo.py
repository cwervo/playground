import json, math

R_MI = 3958.7613
ORIGIN = (40.7580, -73.9855)   # Times Square, Midtown Manhattan
MAX_MI = 300.0

def gc(a, b):
    (la1, lo1), (la2, lo2) = a, b
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R_MI * math.asin(min(1, math.sqrt(h)))

# ---- Albers equal-area conic, tuned to the Northeast corridor -------------
LAT0, LON0, SP1, SP2 = 40.0, -74.5, 37.0, 44.0
_p1, _p2, _p0 = map(math.radians, (SP1, SP2, LAT0))
_n = 0.5 * (math.sin(_p1) + math.sin(_p2))
_C = math.cos(_p1)**2 + 2*_n*math.sin(_p1)
_r0 = math.sqrt(_C - 2*_n*math.sin(_p0)) / _n

def albers(lon, lat):
    p, l = math.radians(lat), math.radians(lon - LON0)
    r = math.sqrt(max(0.0, _C - 2*_n*math.sin(p))) / _n
    t = _n * l
    return (r * math.sin(t), r * math.cos(t) - _r0)     # y negated: north is up in SVG

def rings(geom):
    t = geom["type"]
    if t == "Polygon":  return geom["coordinates"]
    if t == "MultiPolygon": return [r for poly in geom["coordinates"] for r in poly]
    return []

REGION = {"09","10","11","23","24","25","33","34","36","42","44","50","51","54"}
CONTEXT_STATES = {"Connecticut","Delaware","District of Columbia","Maine","Maryland",
                  "Massachusetts","New Hampshire","New Jersey","New York","Pennsylvania",
                  "Rhode Island","Vermont","Virginia","West Virginia","Ohio","North Carolina"}

counties = json.load(open("counties.geojson"))["features"]
states   = json.load(open("states.geojson"))["features"]

def ring_centroid(rs):
    """Area-weighted centroid of the largest ring (planar; fine at this scale)."""
    best, ba = None, -1
    for r in rs:
        a = 0.0; cx = 0.0; cy = 0.0
        for i in range(len(r) - 1):
            x0, y0 = r[i][0], r[i][1]; x1, y1 = r[i+1][0], r[i+1][1]
            cr = x0*y1 - x1*y0
            a += cr; cx += (x0+x1)*cr; cy += (y0+y1)*cr
        a *= 0.5
        if abs(a) > ba:
            ba = abs(a)
            best = (cx/(6*a), cy/(6*a)) if a else (r[0][0], r[0][1])
    return best

def path_of(rs, project, prec=1):
    out = []
    for r in rs:
        pts = []
        last = None
        for lon, lat in r:
            x, y = project(lon, lat)
            p = (round(x, prec), round(y, prec))
            if p != last:
                pts.append(p); last = p
        if len(pts) < 3: continue
        out.append("M" + "L".join(f"{x},{y}" for x, y in pts) + "Z")
    return "".join(out)

# --- scale: project degrees -> px so the 300-mile ring fits a 1000-wide box
def ring_pts(miles, n=180):
    lat0, lon0 = ORIGIN
    pts = []
    for i in range(n + 1):
        brg = math.radians(i * 360.0 / n)
        d = miles / R_MI
        p1 = math.radians(lat0); l1 = math.radians(lon0)
        p2 = math.asin(math.sin(p1)*math.cos(d) + math.cos(p1)*math.sin(d)*math.cos(brg))
        l2 = l1 + math.atan2(math.sin(brg)*math.sin(d)*math.cos(p1),
                             math.cos(d) - math.sin(p1)*math.sin(p2))
        pts.append((math.degrees(l2), math.degrees(p2)))
    return pts

raw = [albers(lo, la) for lo, la in ring_pts(MAX_MI)]
xs = [p[0] for p in raw]; ys = [p[1] for p in raw]
PAD = 0.06
w = (max(xs) - min(xs)) * (1 + 2*PAD); h = (max(ys) - min(ys)) * (1 + 2*PAD)
SCALE = 1000.0 / w
X0 = min(xs) - (max(xs)-min(xs))*PAD
Y0 = min(ys) - (max(ys)-min(ys))*PAD
VB_H = round(h * SCALE, 1)

def proj(lon, lat):
    x, y = albers(lon, lat)
    return ((x - X0) * SCALE, (y - Y0) * SCALE)

BANDS = [50, 100, 150, 200, 250, 300]
def band_of(d):
    for i, b in enumerate(BANDS):
        if d <= b: return i
    return None

county_out, kept = [], 0
for f in counties:
    st = f["properties"]["STATE"]
    if st not in REGION: continue
    rs = rings(f["geometry"])
    if not rs: continue
    cx, cy = ring_centroid(rs)
    d = gc(ORIGIN, (cy, cx))
    b = band_of(d)
    if b is None: continue
    county_out.append({
        "n": f["properties"]["NAME"], "s": st,
        "d": round(d), "b": b,
        "p": path_of(rs, proj, 1),
    })
    kept += 1

state_out = []
for f in states:
    if f["properties"]["name"] not in CONTEXT_STATES: continue
    state_out.append({"n": f["properties"]["name"], "p": path_of(rings(f["geometry"]), proj, 1)})

def south_pt(m):
    lat0, lon0 = ORIGIN
    d = m / R_MI; p1 = math.radians(lat0)
    p2 = math.asin(math.sin(p1)*math.cos(d) - math.cos(p1)*math.sin(d))   # bearing 180
    return proj(lon0, math.degrees(p2))

ring_out = [{"mi": m, "p": "M" + "L".join(f"{proj(lo,la)[0]:.1f},{proj(lo,la)[1]:.1f}"
                                          for lo, la in ring_pts(m, 120)) + "Z",
             "lx": round(south_pt(m)[0],1), "ly": round(south_pt(m)[1],1)} for m in BANDS]

json.dump({"vbW": 1000, "vbH": VB_H, "counties": county_out, "states": state_out,
           "ringPaths": ring_out, "bands": BANDS},
          open("region.json", "w"), separators=(",", ":"))

print("counties kept:", kept, "states:", len(state_out), "viewBox 1000 x", VB_H)
import os; print("region.json", os.path.getsize("region.json")//1024, "KB")
# sanity: where do the anchor cities land?
for nm, (la, lo) in {"TimesSq": ORIGIN, "Beacon": (41.5045,-73.9835), "Buffalo": (42.9333,-78.8760),
                     "DC": (38.8883,-77.0230), "Boston": (42.3601,-71.0589)}.items():
    print(f"  {nm:8s} d={gc(ORIGIN,(la,lo)):6.1f} mi  px={proj(lo,la)[0]:7.1f},{proj(lo,la)[1]:7.1f}")
