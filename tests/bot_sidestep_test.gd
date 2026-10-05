extends Node
## Which way the bot steps round a person in its way (Autopilot.side_choice): away from the person, to a side that is free, never toward a standing train; alternating only when it has no choice.
## (Seven Kings, 2026-10-05: two people waiting beside the bot, which stepped toward them 48 times in a row.)
var ok := true


func check(c: bool, what: String) -> void:
	if not c:
		print("  FAIL ", what)
		ok = false


func run():
	var f := Vector3(0, 0, -1)               # facing -z: the player's right is +x
	check(Autopilot.side_choice(f, Vector3(-0.4, 0, -0.3), true, true, 1.0) == 1.0, "a person ahead on the left: step right")
	check(Autopilot.side_choice(f, Vector3(0.4, 0, -0.3), true, true, -1.0) == -1.0, "a person ahead on the right: step left")
	# facing +x the player's right is +z
	var fx := Vector3(1, 0, 0)
	check(Autopilot.side_choice(fx, Vector3(0.3, 0, 0.4), true, true, 1.0) == -1.0, "facing +x, a person on the right (+z): step left")
	check(Autopilot.side_choice(fx, Vector3(0.3, 0, -0.4), true, true, -1.0) == 1.0, "facing +x, a person on the left (-z): step right")
	# a rotated facing, computed the way the Autopilot does
	for deg in [0.0, 37.0, 90.0, 140.0, 215.0, 300.0]:
		var yaw := deg_to_rad(deg)
		var fw := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		var right := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
		var on_left := fw * 0.3 - right * 0.4
		var on_right := fw * 0.3 + right * 0.4
		check(Autopilot.side_choice(fw, on_left, true, true, -1.0) == 1.0, "yaw %.0f: a person on the left -> right" % deg)
		check(Autopilot.side_choice(fw, on_right, true, true, 1.0) == -1.0, "yaw %.0f: a person on the right -> left" % deg)
	# only one side clear: that side, whatever the person's position
	check(Autopilot.side_choice(f, Vector3(0.4, 0, -0.3), true, false, -1.0) == 1.0, "only the right is clear: right (even toward the person's side)")
	check(Autopilot.side_choice(f, Vector3(-0.4, 0, -0.3), false, true, 1.0) == -1.0, "only the left is clear: left")
	# dead ahead, or nothing known about the thing: alternate; neither side clear: alternate
	check(Autopilot.side_choice(f, Vector3(0, 0, -0.3), true, true, 1.0) == 1.0 and Autopilot.side_choice(f, Vector3(0, 0, -0.3), true, true, -1.0) == -1.0, "dead ahead: alternates")
	check(Autopilot.side_choice(f, Vector3.ZERO, true, true, -1.0) == -1.0, "not a person: alternates")
	check(Autopilot.side_choice(f, Vector3(-0.4, 0, -0.3), false, false, -1.0) == -1.0 and Autopilot.side_choice(f, Vector3(-0.4, 0, -0.3), false, false, 1.0) == 1.0, "no side is clear: alternates")
	print("OK" if ok else "FAILED")
