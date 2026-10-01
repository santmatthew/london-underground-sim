class_name Seats
extends RefCounted
## Seats the player can sit on: Node3D markers in the group "seat" at the pelvis point (top of the cushion, -Z = facing). Train cars carry seat_L_NN / seat_R_NN
## markers; platform benches carry seat_N markers. A train seat is taken while a seated rider stands on it (CrowdManager records the rider on the marker).

const REACH := 1.15               # horizontal distance to a seat at which it can be used
const MAX_DY := 0.5               # the cushion must be about 0.45 m above the floor we stand on


static func occupied(marker: Node3D) -> bool:
	if not marker.has_meta("rider"):
		return false
	var r = marker.get_meta("rider")
	if r == null or not is_instance_valid(r):
		return false
	var rider := r as Node3D
	if not rider.is_inside_tree() or not rider.visible:
		return false
	if rider.get_parent() != marker.get_parent():
		return false          # it got off (reparented) or the car was emptied
	if not bool(rider.get_meta("seated", false)):
		return false
	var d := Vector2(rider.position.x - marker.position.x, rider.position.z - marker.position.z).length()
	return d < 0.5


static func nearest_free(tree: SceneTree, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := REACH
	for n in tree.get_nodes_in_group("seat"):
		var m := n as Node3D
		if m == null or not m.is_inside_tree() or not m.is_visible_in_tree():
			continue
		var p := m.global_position
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d >= best_d or absf((p.y - 0.45) - from.y) > MAX_DY:
			continue
		if occupied(m):
			continue
		best = m
		best_d = d
	return best
