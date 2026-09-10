# Leaving Los Angeles

A drive-time choropleth of California from 1st & Main, downtown LA. Every cell
is colored by how long it takes to drive there, quantized to 30-minute bands on
a blue → red gradient interpolated in OKLab. The three boundaries you cross on
the way out are drawn on top: City of Los Angeles, Los Angeles County, and the
California state line, with the fastest crossing of each called out.

Open `index.html`. It is fully self-contained (d3 and all data are inlined).

## Two sources of drive times

**Highway model (default, offline).** `network.py` is a hand-coded graph of
California's interstates, US routes and state highways, with average speeds by
class (rural freeway 68 mph, metro freeway 50, two-lane highway 52, mountain
pass 38). `build.py` densifies it to ~3 km segments, runs Dijkstra from downtown,
and gives each grid cell the nearest road's time plus a 30 mph straight-line hop.
Grid cells are 0.1° statewide and 0.025° inside the LA County bounding box.

**Live OSRM (one click, needs internet).** The page's *Load live OSRM times*
button asks the public `router.project-osrm.org` table service for real routed
durations to every cell center and every candidate border crossing, then
re-renders and caches the result in `localStorage`. *Save JSON* writes
`osrm_times.json`; drop it in `data/` and rerun `build.py` to bake the routed
times into `index.html`.

## Boundaries

- California and Los Angeles County: US Census cartographic boundaries via
  [us-atlas](https://github.com/topojson/us-atlas) (`data/*.geojson`).
- City of Los Angeles: `data/la_city_approx.geojson` is a hand-traced
  approximation (with holes for Beverly Hills/West Hollywood, Culver City and
  San Fernando). For exact limits download the *City Boundary* GeoJSON from
  [LA GeoHub](https://geohub.lacity.org/) as `data/la_city.geojson` and rebuild;
  the page drops its "(approx.)" tag automatically.

## Rebuild

```sh
pip install numpy scipy shapely
python3 build.py        # -> index.html
```

`template.html` is the page; `build.py` inlines `vendor/d3.min.js`, the data
payload and the GeoJSON into it.
