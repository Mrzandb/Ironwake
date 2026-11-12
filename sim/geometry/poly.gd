extends RefCounted
class_name SimPoly

## Game_test@33f4be8 src/sim/geometry/poly.ts.
## Convex polygons, SAT-style point tests, Cyrus–Beck segment hits.
## Points stay {x, y} dictionaries (64-bit). Judgment does not use the physics server.

const Point := preload("res://sim/point.gd")


static func _at(poly: Array, i: int) -> Dictionary:
	var n := poly.size()
	var k := i % n
	if k < 0:
		k += n
	return poly[k]


static func signed_area(poly: Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in n:
		area += Point.cross(_at(poly, i), _at(poly, i + 1))
	return area / 2.0


static func normalize_winding(poly: Array) -> Array:
	var copy := poly.duplicate()
	if signed_area(poly) < 0.0:
		copy.reverse()
	return copy


static func is_convex(poly: Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var sign := 0.0
	var turn := 0.0
	for i in n:
		var a := _at(poly, i)
		var b := _at(poly, i + 1)
		var c := _at(poly, i + 2)
		var e1x := float(b["x"]) - float(a["x"])
		var e1y := float(b["y"]) - float(a["y"])
		var e2x := float(c["x"]) - float(b["x"])
		var e2y := float(c["y"]) - float(b["y"])
		var z := e1x * e2y - e1y * e2x
		if absf(z) < 1e-9:
			return false
		var s := signf(z)
		if sign == 0.0:
			sign = s
		elif s != sign:
			return false
		turn += atan2(z, e1x * e2x + e1y * e2y)
	return absf(absf(turn) - PI * 2.0) < 1e-6


static func centroid(poly: Array) -> Dictionary:
	var x := 0.0
	var y := 0.0
	for v in poly:
		x += float(v["x"])
		y += float(v["y"])
	var n := float(poly.size())
	return {"x": x / n, "y": y / n}


static func point_in_convex(pt: Dictionary, poly: Array) -> bool:
	var p := normalize_winding(poly)
	var n := p.size()
	var px := float(pt["x"])
	var py := float(pt["y"])
	for i in n:
		var a: Dictionary = p[i]
		var b: Dictionary = p[(i + 1) % n]
		var ex := float(b["x"]) - float(a["x"])
		var ey := float(b["y"]) - float(a["y"])
		var cx := px - float(a["x"])
		var cy := py - float(a["y"])
		if ex * cy - ey * cx < 0.0:
			return false
	return true


static func transform_poly(poly: Array, angle: float, pivot = null, offset = null) -> Array:
	var px := 0.0
	var py := 0.0
	if typeof(pivot) == TYPE_DICTIONARY:
		px = float(pivot["x"])
		py = float(pivot["y"])
	var ox := 0.0
	var oy := 0.0
	if typeof(offset) == TYPE_DICTIONARY:
		ox = float(offset["x"])
		oy = float(offset["y"])
	var c := cos(angle)
	var s := sin(angle)
	var out: Array = []
	for v in poly:
		var x := float(v["x"]) - px
		var y := float(v["y"]) - py
		out.append({
			"x": x * c - y * s + px + ox,
			"y": x * s + y * c + py + oy,
		})
	return out


static func inset_convex(poly: Array, d: float) -> Array:
	var p := normalize_winding(poly)
	var n := p.size()
	var lines: Array = []
	for i in n:
		var a: Dictionary = p[i]
		var b: Dictionary = p[(i + 1) % n]
		var ex := float(b["x"]) - float(a["x"])
		var ey := float(b["y"]) - float(a["y"])
		var l := Point.hypot(ex, ey)
		lines.append({
			"ax": float(a["x"]) + (-ey / l) * d,
			"ay": float(a["y"]) + (ex / l) * d,
			"ex": ex,
			"ey": ey,
		})
	var out: Array = []
	for i in n:
		var left: Dictionary = lines[(i - 1 + n) % n]
		var right: Dictionary = lines[i]
		var den := float(left["ex"]) * float(right["ey"]) - float(left["ey"]) * float(right["ex"])
		if absf(den) < 1e-9:
			out.append({"x": float(right["ax"]), "y": float(right["ay"])})
			continue
		var sx := ((float(right["ax"]) - float(left["ax"])) * float(right["ey"]) - (float(right["ay"]) - float(left["ay"])) * float(right["ex"])) / den
		out.append({
			"x": float(left["ax"]) + float(left["ex"]) * sx,
			"y": float(left["ay"]) + float(left["ey"]) * sx,
		})
	return out


## Cyrus–Beck. t is along a→b in [0, 1]. normal is the outward unit normal
## at entry, or null when the segment starts inside.
static func segment_vs_convex(a: Dictionary, b: Dictionary, poly: Array):
	var p := normalize_winding(poly)
	var ax := float(a["x"])
	var ay := float(a["y"])
	var dx := float(b["x"]) - ax
	var dy := float(b["y"]) - ay
	var t_enter := 0.0
	var t_exit := 1.0
	var enter_normal = null
	var n := p.size()
	for i in n:
		var v0: Dictionary = p[i]
		var v1: Dictionary = p[(i + 1) % n]
		var ex := float(v1["x"]) - float(v0["x"])
		var ey := float(v1["y"]) - float(v0["y"])
		var edge_len := Point.hypot(ex, ey)
		var nx := ey / edge_len
		var ny := -ex / edge_len
		var num := nx * (float(v0["x"]) - ax) + ny * (float(v0["y"]) - ay)
		var den := nx * dx + ny * dy
		if absf(den) < 1e-12:
			if num < 0.0:
				return null
			continue
		var t := num / den
		if den < 0.0:
			if t > t_enter:
				t_enter = t
				enter_normal = {"x": nx, "y": ny}
		elif t < t_exit:
			t_exit = t
		if t_enter > t_exit:
			return null
	return {"t": t_enter, "normal": enter_normal}


static func distance_to_convex(pt: Dictionary, poly: Array) -> float:
	if point_in_convex(pt, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	var px := float(pt["x"])
	var py := float(pt["y"])
	for i in n:
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[(i + 1) % n]
		var ax := float(a["x"])
		var ay := float(a["y"])
		var ex := float(b["x"]) - ax
		var ey := float(b["y"]) - ay
		var l2 := ex * ex + ey * ey
		if l2 == 0.0:
			l2 = 1e-12
		var t := ((px - ax) * ex + (py - ay) * ey) / l2
		if t < 0.0:
			t = 0.0
		elif t > 1.0:
			t = 1.0
		var d := Point.hypot(px - (ax + ex * t), py - (ay + ey * t))
		if d < best:
			best = d
	return best
