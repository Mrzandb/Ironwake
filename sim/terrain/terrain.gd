extends RefCounted
class_name SimTerrain

## Game_test@33f4be8 src/sim/terrain/terrain.ts.
## Rocks block forever. Walls have HP and stop blocking at 0.
## Polygons may be concave. Obstacle order is the map array order.
## Points stay dictionaries. No physics server.

const Point := preload("res://sim/point.gd")

var obstacles: Array = []


func _init(map_def = null, wall_hp: float = 1800.0) -> void:
	obstacles = []
	var list: Array = []
	if typeof(map_def) == TYPE_DICTIONARY and map_def.has("obstacles"):
		list = map_def["obstacles"]
	for def in list:
		var hp := INF
		if str(def["kind"]) == "wall":
			hp = wall_hp
		obstacles.append({
			"def": def,
			"hp": hp,
			"hp_max": hp,
			"alive": true,
			"box": _bbox(def["poly"]),
		})


static func _bbox(poly: Array) -> Dictionary:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for vertex in poly:
		var x := float(vertex["x"])
		var y := float(vertex["y"])
		x0 = minf(x0, x)
		y0 = minf(y0, y)
		x1 = maxf(x1, x)
		y1 = maxf(y1, y)
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1}


static func point_in_polygon(point: Dictionary, poly: Array) -> bool:
	var inside := false
	var px := float(point["x"])
	var py := float(point["y"])
	var j := poly.size() - 1
	for i in poly.size():
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[j]
		var ay := float(a["y"])
		var by := float(b["y"])
		if (ay > py) != (by > py):
			var ax := float(a["x"])
			var bx := float(b["x"])
			var xint := ax + ((py - ay) * (bx - ax)) / (by - ay)
			if px < xint:
				inside = not inside
		j = i
	return inside


static func closest_on_polygon(point: Dictionary, poly: Array) -> Dictionary:
	var px := float(point["x"])
	var py := float(point["y"])
	var best_q := {"x": float(poly[0]["x"]), "y": float(poly[0]["y"])}
	var best_d := INF
	var n := poly.size()
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
		var qx := ax + ex * t
		var qy := ay + ey * t
		var d := Point.hypot(px - qx, py - qy)
		if d < best_d:
			best_d = d
			best_q = {"x": qx, "y": qy}
	return {"q": best_q, "d": best_d}


static func _segment_vs_polygon(a: Dictionary, b: Dictionary, poly: Array):
	var ax := float(a["x"])
	var ay := float(a["y"])
	var rx := float(b["x"]) - ax
	var ry := float(b["y"]) - ay
	var best = null
	var n := poly.size()
	for i in n:
		var p: Dictionary = poly[i]
		var q: Dictionary = poly[(i + 1) % n]
		var sx := float(q["x"]) - float(p["x"])
		var sy := float(q["y"]) - float(p["y"])
		var den := rx * sy - ry * sx
		if absf(den) < 1e-12:
			continue
		var t := ((float(p["x"]) - ax) * sy - (float(p["y"]) - ay) * sx) / den
		var u := ((float(p["x"]) - ax) * ry - (float(p["y"]) - ay) * rx) / den
		if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
			continue
		if best != null and t >= float(best["t"]):
			continue
		var edge_len := Point.hypot(sx, sy)
		if edge_len == 0.0:
			edge_len = 1.0
		var nx := sy / edge_len
		var ny := -sx / edge_len
		if nx * rx + ny * ry > 0.0:
			nx = -nx
			ny = -ny
		best = {"t": t, "normal": {"x": nx, "y": ny}}
	return best


func _near(a: Dictionary, b: Dictionary, pad: float) -> Array:
	var x0 := minf(float(a["x"]), float(b["x"])) - pad
	var x1 := maxf(float(a["x"]), float(b["x"])) + pad
	var y0 := minf(float(a["y"]), float(b["y"])) - pad
	var y1 := maxf(float(a["y"]), float(b["y"])) + pad
	var out: Array = []
	for obstacle in obstacles:
		if not obstacle["alive"]:
			continue
		var box: Dictionary = obstacle["box"]
		if float(box["x1"]) >= x0 and float(box["x0"]) <= x1 and float(box["y1"]) >= y0 and float(box["y0"]) <= y1:
			out.append(obstacle)
	return out


func segment_hit(a: Dictionary, b: Dictionary):
	var best = null
	for obstacle in _near(a, b, 0.0):
		var poly: Array = obstacle["def"]["poly"]
		if point_in_polygon(a, poly):
			return {
				"obstacle": obstacle,
				"t": 0.0,
				"normal": {"x": float(a["x"]) - float(b["x"]), "y": float(a["y"]) - float(b["y"])},
			}
		var hit = _segment_vs_polygon(a, b, poly)
		if hit != null and (best == null or float(hit["t"]) < float(best["t"])):
			best = {"obstacle": obstacle, "t": hit["t"], "normal": hit["normal"]}
	return best


func blocks(a: Dictionary, b: Dictionary) -> bool:
	return segment_hit(a, b) != null


func push_circle(point: Dictionary, radius: float):
	for obstacle in _near(point, point, radius):
		var poly: Array = obstacle["def"]["poly"]
		var inside := point_in_polygon(point, poly)
		var close := closest_on_polygon(point, poly)
		var dist := float(close["d"])
		if not inside and dist >= radius:
			continue
		var q: Dictionary = close["q"]
		var denom := dist if dist != 0.0 else 1.0
		var nx := (float(point["x"]) - float(q["x"])) / denom
		var ny := (float(point["y"]) - float(q["y"])) / denom
		if inside:
			nx = -nx
			ny = -ny
		return {
			"pos": {"x": float(q["x"]) + nx * radius, "y": float(q["y"]) + ny * radius},
			"n": {"x": nx, "y": ny},
		}
	return null


func damage(obstacle: Dictionary, amount: float, at: Dictionary, events: Array, silent: bool = false) -> void:
	var kind := str(obstacle["def"]["kind"])
	if not silent:
		var dealt := amount if kind == "wall" else 0.0
		events.append({
			"t": "terrainHit",
			"obstacle": str(obstacle["def"]["id"]),
			"kind": kind,
			"at": at,
			"damage": dealt,
		})
	if kind != "wall" or not obstacle["alive"] or amount <= 0.0:
		return
	obstacle["hp"] = maxf(0.0, float(obstacle["hp"]) - amount)
	if float(obstacle["hp"]) > 0.0:
		return
	obstacle["alive"] = false
	var poly: Array = obstacle["def"]["poly"]
	var n := float(poly.size())
	var cx := 0.0
	var cy := 0.0
	for vertex in poly:
		cx += float(vertex["x"]) / n
		cy += float(vertex["y"]) / n
	events.append({
		"t": "obstacleDestroyed",
		"obstacle": str(obstacle["def"]["id"]),
		"at": {"x": cx, "y": cy},
	})
