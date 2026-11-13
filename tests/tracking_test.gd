extends RefCounted

const WorldUtil := preload("res://tests/world_util.gd")
const Command := preload("res://sim/command.gd")
const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Simple := preload("res://sim/ai/simple.gd")


static func run(a) -> void:
	print("RUN tracking")
	var cat = WorldUtil.catalog()
	var hawk = cat.vehicle("hawk")
	var radius := float(hawk["move"]["maxSpeed"]) / Angle.deg(float(hawk["move"]["turnRate"]))
	a.ok(radius <= 600.0, "hawk minimum turn radius")
	var golden: Dictionary = WorldUtil.golden()
	var result := _orbit(cat, 600.0)
	a.ok(absf(float(result["average"]) - 600.0) < 120.0, "hawk holds the orbit")
	a.near(float(result["average"]), float(golden["orbit"]["average"]), "orbit average", WorldUtil.TOL)
	a.eq(int(result["samples"]), int(golden["orbit"]["samples"]), "orbit samples")
	WorldUtil.near_body(a, result["flyer"], golden["orbit"]["end"], "orbit end")


static func _orbit(cat, orbit_radius: float) -> Dictionary:
	var world = WorldUtil.fight(cat, 8000.0, 8000.0, 1)
	var anchor = world.spawn(cat.vehicle("bulwark"), 0, {"x": 4000.0, "y": 4000.0}, 0.0)
	var flyer = world.spawn(cat.vehicle("hawk"), 1, {"x": 4000.0, "y": 4000.0 - orbit_radius - 200.0}, PI / 2.0)
	var params := Simple.with_params({"orbit_radius": orbit_radius, "fire": false})
	var dist_sum := 0.0
	var samples := 0
	for i in 30 * 60:
		var cmds := {}
		cmds[int(anchor["id"])] = Command.merge({
			"aim": {"x": float(flyer["pos"]["x"]), "y": float(flyer["pos"]["y"])},
			"secondaries": false,
		})
		cmds[int(flyer["id"])] = Simple.think(flyer, anchor, params, world.table, world.rules)
		world.step(cmds)
		if i > 10 * 60:
			samples += 1
			dist_sum += Point.distance(flyer["pos"], anchor["pos"])
	return {"average": dist_sum / float(samples), "samples": samples, "flyer": flyer}
