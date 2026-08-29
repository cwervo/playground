# Robert Irwin Within 300 Miles

An interactive map of the thirteen places inside a 300-mile circle around Times
Square where you can still encounter Robert Irwin's work — a choropleth of the
282 counties in range, with routes to each site coloured by how you'd get there
(foot, MTA subway, Metro-North, LIRR, Amtrak, car, plane).

`index.html` is fully self-contained apart from the Google Fonts stylesheet: the
projected geometry is inlined, so there are no tile servers and no runtime fetches.

## Rebuilding

    cd build
    curl -o counties.geojson https://raw.githubusercontent.com/plotly/datasets/master/geojson-counties-fips.json
    curl -o states.geojson   https://raw.githubusercontent.com/PublicaMundi/MappingAPI/master/data/geojson/us-states.json
    python3 build_geo.py      # -> region.json  (counties, state outlines, distance rings)
    python3 build_sites.py    # -> sites.json   (the works, plus the Manhattan inset)
    # then splice head.html + body.html + app.js, substituting the two JSON blobs
    # for the __REGION__ / __SITES__ placeholders in app.js

`search6.mjs` is the palette search: it enumerates candidate hue sets in OKLCH and
scores them with the data-viz skill's colour-vision-deficiency validator, keeping
only sets that clear every gate on all pairs in both light and dark. The six route
hues in `head.html` are its best result — worst-case CVD separation ΔE 10.1,
worst-case normal-vision separation ΔE 15.7.

## Caveats

Distances are great-circle miles, not travel time; travel notes are typical trips,
not live schedules. Only Dia Beacon and Wellesley are permanently sited — the rest
are collection holdings whose display rotates, or historic sites where the work is
no longer extant.
