class_name Bend
extends RefCounted
## A planar bend of a straight stretch of tunnel / platform: the space x in [x0, x1] is wrapped round a circular arc of curvature `kappa` (1/m, + turns left: the +x direction swings toward -z),
## x < x0 stays as it is and x > x1 carries on straight, in the direction the arc ended (a rigid move). `z_ref` is the line that keeps its length (the centre line of the thing that is bent), a
## point at lateral offset d from it keeps d (it lies on a concentric arc, so the outside of the bend is longer). Heights are untouched.
## Used to bend the mesh of a platform module (MeshKit.bend), to put its trains, props and people on the curve (map) and to find where a point of the bent module is in the straight design space (unmap).

var kappa := 0.0
var x0 := 0.0
var x1 := 0.0
var z_ref := 0.0


func _init(p_kappa := 0.0, p_x0 := 0.0, p_x1 := 0.0, p_z_ref := 0.0) -> void:
	kappa = p_kappa
	x0 = p_x0
	x1 = p_x1
	z_ref = p_z_ref


func is_straight() -> bool:
	return absf(kappa) < 1e-7 or x1 <= x0


## heading (radians, + = left) of the centre line at x
func theta(x: float) -> float:
	return kappa * (clampf(x, x0, x1) - x0)


## the point of the centre line at x (its z is z_ref when the bend is not there)
func centre(x: float) -> Vector3:
	if x <= x0 or is_straight():
		return Vector3(x, 0.0, z_ref)
	var u := minf(x, x1) - x0
	var th := kappa * u
	var p := Vector3(x0 + sin(th) / kappa, 0.0, z_ref + (cos(th) - 1.0) / kappa)
	if x > x1:
		p += Vector3(cos(th), 0.0, -sin(th)) * (x - x1)
	return p


## straight design space -> bent space
func map(p: Vector3) -> Vector3:
	if p.x <= x0 or is_straight():
		return p
	var th := theta(p.x)
	var c := centre(p.x)
	var d := p.z - z_ref
	return Vector3(c.x + d * sin(th), p.y, c.z + d * cos(th))


## the rotation (about +y) that turns a straight-space direction into the bent one at x
func rot(x: float) -> Basis:
	return Basis(Vector3.UP, theta(x))


## the pose of a thing standing at straight-space (x, z): origin on the bent point (at height y), x axis along the bent track
func pose(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(rot(x), map(Vector3(x, y, z)))


## bent space -> straight design space
func unmap(q: Vector3) -> Vector3:
	if is_straight() or q.x <= x0:
		return q
	var sg := signf(kappa)
	var k := absf(kappa)
	var dz := sg * (q.z - z_ref)              # (mirrored so that the bend turns toward -z)
	var th := atan2(q.x - x0, dz + 1.0 / k)
	var th1 := k * (x1 - x0)
	var x: float
	var off: float
	if th <= th1:
		x = x0 + th / k
		off = Vector2(q.x - x0, dz + 1.0 / k).length() - 1.0 / k
	else:                                     # beyond the end of the arc: undo the rigid move
		var dx := q.x - (x0 + sin(th1) / k)
		var dzz := dz - (cos(th1) - 1.0) / k
		x = x1 + dx * cos(th1) - dzz * sin(th1)
		off = dx * sin(th1) + dzz * cos(th1)
	return Vector3(x, q.y, z_ref + sg * off)


## the design x reached from x after running `ds` metres (signed: + toward +x) along the line at lateral offset z: that line is (1 + kappa (z - z_ref)) times longer than the centre line inside the arc
func advance_x(x: float, ds: float, z: float) -> float:
	if is_straight():
		return x + ds
	var f := 1.0 + kappa * (z - z_ref)
	var rem := absf(ds)
	if ds >= 0.0:
		if x < x0 and rem > 0.0:
			var t := minf(rem, x0 - x)
			x += t
			rem -= t
		if x >= x0 and x < x1 and rem > 0.0:
			var t2 := minf(rem, (x1 - x) * f)
			x += t2 / f
			rem -= t2
		return x + rem
	if x > x1 and rem > 0.0:
		var t3 := minf(rem, x - x1)
		x -= t3
		rem -= t3
	if x <= x1 and x > x0 and rem > 0.0:
		var t4 := minf(rem, (x - x0) * f)
		x -= t4 / f
		rem -= t4
	return x - rem


## the track a train sets off along from design x `x` of this bend, going `dir` (+1 toward +x, -1) on the line at lateral offset z, as [[length, curvature in the direction of travel], ...] up to where it leaves the arc
func departure_segments(x: float, dir: int, z: float) -> Array:
	var out: Array = []
	if is_straight():
		return out
	var f := 1.0 + kappa * (z - z_ref)
	var kt := float(dir) * kappa / f
	if dir > 0:
		if x < x0:
			out.append([x0 - x, 0.0])
			x = x0
		if x < x1:
			out.append([(x1 - x) * f, kt])
	else:
		if x > x1:
			out.append([x - x1, 0.0])
			x = x1
		if x > x0:
			out.append([(x - x0) * f, kt])
	return out


## the same for a train coming in from far away going `dir` to stop at design x `x_stop`: [[length, curvature], ...] in order of travel, the last one ending at the stop
func arrival_segments(x_stop: float, dir: int, z: float) -> Array:
	var out: Array = []
	if is_straight():
		return out
	var f := 1.0 + kappa * (z - z_ref)
	var kt := float(dir) * kappa / f
	if dir > 0:
		if x_stop > x0:
			out.append([(minf(x_stop, x1) - x0) * f, kt])
			if x_stop > x1:
				out.append([x_stop - x1, 0.0])
	else:
		if x_stop < x1:
			out.append([(x1 - maxf(x_stop, x0)) * f, kt])
			if x_stop < x0:
				out.append([x0 - x_stop, 0.0])
	return out
