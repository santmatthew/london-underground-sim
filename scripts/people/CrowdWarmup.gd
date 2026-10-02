class_name CrowdWarmup
extends RefCounted
## Draws every character once in a small off-screen view so that the first time a character shows up in a station nothing has to be uploaded, shaded or
## compiled while the player is looking (the frame-rate experiment measured about 130 ms the first time each of the 36 characters appeared).
## Call `await CrowdWarmup.run(self)` once, e.g. while the menu or briefing is up; it takes a few frames and frees what it made.

static var done := false


static func run(host: Node, frames := 4) -> void:
	if done or host == null or not host.is_inside_tree():
		return
	done = true
	var sv := SubViewport.new()
	sv.size = Vector2i(320, 320)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(0.0, 1.3, 7.5)
	sv.add_child(cam)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3, 4)
	light.omni_range = 20.0
	sv.add_child(light)
	var n := PersonModel.count()
	for i in n:
		var p := PersonModel.create(i, 1)
		sv.add_child(p)
		p.position = Vector3((i % 9 - 4) * 0.7, 0.0, -float(i / 9) * 0.7)
		p.play(&"idle_stand_1", 0.0, 1.0)
	host.add_child(sv)
	var tree := host.get_tree()
	for k in frames:
		await tree.process_frame
	sv.queue_free()
