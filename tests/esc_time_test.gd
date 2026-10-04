extends Node3D
## How long building an escalator takes (the first one in a process pays for materials, textures and shaders): 4 builds of the same bank, then one with a different rise
func _ready() -> void:
	Timetable.build(1)
	add_child(Env.make(1))
	for rep in 4:
		var e := Escalator.new()
		var t0 := Time.get_ticks_usec()
		e.build(11.0, [1.0, -1.0, 1.0])
		var t1 := Time.get_ticks_usec()
		add_child(e)
		await get_tree().process_frame
		var t2 := Time.get_ticks_usec()
		print("ESCTIME rep %d: build %.1f ms, first frame in the tree %.1f ms" % [rep, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0])
		e.queue_free()
	get_tree().quit()
