extends RefCounted

const Util := preload("res://tests/motion_util.gd")
const Terrain := preload("res://sim/terrain/terrain.gd")
const Command := preload("res://sim/command.gd")
const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")


static func run(a) -> void:
	print("RUN terrain")
	print("DEFER projectile impacts, secondary line of sight, base armor regen, lock, and replay")
	var cat = Util.catalog()
	var golden: Dictionary = Util.golden()
	var obstacles := _obstacles(cat)
	var groups := _clusters(obstacles)
	_expect_group(a, groups, "w1", golden["gap"]["groupW1"])
	_expect_group(a, groups, "w3", golden["gap"]["groupW3"])
	var passage := float(cat.min_passage("hills"))
	var narrow := _narrowest(groups, obstacles)
	a.ok(narrow >= passage, "narrowest passage")
	a.near(narrow, float(golden["gap"]["narrow"]), "narrowest passage value", Util.TOL)
	for id in cat.lineup_ids():
		var radius := float(cat.vehicle(str(id))["collisionRadius"])
		a.ok(passage > 2.0 * radius + 150.0, "passage fits " + str(id))
	var hills = cat.map_def("hills")
	var width := float(hills["size"]["w"])
	var height := float(hills["size"]["h"])
	for obstacle in hills["obstacles"]:
		var touches := false
		var nearest := INF
		for vertex in obstacle["poly"]:
			var edge := minf(float(vertex["x"]), float(vertex["y"]))
			edge = minf(edge, width - float(vertex["x"]))
			edge = minf(edge, height - float(vertex["y"]))
			if edge <= 1.0:
				touches = true
			nearest = minf(nearest, edge)
		if touches:
			continue
		a.ok(nearest >= passage, str(obstacle["id"]) + " stays off the border")
	var bases: Array = hills["bases"]
	var dx := float(bases[0]["pos"]["x"]) - float(bases[1]["pos"]["x"])
	var dy := float(bases[0]["pos"]["y"]) - float(bases[1]["pos"]["y"])
	var half := sqrt(dx * dx + dy * dy) / 2.0
	a.ok(float(cat.weapon("bulwark_main")["range"]) < half, "bulwark gun stays inside half the map")
	for point in _sites(hills):
		for obstacle in hills["obstacles"]:
			a.ok(not Terrain.point_in_polygon(point, obstacle["poly"]), "site is open")
			a.ok(float(Terrain.closest_on_polygon(point, obstacle["poly"])["d"]) > 400.0, "site clearance")
	_drive_gap(cat, golden, groups, obstacles, a)
	_rocks(cat, golden, hills, a)
	_wall(cat, golden, a)
	_base_push(cat, golden, a)


static func _drive_gap(cat, golden: Dictionary, groups: Array, obstacles: Dictionary, a) -> void:
	var best_d := INF
	var best_p := {"x": 0.0, "y": 0.0}
	var best_q := {"x": 0.0, "y": 0.0}
	for i in groups.size():
		for j in range(i + 1, groups.size()):
			for left in groups[i]:
				for right in groups[j]:
					var gap := _poly_gap(obstacles[left]["poly"], obstacles[right]["poly"])
					if float(gap["d"]) < best_d:
						best_d = float(gap["d"])
						best_p = gap["p"]
						best_q = gap["q"]
	var mid := {"x": (float(best_p["x"]) + float(best_q["x"])) / 2.0, "y": (float(best_p["y"]) + float(best_q["y"])) / 2.0}
	var nx := -(float(best_q["y"]) - float(best_p["y"])) / best_d
	var ny := (float(best_q["x"]) - float(best_p["x"])) / best_d
	var start := {"x": float(mid["x"]) - nx * 450.0, "y": float(mid["y"]) - ny * 450.0}
	var goal := {"x": float(mid["x"]) + nx * 450.0, "y": float(mid["y"]) + ny * 450.0}
	var world = Util.arena(cat, "hills")
	var vehicle = world.spawn(cat.vehicle("bulwark"), 0, start, atan2(ny, nx))
	var arrived := false
	var arrive_tick := -1
	for i in 25 * 60:
		var want := atan2(float(goal["y"]) - float(vehicle["pos"]["y"]), float(goal["x"]) - float(vehicle["pos"]["x"]))
		var err := Angle.delta(float(vehicle["heading"]), want)
		var throttle := 1.0 if absf(err) < 0.3 else 0.0
		var order := Command.merge({"turn": clampf(err * 3.0, -1.0, 1.0), "throttle": throttle})
		Util.step_id(world, int(vehicle["id"]), order, 1)
		if Point.distance(goal, vehicle["pos"]) < 60.0:
			arrived = true
			arrive_tick = i
			break
	var expect: Dictionary = golden["gap"]
	a.ok(arrived, "bulwark crosses the narrow gap")
	a.eq(arrived, bool(expect["arrived"]), "gap arrival matches the prototype")
	a.eq(arrive_tick, int(expect["arriveTick"]), "gap arrival tick")
	Util.near_body(a, vehicle, expect["end"], "gap end")


static func _rocks(cat, golden: Dictionary, hills: Dictionary, a) -> void:
	var rock_poly: Array = []
	for obstacle in hills["obstacles"]:
		if str(obstacle["id"]) == "rF":
			rock_poly = obstacle["poly"]
	var index := 0
	for spec in golden["rocks"]:
		var id := str(spec["vehicle"])
		var def = cat.vehicle(id)
		var world = Util.arena(cat, "hills")
		var vehicle = world.spawn(def, 0, {"x": 4600.0, "y": 4300.0}, 0.0)
		var touched := false
		var min_clear := INF
		var order := Command.merge({"throttle": 1.0})
		var radius := float(def["collisionRadius"])
		for _i in 15 * 60:
			Util.step_id(world, int(vehicle["id"]), order, 1)
			a.ok(not Terrain.point_in_polygon(vehicle["pos"], rock_poly), id + " stays outside the rock")
			var clear := float(Terrain.closest_on_polygon(vehicle["pos"], rock_poly)["d"])
			a.ok(clear > radius - 2.0, id + " is not buried in the rock")
			if clear < radius + 2.0:
				touched = true
			min_clear = minf(min_clear, clear)
		a.ok(touched, id + " reaches the rock")
		a.eq(touched, bool(spec["touched"]), id + " touch flag")
		a.eq(Terrain.point_in_polygon(vehicle["pos"], rock_poly), bool(spec["inside"]), id + " inside flag")
		a.near(min_clear, float(spec["minClear"]), id + " min clearance", Util.TOL)
		a.near(float(vehicle["pos"]["x"]), float(spec["end"]["x"]), id + " rock x", Util.TOL)
		a.near(float(vehicle["pos"]["y"]), float(spec["end"]["y"]), id + " rock y", Util.TOL)
		index += 1
	a.ok(index == 3, "three locomotion types hit the rock")


static func _wall(cat, golden: Dictionary, a) -> void:
	var world = Util.arena(cat, "hills")
	var wall = null
	var rock = null
	for obstacle in world.terrain.obstacles:
		if str(obstacle["def"]["id"]) == "w3":
			wall = obstacle
		if str(obstacle["def"]["id"]) == "rF":
			rock = obstacle
	var he := float(cat.weapon("bulwark_he_sec")["ammo"][0]["damage"]) * float(cat.rules["terrain"]["heMul"])
	var events: Array = []
	world.terrain.damage(wall, he, {"x": 0.0, "y": 0.0}, events)
	var expect: Dictionary = golden["wall"]
	a.near(float(wall["hp_max"]) - float(wall["hp"]), he, "wall takes the HE amount", Util.TOL)
	a.near(float(wall["hp"]), float(expect["hpAfter36"]), "wall hp", Util.TOL)
	world.terrain.damage(wall, 1e9, {"x": 0.0, "y": 0.0}, events)
	a.eq(bool(wall["alive"]), bool(expect["alive"]), "wall destroyed")
	var poly: Array = wall["def"]["poly"]
	var n := float(poly.size())
	var cx := 0.0
	var cy := 0.0
	for vertex in poly:
		cx += float(vertex["x"]) / n
		cy += float(vertex["y"]) / n
	var center := {"x": cx, "y": cy}
	a.eq(world.terrain.push_circle(center, 100.0) == null, bool(expect["push"]), "dead wall does not push")
	var blocked = world.terrain.segment_hit({"x": cx - 120.0, "y": cy}, {"x": cx + 120.0, "y": cy})
	a.eq(blocked == null, bool(expect["blocked"]), "dead wall does not block")
	var rock_events: Array = []
	world.terrain.damage(rock, 1e9, {"x": 0.0, "y": 0.0}, rock_events)
	a.eq(bool(rock["alive"]), bool(expect["rockAlive"]), "rock ignores damage")
	a.near(float(rock_events[0]["damage"]), float(expect["rockEventDamage"]), "rock hit reports zero damage", Util.TOL)


static func _base_push(cat, golden: Dictionary, a) -> void:
	var world = Util.arena(cat, "hills")
	var base = world.spawn(cat.vehicle("base1"), 1, {"x": 9330.0, "y": 760.0}, 0.0)
	var swarm = world.spawn(cat.vehicle("swarm"), 0, {"x": 8930.0, "y": 760.0}, 0.0)
	Util.step_id(world, int(swarm["id"]), Command.merge({"throttle": 1.0, "secondaries": false}), 240)
	var expect: Dictionary = golden["base"]
	a.near(float(base["pos"]["x"]), float(expect["x"]), "base x", Util.TOL)
	a.near(float(base["pos"]["y"]), float(expect["y"]), "base y", Util.TOL)
	a.eq(float(base["pos"]["x"]), 9330.0, "base is not pushed")
	a.eq(float(base["pos"]["y"]), 760.0, "base y stays")
	var separation := Point.distance(swarm["pos"], base["pos"])
	var min_sep := float(base["def"]["collisionRadius"]) + float(swarm["def"]["collisionRadius"]) - 1.0
	a.ok(separation >= min_sep, "swarm stays outside the base")
	a.near(separation, float(expect["separation"]), "base separation", Util.TOL)
	Util.near_body(a, swarm, expect["swarm"], "swarm against base")


static func _sites(hills: Dictionary) -> Array:
	var out: Array = []
	for base in hills["bases"]:
		out.append(base["pos"])
	for spawn in hills["spawns"]:
		out.append(spawn["pos"])
	return out


static func _obstacles(cat) -> Dictionary:
	var out := {}
	for obstacle in cat.map_def("hills")["obstacles"]:
		out[str(obstacle["id"])] = obstacle
	return out


static func _expect_group(a, groups: Array, needle: String, expected: Array) -> void:
	for group in groups:
		var found := false
		for id in group:
			if str(id) == needle:
				found = true
		if not found:
			continue
		var copy: Array = group.duplicate()
		copy.sort()
		a.eq(copy.size(), expected.size(), needle + " group size")
		for i in expected.size():
			a.eq(str(copy[i]), str(expected[i]), needle + " member")
		return
	a.ok(false, needle + " group missing")


static func _clusters(obstacles: Dictionary) -> Array:
	var ids: Array = obstacles.keys()
	var parent := {}
	for id in ids:
		parent[id] = id
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if float(_poly_gap(obstacles[ids[i]]["poly"], obstacles[ids[j]]["poly"])["d"]) <= 1.0:
				parent[_find(parent, ids[i])] = _find(parent, ids[j])
	var groups := {}
	for id in ids:
		var root = _find(parent, id)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(id)
	var out: Array = []
	for root in groups.keys():
		out.append(groups[root])
	return out


static func _find(parent: Dictionary, id: String) -> String:
	var current := str(id)
	while str(parent[current]) != current:
		current = str(parent[current])
	return current


static func _narrowest(groups: Array, obstacles: Dictionary) -> float:
	var narrow := INF
	for i in groups.size():
		for j in range(i + 1, groups.size()):
			for left in groups[i]:
				for right in groups[j]:
					narrow = minf(narrow, float(_poly_gap(obstacles[left]["poly"], obstacles[right]["poly"])["d"]))
	return narrow


static func _poly_gap(a: Array, b: Array) -> Dictionary:
	for vertex in a:
		if Terrain.point_in_polygon(vertex, b):
			return {"d": 0.0, "p": a[0], "q": a[0]}
	for vertex in b:
		if Terrain.point_in_polygon(vertex, a):
			return {"d": 0.0, "p": a[0], "q": a[0]}
	var best := {"d": INF, "p": a[0], "q": b[0]}
	for vertex in a:
		var close := Terrain.closest_on_polygon(vertex, b)
		if float(close["d"]) < float(best["d"]):
			best = {"d": close["d"], "p": vertex, "q": close["q"]}
	for vertex in b:
		var close := Terrain.closest_on_polygon(vertex, a)
		if float(close["d"]) < float(best["d"]):
			best = {"d": close["d"], "p": close["q"], "q": vertex}
	return best
