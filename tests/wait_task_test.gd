extends Node
## MeshKit.wait_task: waits for a worker task a frame at a time and collects it, also when the node whose coroutine waits is freed meanwhile (a station freed while it is built in the background).
var ok := true
var _done := {}


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func _wait(id: String, task: int, node: Node) -> void:
	await MeshKit.wait_task(task, node)
	_done[id] = true


func run():
	var n := Node.new()
	add_child(n)
	var t1 := WorkerThreadPool.add_task(func(): OS.delay_msec(250), false, "test task 1")
	_wait("alive", t1, n)
	for i in 3:
		await get_tree().process_frame
	check(not _done.has("alive"), "the wait goes on while the task runs (node alive)")
	var t0 := Time.get_ticks_msec()
	while not _done.has("alive") and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(_done.has("alive"), "... and ends when the task is done")
	var t2 := WorkerThreadPool.add_task(func(): OS.delay_msec(250), false, "test task 2")
	var n2 := Node.new()
	add_child(n2)
	_wait("freed", t2, n2)
	for i in 3:
		await get_tree().process_frame
	n2.free()          # (the node whose coroutine waits is gone)
	t0 = Time.get_ticks_msec()
	while not _done.has("freed") and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(_done.has("freed"), "the wait ends and the task is collected when the node was freed meanwhile")
	var t3 := WorkerThreadPool.add_task(func(): OS.delay_msec(60), false, "test task 3")
	var loose := Node.new()          # (not in a tree: no frames to wait for, the task is collected by a blocking wait)
	t0 = Time.get_ticks_msec()
	await MeshKit.wait_task(t3, loose)
	check(Time.get_ticks_msec() - t0 >= 40, "a node outside the tree: the task is waited for at once (%d ms)" % (Time.get_ticks_msec() - t0))
	loose.free()
	print("OK" if ok else "FAILED")
