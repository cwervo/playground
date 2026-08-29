import json, math
exec(open("build_geo.py").read().split("BANDS = [50")[0].replace(
    'counties = json.load(open("counties.geojson"))["features"]', 'counties = []').replace(
    'states   = json.load(open("states.geojson"))["features"]', 'states = []'))

# ---------- Manhattan inset: local equirectangular ------------------------
I_LAT = (40.7215, 40.8015); I_LON = (-74.0320, -73.9420)
I_W = 520.0
_kx = math.cos(math.radians(sum(I_LAT)/2))
I_H = round(I_W * (I_LAT[1]-I_LAT[0]) / ((I_LON[1]-I_LON[0]) * _kx), 1)
def iproj(lon, lat):
    x = (lon - I_LON[0]) / (I_LON[1] - I_LON[0]) * I_W
    y = (I_LAT[1] - lat) / (I_LAT[1] - I_LAT[0]) * I_H
    return (x, y)

# ---------- Manhattan, drawn from its shoreline ---------------------------
# Census county polygons run out to the middle of the rivers, so the boroughs
# arrive as one solid block with no water. These are shorelines instead.
MANHATTAN = [
 (-74.0170,40.7010),(-74.0170,40.7075),(-74.0130,40.7190),(-74.0115,40.7290),
 (-74.0100,40.7400),(-74.0085,40.7500),(-74.0000,40.7625),(-73.9920,40.7790),
 (-73.9770,40.7960),(-73.9630,40.8195),(-73.9530,40.8380),(-73.9470,40.8500),
 (-73.9270,40.8740),(-73.9230,40.8760),(-73.9210,40.8640),(-73.9330,40.8340),
 (-73.9310,40.8200),(-73.9330,40.8030),(-73.9330,40.7930),(-73.9410,40.7810),
 (-73.9480,40.7700),(-73.9560,40.7620),(-73.9640,40.7520),(-73.9700,40.7430),
 (-73.9730,40.7370),(-73.9740,40.7280),(-73.9740,40.7180),(-73.9760,40.7110),
 (-73.9840,40.7090),(-73.9955,40.7075),(-74.0110,40.7020),
]
CENTRAL_PARK = [(-73.9819,40.7681),(-73.9732,40.7644),(-73.9497,40.7968),(-73.9581,40.8005)]
# opposite banks, closed off along the frame edge
NEW_JERSEY = [(-74.0345,40.7150),(-74.0290,40.7280),(-74.0280,40.7380),(-74.0250,40.7480),
              (-74.0180,40.7620),(-74.0100,40.7760),(-73.9990,40.8070),(-74.0420,40.8070),
              (-74.0420,40.7150)]
LONG_ISLAND = [(-73.9640,40.7150),(-73.9610,40.7300),(-73.9580,40.7380),(-73.9580,40.7450),
               (-73.9600,40.7500),(-73.9600,40.7560),(-73.9560,40.7620),(-73.9370,40.7700),
               (-73.9250,40.7800),(-73.9270,40.8070),(-73.9330,40.8070),(-73.9330,40.7150)]

inset_land = [
  {"n":"New Jersey",   "k":"land", "p": path_of([NEW_JERSEY  + [NEW_JERSEY[0]]],  iproj, 1)},
  {"n":"Brooklyn and Queens","k":"land","p": path_of([LONG_ISLAND + [LONG_ISLAND[0]]], iproj, 1)},
  {"n":"Manhattan",    "k":"land", "p": path_of([MANHATTAN   + [MANHATTAN[0]]],   iproj, 1)},
  {"n":"Central Park", "k":"park", "p": path_of([CENTRAL_PARK + [CENTRAL_PARK[0]]],iproj, 1)},
]

# ---------- the works -----------------------------------------------------
S = [
 dict(k="moma", name="Museum of Modern Art", place="11 W 53rd St, Midtown",
      lat=40.7614, lon=-73.9776, mode="foot", status="historic",
      work="Fractured Light—Partial Scrim Ceiling—Eye-Level Wire (1970–71)",
      note="Irwin's first scrim installation, made for a small MoMA gallery and shown 24 Oct 1970 – 16 Feb 1971. The room is long gone; MoMA also holds his acrylic disc Untitled (1968).",
      how="A 10-minute walk up Sixth Avenue."),
 dict(k="pace", name="Pace Gallery", place="540 W 25th St, Chelsea",
      lat=40.7477, lon=-74.0055, mode="foot", status="gallery",
      work="Represents Robert Irwin and his estate",
      note="Irwin's New York gallery. Not a permanent installation — but the place his late light works surface most often in the city.",
      how="A 35-minute walk down Ninth Avenue, or the C/E to 23rd St."),
 dict(k="diachelsea", name="Dia Chelsea", place="537 W 22nd St, Chelsea",
      lat=40.7461, lon=-74.0059, mode="foot", status="historic",
      work="Excursus: Homage to the Square³ (1998–99), premiere",
      note="Irwin built Excursus here in the old Dia Center for the Arts — a maze of scrim chambers lit by fluorescent tubes. Dismantled in 1999 and rebuilt at Dia Beacon sixteen years later.",
      how="A 35-minute walk, or the C/E to 23rd St."),
 dict(k="whitney", name="Whitney Museum of American Art", place="99 Gansevoort St, Meatpacking",
      lat=40.7396, lon=-74.0089, mode="subway", status="collection",
      work="Scrim veil—Black rectangle—Natural light (1977)",
      note="The Whitney owns it outright — a gift of the artist, accession 77.45: a 114-foot scrim bisecting a gallery, with a black line at eye level. Made for the fourth floor of the old Breuer building, not this one.",
      how="A/C/E to 14th St, then five blocks west."),
 dict(k="breuer", name="The Breuer Building", place="945 Madison Ave, Upper East Side",
      lat=40.7735, lon=-73.9639, mode="subway", status="historic",
      work="Scrim veil—Black rectangle—Natural light — original site",
      note="Irwin made the scrim veil for this floor, under Breuer's trapezoidal window. It was reinstalled here in 2013, the last time the work stood in the room it was measured to.",
      how="6 to 77th St."),
 dict(k="met", name="The Metropolitan Museum of Art", place="1000 Fifth Ave",
      lat=40.7794, lon=-73.9632, mode="subway", status="collection",
      work="So. Cal",
      note="A gift of Louise and Leonard Riggio. In the collection; on view only sometimes.",
      how="4/5/6 to 86th St."),
 dict(k="gugg", name="Solomon R. Guggenheim Museum", place="1071 Fifth Ave",
      lat=40.7830, lon=-73.9590, mode="subway", status="collection",
      work="Works from the Panza Collection (gifted 1992)",
      note="Part of the Panza gift; some of the Guggenheim's Irwin holdings sit on permanent loan at Villa Panza in Italy. Check before you go.",
      how="4/5/6 to 86th St."),
 dict(k="beacon", name="Dia Beacon", place="3 Beekman St, Beacon, NY",
      lat=41.5045, lon=-73.9835, mode="metronorth", status="installed",
      work="Excursus: Homage to the Square³ (1998–99, reinstalled 2015) — and the building itself",
      note="The one unmissable Irwin in range. He drew the master plan for the whole museum and its grounds, and Excursus returned to public view here in 2015 after fifteen years in storage. Months into the install he wrapped every fluorescent tube in colored gel.",
      how="Metro-North Hudson Line from Grand Central to Beacon — about 80 minutes — then a 10-minute walk."),
 dict(k="yale", name="Yale University Art Gallery", place="1111 Chapel St, New Haven, CT",
      lat=41.3083, lon=-72.9313, mode="amtrak", status="collection",
      work="A dot painting (1963–65) and an acrylic disc (1969)",
      note="Two acquisitions that bracket his turn away from painting, hung in the Levin Study Gallery. Admission is free.",
      how="Amtrak or Metro-North New Haven Line to Union Station, then a 15-minute walk."),
 dict(k="hirshhorn", name="Hirshhorn Museum and Sculpture Garden", place="Independence Ave SW, Washington, DC",
      lat=38.8883, lon=-77.0230, mode="amtrak", status="collection",
      work="Untitled (1969), acrylic on shaped acrylic, 53¼ in. diameter",
      note="Bought through the Hirshhorn Purchase Fund in 1986. The Hirshhorn gave Irwin his big American retrospective, All the Rules Will Change, in 2016.",
      how="Amtrak to Union Station, then Metro to L'Enfant Plaza. Free admission."),
 dict(k="wellesley", name="Wellesley College", place="Lake Waban, Wellesley, MA",
      lat=42.2936, lon=-71.3064, mode="car", status="installed",
      work="Untitled (Filigreed Steel Line for Wellesley College), 1980",
      note="His first permanent installation anywhere in the United States: a 120-foot steel band, never more than two feet tall, cut with leaf patterns and planted into the slope above Lake Waban. Outdoors, free, always there.",
      how="Drive, or Amtrak to Boston and the MBTA Framingham/Worcester line to Wellesley. Walk toward Clapp Library."),
 dict(k="harvard", name="Harvard Art Museums", place="32 Quincy St, Cambridge, MA",
      lat=42.3742, lon=-71.1145, mode="car", status="historic",
      work="Full Room Skylight—Scrim V—Fogg Museum (1972)",
      note="A room-sized scrim under the Fogg's skylight, one of the first commissions after he closed his studio for good. Not extant.",
      how="Drive, or Amtrak to Boston and the Red Line to Harvard."),
 dict(k="buffalo", name="Buffalo AKG Art Museum", place="1285 Elmwood Ave, Buffalo, NY",
      lat=42.9333, lon=-78.8760, mode="plane", status="collection",
      work="Untitled — a painted aluminum disc",
      note="Lit to Irwin's specification, the disc throws a ring of overlapping shadows that read as solidly present as the object. The far edge of the 300-mile circle.",
      how="An hour's flight to Buffalo Niagara, or roughly seven hours by car or Amtrak's Empire Service."),
]

for s in S:
    s["mi"] = round(gc(ORIGIN, (s["lat"], s["lon"])), 1)
    x, y = proj(s["lon"], s["lat"]); s["x"] = round(x, 1); s["y"] = round(y, 1)
    ix, iy = iproj(s["lon"], s["lat"]); s["ix"] = round(ix, 1); s["iy"] = round(iy, 1)
    s["inInset"] = I_LON[0] < s["lon"] < I_LON[1] and I_LAT[0] < s["lat"] < I_LAT[1]

ox, oy = proj(ORIGIN[1], ORIGIN[0]); iox, ioy = iproj(ORIGIN[1], ORIGIN[0])
json.dump({"sites": S,
           "origin": {"x": round(ox,1), "y": round(oy,1), "ix": round(iox,1), "iy": round(ioy,1),
                      "lat": ORIGIN[0], "lon": ORIGIN[1]},
           "inset": {"w": I_W, "h": I_H, "land": inset_land}},
          open("sites.json","w"), separators=(",",":"))

print("inset", I_W, "x", I_H, "| land parts:", len(inset_land))
for s in S: print(f"  {s['mi']:6.1f} mi  {s['mode']:11s} {s['status']:10s} {s['name']}")
import os; print("sites.json", os.path.getsize("sites.json")//1024, "KB")
