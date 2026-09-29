class_name CrowdLod
extends Node
## Distance / visibility based detail manager for many PersonModel instances.
##
##   var lod := CrowdLod.new(); add_child(lod)
##   lod.register(person)           # once per person
##   lod.camera = get_viewport().get_camera_3d()   # (optional, defaults to the current camera)
##
## Every `interval` seconds it walks a slice of the registered people (round robin, `slice` per update) and assigns a
## PersonModel detail level from the distance to the camera and whether the person is in front of the camera:
##   < near      DETAIL_NEAR       full rate animation + shadows
##   < mid       DETAIL_MID        30 Hz
##   < far       DETAIL_FAR        15 Hz, no shadows
##   < very_far  DETAIL_VERY_FAR    8 Hz, coarser mesh LOD
##   beyond / behind camera / out of view: DETAIL_FROZEN (no animation cost) or DETAIL_HIDDEN when > hide_dist.
## The people are ticked by their own _process (PersonModel.manual_tick == false) so nothing else is needed.

@export var near := 7.0
@export var mid := 15.0
@export var far := 28.0
@export var very_far := 50.0
@export var hide_dist := 90.0
@export var interval := 0.15
@export var slice := 40

var camera: Camera3D
var people: Array = []
var _cursor := 0
var _t := 0.0


func register(p: PersonModel) -> void:
	people.append(p)


func unregister(p: PersonModel) -> void:
	people.erase(p)


func _process(delta: float) -> void:
	_t += delta
	if _t < interval or people.is_empty():
		return
	_t = 0.0
	var cam := camera if camera else get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var n := people.size()
	var count := mini(slice, n)
	for i in count:
		_cursor = (_cursor + 1) % n
		var p: PersonModel = people[_cursor]
		if not is_instance_valid(p):
			continue
		var d := p.global_position - cp
		var dist := d.length()
		var level := PersonModel.DETAIL_NEAR
		if dist > hide_dist:
			level = PersonModel.DETAIL_HIDDEN
		else:
			var dot := d.dot(fwd)
			# well behind the camera (with a margin so people at the edge of the view do not pop)
			if dot < -1.5 or (dist > 4.0 and dot / maxf(dist, 0.01) < 0.25):
				level = PersonModel.DETAIL_FROZEN
			elif dist < near:
				level = PersonModel.DETAIL_NEAR
			elif dist < mid:
				level = PersonModel.DETAIL_MID
			elif dist < far:
				level = PersonModel.DETAIL_FAR
			elif dist < very_far:
				level = PersonModel.DETAIL_VERY_FAR
			else:
				level = PersonModel.DETAIL_FROZEN
		p.set_detail(level)
