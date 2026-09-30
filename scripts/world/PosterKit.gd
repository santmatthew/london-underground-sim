class_name PosterKit
extends RefCounted
## Framed posters on walls, in the real Tube formats (Global/TfL specs, build/refs_dress/ads_maps/SPEC.md), merged into ONE mesh per owner
## (a platform wall, a hall ...) instead of a node per poster. Poster art comes from assets/textures/props/posters2 (manifest.json), falling
## back to the 12 older posters. A per-station Picker limits how many different textures a station uses, which bounds its draw calls.

# format -> overall (frame) size, visible (poster) size, bezel depth, art library ("portrait" 0.66, "land16" 1.52, "land48" 2.03, "info" 0.625, "infoq" 1.25)
const FORMATS := {
	"4": {"o": Vector2(1.016, 1.524), "v": Vector2(0.945, 1.453), "d": 0.030, "lib": "portrait"},
	"6": {"o": Vector2(1.200, 1.800), "v": Vector2(1.150, 1.750), "d": 0.030, "lib": "portrait"},
	"16": {"o": Vector2(3.048, 2.032), "v": Vector2(2.953, 1.937), "d": 0.040, "lib": "land16"},
	"48": {"o": Vector2(6.060, 3.048), "v": Vector2(5.930, 2.918), "d": 0.045, "lib": "land48"},
	"dr": {"o": Vector2(0.703, 1.042), "v": Vector2(0.635, 1.016), "d": 0.039, "lib": "info"},
	"qr": {"o": Vector2(1.337, 1.042), "v": Vector2(1.270, 1.016), "d": 0.039, "lib": "infoq"},
	"lep": {"o": Vector2(0.419, 0.572), "v": Vector2(0.387, 0.540), "d": 0.022, "lib": "portrait"},
}
const DIR := "res://assets/textures/props/posters2/"

static var _manifest: Array = []
static var _loaded := false
static var _mats: Dictionary = {}
static var _by_lib: Dictionary = {}     # lib -> Array of file names


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := DIR + "manifest.json"
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Array:
			_manifest = data
		elif data is Dictionary and data.has("posters"):
			_manifest = data["posters"]
	for e in _manifest:
		var lib := _lib_of(e)
		if lib == "":
			continue
		if not _by_lib.has(lib):
			_by_lib[lib] = []
		_by_lib[lib].append(String(e["file"]))
	# the older posters: portrait 0..7, landscape 8..11 (3:2 and 2:1 both use them when nothing better exists)
	if not _by_lib.has("portrait"):
		_by_lib["portrait"] = ["old:0", "old:1", "old:2", "old:3", "old:4", "old:5", "old:6", "old:7"]
	for lib in ["land16", "land48", "infoq"]:
		if not _by_lib.has(lib):
			_by_lib[lib] = ["old:8", "old:9", "old:10", "old:11"]
	if not _by_lib.has("info"):
		_by_lib["info"] = _by_lib["portrait"]


static func _lib_of(e: Dictionary) -> String:
	var f := String(e.get("format", ""))
	var a := float(e.get("aspect", 0.0))
	if f.contains("info") or String(e.get("style", "")).begins_with("tfl"):
		return "info" if a < 1.0 else "infoq"
	if a < 0.9:
		return "portrait"
	if a < 1.8:
		return "land16"
	return "land48"


static func has_lib(lib: String) -> bool:
	_load()
	return _by_lib.has(lib) and not (_by_lib[lib] as Array).is_empty()


## A per-station choice of poster art: `per_lib` different textures for each library, drawn with a seeded generator
class Picker:
	var _pool: Dictionary = {}
	var rng: RandomNumberGenerator

	func _init(p_rng: RandomNumberGenerator, per_lib := 10) -> void:
		rng = p_rng
		PosterKit._load()
		for lib in PosterKit._by_lib:
			var all: Array = (PosterKit._by_lib[lib] as Array).duplicate()
			# a seeded shuffle
			for i in range(all.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var t = all[i]; all[i] = all[j]; all[j] = t
			_pool[lib] = all.slice(0, mini(per_lib, all.size()))

	func pick(lib: String, avoid := "") -> String:
		var p: Array = _pool.get(lib, [])
		if p.is_empty():
			return ""
		var f: String = p[rng.randi() % p.size()]
		if f == avoid and p.size() > 1:
			f = p[(p.find(f) + 1) % p.size()]
		return f


static func _material(file: String, vw: float, vh: float) -> StandardMaterial3D:
	var key := "%s|%.3f|%.3f" % [file, vw, vh]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var t: Texture2D = null
	if file == "@tubemap":
		t = TubeMapTexture.texture()
		m.albedo_texture = t
		m.emission_enabled = true
		m.emission_texture = t
	elif file.begins_with("old:"):
		m = StationProps.poster_material(int(file.substr(4))).duplicate() as StandardMaterial3D
		t = m.albedo_texture
	else:
		var p := DIR + file
		if ResourceLoader.exists(p):
			t = load(p)
		m.albedo_texture = t
		m.emission_enabled = true
		m.emission_texture = t
	m.roughness = 0.32
	m.emission_energy_multiplier = 0.28
	m.uv1_scale = Vector3(1.0 / vw, 1.0 / vh, 1.0)       # MeshKit UVs are metres
	_mats[key] = m
	return m


static func frame_material(kind: String) -> StandardMaterial3D:
	var key := "frame_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match kind:
		"black":
			m.albedo_color = Color(0.05, 0.05, 0.055); m.roughness = 0.5; m.metallic = 0.2
		"bronze":
			m.albedo_color = Color(0.36, 0.26, 0.17); m.roughness = 0.45; m.metallic = 0.5
		"blank":
			m.albedo_color = Color(0.80, 0.81, 0.80); m.roughness = 0.6
		"enamel":
			m.albedo_color = Color(0.93, 0.94, 0.94); m.roughness = 0.22
		_:
			m.albedo_color = Color(0.62, 0.63, 0.64); m.roughness = 0.42; m.metallic = 0.45         # satin silver, RAL 9006
	_mats[key] = m
	return m


## a framed poster on a wall. `bottom_centre` is the point on the wall surface at the bottom edge of the FRAME, `normal` the axis-aligned
## unit vector pointing out of the wall into the room. `art` is a file from Picker.pick (or "" for a blank backing card).
static func add(kit: MeshKit, fmt: String, bottom_centre: Vector3, normal: Vector3, art: String, frame := "silver", floor_y := 0.0) -> void:
	var f: Dictionary = FORMATS[fmt]
	var ov: Vector2 = f["o"]
	var vv: Vector2 = f["v"]
	var d: float = f["d"]
	var right := Vector3.UP.cross(normal).normalized()
	var fc := bottom_centre + Vector3.UP * ov.y * 0.5 + normal * d * 0.5
	kit.box_xf("frame_" + frame, Transform3D(Basis(right, Vector3.UP, normal), fc), Vector3(ov.x, ov.y, d), floor_y)
	var pc := bottom_centre + Vector3.UP * ov.y * 0.5 + normal * (d + 0.0015)
	var l := pc - right * vv.x * 0.5
	var r := pc + right * vv.x * 0.5
	var up := Vector3.UP * vv.y * 0.5
	var mat := "poster:%s|%.3f|%.3f" % [art, vv.x, vv.y] if art != "" else "frame_blank"
	kit.quad(mat, l + up, l - up, r - up, r + up, floor_y, Vector2.ZERO, 0.0, true)


## a plain white enamel plate on a wall (the panel between poster groups that carries a roundel), navy keyline; bottom_centre on the wall surface
static func add_plate(kit: MeshKit, size: Vector2, bottom_centre: Vector3, normal: Vector3, floor_y := 0.0) -> void:
	var right := Vector3.UP.cross(normal).normalized()
	var fc := bottom_centre + Vector3.UP * size.y * 0.5 + normal * 0.012
	kit.box_xf("frame_enamel", Transform3D(Basis(right, Vector3.UP, normal), fc), Vector3(size.x, size.y, 0.024), floor_y)


## turn the kit into a mesh instance under `parent`
static func finish(kit: MeshKit, parent: Node3D, node_name := "Posters") -> MeshInstance3D:
	if kit.surfaces.is_empty():
		return null
	var mats := {}
	for k in kit.surfaces.keys():
		var key: String = k
		if key.begins_with("poster:"):
			var parts := key.substr(7).split("|")
			mats[key] = _material(parts[0], float(parts[1]), float(parts[2]))
		elif key.begins_with("frame_"):
			mats[key] = frame_material(key.substr(6))
		else:
			mats[key] = Mats.get_mat(key)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = node_name
	parent.add_child(mi)
	return mi
