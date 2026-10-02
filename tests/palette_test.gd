extends Node
## Colour-blind palettes: every mode has a colour for every line, the colour changes with the setting, and the closest two lines are far apart as the matching colour-vision
## deficiency sees them (the simulation of tools/gen_cvd_palettes.py, re-done here in linear RGB).
var ok := true
const SIM := {
	"protanopia": [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
	"deuteranopia": [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
	"tritanopia": [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}


func check(c: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if c else "FAIL", what])
	if not c:
		ok = false


func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _lab(c: Color, kind: String) -> Vector3:
	var lin := [_lin(c.r), _lin(c.g), _lin(c.b)]
	var m: Array = SIM[kind]
	var s: Array = []
	for r in 3:
		s.append(clampf(m[r][0] * lin[0] + m[r][1] * lin[1] + m[r][2] * lin[2], 0.0, 1.0))
	var x: float = (0.4124564 * s[0] + 0.3575761 * s[1] + 0.1804375 * s[2]) / 0.95047
	var y: float = 0.2126729 * s[0] + 0.7151522 * s[1] + 0.0721750 * s[2]
	var z: float = (0.0193339 * s[0] + 0.1191920 * s[1] + 0.9503041 * s[2]) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 216.0 / 24389.0 else (24389.0 / 27.0 * t + 16.0) / 116.0
	return Vector3(116.0 * f.call(y) - 16.0, 500.0 * (f.call(x) - f.call(y)), 200.0 * (f.call(y) - f.call(z)))


func run():
	Settings.reset_section("access")
	var base := {}
	for lid in Net.line_ids:
		base[lid] = Net.line_color(lid)
	check(Palette.kinds().size() == 4, "four colour-vision modes: %s" % str(Palette.kinds()))
	for kind in ["protanopia", "deuteranopia", "tritanopia"]:
		Settings.set_v("access", "colour_vision", kind, false)
		var cols := {}
		for lid in Net.line_ids:
			cols[lid] = Net.line_color(lid)
		check(cols["central"] != base["central"] or cols["bakerloo"] != base["bakerloo"] or kind == "tritanopia", "%s: the colours changed" % kind)
		var worst := 1e9
		var pair := ""
		for a in Net.line_ids:
			for b in Net.line_ids:
				if a < b:
					var d := _lab(cols[a], kind).distance_to(_lab(cols[b], kind))
					if d < worst:
						worst = d
						pair = "%s/%s" % [a, b]
		check(worst >= 24.0, "%s: the closest two lines are %.1f apart as seen (%s)" % [kind, worst, pair])
		var worst0 := 1e9
		for a in Net.line_ids:
			for b in Net.line_ids:
				if a < b:
					worst0 = minf(worst0, _lab(base[a], kind).distance_to(_lab(base[b], kind)))
		check(worst > worst0 + 5.0 or worst0 > 24.0, "%s: better than the standard colours (%.1f)" % [kind, worst0])
	Settings.set_v("access", "colour_vision", "standard", false)
	check(Net.line_color("central") == base["central"], "standard gives the brand colours back")
	Settings.reset_section("access")
	print("OK" if ok else "FAILED")
