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
from searoute.data.marnet_dict import node_list, edge_list
from catalogue_routes import canonical_network, canonical_passages, canonical_canal_edges

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
# Active-world minutes: shelf lives shortened 10x alongside playtest voyage pacing.
# Ordinary biological life; quarter-speed refrigeration extends viable lifetime.
# Fruit is tuned against bananas, while meat and seafood need refrigeration.
life_minutes={'Fruit':60,'Seafood':1,'Meat':1.5}
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
   'volume_l':volume,'hold':'liquid' if name in liquid else 'reefer' if name in life_minutes else 'dry',
   'shelf_ms':int(life_minutes.get(name,0)*60000),
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
network = canonical_network(node_list, edge_list)
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
   route=searoute.searoute(locations[origin],locations[dest],units='naut',return_passages=True,M=network)
   coords=route['geometry']['coordinates']
   # Close local port connections to the network with explicitly displayed harbor legs.
   approach=distance(locations[origin],coords[0])+distance(coords[-1],locations[dest])
   coords=[locations[origin]]+coords+[locations[dest]]
   routes[key]={'nautical_miles':max(1,round(route['properties']['length']+approach)),
    'coordinates':coords,'passages':canonical_passages(route['properties'].get('traversed_passages',[]))}
canal_edges = canonical_canal_edges(edge_list)
# NPC factory recipes are authoritative here, alongside the cargo tuning above.
manufacturing = {
 'agricultural_machinery': {'inputs': {'iron_ore': 10, 'refined_fuel': 2}, 'local_cost_cents': 80000},
 'appliances': {'inputs': {'iron_ore': 2, 'recovered_plastics': 2}, 'local_cost_cents': 8000},
 'construction_equipment': {'inputs': {'iron_ore': 15, 'refined_fuel': 3}, 'local_cost_cents': 120000},
 'designer_clothing': {'inputs': {'everyday_clothing': 1}, 'local_cost_cents': 20000},
 'electronics': {'inputs': {'aluminium_scrap': 1, 'recovered_plastics': 2}, 'local_cost_cents': 20000},
 'everyday_clothing': {'inputs': {'recovered_plastics': 2}, 'local_cost_cents': 6000},
 'jewelry': {'inputs': {'copper_scrap': 1}, 'local_cost_cents': 50000},
 'refined_fuel': {'inputs': {'crude_oil': 1}, 'local_cost_cents': 6500},
 'turbines': {'inputs': {'copper_scrap': 1, 'iron_ore': 20}, 'local_cost_cents': 200000},
 'vegetable_oil': {'inputs': {'grain': 2}, 'local_cost_cents': 9000},
 'whisky': {'inputs': {'grain': 3}, 'local_cost_cents': 15000},
}
handling={'speed_ms_per_lot':{'slow':500,'med':350,'fast':250},'cargo_bps':{'Perishables':12500,'Scrap':15000,'liquid':7500},'minimum_ms':1000}
weather={'period_ms':1800000,'duration_ms':60000,'chance_bps':1000,'first_slot':1,'seed':1729,'stagger':True}
def piracy_kind(mark, hold_ms, charge_bps, storm_suppressed):
    return {'mark':mark,'hold_ms':hold_ms,'charge_bps':charge_bps,'storm_suppressed':storm_suppressed}
FLAG='\U0001F3F4‍☠️'
piracy={'seed':1777,'first_slot':1,
 'campaign':{'period_ms':43200000,'duration_ms':10800000,'warning_ms':1800000,'multiplier':4},
 'kinds':{'piracy':piracy_kind(FLAG,600000,400,True),'fleet_piracy':piracy_kind(FLAG,480000,300,True),
          'boarding':piracy_kind(FLAG,120000,50,True),'militia':piracy_kind('\U0001F4A5',300000,200,False)},
 'zones':{
  'red_sea':{'name':'Red Sea','kind':'militia','chance_bps':300,'campaign_bps':4000,'guard_pct':25,
   'campaign_names':['Bab-el-Mandeb blockade','Red Sea strike wave'],'label':[38.5,20.0],
   'polygon':[[32.2,29.9],[33.0,27.0],[35.0,23.5],[37.5,19.0],[40.0,15.0],[42.6,12.3],[43.45,12.4],[43.4,13.3],[41.5,16.8],[39.0,21.5],[36.5,25.5],[34.9,28.2],[32.7,30.2]]},
  'gulf_of_aden':{'name':'Gulf of Aden','kind':'piracy','chance_bps':400,'campaign_bps':2500,'guard_pct':90,
   'campaign_names':['Somali Basin raids','Gulf of Aden hijackings'],'label':[52.0,11.0],
   'polygon':[[43.5,11.0],[43.5,13.1],[45.0,14.0],[49.0,15.2],[52.0,16.5],[56.0,18.0],[60.0,19.0],[60.0,8.0],[52.0,3.0],[47.0,2.0],[44.0,9.0]]},
  'malacca':{'name':'Malacca Strait','kind':'boarding','chance_bps':600,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Night boardings','Strait boarding spree'],'label':[99.0,4.0],
   'polygon':[[95.0,6.5],[98.5,6.5],[101.0,3.5],[103.2,1.6],[103.0,1.1],[100.5,1.8],[98.0,3.0],[95.0,5.0]]},
  'south_china_sea':{'name':'South China Sea','kind':'fleet_piracy','chance_bps':200,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Red Flag Fleet','Black Flag Fleet'],'label':[114.0,13.0],
   'polygon':[[109.0,6.0],[119.0,6.0],[119.0,20.0],[109.0,20.0]]},
  'caribbean':{'name':'Caribbean Sea','kind':'piracy','chance_bps':200,'campaign_bps':2500,'guard_pct':60,
   'campaign_names':['Brethren of the Coast','Windward raiders'],'label':[-75.0,15.0],
   'polygon':[[-88.0,10.5],[-60.0,10.5],[-60.0,22.0],[-88.0,22.0]]}}}
def piracy_inside(pt,ring):
    x,y=pt; inside=False
    for (x1,y1),(x2,y2) in zip(ring,ring[1:]+ring[:1]):
        if (y1>y)!=(y2>y) and x < x1+(y-y1)*(x2-x1)/(y2-y1): inside=not inside
    return inside
def piracy_cross(a,b,c,d):
    o=lambda p,q,r:(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    return o(a,b,c)*o(a,b,d)<0 and o(c,d,a)*o(c,d,b)<0
for zid,zone in piracy['zones'].items():
    ring=zone['polygon']
    for port,data in ports.items():
        assert not piracy_inside(data['coordinates'],ring), f'{port} lies inside piracy zone {zid}'
    assert piracy_inside(zone['label'],ring), f'{zid} label lies outside its polygon'
zone_items=list(piracy['zones'].items())
for i,(a,ra) in enumerate(zone_items):
    for b,rb in zone_items[i+1:]:
        ea=list(zip(ra['polygon'],ra['polygon'][1:]+ra['polygon'][:1]))
        eb=list(zip(rb['polygon'],rb['polygon'][1:]+rb['polygon'][:1]))
        assert not any(piracy_cross(p,q,r,s) for p,q in ea for r,s in eb), f'piracy zones {a} and {b} overlap'
        assert not any(piracy_inside(v,rb['polygon']) for v in ra['polygon']), f'piracy zones {a} and {b} overlap'
        assert not any(piracy_inside(v,ra['polygon']) for v in rb['polygon']), f'piracy zones {a} and {b} overlap'
result={'weather':weather,'piracy':piracy,'handling':handling,'refrigeration':{'aging_bps':2500},'manufacturing':manufacturing,'canal_edges':canal_edges,'version':1,'goods':goods,'ports':ports,'routes':routes,'clusters':namespace['CLUSTERS']}
(ROOT/'priv/game').mkdir(parents=True,exist_ok=True)
(ROOT/'priv/game/catalogue.json').write_text(json.dumps(result,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n')
print(f'Generated {len(goods)} goods, {len(ports)} ports, {len(routes)} directed sea routes')
