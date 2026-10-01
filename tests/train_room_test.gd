extends Node3D
## Steps the timetable and reports any visible train whose body overlaps a room (hall, landing, passage) of its own station.
## args: --stations="A|B|C" (default: a sample)  --from=7.0 --to=8.0 (hours)  --step=6 (seconds)
func run():
	Timetable.build(1)
	add_child(Env.make(0))
	var names := ["Acton Town", "Baker Street", "Oxford Circus", "Bank", "King's Cross St. Pancras", "Waterloo", "Cockfosters", "Stratford", "Paddington", "Victoria", "Heathrow Terminal 5", "Upminster"]
	var h0 := 7.0
	var h1 := 8.0
	var step := 6.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stations="): names = Array(a.substr(11).split("|"))
		if a.begins_with("--from="): h0 = float(a.substr(7))
		if a.begins_with("--to="): h1 = float(a.substr(5))
		if a.begins_with("--step="): step = float(a.substr(7))
	var grand := 0
	for nm in names:
		if not Net.name_to_idx.has(nm):
			continue
		var plan := StationPlan.for_station(Net.name_to_idx[nm])
		var st := Station.new()
		add_child(st)
		st.build(plan)
		Clock.running = false
		Clock.set_time(h0 * 3600.0)
		st.trains.setup(st, null)
		var hits := {}
		var seen := 0
		var t := h0 * 3600.0
		while t < h1 * 3600.0:
			Clock.set_time(t)
			st.trains._process(0.5)
			for tr in st.find_children("*", "Train", true, false):
				var train := tr as Train
				if not train.visible:
					continue
				seen += 1
				var last := train.cars.size() - 1
				for ci in train.cars.size():
					var car := train.cars[ci] as Node3D
					if not car.visible:
						continue
					var c := st.global_transform.affine_inverse() * car.global_position
					var half_len: float = float(Train.CAR_LEN[train.kind + ("_cab" if (ci == 0 or ci == last) else "_mid")]) * 0.5
					for rm in plan.rooms:
						var r: Array = rm["rect"]
						var ry: float = rm["y"]
						var rh: float = rm["h"]
						var ox := minf(c.x + half_len, r[1]) - maxf(c.x - half_len, r[0])
						var oz := minf(c.z + 1.4, r[3]) - maxf(c.z - 1.4, r[2])
						var oy := minf(c.y + 3.3, ry + rh) - maxf(c.y - 0.3, ry)
						if ox > 0.5 and oz > 0.5 and oy > 0.5:
							var key := "%s run %s car %d" % [rm["name"], str(train.run), ci]
							if not hits.has(key):
								hits[key] = "t=%s car %d x %.1f..%.1f z %.1f y %.1f overlaps %s by %.1f x %.1f x %.1f m" % [Clock.fmt(t, true), ci, c.x - half_len, c.x + half_len, c.z, c.y, rm["name"], ox, oz, oy]
			t += step
		print("%-26s %5d visible-train samples, %d overlaps with rooms" % [nm, seen, hits.size()])
		for k in hits:
			print("   ", hits[k])
		grand += hits.size()
		st.queue_free()
		await get_tree().process_frame
	print("TOTAL overlaps: ", grand)
