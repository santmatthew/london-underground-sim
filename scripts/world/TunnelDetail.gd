class_name TunnelDetail
extends RefCounted
## What the bore between stations carries on its dark lining: long runs of cable on trays along both walls, brackets, junction boxes, conduit drops, the odd refuge niche, and a lamp
## only here and there. Used by PlatformModule for the running tunnel beyond each platform end and by TunnelRun for the scenery that scrolls past while riding, so both look the same.
## Face-A coordinates (z positive toward the track-side wall at `zfar`; the platform-side wall of the running tunnel at `zwall`), mirrored by `s`; y = 0 is platform level.

const LAMP_Y := 2.45
const CELL := 3.0                 # clutter is laid in cells of this length (brackets, boxes, drops)

## rows of the track-side wall: [y, cables]  (a tray with `cables` cables on it)
const ROWS_TRACK := [[0.35, 3], [0.88, 4], [1.42, 3], [1.98, 4]]
## rows of the far wall
const ROWS_FAR := [[0.95, 3], [1.55, 4], [2.1, 3]]


static func _h(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663)
	x = (x ^ (x >> 13)) * 1274126177
	return (x ^ (x >> 16)) & 0x7fffffff


static func _f(a: int, b: int) -> float:
	return float(_h(a, b) % 10000) / 10000.0


## Adds the detail of the stretch xa..xb. opts: seed (int), lamps (Array of x: where a lamp hangs on the track-side wall), near (Vector2: x range with the full clutter; the rest only has the runs and the
## lamps), lamp_lights (Array: filled with the Vector3 positions of the lamps, for the caller's real lights).
static func add(kit: MeshKit, s: float, xa: float, xb: float, zwall: float, zfar: float, opts: Dictionary = {}) -> void:
	var seed: int = int(opts.get("seed", 1))
	var near: Vector2 = opts.get("near", Vector2(xa, xb))
	var len := xb - xa
	var xc := (xa + xb) * 0.5
	var fy := PlatformModule.BED_Y
	# the runs: a tray and cables, the whole stretch (one box each)
	for wall in [0, 1]:
		var rows: Array = ROWS_TRACK if wall == 0 else ROWS_FAR
		var zw: float = zfar if wall == 0 else zwall
		var into: float = -1.0 if wall == 0 else 1.0          # into the tunnel from that wall
		for ri in rows.size():
			var y: float = rows[ri][0]
			var n: int = rows[ri][1]
			# (the tray stands against the wall: its wall-side face is left out. On the far wall that face lies in the plane of the spine's wall, which faces the other way and would z-fight with it)
			kit.box("metal", Vector3(xc, y, s * (zw + into * 0.15)), Vector3(len, 0.045, 0.30), fy, false, int(s) * (1 if wall == 0 else -1))
			var zc0 := zw + into * 0.15 - 0.10
			for c in n:
				# (each cable has its own height, and they are spaced wider than they are thick: two tops at the same height that overlap would flicker)
				var th := 0.040 + 0.006 * c + 0.012 * _f(seed + wall * 7 + ri, c)
				var mat: String = ["cable_black", "cable_black", "cable_grey", "cable_black", "cable_black", "cable_grey", "cable_black", "cable_red"][_h(seed + wall * 11 + ri, c) % 8]
				kit.box(mat, Vector3(xc, y + 0.025 + th * 0.5, s * (zc0 + c * 0.07)), Vector3(len, th, th), fy)
	# a heavy power cable high on the track-side wall
	kit.box("cable_black", Vector3(xc, 2.65, s * (zfar - 0.12)), Vector3(len, 0.13, 0.13), fy)
	kit.box("cable_black", Vector3(xc, 2.82, s * (zfar - 0.22)), Vector3(len, 0.10, 0.10), fy)
	# the clutter, cell by cell (absolute cells, so neighbouring stretches agree)
	var c0 := int(floor(maxf(xa, near.x) / CELL))
	var c1 := int(floor(minf(xb, near.y) / CELL))
	for ci in range(c0, c1 + 1):
		var x: float = (float(ci) + 0.5) * CELL
		if x < xa + 0.2 or x > xb - 0.2:
			continue
		# brackets holding the trays: a post across the rows of each wall
		kit.box("metal", Vector3(x, 1.2, s * (zfar - 0.03)), Vector3(0.05, 2.0, 0.05), fy)
		kit.box("metal", Vector3(x, 1.5, s * (zwall + 0.03)), Vector3(0.05, 1.8, 0.05), fy)
		var r := _f(seed, ci)
		if r < 0.16:
			# a junction box on the track-side wall with a conduit up to the high cables
			kit.box("steel", Vector3(x + 0.6, 1.15, s * (zfar - 0.45)), Vector3(0.55, 0.45, 0.22), fy)
			kit.box("cable_black", Vector3(x + 0.6, 1.9, s * (zfar - 0.45)), Vector3(0.05, 1.3, 0.05), fy)
		elif r < 0.26:
			# a refuge niche in the far wall
			kit.box("black", Vector3(x, 0.85, s * (zwall + 0.02)), Vector3(1.4, 1.7, 0.04), fy, false, -int(s))
		elif r < 0.36:
			# a cable drop from the high runs to the floor, in a steel cover
			kit.box("steel", Vector3(x, 1.3, s * (zfar - 0.33)), Vector3(0.12, 2.6, 0.10), fy)
		elif r < 0.44:
			# a signalling cabinet at the track side of the far wall
			kit.box("steel", Vector3(x, 0.6, s * (zwall + 0.35)), Vector3(0.9, 1.2, 0.5), fy)
			kit.box("cable_black", Vector3(x, 1.4, s * (zwall + 0.35)), Vector3(0.08, 0.5, 0.08), fy)
		elif r < 0.5:
			# a yellow and black tunnel marker plate on the track-side wall
			kit.box("yellow_paint", Vector3(x, 1.65, s * (zfar - 0.02)), Vector3(0.45, 0.28, 0.02), fy)
			kit.box("black", Vector3(x, 1.65, s * (zfar - 0.035)), Vector3(0.36, 0.05, 0.01), fy)
	# lamps: a bulkhead on the track-side wall (a steel body and a bright diffuser)
	var lamp_pos: Array = opts.get("lamp_lights", [])
	for lx: float in opts.get("lamps", []):
		if lx < xa + 0.3 or lx > xb - 0.3:
			continue
		kit.box("steel", Vector3(lx, LAMP_Y, s * (zfar - 0.1)), Vector3(0.62, 0.2, 0.16), fy)
		kit.box("light_emissive", Vector3(lx, LAMP_Y, s * (zfar - 0.2)), Vector3(0.5, 0.12, 0.04), fy)
		lamp_pos.append(Vector3(lx, LAMP_Y - 0.1, s * (zfar - 0.7)))
