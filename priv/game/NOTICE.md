# Game map data

The sea-route geometries in `catalogue.json` are generated using
[searoute-py 1.6.0](https://github.com/genthalili/searoute-py), by Gent Halili,
under Apache-2.0; the license is retained in `licenses/`. They are visualization
routes, not maritime navigation instructions. Local harbor coordinates are
curated game anchors and the approach segments are approximate.

`land.json` contains exterior polygon rings from Natural Earth's public-domain
[1:110m land dataset](https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_land.geojson).
`regional-land.json` contains regional clips from the public-domain
[1:10m land dataset, v5.1.2](https://github.com/nvkelso/natural-earth-vector/blob/v5.1.2/geojson/ne_10m_land.geojson),
reproduced with `scripts/gen-regional-land.py`. Regional views use these more
detailed coastlines; the world overview retains the lightweight 1:110m data.
The coastlines are displayed on an Equal Earth projection. They are
not used as a precise collision or navigational chart.

Port identities, trade roles and cargo categories come from the approved Tijara
Tides roster. Numeric economic and ship parameters are provisional game tuning.

The Equal Earth forward equations follow the
[d3-geo reference implementation](https://github.com/d3/d3-geo/blob/main/src/projection/equalEarth.js).
Route legs crossing the antimeridian are split and interpolated to both map edges.
