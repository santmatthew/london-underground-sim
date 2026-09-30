extends Node
func run():
	for n in ["ticket_machine_mfm", "ticket_machine_tvm", "tickets_sign", "assistance_booth", "crowd_barrier", "help_point", "help_point_pole", "poster_stand", "newspaper_stand", "defibrillator_cabinet", "cid_totem", "cid_wall_screen", "leaflet_rack", "planter", "clock", "gate_unit", "gate_wide"]:
		var fp := StationDressing.footprint(n)
		print("FP %-22s centre (%.2f, %.2f) half (%.2f, %.2f) height %.2f" % [n, fp["c"].x, fp["c"].y, fp["h"].x, fp["h"].y, fp["y"]])
