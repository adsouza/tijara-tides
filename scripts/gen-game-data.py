#!/usr/bin/env python3
"""Generate runtime catalogue/sea routes. Requires searoute==1.6.0 in a venv.
The port matrix remains authoritative in gen-ports-roster.py. Tuning is provisional.
"""
import os
import sys

# Network construction uses hash-based collections; fix their order for route ties.
if os.environ.get("PYTHONHASHSEED") != "0":
 os.execve(sys.executable, [sys.executable, *sys.argv], {**os.environ, "PYTHONHASHSEED": "0"})

import math
import json
from pathlib import Path
import searoute

ROOT = Path(__file__).resolve().parent.parent
source = (ROOT / 'scripts/gen-ports-roster.py').read_text()
# Execute only definitions, before document rendering; do not rewrite other artifacts.
namespace = {'__file__': str(ROOT / 'scripts/gen-ports-roster.py')}
exec(compile(source.split('o = []')[0], 'port_definitions', 'exec'), namespace)
locations = {
 'Shanghai':[121.88,30.62], 'Singapore':[103.76,1.26], 'Shenzhen':[114.28,22.57],
 'Guangzhou':[113.68,22.65], 'Hong Kong':[114.12,22.31], 'Busan':[129.04,35.08],
 'Tokyo':[139.80,35.61], 'Ho Chi Minh City':[107.02,10.51], 'Jakarta':[106.89,-6.10],
 'Manila':[120.95,14.59], 'Colombo':[79.84,6.96], 'Mumbai':[72.95,18.95],
 'Dubai':[55.06,24.98], 'Abu Dhabi':[54.65,24.81], 'Rotterdam':[4.03,51.97],
 'Antwerp':[4.28,51.34], 'Hamburg':[9.95,53.53], 'Valencia':[-0.32,39.44],
 'Athens':[23.63,37.94], 'Tangier':[-5.49,35.89], 'New York City':[-74.13,40.67],
 'Los Angeles':[-118.25,33.73], 'Houston':[-95.02,29.61], 'Colón':[-79.88,9.36],
 'São Paulo':[-46.30,-23.97],
}
# cents/lot, kg/lot, litres/lot; ordinary dry cargo unless specified below.
tuning = {
 'Iron ore':[12000,1000,600], 'Grain':[20000,1000,1400], 'Lumber':[25000,500,1600],
 'Crude oil':[40000,1000,1200], 'Refined fuel':[65000,1000,1250], 'Vegetable oil':[90000,1000,1100],
 'Whisky':[150000,20,50], 'Jewelry':[500000,1,2], 'Designer clothing':[200000,20,100],
 'Turbines':[2000000,5000,12000], 'Construction equipment':[1200000,8000,20000],
 'Agricultural machinery':[800000,5000,18000], 'Electronics':[200000,100,1000],
 'Appliances':[80000,250,1800], 'Everyday clothing':[60000,150,1400], 'Spices':[300000,20,80],
 'Aluminium scrap':[100000,1000,2500], 'Copper scrap':[350000,1000,500],
 'Recovered plastics':[6000,200,2000], 'Fruit':[50000,1000,1600],
 'Seafood':[250000,1000,1400], 'Meat':[200000,1000,1400],
}
liquid={'Crude oil','Refined fuel','Vegetable oil'}
life={'Fruit':72,'Seafood':36,'Meat':48}
# Explicit IDs stay fixed when display labels change. Never derive saved IDs from labels.
CARGO_IDS = {'Agricultural machinery': 'agricultural_machinery', 'Appliances': 'appliances', 'Construction equipment': 'construction_equipment', 'Copper scrap': 'copper_scrap', 'Crude oil': 'crude_oil', 'Designer clothing': 'designer_clothing', 'Electronics': 'electronics', 'Everyday clothing': 'everyday_clothing', 'Fruit': 'fruit', 'Grain': 'grain', 'Iron ore': 'iron_ore', 'Jewelry': 'jewelry', 'Lumber': 'lumber', 'Meat': 'meat', 'Recovered plastics': 'recovered_plastics', 'Refined fuel': 'refined_fuel', 'Aluminium scrap': 'aluminium_scrap', 'Seafood': 'seafood', 'Spices': 'spices', 'Turbines': 'turbines', 'Vegetable oil': 'vegetable_oil', 'Whisky': 'whisky'}
assert len(set(CARGO_IDS.values())) == len(CARGO_IDS)
def cargo_id(name):
 return CARGO_IDS[name]
goods={}
for category, names in namespace['CATEGORIES']:
 for name in names:
  display_name=name
  good_id=cargo_id(name)
  price, weight, volume=tuning[name]
  goods[good_id]={'id':good_id,'name':display_name,'category':category,'reference_cents':price,'weight_kg':weight,
   'volume_l':volume,'hold':'liquid' if name in liquid else 'reefer' if name in life else 'dry',
   'shelf_ms':life.get(name,0)*3600000,
   'manual':category not in ['Luxury items','Industrial machinery']}
ports={}
for name in namespace['ORDER']:
 harbor,identity,tiers=namespace['PORTS'][name]
 ports[name]={'id':name,'harbor':harbor,'identity':identity,'coordinates':locations[name],
  'roles':dict(zip(map(cargo_id, namespace['GOODS']),namespace['M'][name])),
  'tiers':dict(zip(['berths','ordinary','reefer','liquid','speed','cost','size'],tiers))}
assert set(ports)==set(locations)
def distance(a,b):
 x1,y1,x2,y2=map(math.radians,[*a,*b])
 h=math.sin((y2-y1)/2)**2+math.cos(y1)*math.cos(y2)*math.sin((x2-x1)/2)**2
 return 3440.065*2*math.asin(math.sqrt(min(1,h)))
routes={}
for origin in ports:
 for dest in ports:
  if origin==dest: continue
  key=origin+'|'+dest
  reverse=dest+'|'+origin
  if reverse in routes:
   previous=routes[reverse]
   routes[key]={**previous,'coordinates':list(reversed(previous['coordinates']))}
  else:
   route=searoute.searoute(locations[origin],locations[dest],units='naut',return_passages=True)
   coords=route['geometry']['coordinates']
   # Close local port connections to the network with explicitly displayed harbor legs.
   approach=distance(locations[origin],coords[0])+distance(coords[-1],locations[dest])
   coords=[locations[origin]]+coords+[locations[dest]]
   routes[key]={'nautical_miles':max(1,round(route['properties']['length']+approach)),
    'coordinates':coords,'passages':route['properties'].get('traversed_passages',[])}
result={'version':1,'goods':goods,'ports':ports,'routes':routes,'clusters':namespace['CLUSTERS']}
(ROOT/'priv/game').mkdir(parents=True,exist_ok=True)
(ROOT/'priv/game/catalogue.json').write_text(json.dumps(result,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n')
print(f'Generated {len(goods)} goods, {len(ports)} ports, {len(routes)} directed sea routes')
