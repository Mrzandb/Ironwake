extends RefCounted

const Util := preload("res://tests/world_util.gd")
const Simple := preload("res://sim/ai/simple.gd")
const Team := preload("res://sim/ai/team.gd")
const NavScript := preload("res://sim/ai/nav.gd")
const MatchScript := preload("res://sim/match/match.gd")
const Command := preload("res://sim/command.gd")
const Point := preload("res://sim/point.gd")


static func run(a) -> void:
	print("RUN ai")
	var cat = Util.catalog()
	var golden: Dictionary = Util.golden()
	_nose(a, cat, golden)
	_paths(a, cat, golden)
	_duel(a, cat, golden)
	_team(a, cat, golden)
	_bulwarks(a, cat)
	_hawks(a, cat)
	_swarms(a, cat)
	_crossing(a, cat)
	_shoulder(a, cat)


static func _nose(a, cat, golden: Dictionary) -> void:
	var world = Util.fight(cat, 8000.0, 8000.0, 1)
	var target = world.spawn(cat.vehicle("bulwark"), 0, {"x": 4000.0, "y": 4000.0}, 0.0)
	var hawk = world.spawn(cat.vehicle("hawk"), 1, {"x": 4000.0, "y": 3400.0}, PI / 2.0)
	var params := Simple.with_params()
	Util.near_cmd(a, Simple.think(hawk, target, params, world.table, world.rules), golden["noseCold"], "missile not ready")
	for module in hawk["def"]["modules"]:
		if not module.has("weapon"):
			continue
		if str(world.table[str(module["weapon"])]["kind"]) == "missile":
			hawk["weapons"][str(module["id"])]["reload"] = 0.0
	var hot: Dictionary = Simple.think(hawk, target, params, world.table, world.rules)
	Util.near_cmd(a, hot, golden["noseHot"], "missile ready")
	a.eq(int(hot["slot"]), 1, "a ready missile selects the missile slot")
	a.near(float(hot["turn"]), 0.0, "a ready missile points the nose at the target", Util.TOL)
	a.ok(float(golden["noseCold"]["turn"]) > 0.5, "an unready missile keeps the orbit offset")


static func _paths(a, cat, golden: Dictionary) -> void:
	var hills = cat.map_def("hills")
	var world = Util.fight(cat, float(hills["size"]["w"]), float(hills["size"]["h"]), 1, "hills")
	var nav = NavScript.new(world)
	var expect: Array = golden["paths"]
	a.eq(expect.size(), hills["spawns"].size(), "one path per spawn")
	for i in hills["spawns"].size():
		var spawn: Dictionary = hills["spawns"][i]
		var goal = null
		for base in hills["bases"]:
			if int(base["team"]) != int(spawn["team"]):
				goal = base["pos"]
		var path = nav.find_path(spawn["pos"], goal)
		a.ok(path != null, "spawn %d has a path" % i)
		var points: Array = expect[i]["points"]
		a.eq(path.size(), points.size(), "spawn %d path length" % i)
		for j in points.size():
			a.near(float(path[j]["x"]), float(points[j][0]), "spawn %d point %d x" % [i, j], Util.TOL)
			a.near(float(path[j]["y"]), float(points[j][1]), "spawn %d point %d y" % [i, j], Util.TOL)


static func _duel(a, cat, golden: Dictionary) -> void:
	var params := Simple.with_params({"keep_distance": 1500.0})
	var end: Dictionary = golden["duel180"]
	var first := _play_duel(cat, params)
	a.eq(int(first["shots"]), int(end["shots"]), "duel shots")
	a.eq(first["world"].projectiles.size(), int(end["projectiles"]), "duel projectiles")
	Util.near_body(a, first["left"], end["left"], "duel left")
	Util.near_body(a, first["right"], end["right"], "duel right")
	var second := _play_duel(cat, params)
	a.eq(second["world"].state_hash(), first["world"].state_hash(), "duel hash repeats")


static func _play_duel(cat, params: Dictionary) -> Dictionary:
	var world = Util.fight(cat, 20000.0, 20000.0, 11)
	var left = world.spawn(cat.vehicle("bulwark"), 0, {"x": 8000.0, "y": 10000.0}, 0.0)
	var right = world.spawn(cat.vehicle("bulwark"), 1, {"x": 10000.0, "y": 10000.0}, PI)
	var shots := 0
	for _i in 180:
		var cmds := {}
		cmds[int(left["id"])] = Simple.think(left, right, params, world.table, world.rules)
		cmds[int(right["id"])] = Simple.think(right, left, params, world.table, world.rules)
		world.step(cmds)
		for event in world.events:
			if str(event.get("t", "")) == "fire":
				shots += 1
	return {"world": world, "left": left, "right": right, "shots": shots}


static func _team(a, cat, golden: Dictionary) -> void:
	var end: Dictionary = golden["team180"]
	var first := _play_team(cat)
	a.eq(int(first["shots"]), int(end["shots"]), "team shots")
	a.near(float(first["match"].time_left), float(end["timeLeft"]), "team time left", Util.TOL)
	var expect: Array = end["vehicles"]
	var bodies: Array = first["bodies"]
	a.eq(bodies.size(), expect.size(), "team vehicle count")
	for i in bodies.size():
		a.eq(int(bodies[i]["id"]), int(expect[i]["id"]), "team id")
		a.eq(str(bodies[i]["def"]["id"]), str(expect[i]["def"]), "team def")
		Util.near_body(a, bodies[i], expect[i], "team " + str(expect[i]["id"]))
	var second := _play_team(cat)
	a.eq(second["world"].state_hash(), first["world"].state_hash(), "team hash repeats")


static func _play_team(cat) -> Dictionary:
	var hills = cat.map_def("hills")
	var world = Util.fight(cat, float(hills["size"]["w"]), float(hills["size"]["h"]), 1, "hills")
	var roster := MatchScript.default_roster(0, "bulwark", ["bulwark", "swarm", "hawk"], 3, int(cat.rules["match"]["quotaPerType"]))
	var fixture = MatchScript.new(world, hills, cat, roster, 600.0)
	var nav = NavScript.new(world)
	var params := Simple.with_params()
	var shots := 0
	for _i in 180:
		var cmds := {}
		for slot in fixture.players:
			var body = fixture.vehicle_of(slot)
			if body != null and body["alive"]:
				cmds[int(body["id"])] = Team.think(world, nav, body, params)
		world.step(cmds)
		fixture.step()
		for event in world.events:
			if str(event.get("t", "")) == "fire":
				shots += 1
	var bodies: Array = []
	for vehicle in world.vehicles:
		if str(vehicle["def"]["locomotion"]) != "static":
			bodies.append(vehicle)
	return {"world": world, "match": fixture, "bodies": bodies, "shots": shots}


static func _bulwarks(a, cat) -> void:
	var params := Simple.with_params({"keep_distance": 1500.0})
	var first := _exchange(cat, "bulwark", "bulwark", params, params, 60)
	a.ok(_hurt(first["left"]) > 0.0, "bulwark a is damaged")
	a.ok(_hurt(first["right"]) > 0.0, "bulwark b is damaged")
	var second := _exchange(cat, "bulwark", "bulwark", params, params, 60)
	a.eq(second["world"].replay_hash(), first["world"].replay_hash(), "bulwark duel repeats")


static func _hawks(a, cat) -> void:
	var left_params := Simple.with_params({"orbit_radius": 450.0})
	var right_params := Simple.with_params({"orbit_radius": 450.0, "orbit_dir": -1.0})
	var world = Util.fight(cat, 20000.0, 20000.0, 5)
	var left = world.spawn(cat.vehicle("hawk"), 0, {"x": 9600.0, "y": 10000.0}, 0.0)
	var right = world.spawn(cat.vehicle("hawk"), 1, {"x": 10400.0, "y": 10000.0}, PI)
	for _i in 60 * 90:
		if not left["alive"] or not right["alive"]:
			break
		var cmds := {}
		cmds[int(left["id"])] = Simple.think(left, right, left_params, world.table, world.rules)
		cmds[int(right["id"])] = Simple.think(right, left, right_params, world.table, world.rules)
		world.step(cmds)
	a.ok(not (bool(left["alive"]) and bool(right["alive"])), "hawks resolve within 90s")


static func _swarms(a, cat) -> void:
	var params := Simple.with_params({"keep_distance": 1200.0})
	var against_bulwark := _exchange(cat, "swarm", "bulwark", params, params, 45, 5)
	a.ok(int(against_bulwark["main_fires"]) > 3, "swarm main fires at a bulwark")
	a.ok(int(against_bulwark["sec_fires"]) > 10, "swarm secondaries fire at a bulwark")
	a.ok(_hurt(against_bulwark["right"]) > 0.0, "swarm damages the bulwark")
	a.ok(_hurt(against_bulwark["left"]) > 0.0, "bulwark damages the swarm")
	var again := _exchange(cat, "swarm", "bulwark", params, params, 45, 5)
	a.eq(again["world"].replay_hash(), against_bulwark["world"].replay_hash(), "swarm duel repeats")
	var against_hawk := _exchange(cat, "swarm", "hawk", params, params, 40, 5)
	a.ok(int(against_hawk["sec_fires"]) > 10, "swarm secondaries fire at a hawk")
	a.ok(_hurt(against_hawk["right"]) > 0.0, "secondaries hit the orbiting hawk")


static func _crossing(a, cat) -> void:
	var sec: Dictionary = cat.weapon("bulwark_he_sec")
	var shots := 0
	var hits := 0
	for seed in range(1, 13):
		var world = Util.fight(cat, 20000.0, 20000.0, seed)
		var gun = world.spawn(cat.vehicle("bulwark"), 0, {"x": 10000.0, "y": 10000.0}, 0.0)
		var hawk = world.spawn(cat.vehicle("hawk"), 1, {"x": 9300.0, "y": 10000.0 - float(sec["range"]) * 0.96}, 0.0)
		for _i in int(6.4 * 60.0):
			var cmds := {}
			cmds[int(gun["id"])] = Command.merge({"secondaries": true})
			cmds[int(hawk["id"])] = Command.merge({"throttle": 1.0})
			world.step(cmds)
			for event in world.events:
				if str(event.get("t", "")) == "fire" and int(event["vehicle"]) == int(gun["id"]) and str(event["module"]).begins_with("sec"):
					shots += 1
				if str(event.get("t", "")) == "hit" and str(event.get("result", "")) == "he" and int(event["vehicle"]) == int(hawk["id"]):
					hits += 1
	a.ok(shots > 30, "crossing sample has enough shots")
	var rate := float(hits) / float(shots)
	a.ok(rate > 0.1 and rate < 0.35, "crossing hit rate stays in the calibrated band")


static func _shoulder(a, cat) -> void:
	var weapon: Dictionary = cat.weapon("bulwark_main")
	var saved: Dictionary = (weapon["dispersion"] as Dictionary).duplicate(true)
	weapon["dispersion"]["base"] = 0
	weapon["dispersion"]["kV"] = 0
	weapon["dispersion"]["kT"] = 0
	var near = _shoulder_at(cat, 400.0 * 3.0)
	var far = _shoulder_at(cat, 800.0 * 3.0)
	weapon["dispersion"] = saved
	a.eq(str(near.get("result", "")), "pen", "AP pens the shoulder inside the window")
	a.eq(str(far.get("result", "")), "nonpen", "AP does not pen the shoulder past the window")
	a.eq(float(far.get("erode", -1.0)), 8.0, "a non-pen erodes a fixed amount")


static func _shoulder_at(cat, dist: float) -> Dictionary:
	var world = Util.fight(cat, 20000.0, 20000.0, 3)
	var left = world.spawn(cat.vehicle("bulwark"), 0, {"x": 5000.0, "y": 10000.0}, 0.0)
	var right = world.spawn(cat.vehicle("bulwark"), 1, {"x": 5000.0 + dist + 254.0 + 120.0, "y": 10060.0}, PI)
	right["crown_angle"] = (25.0 * PI) / 180.0
	for _i in 60 * 14:
		var cmds := {}
		cmds[int(left["id"])] = Command.merge({
			"aim": {"x": float(right["pos"]["x"]), "y": float(right["pos"]["y"]) + 40.0},
			"fire": true,
			"secondaries": false,
		})
		cmds[int(right["id"])] = Command.merge({"secondaries": false})
		world.step(cmds)
		for event in world.events:
			if str(event.get("t", "")) != "hit":
				continue
			var log: Dictionary = event["log"]
			if str(log.get("module", "")).contains("主装"):
				return log
	return {}


static func _exchange(cat, left_id: String, right_id: String, left_params: Dictionary, right_params: Dictionary, seconds: int, seed: int = 11) -> Dictionary:
	var world = Util.fight(cat, 20000.0, 20000.0, seed)
	var left = world.spawn(cat.vehicle(left_id), 0, {"x": 8000.0 if left_id != "swarm" else 9000.0, "y": 10000.0}, 0.0)
	var right_x := 10000.0 if left_id != "swarm" else 10500.0
	if left_id == "bulwark" and right_id == "bulwark":
		left = world.vehicles[0]
	var right = world.spawn(cat.vehicle(right_id), 1, {"x": right_x, "y": 10000.0}, PI)
	if left_id == "bulwark" and right_id == "bulwark":
		# The first spawn above already placed the left bulwark. Rebind it.
		left = world.vehicles[0]
	var main_fires := 0
	var sec_fires := 0
	for _i in seconds * 60:
		var cmds := {}
		cmds[int(left["id"])] = Simple.think(left, right, left_params, world.table, world.rules)
		cmds[int(right["id"])] = Simple.think(right, left, right_params, world.table, world.rules)
		world.step(cmds)
		for event in world.events:
			if str(event.get("t", "")) != "fire" or int(event["vehicle"]) != int(left["id"]):
				continue
			if str(event["module"]) == "mainGun":
				main_fires += 1
			else:
				sec_fires += 1
	return {"world": world, "left": left, "right": right, "main_fires": main_fires, "sec_fires": sec_fires}


static func _hurt(vehicle: Dictionary) -> float:
	var total := 0.0
	for module in vehicle["def"]["modules"]:
		total += float(module["structure"]) - float(vehicle["modules"][str(module["id"])]["structure"])
	return total
