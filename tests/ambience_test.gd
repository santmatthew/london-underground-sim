extends Node
## What a passenger hears follows what the track runs through: Ride.ambience() (open / box shares round the player's car, blended over a few cells so the portals fade) and the layers Sfx.set_zone mixes from it
## (outdoor bed up and tunnel rumble down in the open, a closer rumble in a cut-and-cover box).
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var r := Ride.new()
	var path := TrackPath.new()
	var ks := PackedFloat32Array()
	ks.resize(120)
	path._build(ks, 1200.0)
	path.plan_scenes([[0, 400.0], [1, 400.0], [2, 200.0], [4, 200.0]], false, 1, 0, 119)
	r.path = path
	r.train = Train.new()
	r.train.car_x = [0.0]
	r.ref_car = 0
	r.s_now = 100.0
	check(float(r.ambience()["open"]) > 0.99, "open land: fully outdoors (%.2f)" % float(r.ambience()["open"]))
	r.s_now = 400.0
	var at_portal := float(r.ambience()["open"])
	check(at_portal > 0.2 and at_portal < 0.8, "at the tunnel mouth the outdoors is half there (%.2f)" % at_portal)
	r.s_now = 600.0
	check(float(r.ambience()["open"]) < 0.01, "in the bore: none (%.2f)" % float(r.ambience()["open"]))
	r.s_now = 900.0
	var cut := float(r.ambience()["open"])
	check(cut > 0.6 and cut < 0.75, "in a cutting the banks muffle it (%.2f)" % cut)
	r.s_now = 1100.0
	check(float(r.ambience()["open"]) > 0.99, "on a viaduct: fully outdoors")
	# a box tunnel
	path.plan_scenes([[1, 1200.0]], true, 1, 0, 119)
	r.s_now = 600.0
	check(float(r.ambience()["box"]) > 0.99 and float(r.ambience()["open"]) < 0.01, "a sub-surface line's tunnel is a box")
	# the mix
	Sfx.set_zone("train_run", 0.5, 15.0, 0.0, 0.0)
	var bore_db: float = Sfx._layers["tunnel"]["target"]
	var base_off: bool = String(Sfx._layers["base"]["key"]) == ""
	Sfx.set_zone("train_run", 0.5, 15.0, 1.0, 0.0)
	var open_db: float = Sfx._layers["tunnel"]["target"]
	var open_base: String = Sfx._layers["base"]["key"]
	Sfx.set_zone("train_run", 0.5, 15.0, 0.0, 1.0)
	var box_db: float = Sfx._layers["tunnel"]["target"]
	check(base_off, "no outdoor bed in the bore")
	check(open_base.begins_with("outdoor_"), "the outdoor bed in the open (%s)" % open_base)
	check(open_db < bore_db - 8.0, "the rumble drops in the open (%.1f -> %.1f dB)" % [bore_db, open_db])
	check(box_db > bore_db, "a box tunnel's rumble is closer (%.1f vs %.1f dB)" % [box_db, bore_db])
	Sfx.silence()
	print("OK" if ok else "FAILED")
