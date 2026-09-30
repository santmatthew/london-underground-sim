class_name StationDressing
extends RefCounted
## Places the dressing of a station (ticket-hall furniture, bays, kiosks, posters, maps, benches ...) from rules taken from real Tube stations
## (see build/refs_dress/*/SPEC.md, private reference). Everything is deterministic per station (seeded from the station id).
##
## Every floor-standing item goes through DressMap: it is refused if it would sit on a walking route, on the gateline band or on something
## already placed, so a passenger can always walk every route. Wall-mounted items take free stretches of wall (no openings, no signs).

const ROUTE_MARGIN := 0.85          # metres kept clear around every walking route (crowds spread about a metre either side)
const WALL_MARGIN := 0.5            # metres kept clear beside an opening

static var _fp_cache: Dictionary = {}     # prop name -> {c: Vector2 (local x, z of the footprint centre), h: Vector2 (half extents), y: float (height)}

var station: Station
var plan: StationPlan
var map: DressMap
var rng := RandomNumberGenerator.new()
var root: Node3D
var _wall_used: Dictionary = {}           # "room|side" -> Array of [t0, t1, y0, y1] already taken on that wall
var stats := {"placed": 0, "refused": 0}
var picker: PosterKit.Picker
var _kits: Dictionary = {}                # room name -> MeshKit collecting that room's framed posters


static func place(st: Station) -> void:
	var d := StationDressing.new()
	d.run(st)


func run(st: Station) -> void:
	station = st
	plan = st.plan
	rng.seed = plan.seed_value + 4242
	map = DressMap.build(st)
	picker = PosterKit.Picker.new(rng)
	root = Node3D.new()
	root.name = "Props"
	station.add_child(root)
	_note_signs()
	for gl in plan.gatelines:
		_hall(gl)
	for rm in plan.rooms:
		var nm: String = rm["name"]
		if nm.begins_with("landing") or nm.begins_with("corridor"):
			_room(rm)
	for mi in plan.modules.size():
		_platform(mi)
	for k in _kits:
		var mi := PosterKit.finish(_kits[k], root, "Posters_" + String(k))
		if mi != null:
			mi.visibility_range_end = 45.0
			mi.visibility_range_end_margin = 4.0
	StationSigns.cull(root, 55.0)
	for pm in station.modules:
		var ph: Node = pm.get_node_or_null("Props")
		if ph:
			StationSigns.cull(ph, 55.0)


# ---------------------------------------------------------------------------------------------------
# footprints and placement
# ---------------------------------------------------------------------------------------------------
## the footprint of a prop in its own frame, taken from its collision shapes (or, without any, its meshes)
static func footprint(name: String) -> Dictionary:
	if _fp_cache.has(name):
		return _fp_cache[name]
	var n := StationProps.inst(name)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for cs in n.find_children("*", "CollisionShape3D", true, false):
		var c := cs as CollisionShape3D
		var xf := _rel_xf(c, n)
		var pts := PackedVector3Array()
		if c.shape is ConvexPolygonShape3D:
			pts = (c.shape as ConvexPolygonShape3D).points
		elif c.shape is BoxShape3D:
			var b := (c.shape as BoxShape3D).size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						pts.append(Vector3(b.x * sx, b.y * sy, b.z * sz))
		for p in pts:
			var q := xf * p
			lo = lo.min(q)
			hi = hi.max(q)
			found = true
	if not found:
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var bb := _rel_xf(m, n) * m.get_aabb()
			lo = lo.min(bb.position)
			hi = hi.max(bb.end)
			found = true
	n.free()
	if not found:
		lo = Vector3(-0.3, 0, -0.3)
		hi = Vector3(0.3, 1.0, 0.3)
	var out := {"c": Vector2((lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5), "h": Vector2((hi.x - lo.x) * 0.5, (hi.z - lo.z) * 0.5), "y": hi.y}
	_fp_cache[name] = out
	return out


static func _rel_xf(n: Node3D, root_n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root_n:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## put a floor-standing prop at `pos` (floor point) with its front along `dir`, unless it would obstruct something. Returns null if refused.
func floor_prop(parent: Node3D, name: String, pos: Vector3, dir: Vector3, margin := ROUTE_MARGIN, frame_off := Vector3.ZERO) -> Node3D:
	var fp := footprint(name)
	var yaw := atan2(-dir.x, -dir.z)
	var c: Vector2 = fp["c"]
	var world_c := Vector3(pos.x, pos.y, pos.z) + Basis(Vector3.UP, yaw) * Vector3(c.x, 0, c.y)
	if not map.is_clear(world_c + frame_off, fp["h"], yaw, margin):
		stats["refused"] += 1
		return null
	var n := StationProps.put(parent, name, pos, dir)
	map.add_placed(world_c + frame_off, fp["h"], yaw)
	stats["placed"] += 1
	return n


# ---------------------------------------------------------------------------------------------------
# walls
# ---------------------------------------------------------------------------------------------------
## free stretches [a, b] along one wall of a room (x for N/S walls, z for W/E walls), minus openings (with margin) and what is already taken
func wall_free(rm: Dictionary, side: String, y0 := 0.0, y1 := 3.0, margin := WALL_MARGIN) -> Array:
	var r: Array = rm["rect"]
	var lo: float = r[0] if side in ["N", "S"] else r[2]
	var hi: float = r[1] if side in ["N", "S"] else r[3]
	if side in rm.get("open_ends", []):
		return []
	var cuts: Array = []
	for o in rm.get("openings", []):
		if o["side"] == side:
			cuts.append([float(o["c"]) - float(o["w"]) * 0.5 - margin, float(o["c"]) + float(o["w"]) * 0.5 + margin])
	for u in _wall_used.get(_wkey(rm, side), []):
		if u[3] > y0 and u[2] < y1:
			cuts.append([u[0] - 0.1, u[1] + 0.1])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	var cur := lo
	for c in cuts:
		if c[0] > cur:
			out.append([cur, minf(c[0], hi)])
		cur = maxf(cur, c[1])
	if cur < hi:
		out.append([cur, hi])
	return out.filter(func(iv): return iv[1] - iv[0] > 0.2)


func wall_take(rm: Dictionary, side: String, t0: float, t1: float, y0: float, y1: float) -> void:
	var k := _wkey(rm, side)
	if not _wall_used.has(k):
		_wall_used[k] = []
	_wall_used[k].append([t0, t1, y0, y1])


func _wkey(rm: Dictionary, side: String) -> String:
	return "%s|%s" % [rm["name"], side]


## a point on the wall at coordinate t (floor height y_floor) and the direction the wall faces into the room
static func wall_point(rm: Dictionary, side: String, t: float, y_floor: float, inset := 0.0) -> Array:
	var r: Array = rm["rect"]
	match side:
		"N":
			return [Vector3(t, y_floor, r[2] + inset), Vector3(0, 0, 1)]
		"S":
			return [Vector3(t, y_floor, r[3] - inset), Vector3(0, 0, -1)]
		"W":
			return [Vector3(r[0] + inset, y_floor, t), Vector3(1, 0, 0)]
		_:
			return [Vector3(r[1] - inset, y_floor, t), Vector3(-1, 0, 0)]


## walls already carrying a sign (roundel, "Way out", wall blades ...) are not free for posters or maps
func _note_signs() -> void:
	var sroot := station.get_node_or_null("Signs")
	if sroot == null:
		return
	var holders: Array = sroot.get_children()
	for pm in station.modules:
		for c in pm.get_children():
			if c is Node3D and not (c is MeshInstance3D) and c.name not in ["Collision", "EdgeGuard", "Lights", "Props", "Decals"] and not (c is Train):
				holders.append(c)
	for hd in holders:
		if not (hd is Node3D):
			continue
		var origin := _rel_xf(hd as Node3D, station).origin
		var pm_off := Vector3.ZERO
		# module children live in the module's frame: shift into the station frame
		var par := (hd as Node).get_parent()
		if par is PlatformModule:
			pm_off = (par as Node3D).position
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for mi in (hd as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var bb := _rel_xf(m, station) * m.get_aabb()
			lo = lo.min(bb.position + pm_off)
			hi = hi.max(bb.end + pm_off)
		if lo.x > hi.x:
			continue
		# which room wall is it hanging on (within 0.45 m of a wall of a room whose level it is on)?
		for rm in plan.rooms:
			var r: Array = rm["rect"]
			var y: float = rm["y"]
			if hi.y < y or lo.y > y + float(rm["h"]):
				continue
			if hi.x < r[0] - 0.5 or lo.x > r[1] + 0.5 or hi.z < r[2] - 0.5 or lo.z > r[3] + 0.5:
				continue
			if lo.z < r[2] + 0.45 and hi.z > r[2] - 0.5:
				wall_take(rm, "N", lo.x, hi.x, lo.y - y, hi.y - y)
			if hi.z > r[3] - 0.45 and lo.z < r[3] + 0.5:
				wall_take(rm, "S", lo.x, hi.x, lo.y - y, hi.y - y)
			if lo.x < r[0] + 0.45 and hi.x > r[0] - 0.5:
				wall_take(rm, "W", lo.z, hi.z, lo.y - y, hi.y - y)
			if hi.x > r[1] - 0.45 and lo.x < r[1] + 0.5:
				wall_take(rm, "E", lo.z, hi.z, lo.y - y, hi.y - y)


func kit_for(rm: Dictionary) -> MeshKit:
	var k: String = rm["name"]
	if not _kits.has(k):
		var kit := MeshKit.new()
		kit.seed_rng(plan.seed_value + k.hash())
		_kits[k] = kit
	return _kits[k]


## a framed poster of format `fmt` on a free stretch of `side`. Frame bottom at `bottom` m above the room floor (or its top at `top` when given).
## art: a Picker file, "@tubemap", or "" for a blank card. Returns false when the wall has no room for it.
func wall_frame(rm: Dictionary, side: String, fmt: String, near: float, art: String, bottom := 0.4, top := -1.0, frame := "silver") -> bool:
	var ov: Vector2 = PosterKit.FORMATS[fmt]["o"]
	var y0 := bottom if top < 0.0 else top - ov.y
	var t := wall_slot(rm, side, ov.x + 0.12, y0, y0 + ov.y, near)
	if is_nan(t):
		stats["refused"] += 1
		return false
	var wp := wall_point(rm, side, t, float(rm["y"]) + y0, 0.0)
	PosterKit.add(kit_for(rm), fmt, wp[0], wp[1], art, frame, float(rm["y"]))
	stats["placed"] += 1
	return true


## claim `width` metres of a wall for something mounted between heights y0..y1 (relative to the floor); returns the wall coordinate of its
## centre, or NAN when there is no room. `near` prefers the free spot closest to that coordinate; `from_end` measures spacing from the wall start.
func wall_slot(rm: Dictionary, side: String, width: float, y0: float, y1: float, near := NAN) -> float:
	var best := NAN
	var best_d := 1e9
	for iv in wall_free(rm, side, y0, y1):
		if iv[1] - iv[0] < width:
			continue
		var c: float = (iv[0] + iv[1]) * 0.5
		if not is_nan(near):
			c = clampf(near, iv[0] + width * 0.5, iv[1] - width * 0.5)
		var d: float = absf(c - near) if not is_nan(near) else absf(c)
		if d < best_d:
			best_d = d
			best = c
	if not is_nan(best):
		wall_take(rm, side, best - width * 0.5, best + width * 0.5, y0, y1)
	return best


## mount a wall prop of `width` on a free stretch of `side` near `near`; y is the height of its origin above the room floor
func wall_prop(rm: Dictionary, side: String, name: String, width: float, y_origin: float, y0: float, y1: float, near := NAN) -> Node3D:
	var t := wall_slot(rm, side, width, y0, y1, near)
	if is_nan(t):
		stats["refused"] += 1
		return null
	var wp := wall_point(rm, side, t, float(rm["y"]) + y_origin, 0.02)
	stats["placed"] += 1
	return StationProps.put(root, name, wp[0], wp[1])


# ---------------------------------------------------------------------------------------------------
# ticket halls
# ---------------------------------------------------------------------------------------------------
func _hall(gl: Dictionary) -> void:
	var r: Array = gl.get("rect", plan.hall["rect"])
	var hall_room := _room_for_rect(r)
	var h: float = StationPlan.HALL_H
	var gz: float = gl["z"]
	var imp := plan.imp
	var medium := imp >= 1.2
	# the gateline band (gates, fence, and the space a queue needs): nothing stands there
	map.add_placed(Vector3((r[0] + r[1]) * 0.5, 0, gz), Vector2((r[1] - r[0]) * 0.5 + 1.0, 2.2), 0.0)
	# the big things first: shops, then the ticket-machine bay
	if medium:
		_retail(hall_room, r, gz, imp)
	_ticket_machines(hall_room, r, gz, 2 if not medium else (3 if imp < 2.2 else 4))
	# floor furniture that lives by the walls: info totem, help point
	floor_prop(root, "info_totem", Vector3(r[1] - 5.0, 0, r[2] + 3.6), Vector3(0, 0, 1))
	floor_prop(root, "help_point", Vector3(r[0] + 0.3, 0, gz + 4.0), Vector3(1, 0, 0))
	# wall furniture on free wall: clock high on a paid-side wall, a fire cabinet
	wall_prop(hall_room, "E", "clock", 0.6, 3.0, 2.6, 3.4, gz + 2.5)
	wall_prop(hall_room, "E", "fire_cabinet", 0.6, 0.3, 0.3, 1.3, gz + 6.0)
	# cameras and speakers hang from the ceiling
	for k in 4:
		var cx: float = lerpf(r[0] + 3.0, r[1] - 3.0, k / 3.0)
		var cz: float = r[2] + 2.0 if k % 2 == 0 else r[3] - 2.0
		put_wall(root, "cctv_dome", Vector3(cx, h, cz), Vector3(0, 0, 1))
	for k in 3:
		put_wall(root, "pa_speaker", Vector3(lerpf(r[0] + 4.0, r[1] - 4.0, k / 2.0), h - 0.6, (r[2] + r[3]) * 0.5), Vector3(0, 0, 1))
	# TfL information: a Tube map (Quad Royal) beside the gateline on the unpaid side, a cluster of Double Royal frames (customer information)
	# next to the ticket machines; commercial 6-sheets on the paid-side walls, on whatever wall is still free
	for side in ["W", "E"]:
		if wall_frame(hall_room, side, "qr", gz - 4.0, "@tubemap", 0.0, 2.0):
			break
	for side in ["E", "W"]:
		var n_info := 0
		for k in 3:
			if wall_frame(hall_room, side, "dr", r[2] + 6.5 + k * 0.9, picker.pick("info"), 0.0, 2.0):
				n_info += 1
		if n_info > 0:
			break
	for side in ["W", "E"]:
		var z: float = gz + 3.5
		while z < r[3] - 4.0:
			if not wall_frame(hall_room, side, "6", z, picker.pick("portrait"), 0.4):
				break
			z += 6.0


func _room_for_rect(r: Array) -> Dictionary:
	for rm in plan.rooms:
		var rr: Array = rm["rect"]
		if absf(rr[0] - r[0]) < 0.01 and absf(rr[1] - r[1]) < 0.01 and absf(rr[2] - r[2]) < 0.01 and absf(rr[3] - r[3]) < 0.01:
			return rm
	return plan.rooms[0]


## a run of wall-bay ticket machines on the unpaid side (real halls: machines are set in wall bays, never free-standing)
func _ticket_machines(rm: Dictionary, r: Array, gz: float, n: int) -> void:
	var placed := 0
	for side in ["W", "E"]:
		var free: Array = wall_free(rm, side, 0.0, 2.2)
		for iv in free:
			var z0: float = maxf(iv[0], r[2] + 3.0)
			var z1: float = minf(iv[1], gz - 3.2)
			var z: float = z0 + 0.6
			while placed < n and z + 0.5 < z1:
				var wp := wall_point(rm, side, z, 0.0, 0.32)
				if floor_prop(root, "ticket_machine", wp[0], wp[1]) != null:
					placed += 1
					wall_take(rm, side, z - 0.55, z + 0.55, 0.0, 2.4)
					z += 1.05
				else:
					z += 0.5
		if placed >= n:
			return


## retail units against the side walls (real halls: shops stand against a wall by the gateline or the entrance, on the unpaid side; big
## concourses also have some on the paid side)
func _retail(rm: Dictionary, r: Array, gz: float, imp: float) -> void:
	var kinds: Array = ShopKit.KINDS.keys()
	var n_units := 1 if imp < 2.2 else (2 if imp < 3.0 else 3)
	var sizes: Array = [Vector2(4.0, 3.0), Vector2(2.4, 1.9), Vector2(5.5, 3.6)] if imp >= 2.2 else [Vector2(3.0, 2.4), Vector2(2.4, 1.9)]
	var zones: Array = [[r[2] + 3.0, gz - 2.6], [gz + 3.2, r[3] - 5.5]]     # unpaid zone first, then the paid concourse
	var placed := 0
	for zone in zones:
		for side in ["E", "W"]:
			if placed >= n_units:
				return
			for iv in wall_free(rm, side, 0.0, 3.0):
				var z0: float = maxf(iv[0], zone[0])
				var z1: float = minf(iv[1], zone[1])
				var z := z0
				while placed < n_units and z + 1.6 < z1:
					var sz: Vector2 = sizes[placed % sizes.size()]
					if z + sz.x > z1:
						sz = Vector2(2.4, 1.9)
						if z + sz.x > z1:
							break
					var kind: String = kinds[rng.randi() % kinds.size()]
					var wall_t := z + sz.x * 0.5
					var wp := wall_point(rm, side, wall_t, 0.0, 0.0)
					var shop := ShopKit.build(kind, sz.x, sz.y, rng.randi())
					# the unit's width runs along the wall: it is turned to face into the room
					if floor_node(root, shop, wp[0], wp[1], Vector2(sz.x * 0.5, sz.y * 0.5), Vector2(0, -sz.y * 0.5), 1.25):
						placed += 1
						wall_take(rm, side, wall_t - sz.x * 0.5, wall_t + sz.x * 0.5, 0.0, 3.0)
						z = wall_t + sz.x * 0.5 + 2.5
					else:
						shop.free()
						z += 0.6


## place a procedural node (origin on its wall/back edge, front facing -Z) if its footprint is clear; half/centre are in the node's own frame
func floor_node(parent: Node3D, n: Node3D, pos: Vector3, dir: Vector3, half: Vector2, centre: Vector2, margin := ROUTE_MARGIN) -> bool:
	var yaw := atan2(-dir.x, -dir.z)
	var world_c := pos + Basis(Vector3.UP, yaw) * Vector3(centre.x, 0, centre.y)
	if not map.is_clear(world_c, half, yaw, margin):
		stats["refused"] += 1
		return false
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	map.add_placed(world_c, half, yaw)
	stats["placed"] += 1
	return true


# ---------------------------------------------------------------------------------------------------
# platforms
# ---------------------------------------------------------------------------------------------------
func _platform(mi: int) -> void:
	var pm: PlatformModule = station.modules[mi]
	var m: Dictionary = plan.modules[mi]
	var spec: Dictionary = m["spec"]
	var L: float = spec["length"]
	var pw: float = spec["pw"]
	var ox: Array = spec["openings_x"]
	var zwall := PlatformModule.GAP * 0.5
	var zedge := zwall + pw
	var zfar := zedge + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
	var faces: Array = spec["faces"]
	var holder := Node3D.new()
	holder.name = "Props"
	pm.add_child(holder)
	var kit := MeshKit.new()
	kit.seed_rng(plan.seed_value + mi * 31)
	for fi in faces.size():
		var s := 1.0 if fi == 0 else -1.0
		_far_wall(kit, s, zfar, L)
		_platform_wall(kit, pm, s, zwall, L, ox)
		_platform_furniture(holder, pm, s, zwall, zedge, zfar, L, ox)
	var mi_node := PosterKit.finish(kit, holder, "Posters")
	if mi_node != null:
		mi_node.visibility_range_end = 60.0
		mi_node.visibility_range_end_margin = 6.0


## the wall across the track: a near-continuous run of posters from platform level up to the arch spring, broken by the white roundel plates
## (real deep-tube platforms show 80-100 % of the wall carrying paid sites at busy stations, under 20 % at suburban ones)
func _far_wall(kit: MeshKit, s: float, zfar: float, L: float) -> void:
	var seps: Array = StationSigns.far_wall_separators(L)
	var normal := Vector3(0, 0, -s)
	var coverage := 0.92 if plan.imp >= 2.0 else (0.6 if plan.imp >= 1.2 else 0.16)
	var y0 := 0.27
	for x in seps:
		PosterKit.add_plate(kit, Vector2(1.4, 2.03), Vector3(x, y0, s * zfar), normal)
	var cuts: Array = [-L * 0.5 + 0.7]
	for x in seps:
		cuts.append(x - 0.75)
		cuts.append(x + 0.75)
	cuts.append(L * 0.5 - 0.7)
	var prev := ""
	for gi in range(0, cuts.size(), 2):
		var x: float = cuts[gi]
		var x_end: float = cuts[gi + 1]
		while x_end - x > 1.0:
			var room := x_end - x
			var fmt := "6"
			var r := rng.randf()
			if room >= 3.1 and r < 0.6:
				fmt = "16"
			elif room >= 1.1 and r < 0.85:
				fmt = "6"
			elif room >= 1.05:
				fmt = "4"
			else:
				break
			var ov: Vector2 = PosterKit.FORMATS[fmt]["o"]
			if rng.randf() < coverage:
				var lib: String = PosterKit.FORMATS[fmt]["lib"]
				var art := picker.pick(lib, prev) if rng.randf() > 0.06 else ""
				prev = art
				PosterKit.add(kit, fmt, Vector3(x + ov.x * 0.5, y0, s * zfar), normal, art, "black" if fmt == "16" else "silver")
				stats["placed"] += 1
			x += ov.x + 0.04


## the wall behind the waiting passengers: TfL information beside each cross-passage (Tube map + Double Royal frames, top edge at 2.0 m)
## and a few adverts between openings; roundel spots are kept free
func _platform_wall(kit: MeshKit, pm: PlatformModule, s: float, zwall: float, L: float, ox: Array) -> void:
	var normal := Vector3(0, 0, s)
	var cuts: Array = []
	for o in ox:
		cuts.append([o - PlatformModule.OPEN_W * 0.5 - 0.5, o + PlatformModule.OPEN_W * 0.5 + 0.5])
	var seps: Array = StationSigns.far_wall_separators(L)
	if not pm.box:
		for k in seps.size():
			if k % 2 == 1:
				var xr: float = seps[k] + 1.5
				var near_open := false
				for o in ox:
					if absf(xr - o) < 4.0:
						near_open = true
				if not near_open:
					cuts.append([xr - 1.0, xr + 1.0])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var free: Array = []
	var cur := -L * 0.5 + 1.0
	for c in cuts:
		if c[0] > cur:
			free.append([cur, minf(c[0], L * 0.5 - 1.0)])
		cur = maxf(cur, c[1])
	if cur < L * 0.5 - 1.0:
		free.append([cur, L * 0.5 - 1.0])
	var ad_p := 0.25 if plan.imp >= 2.0 else 0.08
	for iv in free:
		var x: float = iv[0]
		var end: float = iv[1]
		# an information group at the start of each stretch that follows an opening
		if end - x >= 3.0 and not pm.box:
			var g := [["qr", "@tubemap"], ["dr", picker.pick("info")]]
			for it in g:
				var ov: Vector2 = PosterKit.FORMATS[it[0]]["o"]
				if x + ov.x > end:
					break
				PosterKit.add(kit, it[0], Vector3(x + ov.x * 0.5, 2.0 - ov.y, s * zwall), normal, it[1], "silver")
				x += ov.x + 0.06
				stats["placed"] += 1
		while end - x >= 1.1:
			var ov4: Vector2 = PosterKit.FORMATS["4"]["o"]
			if rng.randf() < ad_p:
				PosterKit.add(kit, "4", Vector3(x + ov4.x * 0.5, 0.45, s * zwall), normal, picker.pick("portrait"), "silver")
				stats["placed"] += 1
			x += ov4.x + 1.2 + rng.randf() * 2.5


func _platform_furniture(holder: Node3D, pm: PlatformModule, s: float, zwall: float, zedge: float, zfar: float, L: float, ox: Array) -> void:
	var off := pm.position
	# benches against the platform-side wall, away from the cross-passages
	var n_b := clampi(int(L / 34.0), 2, 4)
	for k in n_b:
		var x := -L * 0.5 + (k + 0.5) * L / n_b + rng.randf_range(-2.0, 2.0)
		if StationProps._near(x, ox, 4.0):
			x += 6.0
		floor_prop(holder, "bench_platform", Vector3(x, 0, s * (zwall + 0.30)), Vector3(0, 0, s), 0.5, off)
	# a bin by an exit end, help points at both ends
	floor_prop(holder, "bin", Vector3(-L * 0.5 + 12.0, 0, s * (zwall + 0.3)), Vector3(0, 0, s), 0.4, off)
	floor_prop(holder, "help_point", Vector3(-L * 0.5 + 3.0, 0, s * (zwall + 0.25)), Vector3(0, 0, s), 0.4, off)
	floor_prop(holder, "help_point", Vector3(L * 0.5 - 3.0, 0, s * (zwall + 0.25)), Vector3(0, 0, s), 0.4, off)
	for ex in [-L * 0.5 + 1.0, L * 0.5 - 1.0]:
		StationProps.put(holder, "platform_edge_marker", Vector3(ex, 0, s * (zedge - 0.3)), Vector3(0, 0, s))
	# cameras, clocks and speakers on the platform wall
	var x3 := -L * 0.5 + 10.0
	while x3 < L * 0.5 - 6.0:
		StationProps.put(holder, "cctv_dome", Vector3(x3, 2.15, s * (zwall + 0.1)), Vector3(0, 0, s))
		x3 += 26.0
	StationProps.put(holder, "clock", Vector3(-L * 0.25, 2.1, s * (zwall + 0.03)), Vector3(0, 0, s))
	StationProps.put(holder, "clock", Vector3(L * 0.25, 2.1, s * (zwall + 0.03)), Vector3(0, 0, s))
	var x4 := -L * 0.5 + 18.0
	while x4 < L * 0.5 - 8.0:
		StationProps.put(holder, "pa_speaker", Vector3(x4, 2.3, s * (zwall + 0.1)), Vector3(0, 0, s))
		x4 += 20.0
	# tunnel-mouth signals
	var ztrack := zedge + PlatformModule.TRACK_TO_EDGE
	StationProps.put(holder, "signal_lamp", Vector3(L * 0.5 + 18.0, PlatformModule.BED_Y, s * (ztrack + 1.35)), Vector3(0, 0, -s))
	StationProps.put(holder, "signal_lamp", Vector3(-L * 0.5 - 18.0, PlatformModule.BED_Y, s * (ztrack + 1.35)), Vector3(0, 0, -s))


## a wall-mounted prop: origin on the wall surface, front facing `dir` (into the room); no route test (it is off the floor)
func put_wall(parent: Node3D, name: String, pos: Vector3, dir: Vector3) -> Node3D:
	stats["placed"] += 1
	return StationProps.put(parent, name, pos, dir)


func _room(rm: Dictionary) -> void:
	StationProps._room_dressing(root, rm, rng)
