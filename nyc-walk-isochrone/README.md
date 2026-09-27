# NYC walk reach: crow flies vs A*

A MapLibre GL JS demo. Drop a pin anywhere in NYC and compare:

- **Blue (`#1010ff`) trails**: straight lines to everywhere 30 minutes away as the crow flies (a circle, radius = pace × 30 min).
- **Orange trails**: A* walking routes over the real OpenStreetMap pedestrian network, to the farthest point reachable in 29 minutes in each of 72 directions. The faint orange mesh is every street/path segment reachable within 29 minutes.
- **Hover** anywhere to A* a single walk from the pin and see its crow-flies vs walking distance, time, and detour factor.

Sliders change both time budgets and walking pace (default 5 km/h). The pin is kept in the URL hash (`#lon,lat`) so views can be shared.

## Run

Needs a static server (ES modules don't load from `file://`):

```sh
cd nyc-walk-isochrone && python3 -m http.server 8000
# open http://localhost:8000
```

Data comes live from the Overpass API (walkable `highway=*` ways, minus motorways/trunks and `foot=no`/private access) and base tiles from OpenFreeMap; no API keys.

## Files

- `walkgraph.js`: DOM-free graph code: CSR graph from Overpass JSON, binary heap, A* (great-circle heuristic, so routes are optimal), budgeted Dijkstra for the isochrone (an isochrone has no single goal, so it's A* with h = 0), and a grid nearest-node index.
- `app.js`: map layers, Overpass fetch, and UI.
