extends Node
## How long does PersonModel.create take the first time a character is used, and afterwards? (the crowd stutter of the frame-rate experiment)
func run():
	var n := PersonModel.count()
	var first: Array = []
	var again: Array = []
	for i in n:
		var t0 := Time.get_ticks_usec()
		var p := PersonModel.create(i, 1)
		add_child(p)
		first.append((Time.get_ticks_usec() - t0) / 1000.0)
	for i in n:
		var t0 := Time.get_ticks_usec()
		var p := PersonModel.create(i, 2)
		add_child(p)
		again.append((Time.get_ticks_usec() - t0) / 1000.0)
	var s1 := 0.0
	var s2 := 0.0
	for v in first: s1 += v
	for v in again: s2 += v
	print("characters: ", n)
	print("first use: total %.0f ms, mean %.1f ms, max %.1f ms" % [s1, s1 / n, first.max()])
	print("second use: total %.0f ms, mean %.1f ms, max %.1f ms" % [s2, s2 / n, again.max()])
	print("OK")
