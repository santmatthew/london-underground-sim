class_name DressMap
extends RefCounted
## Where station dressing must NOT go. Every walking route a passenger can take (the same routes tests/route_audit_test.gd sweeps with a
## capsule: each street door <-> each platform face, face <-> face, each start spot -> doors and faces) is sampled into grid cells; a prop
## footprint is "clear" only if no route cell lies within its rectangle plus a margin. Also holds the footprints of everything placed so far.
## Station frame (the frame the plan and Station children use); y is the floor height of the level the prop stands on.

const CELL := 0.3
const YCELL := 0.6

var _route: Dictionary = {}          # Vector3i -> true
var _placed: Array = []              # [Vector3 centre, Vector2 half, float yaw, float y]


static func build(station: Station) -> DressMap:
	var dm := DressMap.new()
	var plan := station.plan
	var fkeys: Array = plan.faces.keys()
	var routes: Array = []
	for sd in plan.street_doors:
		for fk in fkeys:
			routes.append([plan.path(sd["id"], "face:" + fk), null, "face:" + fk])
			routes.append([plan.path("face:" + fk, sd["id"]), "face:" + fk, null])
	for fa in fkeys:
		for fb in fkeys:
			if fa != fb:
				routes.append([plan.path("face:" + fa, "face:" + fb), "face:" + fa, "face:" + fb])
	for sp in plan.start_spots:
		for sd in plan.street_doors:
			routes.append([plan.path(String(sp["node"]), sd["id"]), sp["pos"], null])
		for fk in fkeys:
			routes.append([plan.path(String(sp["node"]), "face:" + fk), sp["pos"], "face:" + fk])
	for r in routes:
		var names: Array = r[0]
		if names.is_empty():
			continue
		var pts: Array = []
		if r[1] is Vector3:
			pts.append(r[1])
		elif r[1] != null:
			pts.append(station.platform_point(String(r[1]).substr(5), 0.5, 1.4))
		for w in plan.walk_points(names, 0):
			pts.append(w["pos"])
		if r[2] != null:
			pts.append(station.platform_point(String(r[2]).substr(5), 0.5, 1.4))
		for i in pts.size() - 1:
			dm._mark(pts[i], pts[i + 1])
	return dm


func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x / CELL), roundi(p.y / YCELL), roundi(p.z / CELL))


func _mark(a: Vector3, b: Vector3) -> void:
	var n := maxi(1, int(a.distance_to(b) / (CELL * 0.5)))
	for i in n + 1:
		_route[_key(a.lerp(b, float(i) / n))] = true


## true if the rectangle (half extents in its own frame, rotated by yaw about Y, centred at `pos`, standing on floor height pos.y)
## keeps `margin` metres clear of every walking route and of everything already placed
func is_clear(pos: Vector3, half: Vector2, yaw: float, margin: float, check_placed := true) -> bool:
	var rx := half.x + margin
	var rz := half.y + margin
	var reach := int(ceil(sqrt(rx * rx + rz * rz) / CELL)) + 1
	var c := _key(pos)
	var s := sin(yaw)
	var co := cos(yaw)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for dy in [-1, 0, 1]:
				var key := Vector3i(c.x + dx, roundi(pos.y / YCELL) + dy, c.z + dz)
				if not _route.has(key):
					continue
				# the cell centre in the prop's frame
				var wx := key.x * CELL - pos.x
				var wz := key.z * CELL - pos.z
				var lx := wx * co - wz * s
				var lz := wx * s + wz * co
				if absf(lx) <= rx and absf(lz) <= rz:
					return false
	if check_placed:
		for p in _placed:
			if absf((p[3] as float) - pos.y) > 1.5:
				continue
			var pp: Vector3 = p[0]
			var ph: Vector2 = p[1]
			var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
			if d < (ph.length() + half.length()) * 0.9 + margin * 0.5 and _rects_overlap(pos, half, yaw, pp, ph, p[2], margin * 0.5):
				return false
	return true


func add_placed(pos: Vector3, half: Vector2, yaw: float) -> void:
	_placed.append([pos, half, yaw, pos.y])


func _rects_overlap(pa: Vector3, ha: Vector2, ya: float, pb: Vector3, hb: Vector2, yb: float, margin: float) -> bool:
	# separating-axis test between two rotated rectangles (b grown by margin)
	var axes := [Vector2(cos(ya), -sin(ya)), Vector2(sin(ya), cos(ya)), Vector2(cos(yb), -sin(yb)), Vector2(sin(yb), cos(yb))]
	var d := Vector2(pb.x - pa.x, pb.z - pa.z)
	for ax: Vector2 in axes:
		var ra := absf(ax.dot(Vector2(cos(ya), -sin(ya)))) * ha.x + absf(ax.dot(Vector2(sin(ya), cos(ya)))) * ha.y
		var rb := (absf(ax.dot(Vector2(cos(yb), -sin(yb)))) * hb.x + absf(ax.dot(Vector2(sin(yb), cos(yb)))) * hb.y) + margin
		if absf(ax.dot(d)) > ra + rb:
			return false
	return true
