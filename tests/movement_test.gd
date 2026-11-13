extends RefCounted

const Util := preload("res://tests/motion_util.gd")
const Command := preload("res://sim/command.gd")
const Point := preload("res://sim/point.gd")
const Mob := preload("res://sim/movement/mobility.gd")
const Kin := preload("res://sim/movement/kinematics.gd")
const Angle := preload("res://sim/angle.gd")


static func run(a) -> void:
	print("RUN movement")
	print("DEFER destroyModule host cascade and the swarm/hawk fight smoke; the down-set is the mobility stub")
	var cat = Util.catalog()
	var golden: Dictionary = Util.golden()
	_singles(cat, golden, a)
	_bulwark_behavior(cat, a)
	_hawk_behavior(cat, a)
	_swarm_behavior(cat, a)
	_gait(cat, golden, a)
	_frozen(cat, golden, a)
	_pair(cat, golden, a)
	_mobility(cat, golden, a)
	a.near(Kin.TRACK_TURN_DRAG, 0.25, "track turn drag", 0.0)


static func _singles(cat, golden: Dictionary, a) -> void:
	for spec in golden["single"]:
		var vehicle = Util.run_single(cat, spec)
		Util.near_body(a, vehicle, spec["end"], str(spec["name"]))


static func _bulwark_behavior(cat, a) -> void:
	var def = cat.vehicle("bulwark")
	var world = Util.arena(cat)
	var vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	var peak := 0.0
	var throttle := Command.merge({"throttle": 1.0})
	for _i in 240:
		Util.step_id(world, int(vehicle["id"]), throttle, 1)
		peak = maxf(peak, Util.hypot(vehicle))
	a.near(peak, float(def["move"]["maxSpeed"]), "bulwark reaches max speed", 5e-6)
	Util.step_id(world, int(vehicle["id"]), Command.idle(), 60)
	a.eq(Util.hypot(vehicle), 0.0, "bulwark stops")
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	var turning := Command.merge({"throttle": 1.0, "turn": 1.0})
	for _i in 180:
		Util.step_id(world, int(vehicle["id"]), turning, 1)
		var along := float(vehicle["vel"]["x"]) * cos(float(vehicle["heading"])) + float(vehicle["vel"]["y"]) * sin(float(vehicle["heading"]))
		a.ok(absf(along - Util.hypot(vehicle)) < 1e-6, "bulwark velocity stays on heading")
	a.near(Angle.to_deg(float(vehicle["ang_vel"])), float(def["move"]["turnRate"]), "bulwark turn rate", 5e-6)


static func _hawk_behavior(cat, a) -> void:
	var def = cat.vehicle("hawk")
	var world = Util.arena(cat)
	var vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0}), 180)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"turn": 1.0}), 90)
	var lateral := -float(vehicle["vel"]["x"]) * sin(float(vehicle["heading"])) + float(vehicle["vel"]["y"]) * cos(float(vehicle["heading"]))
	a.ok(absf(lateral) > 30.0, "hawk keeps lateral speed after a turn")
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"strafe": 1.0}), 240)
	a.near(Util.hypot(vehicle), float(def["move"]["maxSpeed"]) * float(def["move"]["strafeRatio"]), "hawk strafe cap", 5e-4)
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0}), 180)
	Util.step_id(world, int(vehicle["id"]), Command.idle(), 60)
	a.ok(Util.hypot(vehicle) > 100.0, "hawk still coasting after one second")


static func _swarm_behavior(cat, a) -> void:
	var def = cat.vehicle("swarm")
	var world = Util.arena(cat)
	var vehicle = world.spawn(def, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0, "strafe": 1.0}), 300)
	a.near(Util.hypot(vehicle), float(def["move"]["maxSpeed"]), "swarm top speed", 0.5)
	a.ok(absf(float(vehicle["pos"]["y"]) - 15000.0) < 1e-6, "swarm ignores strafe")
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0, "turn": 1.0}), 300)
	var fx := cos(float(vehicle["heading"]))
	var fy := sin(float(vehicle["heading"]))
	a.ok(absf(float(vehicle["vel"]["x"]) * fy - float(vehicle["vel"]["y"]) * fx) < 1e-6, "swarm does not sideslip")
	a.near(float(vehicle["speed"]), float(def["move"]["maxSpeed"]) * (1.0 - Kin.TRACK_TURN_DRAG), "swarm turn drag", 0.5)
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"turn": 1.0}), 180)
	a.ok(float(vehicle["heading"]) > 1.0, "swarm can pivot")
	a.ok(Point.distance(vehicle["pos"], {"x": 15000.0, "y": 15000.0}) < 1e-6, "pivot stays put")
	world = Util.arena(cat)
	vehicle = world.spawn(def, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0}), 60)
	a.ok(float(vehicle["speed"]) < float(def["move"]["maxSpeed"]), "swarm accel is slower than a hover")
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0}), 180)
	var x0 := float(vehicle["pos"]["x"])
	Util.step_id(world, int(vehicle["id"]), Command.idle(), 120)
	a.ok(float(vehicle["pos"]["x"]) - x0 > 40.0, "swarm coasts")
	a.eq(float(vehicle["speed"]), 0.0, "swarm coast ends at rest")


static func _gait(cat, golden: Dictionary, a) -> void:
	var def = cat.vehicle("bulwark")
	var spec: Dictionary = {}
	for module in def["modules"]:
		if module.has("leg"):
			spec = module["leg"]["spec"]
			break
	var reach := float(spec["upper"]) + float(spec["lower"]) + 40.0
	var world = Util.arena(cat)
	var vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	var prev: Array = []
	for leg in vehicle["legs"]:
		prev.append(Point.copy(leg["foot"]))
	var plants := 0
	var orders := [
		Command.merge({"throttle": 1.0}),
		Command.merge({"throttle": 1.0, "turn": 1.0}),
		Command.merge({"turn": -1.0}),
		Command.merge({"throttle": -1.0}),
	]
	for order in orders:
		for _i in 240:
			Util.step_id(world, int(vehicle["id"]), order, 1)
			var groups := {}
			for leg in vehicle["legs"]:
				if leg["stepping"]:
					groups[leg["group"]] = true
			a.ok(groups.size() <= 1, "at most one gait group")
			for i in vehicle["legs"].size():
				var leg: Dictionary = vehicle["legs"][i]
				var module := _module(def, str(leg["id"]))
				var hip = world.to_world(vehicle, module["leg"]["hip"])
				a.ok(Point.distance(leg["foot"], hip) < reach, str(leg["id"]) + " stays in reach")
				if not leg["stepping"] and float(leg["t"]) == 0.0:
					a.eq(float(leg["foot"]["x"]), float(prev[i]["x"]), str(leg["id"]) + " planted x")
					a.eq(float(leg["foot"]["y"]), float(prev[i]["y"]), str(leg["id"]) + " planted y")
				prev[i] = Point.copy(leg["foot"])
			for event in world.events:
				if str(event["t"]) == "footPlant":
					plants += 1
	var expect: Dictionary = golden["gait"]
	a.eq(plants, int(expect["plants"]), "foot plants")
	a.ok(plants > 20, "enough steps")
	a.eq(int(expect["maxGroups"]), 1, "golden gait groups")
	Util.near_body(a, vehicle, expect["end"], "gait end")
	var feet: Dictionary = expect["feet"]
	for leg in vehicle["legs"]:
		var xy: Array = feet[leg["id"]]
		a.near(float(leg["foot"]["x"]), float(xy[0]), str(leg["id"]) + " foot x", Util.TOL)
		a.near(float(leg["foot"]["y"]), float(xy[1]), str(leg["id"]) + " foot y", Util.TOL)


static func _frozen(cat, golden: Dictionary, a) -> void:
	var def = cat.vehicle("bulwark")
	var world = Util.arena(cat)
	var vehicle = world.spawn(def, 0, {"x": 10000.0, "y": 10000.0}, 0.0)
	vehicle["down"]["legFR"] = true
	var throttle := Command.merge({"throttle": 1.0})
	Util.step_id(world, int(vehicle["id"]), throttle, 6)
	var d0 := _hip_distance(world, vehicle, def, "legFR")
	Util.step_id(world, int(vehicle["id"]), throttle, 600)
	var moved := Point.distance(vehicle["pos"], {"x": 10000.0, "y": 10000.0})
	a.ok(moved > 500.0, "frozen leg still lets the hull move")
	Util.step_id(world, int(vehicle["id"]), Command.merge({"throttle": 1.0, "turn": 1.0}), 240)
	var d1 := _hip_distance(world, vehicle, def, "legFR")
	a.ok(absf(d1 - d0) < 1e-6, "frozen foot keeps its reach")
	var expect: Dictionary = golden["frozen"]
	a.near(d0, float(expect["d0"]), "frozen d0", Util.TOL)
	a.near(d1, float(expect["d1"]), "frozen d1", Util.TOL)
	a.near(moved, float(expect["moved"]), "frozen moved", Util.TOL)
	Util.near_body(a, vehicle, expect["end"], "frozen end")


static func _pair(cat, golden: Dictionary, a) -> void:
	var first := _play_pair(cat)
	var second := _play_pair(cat)
	a.eq(first["hash"], second["hash"], "same commands same motion hash")
	var expect: Dictionary = golden["pair"]
	Util.near_body(a, first, expect["a"], "pair bulwark")
	Util.near_body(a, second, expect["a"], "pair bulwark repeat")
	_near_saved(a, first["hawk"], expect["b"], "pair hawk")
	var feet: Dictionary = expect["feet"]
	for leg_id in feet.keys():
		var xy: Array = feet[leg_id]
		var got: Array = first["feet"][leg_id]
		a.near(float(got[0]), float(xy[0]), str(leg_id) + " pair x", Util.TOL)
		a.near(float(got[1]), float(xy[1]), str(leg_id) + " pair y", Util.TOL)


static func _play_pair(cat) -> Dictionary:
	var world = Util.arena(cat)
	var bulwark = world.spawn(cat.vehicle("bulwark"), 0, {"x": 9000.0, "y": 10000.0}, 0.0)
	var hawk = world.spawn(cat.vehicle("hawk"), 1, {"x": 9400.0, "y": 10000.0}, PI)
	for i in 600:
		var s := sin(float(i) / 37.0)
		var cmds := {}
		cmds[bulwark["id"]] = Command.merge({"throttle": s, "turn": cos(float(i) / 53.0)})
		cmds[hawk["id"]] = Command.merge({"throttle": 1.0, "turn": s, "strafe": -1.0})
		world.step(cmds)
	var feet := {}
	for leg in bulwark["legs"]:
		feet[leg["id"]] = [leg["foot"]["x"], leg["foot"]["y"]]
	return {
		"hash": world.state_hash(),
		"pos": bulwark["pos"],
		"vel": bulwark["vel"],
		"heading": bulwark["heading"],
		"ang_vel": bulwark["ang_vel"],
		"speed": bulwark["speed"],
		"feet": feet,
		"hawk": {
			"pos": hawk["pos"],
			"vel": hawk["vel"],
			"heading": hawk["heading"],
			"ang_vel": hawk["ang_vel"],
			"speed": hawk["speed"],
		},
	}


static func _near_saved(a, saved: Dictionary, end: Dictionary, label: String) -> void:
	Util.near_body(a, saved, end, label)


static func _mobility(cat, golden: Dictionary, a) -> void:
	var expect: Dictionary = golden["mobility"]
	var bulwark = cat.vehicle("bulwark")
	var down := {"legFR": true}
	var mods := Mob.of_vehicle(bulwark, down, true)
	a.near(float(mods["speed_mul"]), float(expect["legFR"]["speedMul"]), "one leg speed", Util.TOL)
	a.near(float(mods["turn_bias"]), float(expect["legFR"]["turnBias"]), "one leg bias", Util.TOL)
	a.ok(float(mods["turn_bias"]) > 0.0, "damaged right leg biases clockwise")
	var swarm = cat.vehicle("swarm")
	mods = Mob.of_vehicle(swarm, {"trackR": true}, true)
	a.near(float(mods["speed_mul"]), float(expect["trackR"]["speedMul"]), "one track speed", Util.TOL)
	a.ok(float(mods["turn_bias"]) > 0.0, "damaged right track biases clockwise")
	mods = Mob.of_vehicle(swarm, {"trackR": true, "trackL": true}, true)
	a.eq(float(mods["speed_mul"]), float(expect["bothTracks"]["speedMul"]), "no tracks")
	a.eq(float(mods["turn_mul"]), 0.0, "no tracks cannot turn")


static func _module(vehicle: Dictionary, id: String) -> Dictionary:
	for module in vehicle["modules"]:
		if str(module["id"]) == id:
			return module
	return {}


static func _hip_distance(world, vehicle: Dictionary, def: Dictionary, id: String) -> float:
	var module := _module(def, id)
	var hip = world.to_world(vehicle, module["leg"]["hip"])
	for leg in vehicle["legs"]:
		if str(leg["id"]) == id:
			return Point.distance(leg["foot"], hip)
	return -1.0
