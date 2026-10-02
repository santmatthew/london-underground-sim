extends Node
## AdaptiveScale.decide: down after two seconds over the target, up only after four seconds well under it and when the next step is predicted to fit, never beyond the ends.
var ok := true


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func run():
	var st: Array = AdaptiveScale.make_steps(1.0)
	print("  ladder from 1.0: ", st)
	check(st[0] == 1.0 and st[st.size() - 1] == 0.4 and st.size() >= 5, "ladder runs from the ceiling down to 0.40")
	var st4: Array = AdaptiveScale.make_steps(0.54)
	check(st4[0] == 0.54 and st4[st4.size() - 1] == 0.4, "a 4K ceiling of 0.54 still has room below (%s)" % str(st4))
	var r: Dictionary = AdaptiveScale.decide(st, 1.0, 20.0, 14.5, 0, 0)
	check(r["scale"] == 1.0 and r["over"] == 1, "one slow second: wait")
	r = AdaptiveScale.decide(st, 1.0, 20.0, 14.5, r["over"], r["under"])
	check(r["scale"] == st[1], "two slow seconds: one step down")
	var cur := 1.0
	var over := 0
	var under := 0
	for i in 40:
		r = AdaptiveScale.decide(st, cur, 30.0, 14.5, over, under)
		cur = r["scale"]; over = r["over"]; under = r["under"]
	check(cur == 0.4, "stays slow: bottoms out at the floor (%.2f)" % cur)
	cur = st[2]
	over = 0
	under = 0
	for i in 3:
		r = AdaptiveScale.decide(st, cur, 6.0, 14.5, over, under)
		cur = r["scale"]; over = r["over"]; under = r["under"]
	check(cur == st[2], "three fast seconds: not yet")
	r = AdaptiveScale.decide(st, cur, 6.0, 14.5, over, under)
	check(r["scale"] == st[1], "four fast seconds: one step up")
	r = AdaptiveScale.decide(st, st[2], 10.4, 14.5, 0, 3)
	check(r["scale"] == st[2], "fast enough to count as 'under' but the next step up is predicted not to fit: stay")
	r = AdaptiveScale.decide(st, 1.0, 3.0, 14.5, 0, 10)
	check(r["scale"] == 1.0, "never above the ceiling")
	r = AdaptiveScale.decide(st, st[3], 13.0, 14.5, 1, 1)
	check(r["scale"] == st[3] and r["over"] == 0 and r["under"] == 0, "inside the band: counters reset")
	print("OK" if ok else "FAILED")
