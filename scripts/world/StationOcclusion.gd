class_name StationOcclusion
extends RefCounted
## Occlusion culling for a station. Without it the renderer draws everything inside the camera frustum: from a ticket hall that includes the
## escalator landings and platforms below, their trains and posters, a thousand draw calls for what is really a few hundred visible.
## The occluders are the architecture's own solid boxes (room floors and ceilings, wall segments between the openings, platform slabs and
## track-side walls) plus a lid over each platform tunnel, merged into one ArrayOccluder3D.

const MIN_THICKNESS := 0.2          # smaller solids (rails, edge guards, posts) do not occlude anything worth the cost


static func build(st: Station) -> void:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in st.spaces:
		var sp: Space = st.spaces[k]
		for c in sp.cols:
			_box(verts, idx, c[0], c[1])
	for pm in st.modules:
		var m := pm as PlatformModule
		for c in m._cols:
			if c.size() > 2 and c[2] == "edge":
				continue
			var sz: Vector3 = c[1]
			if minf(sz.x, minf(sz.y, sz.z)) < MIN_THICKNESS and (sz.x * sz.y * sz.z) < 2.0:
				continue
			_box(verts, idx, m.position + (c[0] as Vector3), sz)
		# the rock above the tunnel: a lid over the arch's crown, spanning the module
		var spec: Dictionary = m.spec
		var L: float = spec["length"]
		var zfar := PlatformModule.GAP * 0.5 + float(spec["pw"]) + PlatformModule.TRACK_TO_EDGE + PlatformModule.TRACK_TO_WALL
		var top := (PlatformModule.BOX_H if m.box else PlatformModule.SPRING_Y + PlatformModule.RISE) + 0.15
		_box(verts, idx, m.position + Vector3(0, top + 0.5, 0), Vector3(L, 1.0, zfar * 2.0 - 0.6))
	if verts.is_empty():
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var inst := OccluderInstance3D.new()
	inst.name = "Occluders"
	inst.occluder = occ
	st.add_child(inst)


## an axis-aligned box as 12 outward-facing triangles
static func _box(verts: PackedVector3Array, idx: PackedInt32Array, centre: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var b := verts.size()
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				verts.append(centre + Vector3(h.x * sx, h.y * sy, h.z * sz))
	# corner index = 4*(sx>0) + 2*(sy>0) + (sz>0)
	var faces := [
		[0, 1, 3, 2], [4, 6, 7, 5],      # -x, +x
		[0, 4, 5, 1], [2, 3, 7, 6],      # -y, +y
		[0, 2, 6, 4], [1, 5, 7, 3],      # -z, +z
	]
	for f in faces:
		idx.append_array([b + f[0], b + f[1], b + f[2], b + f[0], b + f[2], b + f[3]])
