extends Node
## How long does the first use of each train car model take (load from disk + instantiate), and the second?
func run():
	for key in Train.CAR_SCENES:
		var t0 := Time.get_ticks_usec()
		var sc := Train.scene_for(key)
		var t1 := Time.get_ticks_usec()
		var n := sc.instantiate()
		add_child(n)
		var t2 := Time.get_ticks_usec()
		var n2 := sc.instantiate()
		add_child(n2)
		var t3 := Time.get_ticks_usec()
		print("%-9s load %7.1f ms   first instance %6.1f ms   second instance %6.1f ms" % [key, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	print("OK")
