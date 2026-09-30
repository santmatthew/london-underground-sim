#!/usr/bin/env python3
"""Paddington (Circle / District / Bakerloo; 940GZZLUPAC) from TfL station layout diagram B071-02 (topology; dimensions estimated).
Ticket hall A (Praed Street) and ticket halls B (the Lawn, Paddington main line) / C (Bakerloo) -> District & Circle platforms 1 & 2 (5.2 m) ->
Bakerloo platforms 3 & 4 (9.7 m).  The TfL data has only the northbound Bakerloo platform."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUPAC", "Paddington (Circle/District/Bakerloo), from TfL layout diagram B071-02 (topology; dimensions estimated): halls A (Praed Street), B/C (Lawn, Bakerloo), D&C 5.2 m, Bakerloo 9.7 m",
     halls=[
         {"id": "hall_a", "x0": -44, "x1": -28, "gates": 8, "doors": [{"name": "Praed Street"}]},
         {"id": "hall_main", "x0": -16, "x1": 16, "gates": 12, "doors": [{"name": "Paddington Station (The Lawn)"}, {"name": "London Street"}]},
     ],
     landings=[
         {"id": "conc_dc", "depth": 5.2, "w": 60, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1, 1], "stairs": True}, {"from": "hall_a", "lanes": [1, -1], "stairs": True}]},
         {"id": "conc_b", "depth": 9.7, "w": 40, "d": 14, "parents": [{"from": "conc_dc", "lanes": [1, -1, 1], "stairs": True}]},
     ],
     modules=[
         {"attach": "conc_dc", "group": "ss", "faces": [["ss:Eastbound", 0], ["ss:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_b", "group": "bakerloo", "faces": [["bakerloo:Northbound", 0]], "lane": 0, "corr": 12},
     ])
