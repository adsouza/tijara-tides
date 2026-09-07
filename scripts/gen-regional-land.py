#!/usr/bin/env python3
"""Clip Natural Earth 1:10m land for regional maps (standard library only).

Usage: python3 scripts/gen-regional-land.py path/to/ne_10m_land.geojson
Source: https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_land.geojson
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Generous coverage beyond each region's projected viewport, including coastlines
# nearby. Clip instead of shipping the full high-resolution world to every client.
BOUNDS = {
    "Northern Frangistan": (-12, 43, 24, 62),
    "Pearl River Delta": (103, 16, 124, 29),
    "Strait of Hormuz": (45, 18, 65, 32),
}


def clip(ring, bounds):
    points = ring[:-1]
    for axis, edge, lower in [(0, bounds[0], True), (0, bounds[2], False),
                              (1, bounds[1], True), (1, bounds[3], False)]:
        result = []
        for a, b in zip(points[-1:] + points[:-1], points):
            inside_a = a[axis] >= edge if lower else a[axis] <= edge
            inside_b = b[axis] >= edge if lower else b[axis] <= edge
            if inside_a != inside_b:
                t = (edge - a[axis]) / (b[axis] - a[axis])
                result.append([a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])])
            if inside_b:
                result.append(b)
        points = result
    if len(points) < 3:
        return []
    points = [[round(x, 5), round(y, 5)] for x, y in points]
    return points + [points[0]]


source = json.loads(Path(sys.argv[1]).read_text())
rings = []
for feature in source['features']:
    geometry = feature['geometry']
    polygons = geometry['coordinates'] if geometry['type'] == 'MultiPolygon' else [geometry['coordinates']]
    rings.extend(polygon[0] for polygon in polygons)
result = {region: [clipped for ring in rings if (clipped := clip(ring, bounds))]
          for region, bounds in BOUNDS.items()}
(ROOT / 'priv/game/regional-land.json').write_text(json.dumps(result, separators=(',', ':')) + '\n')
print({region: sum(map(len, polygons)) for region, polygons in result.items()})
