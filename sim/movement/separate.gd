extends RefCounted
class_name SimSeparate

## Vehicle-circle push, terrain push, and arena clamp from Game_test World.collide.
## Static bodies are not pushed. No impact damage. Points stay dictionaries.

const Point := preload("res://sim/point.gd")


static func resolve(vehicles: Array, terrain, arena_w: float, arena_h: float) -> void:
	var count := vehicles.size()
	for i in count:
		for j in range(i + 1, count):
			var a: Dictionary = vehicles[i]
			var b: Dictionary = vehicles[j]
			var dx := float(b["pos"]["x"]) - float(a["pos"]["x"])
			var dy := float(b["pos"]["y"]) - float(a["pos"]["y"])
			var dist := Point.hypot(dx, dy)
			if dist == 0.0:
				dist = 1e-6
			var ra := float(a["def"]["collisionRadius"])
			var rb := float(b["def"]["collisionRadius"])
			var overlap := ra + rb - dist
			if overlap <= 0.0:
				continue
			var a_static := str(a["def"]["locomotion"]) == "static"
			var b_static := str(b["def"]["locomotion"]) == "static"
			if a_static and b_static:
				continue
			var nx := dx / dist
			var ny := dy / dist
			var wa := rb / (ra + rb)
			if a_static:
				wa = 0.0
			elif b_static:
				wa = 1.0
			a["pos"] = {
				"x": float(a["pos"]["x"]) - nx * overlap * wa,
				"y": float(a["pos"]["y"]) - ny * overlap * wa,
			}
			b["pos"] = {
				"x": float(b["pos"]["x"]) + nx * overlap * (1.0 - wa),
				"y": float(b["pos"]["y"]) + ny * overlap * (1.0 - wa),
			}
			_clip_apart(a, nx, ny, 1.0)
			_clip_apart(b, nx, ny, -1.0)
	for vehicle in vehicles:
		var radius := float(vehicle["def"]["collisionRadius"])
		if str(vehicle["def"]["locomotion"]) != "static":
			for _k in 3:
				var hit = terrain.push_circle(vehicle["pos"], radius)
				if hit == null:
					break
				vehicle["pos"] = hit["pos"]
				var nx := float(hit["n"]["x"])
				var ny := float(hit["n"]["y"])
				var vn := float(vehicle["vel"]["x"]) * nx + float(vehicle["vel"]["y"]) * ny
				if vn < 0.0:
					vehicle["vel"] = {
						"x": float(vehicle["vel"]["x"]) - nx * vn,
						"y": float(vehicle["vel"]["y"]) - ny * vn,
					}
		var x := clampf(float(vehicle["pos"]["x"]), radius, arena_w - radius)
		var y := clampf(float(vehicle["pos"]["y"]), radius, arena_h - radius)
		var vx := float(vehicle["vel"]["x"])
		var vy := float(vehicle["vel"]["y"])
		if x != float(vehicle["pos"]["x"]):
			vx = 0.0
		if y != float(vehicle["pos"]["y"]):
			vy = 0.0
		vehicle["vel"] = {"x": vx, "y": vy}
		vehicle["pos"] = {"x": x, "y": y}


static func _clip_apart(vehicle: Dictionary, nx: float, ny: float, side: float) -> void:
	var vn := (float(vehicle["vel"]["x"]) * nx + float(vehicle["vel"]["y"]) * ny) * side
	if vn > 0.0:
		vehicle["vel"] = {
			"x": float(vehicle["vel"]["x"]) - nx * vn * side,
			"y": float(vehicle["vel"]["y"]) - ny * vn * side,
		}
