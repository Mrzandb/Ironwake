extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const MotionScript := preload("res://sim/motion.gd")
const Command := preload("res://sim/command.gd")
const Point := preload("res://sim/point.gd")

const TOL := 1e-9


static func golden() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://tests/motion_golden.json"))
	return parsed


static func catalog():
	return CatalogScript.new()


static func arena(cat, map_id: String = ""):
	var map_def = null
	var width := 20000.0
	var height := 20000.0
	if map_id != "":
		map_def = cat.map_def(map_id)
		width = float(map_def["size"]["w"])
		height = float(map_def["size"]["h"])
	return MotionScript.new({"w": width, "h": height}, map_def, float(cat.rules["terrain"]["wallHp"]))


static func phase_command(phase: Dictionary) -> Dictionary:
	return Command.merge({
		"throttle": float(phase.get("throttle", 0.0)),
		"turn": float(phase.get("turn", 0.0)),
		"strafe": float(phase.get("strafe", 0.0)),
	})


static func step_id(world, id: int, command: Dictionary, ticks: int) -> void:
	var cmds := {}
	cmds[id] = command
	for _i in ticks:
		world.step(cmds)


static func run_single(cat, spec: Dictionary):
	var world = arena(cat)
	var vehicle = world.spawn(
		cat.vehicle(str(spec["vehicle"])),
		0,
		{"x": float(spec["x"]), "y": float(spec["y"])},
		float(spec["heading"])
	)
	for phase in spec["phases"]:
		step_id(world, int(vehicle["id"]), phase_command(phase), int(phase["ticks"]))
	return vehicle


static func near_body(a, vehicle: Dictionary, end: Dictionary, label: String) -> void:
	a.near(float(vehicle["pos"]["x"]), float(end["x"]), label + ".x", TOL)
	a.near(float(vehicle["pos"]["y"]), float(end["y"]), label + ".y", TOL)
	a.near(float(vehicle["vel"]["x"]), float(end["vx"]), label + ".vx", TOL)
	a.near(float(vehicle["vel"]["y"]), float(end["vy"]), label + ".vy", TOL)
	a.near(float(vehicle["heading"]), float(end["heading"]), label + ".heading", TOL)
	a.near(float(vehicle["ang_vel"]), float(end["angVel"]), label + ".angVel", TOL)
	a.near(float(vehicle["speed"]), float(end["speed"]), label + ".speed", TOL)


static func hypot(vehicle: Dictionary) -> float:
	return Point.length(vehicle["vel"])
