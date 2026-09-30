#!/usr/bin/env python3
"""Canary Wharf (940GZZLUCYF, Jubilee) from TfL station layout diagram J007-02 (topology; dimensions estimated).
Ticket hall / mezzanine with the three street entrances (West = Plaza, Fosterito, East) -> a wide battery of escalators (the diagram numbers
them 1-9) to the Jubilee platforms 23.0 m below street; the mezzanine level is folded into the ticket hall."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from make_layout import make

make("940GZZLUCYF", "Canary Wharf, from TfL layout diagram J007-02 (topology; dimensions estimated): ticket hall with 3 entrances, escalators to Jubilee 23.0 m",
     halls=[
         {"id": "hall_main", "x0": -18, "x1": 18, "gates": 18, "doors": [{"name": "West Entrance (Plaza)"}, {"name": "Fosterito Entrance"}, {"name": "East Entrance"}]},
     ],
     landings=[
         {"id": "conc_j", "depth": 23.0, "w": 44, "d": 16, "parents": [{"from": "hall_main", "lanes": [1, -1, 1, -1, 1]}]},
     ],
     modules=[
         {"attach": "conc_j", "group": "jubilee", "faces": [["jubilee:Eastbound", 0], ["jubilee:Westbound", 0]], "lane": 0, "corr": 12},
     ])
