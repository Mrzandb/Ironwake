extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const FightScript := preload("res://sim/fight.gd")
const Modules := preload("res://sim/combat/modules.gd")

const TOL := 1e-9


static func catalog():
	return CatalogScript.new()


static func golden() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/world_golden.json"))


static func fight(cat, width: float, height: float, seed: int, map_id: String = ""):
	var map_def = null
	if map_id != "":
		map_def = cat.map_def(map_id)
	return FightScript.new({"w": width, "h": height}, seed, map_def, cat)


static func kill(vehicle: Dictionary) -> void:
	for module in vehicle["def"]["modules"]:
		if str(module["kind"]) == "core":
			Modules.destroy_module(vehicle, module, [])
			return


static func near_point(a, point: Dictionary, x: float, y: float, label: String) -> void:
	a.near(float(point["x"]), x, label + ".x", TOL)
	a.near(float(point["y"]), y, label + ".y", TOL)


static func near_body(a, vehicle: Dictionary, end: Dictionary, label: String) -> void:
	a.near(float(vehicle["pos"]["x"]), float(end["x"]), label + ".x", TOL)
	a.near(float(vehicle["pos"]["y"]), float(end["y"]), label + ".y", TOL)
	a.near(float(vehicle["vel"]["x"]), float(end["vx"]), label + ".vx", TOL)
	a.near(float(vehicle["vel"]["y"]), float(end["vy"]), label + ".vy", TOL)
	a.near(float(vehicle["heading"]), float(end["heading"]), label + ".heading", TOL)
	a.near(float(vehicle["ang_vel"]), float(end["angVel"]), label + ".angVel", TOL)
	a.near(float(vehicle["speed"]), float(end["speed"]), label + ".speed", TOL)
	if end.has("crown"):
		a.near(float(vehicle["crown_angle"]), float(end["crown"]), label + ".crown", TOL)
	if end.has("alive"):
		a.eq(bool(vehicle["alive"]), bool(end["alive"]), label + ".alive")
	if end.has("modules"):
		for module in end["modules"]:
			var runtime: Dictionary = vehicle["modules"][str(module["id"])]
			a.near(float(runtime["armor"]), float(module["armor"]), label + "." + str(module["id"]) + ".armor", TOL)
			a.near(float(runtime["structure"]), float(module["structure"]), label + "." + str(module["id"]) + ".structure", TOL)


static func near_cmd(a, cmd: Dictionary, expect: Dictionary, label: String) -> void:
	a.near(float(cmd["throttle"]), float(expect["throttle"]), label + ".throttle", TOL)
	a.near(float(cmd["turn"]), float(expect["turn"]), label + ".turn", TOL)
	a.near(float(cmd["strafe"]), float(expect["strafe"]), label + ".strafe", TOL)
	a.eq(bool(cmd["fire"]), bool(expect["fire"]), label + ".fire")
	a.eq(int(cmd["slot"]), int(expect["slot"]), label + ".slot")
	a.eq(int(cmd["lock"]), int(expect["lock"]), label + ".lock")
	a.near(float(cmd["aim"]["x"]), float(expect["aimX"]), label + ".aimX", TOL)
	a.near(float(cmd["aim"]["y"]), float(expect["aimY"]), label + ".aimY", TOL)
