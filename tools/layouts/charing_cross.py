#!/usr/bin/env python3
"""Charing Cross (940GZZLUCHX) from TfL station layout diagram N109-02 (topology; dimensions estimated).
Northern line ticket hall (+ subways) -> escalators to the Northern platforms 5 & 6 (19.5 m) -> interchange passage -> intermediate concourse ->
escalators to the Bakerloo platforms 3 & 4 (26.2 m; the diagram still labels them Jubilee line).
Street names are the areas the diagram's subways run to (it only letters the exits); OSM has no exit numbers here."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUCHX", "Charing Cross, from TfL layout diagram N109-02 (topology; dimensions estimated): Northern ticket hall, Northern platforms 19.5 m, Bakerloo platforms 26.2 m",
     halls=[
         {"id": "hall_main", "x0": -16, "x1": 16, "gates": 10, "doors": [{"name": "Strand"}, {"name": "Trafalgar Square"}, {"name": "Northumberland Avenue"}, {"name": "Charing Cross Station"}]},
     ],
     landings=[
         {"id": "conc_n", "depth": 19.5, "w": 40, "d": 18, "parents": [{"from": "hall_main", "lanes": [1, -1, 1]}]},
         {"id": "conc_b", "depth": 26.2, "w": 36, "d": 16, "parents": [{"from": "conc_n", "lanes": [1, -1, 1]}]},
     ],
     modules=[
         {"attach": "conc_n", "group": "northern", "faces": [["northern:Northbound", 0], ["northern:Southbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_b", "group": "bakerloo", "faces": [["bakerloo:Northbound", 0], ["bakerloo:Southbound", 0]], "lane": 0, "corr": 12},
     ])
