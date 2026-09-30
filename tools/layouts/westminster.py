#!/usr/bin/env python3
"""Westminster (940GZZLUWSM) from TfL station layout diagram D101-02 (topology; dimensions estimated).
Ticket hall -> escalators to the District & Circle platforms 1 & 2 (shallow; ~7 m assumed, the diagram gives no figure) -> intermediate level ->
long escalator bank to the Jubilee platforms 3 & 4 (33.0 m)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUWSM", "Westminster, from TfL layout diagram D101-02 (topology; dimensions estimated): ticket hall, D&C platforms (~7 m), Jubilee platforms 33.0 m",
     halls=[
         {"id": "hall_main", "x0": -14, "x1": 14, "gates": 12, "doors": [{"ref": "1"}, {"ref": "2"}]},
     ],
     landings=[
         {"id": "conc_dc", "depth": 7.0, "w": 40, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1]}]},
         {"id": "conc_j", "depth": 33.0, "w": 40, "d": 16, "parents": [{"from": "conc_dc", "lanes": [1, -1, 1, -1]}]},
     ],
     modules=[
         {"attach": "conc_dc", "group": "ss", "faces": [["ss:Eastbound", 0], ["ss:Westbound", 0]], "lane": 0, "corr": 12},
         {"attach": "conc_j", "group": "jubilee", "faces": [["jubilee:Eastbound", 0], ["jubilee:Westbound", 0]], "lane": 0, "corr": 12},
     ])
