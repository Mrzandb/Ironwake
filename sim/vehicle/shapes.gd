extends RefCounted
class_name SimLegShape

## Constructors used only while a leg is moving (Game_test shapes.ts).
## Static module rings stay the baked JSON. Do not rebuild those with these.
## lift = 0 of leg_parts() is checked against the baked bulwark vertices.

const DEG := PI / 180.0


static func _xy(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y}


static func polar(radius: float, degrees: float, origin: Dictionary) -> Dictionary:
	var rad := degrees * DEG
	return _xy(float(origin["x"]) + cos(rad) * radius, float(origin["y"]) + sin(rad) * radius)


static func regular(center: Dictionary, radius: float, n: int, rot_deg: float) -> Array:
	var out: Array = []
	var step := 360.0 / float(n)
	for i in n:
		out.append(polar(radius, rot_deg + step * float(i), center))
	return out


static func strut(a: Dictionary, b: Dictionary, w0: float, w1: float) -> Array:
	var dx := float(b["x"]) - float(a["x"])
	var dy := float(b["y"]) - float(a["y"])
	var l := sqrt(dx * dx + dy * dy)
	var nx := -dy / l
	var ny := dx / l
	return [
		_xy(float(a["x"]) + (nx * w0) / 2.0, float(a["y"]) + (ny * w0) / 2.0),
		_xy(float(b["x"]) + (nx * w1) / 2.0, float(b["y"]) + (ny * w1) / 2.0),
		_xy(float(b["x"]) - (nx * w1) / 2.0, float(b["y"]) - (ny * w1) / 2.0),
		_xy(float(a["x"]) - (nx * w0) / 2.0, float(a["y"]) - (ny * w0) / 2.0),
	]


static func chamfer_rect(center: Dictionary, length: float, wid: float, angle_deg: float, ch: float) -> Array:
	var hl := length / 2.0
	var hw := wid / 2.0
	var local := [
		_xy(hl - ch, -hw),
		_xy(hl, -hw + ch),
		_xy(hl, hw - ch),
		_xy(hl - ch, hw),
		_xy(-hl + ch, hw),
		_xy(-hl, hw - ch),
		_xy(-hl, -hw + ch),
		_xy(-hl + ch, -hw),
	]
	var a := angle_deg * DEG
	var cs := cos(a)
	var sn := sin(a)
	var cx := float(center["x"])
	var cy := float(center["y"])
	var out: Array = []
	for v in local:
		var x := float(v["x"])
		var y := float(v["y"])
		out.append(_xy(cx + x * cs - y * sn, cy + x * sn + y * cs))
	return out
