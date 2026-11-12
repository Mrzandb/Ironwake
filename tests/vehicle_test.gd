extends RefCounted

const Util := preload("res://tests/motion_util.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Legs := preload("res://sim/vehicle/legs.gd")
const Poly := preload("res://sim/geometry/poly.gd")
const Validate := preload("res://sim/vehicle/validate.gd")
const Point := preload("res://sim/point.gd")


static func run(a) -> void:
	print("RUN vehicles")
	print("DEFER swarm turret arcs; inTurretArc belongs to combat")
	print("DEFER base coverage fan; a base is one exposed core and has no power module")
	var cat = Util.catalog()
	var golden: Dictionary = Util.golden()
	var bulwark = cat.vehicle("bulwark")
	_valid(a, bulwark, "bulwark")
	_hits(a, bulwark, golden)
	_crown(a, bulwark)
	_legs(a, bulwark, golden)
	for id in ["hawk", "hawkB", "hawkC"]:
		var def = cat.vehicle(id)
		_valid(a, def, id)
		a.ok(Validate.vehicle_radius(def) * 2.0 < 150.0, id + " diameter")
		a.near(Validate.vehicle_radius(def), float(golden["radii"][id]), id + " radius", Util.TOL)
		var lasers := 0
		var chassis := true
		for module in def["modules"]:
			if str(module["finish"]) == "laser":
				lasers += 1
			if str(module["ring"]) != "chassis":
				chassis = false
		a.eq(lasers, 2, id + " lasers")
		a.ok(chassis, id + " has no crown")
	var swarm = cat.vehicle("swarm")
	_valid(a, swarm, "swarm")
	var stripped = swarm.duplicate(true)
	var kept: Array = []
	for module in swarm["modules"]:
		if not module.has("turret"):
			kept.append(module)
	stripped["modules"] = kept
	var radius := Validate.vehicle_radius(stripped)
	a.ok(radius > 90.0 and radius < 130.0, "swarm body radius")
	a.near(radius, float(golden["radii"]["swarmNoTurret"]), "swarm body radius value", Util.TOL)
	a.eq(str(swarm["size"]), "medium", "swarm size")
	a.ok(_extreme_x(swarm, "trackR", true) > _extreme_x(swarm, "hullR", true), "right track sticks out")
	a.ok(_extreme_x(swarm, "trackL", false) < _extreme_x(swarm, "hullL", false), "left track sticks out")
	for id in cat.structure_ids():
		var base = cat.vehicle(str(id))
		var powers := 0
		for module in base["modules"]:
			if str(module["kind"]) == "power":
				powers += 1
			for part in module["parts"]:
				a.ok(Poly.is_convex(part), str(id) + " convex")
		a.eq(powers, 0, str(id) + " has no power module")


static func _valid(a, vehicle: Dictionary, label: String) -> void:
	var report: Dictionary = Validate.validate_vehicle(vehicle)
	if report["errors"].size() > 0:
		print(label, " ", report["errors"])
	a.eq(report["errors"].size(), 0, label + " validates")


static func _cover(module: Dictionary) -> bool:
	return not bool(module.get("movingPart", false))


static func _hits(a, bulwark: Dictionary, golden: Dictionary) -> void:
	var filter := func(module):
		return _cover(module)
	var shield = Pose.first_hit(bulwark, Pose.zero(), {"x": 400.0, "y": 0.0}, {"x": -400.0, "y": 0.0}, filter)
	var arm = Pose.first_hit(bulwark, Pose.zero(), {"x": 400.0, "y": 29.0}, {"x": -400.0, "y": 29.0}, filter)
	a.eq(str(shield["module"]["id"]), str(golden["hits"]["shield"]["id"]), "front hit is the shield")
	a.near(float(shield["t"]), float(golden["hits"]["shield"]["t"]), "shield t", Util.TOL)
	a.eq(str(arm["module"]["id"]), str(golden["hits"]["arm"]["id"]), "overlap hit is the shoulder")
	a.near(float(arm["t"]), float(golden["hits"]["arm"]["t"]), "shoulder t", Util.TOL)


static func _crown(a, bulwark: Dictionary) -> void:
	var pose := Pose.zero()
	pose["crown_angle"] = 1.1
	var filter := func(module):
		return _cover(module)
	for deg_i in range(0, 360, 5):
		var rad := float(deg_i) * PI / 180.0
		var origin := {"x": cos(rad) * 400.0, "y": sin(rad) * 400.0}
		var hit = Pose.first_hit(bulwark, pose, origin, {"x": 0.0, "y": 0.0}, filter)
		a.ok(hit != null, "crown ray hits")
		if hit == null:
			continue
		a.ok(str(hit["module"]["kind"]) != "core", "crown ray misses the core")
		a.ok(str(hit["module"]["kind"]) != "power", "crown ray misses the power module")


static func _legs(a, bulwark: Dictionary, golden: Dictionary) -> void:
	var max_delta := 0.0
	var fl = {}
	var fr = {}
	for module in bulwark["modules"]:
		if not module.has("leg"):
			continue
		var built: Array = Legs.leg_parts(module["leg"]["hip"], module["leg"]["foot"], module["leg"]["spec"], 0.0)
		var baked: Array = module["parts"]
		a.eq(built.size(), baked.size(), str(module["id"]) + " part count")
		for i in built.size():
			a.eq(built[i].size(), baked[i].size(), str(module["id"]) + " vertex count")
			for j in built[i].size():
				max_delta = maxf(max_delta, Point.distance(built[i][j], baked[i][j]))
		if str(module["id"]) == "legFL":
			fl = module
		if str(module["id"]) == "legFR":
			fr = module
	a.ok(max_delta < 1e-9, "lift 0 matches baked legs")
	a.near(max_delta, 0.0, "lift 0 delta", 1e-9)
	var lifted: Array = Legs.leg_parts(fl["leg"]["hip"], fl["leg"]["foot"], fl["leg"]["spec"], 1.0)
	var expect: Array = golden["lift1Foot"]
	a.near(float(lifted[4][0]["x"]), float(expect[0]), "lifted foot x", Util.TOL)
	a.near(float(lifted[4][0]["y"]), float(expect[1]), "lifted foot y", Util.TOL)
	var left: Array = Legs.leg_parts(fl["leg"]["hip"], fl["leg"]["foot"], fl["leg"]["spec"], 0.0)
	var right: Array = Legs.leg_parts(fr["leg"]["hip"], fr["leg"]["foot"], fr["leg"]["spec"], 0.0)
	a.ok(absf(float(left[2][0]["x"]) - float(right[2][0]["x"])) < 40.0, "knees mirror")


static func _extreme_x(vehicle: Dictionary, id: String, want_max: bool) -> float:
	var best := -INF if want_max else INF
	for module in vehicle["modules"]:
		if str(module["id"]) != id:
			continue
		for part in module["parts"]:
			for vertex in part:
				if want_max:
					best = maxf(best, float(vertex["x"]))
				else:
					best = minf(best, float(vertex["x"]))
	return best
