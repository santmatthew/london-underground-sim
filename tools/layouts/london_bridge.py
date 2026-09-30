#!/usr/bin/env python3
"""London Bridge (940GZZLULNB) from TfL station layout diagram N135-02 (topology; dimensions estimated).
Main ticket hall (street names as printed on the diagram: Duke Street Hill, Joiner Street, London Bridge Street, Borough High Street) ->
escalators to the Northern line platforms 1 & 2 (24.1 m) -> the Jubilee/Northern interchange -> Jubilee platforms 3 & 4 (27.3 m)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLULNB", "London Bridge, from TfL layout diagram N135-02 (topology; dimensions estimated): main ticket hall, Northern 24.1 m, Jubilee 27.3 m",
     halls=[
         {"id": "hall_main", "x0": -16, "x1": 16, "gates": 14, "doors": [{"name": "Duke Street Hill"}, {"name": "Joiner Street"}, {"name": "London Bridge Street"}, {"name": "Borough High Street"}]},
     ],
     landings=[
         {"id": "conc_n", "depth": 24.1, "w": 40, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1, 1]}]},
         {"id": "conc_j", "depth": 27.3, "w": 36, "d": 14, "parents": [{"from": "conc_n", "lanes": [1, -1], "stairs": True}]},
     ],
     modules=[
         {"attach": "conc_n", "group": "northern", "faces": [["northern:Northbound", 0], ["northern:Southbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_j", "group": "jubilee", "faces": [["jubilee:Eastbound", 0], ["jubilee:Westbound", 0]], "lane": 0, "corr": 12},
     ])
