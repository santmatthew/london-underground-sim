#!/usr/bin/env python3
"""Holborn (940GZZLUHBN) from TfL station layout diagram P055-02 (topology; dimensions estimated).
Ticket hall (exits A and B) -> escalators to the middle concourse and the Central line platforms 1 & 2 (27.4 m) -> escalators to the lower
concourse and the Piccadilly line platforms (33.8 m for platform 3; platforms 4 & 5 are deeper, 39.6 m, and are modelled at 33.8 m)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUHBN", "Holborn, from TfL layout diagram P055-02 (topology; dimensions estimated): ticket hall A/B, Central platforms 27.4 m, Piccadilly platforms 33.8 m",
     halls=[
         {"id": "hall_main", "x0": -14, "x1": 14, "gates": 12, "doors": [{"ref": "A"}, {"ref": "B"}]},
     ],
     landings=[
         {"id": "conc_c", "depth": 27.4, "w": 40, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1, 1]}]},
         {"id": "conc_p", "depth": 33.8, "w": 36, "d": 14, "parents": [{"from": "conc_c", "lanes": [1, -1, 1]}]},
     ],
     modules=[
         {"attach": "conc_c", "group": "central", "faces": [["central:Eastbound", 0], ["central:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_p", "group": "piccadilly", "faces": [["piccadilly:Northbound", 0], ["piccadilly:Southbound", 0]], "lane": 0, "corr": 12},
     ])
