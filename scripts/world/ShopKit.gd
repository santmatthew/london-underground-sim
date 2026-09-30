class_name ShopKit
extends RefCounted
## Procedural ticket-hall retail units, after real Tube kiosks and shopfronts (build/refs_dress/halls/SPEC.md sec 5): a closed box with a
## counter and serving hatch across the front, frameless glazing either side, a stainless glazing skirt, a dark fascia with the shop name
## (backlit letters), a roller-shutter housing, lit shelves and a chiller inside. Names are generic (no real brands).
## Local frame: origin at the BACK centre on the wall, the body extends toward -Z (front faces -Z), like the wall props.

const H := 2.9                 # overall height
const FASCIA_Y0 := 2.32
const COUNTER_H := 0.95
const SKIN := 0.10             # wall thickness

const KINDS := {
	"news": {"name": "NEWS & CONFECTIONERY", "accent": Color(0.72, 0.10, 0.16), "counter": Color(0.42, 0.28, 0.17)},
	"coffee": {"name": "COFFEE", "accent": Color(0.28, 0.17, 0.10), "counter": Color(0.36, 0.24, 0.15)},
	"bakery": {"name": "BAKERY", "accent": Color(0.55, 0.30, 0.10), "counter": Color(0.62, 0.55, 0.42)},
	"convenience": {"name": "CONVENIENCE", "accent": Color(0.06, 0.32, 0.55), "counter": Color(0.20, 0.22, 0.25)},
	"pharmacy": {"name": "PHARMACY", "accent": Color(0.05, 0.45, 0.30), "counter": Color(0.80, 0.82, 0.82)},
	"phones": {"name": "PHONE ACCESSORIES", "accent": Color(0.10, 0.10, 0.12), "counter": Color(0.16, 0.16, 0.18)},
}

static var _mats: Dictionary = {}


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


static func _mat(full_key: String) -> Material:
	if _mats.has(full_key):
		return _mats[full_key]
	var key := full_key.get_slice("@", 0)
	var m := StandardMaterial3D.new()
	match key:
		"ss":
			m.albedo_color = Color(0.72, 0.73, 0.75); m.metallic = 0.85; m.roughness = 0.38
		"glass":
			m.albedo_color = Color(0.75, 0.88, 0.95, 0.16); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.roughness = 0.04; m.metallic_specular = 0.9
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"panel":
			m.albedo_color = Color(0.86, 0.86, 0.84); m.roughness = 0.6
		"ceil":
			m.albedo_color = Color(1.0, 0.93, 0.80); m.emission_enabled = true; m.emission = Color(1.0, 0.90, 0.72); m.emission_energy_multiplier = 1.6
		"shutter":
			m.albedo_color = Color(0.30, 0.31, 0.29); m.metallic = 0.5; m.roughness = 0.55         # RAL 7022 umbra grey
		"black":
			m.albedo_color = Color(0.03, 0.03, 0.035); m.roughness = 0.4
		"glow_blue":
			m.albedo_color = Color(0.7, 0.85, 0.95); m.emission_enabled = true; m.emission = Color(0.6, 0.82, 1.0); m.emission_energy_multiplier = 1.1
		_:
			if key.begins_with("fascia:"):
				m.albedo_color = Color(key.substr(7))
				m.roughness = 0.35
			elif key.begins_with("counter:"):
				m.albedo_color = Color(key.substr(8)); m.roughness = 0.5
			elif key.begins_with("shelf:") or key.begins_with("menu:") or key == "chiller":
				var t := _tex("res://assets/textures/props/shops/%s.png" % key.replace(":", "_"))
				m.albedo_texture = t
				m.emission_enabled = true
				m.emission_texture = t
				m.emission_energy_multiplier = 0.75
				m.roughness = 0.5
				# UVs are in metres (MeshKit): the caller scales the quads so that the texture spans them once
			else:
				m.albedo_color = Color(0.5, 0.5, 0.5)
	if full_key.contains("@") and m.albedo_texture != null:
		m.uv1_scale = Vector3(1.0 / float(full_key.get_slice("@", 1)), 1.0 / float(full_key.get_slice("@", 2)), 1.0)
	_mats[full_key] = m
	return m


## a shop of `kind` (a key of KINDS) w metres wide and d deep; `w_name` overrides the fascia text
static func build(kind: String, w: float, d: float, seed_v := 1) -> Node3D:
	var spec: Dictionary = KINDS.get(kind, KINDS["news"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var kit := MeshKit.new()
	kit.seed_rng(seed_v)
	var hw := w * 0.5
	var acc: Color = spec["accent"]
	var fascia_key := "fascia:#" + acc.to_html(false)
	var counter_key := "counter:#" + (spec["counter"] as Color).to_html(false)
	# shell: back wall, side walls, roof (outer faces panel, inner faces are seen through the glazing so they are panel too)
	kit.box("panel", Vector3(0, H * 0.5, -SKIN * 0.5), Vector3(w, H, SKIN), 0.0)
	for s in [-1.0, 1.0]:
		kit.box("panel", Vector3(s * (hw - SKIN * 0.5), H * 0.5, -d * 0.5), Vector3(SKIN, H, d), 0.0)
	kit.box("panel", Vector3(0, H + 0.04, -d * 0.5), Vector3(w + 0.1, 0.08, d + 0.1), 0.0)
	# stainless glazing skirt (150 mm) along the front and the sides' base
	kit.box("ss", Vector3(0, 0.075, -d + 0.02), Vector3(w, 0.15, 0.05), 0.0)
	# counter with cladding, overhanging top, tills, and the serving hatch in the middle
	kit.box(counter_key, Vector3(0, COUNTER_H * 0.5 - 0.04, -d + 0.30), Vector3(w - 2 * SKIN, COUNTER_H - 0.08, 0.55), 0.0)
	kit.box("ss", Vector3(0, COUNTER_H - 0.02, -d + 0.34), Vector3(w - 2 * SKIN + 0.04, 0.04, 0.68), 0.0)
	# glazing above the counter either side of a central open hatch, with stainless mullions
	var hatch := clampf(w * 0.4, 1.0, 2.0)
	for s in [-1.0, 1.0]:
		var gx0: float = s * hatch * 0.5
		var gx1: float = s * (hw - SKIN)
		var cx := (gx0 + gx1) * 0.5
		var gw := absf(gx1 - gx0)
		kit.box("glass", Vector3(cx, (COUNTER_H + FASCIA_Y0) * 0.5, -d + 0.02), Vector3(gw, FASCIA_Y0 - COUNTER_H, 0.012), 0.0)
		kit.box("ss", Vector3(gx0, (COUNTER_H + FASCIA_Y0) * 0.5, -d + 0.02), Vector3(0.05, FASCIA_Y0 - COUNTER_H, 0.05), 0.0)
	# fascia band: dark accent panel with the backlit name, and the roller-shutter housing above the hatch opening
	kit.box(fascia_key, Vector3(0, (FASCIA_Y0 + H) * 0.5, -d + 0.03), Vector3(w, H - FASCIA_Y0, 0.08), 0.0)
	kit.box("shutter", Vector3(0, FASCIA_Y0 - 0.09, -d + 0.05), Vector3(w - 2 * SKIN, 0.18, 0.12), 0.0)
	# interior: lit back wall of shelves, a menu board, a chiller against one side, ceiling light panel, till and display on the counter
	var sh_w := w - 2 * SKIN
	var sh_h := FASCIA_Y0 - 0.35
	_face(kit, "shelf:" + kind, Vector3(-sh_w * 0.5, 0.35 + sh_h, -SKIN - 0.005), Vector3(sh_w * 0.5, 0.35, -SKIN - 0.005), sh_w, sh_h)
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	kit.box("black", Vector3(side * (hw - SKIN - 0.32), 0.95, -0.95), Vector3(0.6, 1.9, 1.2), 0.0)
	# chiller glass front faces the room (toward the other side wall)
	var fx: float = side * (hw - SKIN - 0.62)
	_face_x(kit, "chiller", fx - side * 0.005, -0.95 + 0.6, -0.95 - 0.6, 0.05, 1.85, -side)
	kit.box("ceil", Vector3(0, FASCIA_Y0 - 0.02, -d * 0.5), Vector3(w - 0.4, 0.03, d - 0.9), 0.0)
	kit.box("black", Vector3(hatch * 0.5 + 0.5, COUNTER_H + 0.1, -d + 0.35), Vector3(0.35, 0.2, 0.3), 0.0)     # till
	kit.box("ss", Vector3(-hatch * 0.5 - 0.6, COUNTER_H + 0.16, -d + 0.38), Vector3(0.7, 0.32, 0.3), 0.0)      # display case
	var mats := {}
	for k in kit.surfaces.keys():
		mats[k] = _mat(k)
	var root := Node3D.new()
	root.name = "Shop_" + kind
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(mats)
	mi.name = "Mesh"
	root.add_child(mi)
	# the backlit shop name (individual letters on the fascia) and a small menu board beside the hatch
	var lab := Label3D.new()
	lab.text = spec["name"]
	lab.font = load("res://assets/fonts/Barlow-Bold.ttf")
	lab.font_size = 96
	lab.pixel_size = clampf(0.36 / 96.0 * 1.0, 0.002, 0.005)
	lab.modulate = Color(1, 1, 1)
	lab.outline_size = 0
	lab.shaded = false
	lab.double_sided = false
	lab.width = w * 1000.0 / 4.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.position = Vector3(0, (FASCIA_Y0 + H) * 0.5, -d - 0.012)
	lab.rotation.y = PI
	root.add_child(lab)
	# collision: the whole footprint is solid (the interior is seen through the glazing, not entered)
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(w, H, d)
	cs.shape = sh
	cs.position = Vector3(0, H * 0.5, -d * 0.5)
	body.add_child(cs)
	root.add_child(body)
	root.set_meta("footprint", Vector2(w, d))
	return root


## a quad facing -Z spanning the two top/bottom corner points (left = -x side seen from the front), textured once across its size
static func _face(kit: MeshKit, mat: String, tl: Vector3, br: Vector3, w: float, h: float) -> void:
	# the front (visible) side faces -Z: seen from -Z, +x is to the LEFT, so the left edge of the picture is at +x
	var p0 := Vector3(br.x, tl.y, tl.z)       # top-left as seen by the viewer (+x)
	var p1 := Vector3(br.x, br.y, tl.z)       # bottom-left
	var p2 := Vector3(tl.x, br.y, tl.z)       # bottom-right
	var p3 := Vector3(tl.x, tl.y, tl.z)       # top-right
	kit.quad("%s@%.3f@%.3f" % [mat, w, h], p0, p1, p2, p3, 0.0, Vector2.ZERO, 0.0, true)


static func _face_x(kit: MeshKit, mat: String, x: float, z0: float, z1: float, y0: float, y1: float, dir_x: float) -> void:
	# a quad in the plane x = const facing +dir_x (dir_x = +1 -> faces +x)
	var zl := z0 if dir_x > 0.0 else z1
	var zr := z1 if dir_x > 0.0 else z0
	var p0 := Vector3(x, y1, zl)
	var p1 := Vector3(x, y0, zl)
	var p2 := Vector3(x, y0, zr)
	var p3 := Vector3(x, y1, zr)
	kit.quad("%s@%.3f@%.3f" % [mat, absf(z0 - z1), y1 - y0], p0, p1, p2, p3, 0.0, Vector2.ZERO, 0.0, true)

