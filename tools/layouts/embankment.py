#!/usr/bin/env python3
"""Embankment (940GZZLUEMB) from TfL station layout diagram N113-02 (topology; dimensions estimated), three levels:
District & Circle platforms 5.5 m (stairs from the ticket halls), Northern 16.2 m (escalators 7-10), Bakerloo 21.0 m.
North and south ticket halls both drop to the District & Circle level; exit refs A and B come from OSM."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUEMB", "Embankment, from TfL layout diagram N113-02 (topology; dimensions estimated): two ticket halls, D&C 5.5 m, Northern 16.2 m, Bakerloo 21.0 m",
     halls=[
         {"id": "hall_main", "x0": -16, "x1": 16, "gates": 10, "doors": [{"ref": "A"}, {"name": "Villiers Street"}]},
         {"id": "hall_s", "x0": -44, "x1": -28, "gates": 6, "doors": [{"ref": "B"}]},
     ],
     landings=[
         {"id": "conc_dc", "depth": 5.5, "w": 60, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1], "stairs": True}, {"from": "hall_s", "lanes": [1, -1], "stairs": True}]},
         {"id": "conc_n", "depth": 16.2, "w": 40, "d": 16, "parents": [{"from": "conc_dc", "lanes": [1, -1, 1]}]},
         {"id": "conc_b", "depth": 21.0, "w": 36, "d": 14, "parents": [{"from": "conc_n", "lanes": [1, -1], "stairs": True}]},
     ],
     modules=[
         {"attach": "conc_dc", "group": "ss", "faces": [["ss:Eastbound", 0], ["ss:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_n", "group": "northern", "faces": [["northern:Northbound", 0], ["northern:Southbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_b", "group": "bakerloo", "faces": [["bakerloo:Northbound", 0], ["bakerloo:Southbound", 0]], "lane": 0, "corr": 12},
     ])
