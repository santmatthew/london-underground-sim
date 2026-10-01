extends Node
func run():
	var ok := true
	for c in [[Vector2i(1280, 720), 1.0], [Vector2i(1920, 1080), 1.0], [Vector2i(2560, 1440), 0.0], [Vector2i(3840, 2160), 0.0]]:
		var sc := Game.auto_scale(c[0])
		var px: float = float((c[0] as Vector2i).x * (c[0] as Vector2i).y) * sc * sc
		print("auto_scale %s -> %.2f  (%.2f MP internal)" % [str(c[0]), sc, px / 1e6])
		if c[1] == 1.0 and sc != 1.0: ok = false
		if sc < 0.5 or sc > 1.0 or px > 3.0e6 and sc > 0.5: ok = false
	print("OK" if ok else "FAILED")
