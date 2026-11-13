extends RefCounted
class_name SimTurret

## Game_test@33f4be8 src/sim/combat/turret.ts.
## Traverse stays inside the arc and does not cross the dead zone.
## A turret already on an edge stays there when the target walks around the gap.

const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Stats := preload("res://sim/stats/resolver.gd")

const EDGE_HOLD := PI / 36.0


static func arc_of(turret: Dictionary):
	if not turret.has("arcCenter") or not turret.has("arcHalf"):
		return null
	if float(turret["arcHalf"]) >= 180.0:
		return null
	return {"center": Angle.deg(float(turret["arcCenter"])), "half": Angle.deg(float(turret["arcHalf"]))}


static func ring_angle_to(vehicle: Dictionary, module: Dictionary, point: Dictionary) -> float:
	var turret: Dictionary = module["turret"]
	var blueprint: Dictionary = vehicle["def"]
	var local := Point.rotated({
		"x": float(point["x"]) - float(vehicle["pos"]["x"]),
		"y": float(point["y"]) - float(vehicle["pos"]["y"]),
	}, -float(vehicle["heading"]))
	if str(module["ring"]) == "crown":
		var pivot: Dictionary = blueprint["crownPivot"]
		local = Point.rotated({
			"x": float(local["x"]) - float(pivot["x"]),
			"y": float(local["y"]) - float(pivot["y"]),
		}, -float(vehicle["crown_angle"]))
		local = {
			"x": float(local["x"]) + float(pivot["x"]),
			"y": float(local["y"]) + float(pivot["y"]),
		}
	return atan2(float(local["y"]) - float(turret["pivot"]["y"]), float(local["x"]) - float(turret["pivot"]["x"]))


static func in_turret_arc(vehicle: Dictionary, module: Dictionary, point: Dictionary) -> bool:
	var arc = null
	if module.has("turret"):
		arc = arc_of(module["turret"])
	if arc == null:
		return true
	return absf(Angle.delta(float(arc["center"]), ring_angle_to(vehicle, module, point))) <= float(arc["half"])


static func arc_goal(current: float, want: float, turret: Dictionary) -> Dictionary:
	var arc = arc_of(turret)
	if arc == null:
		return {"goal": want, "in_arc": true}
	var center := float(arc["center"])
	var half := float(arc["half"])
	var dw := Angle.delta(center, want)
	if absf(dw) <= half:
		return {"goal": want, "in_arc": true}
	var dc := clampf(Angle.delta(center, current), -half, half)
	var side := signf(dw)
	if half - absf(dc) <= EDGE_HOLD:
		var held := signf(dc)
		side = held if held != 0.0 else signf(dw)
	return {"goal": Angle.wrap_signed(center + side * half), "in_arc": false}


static func step_turret(vehicle: Dictionary, module: Dictionary, target, dt: float, rules: Dictionary) -> Dictionary:
	var turret: Dictionary = module["turret"]
	var angles: Dictionary = vehicle["turret_angles"]
	var current := 0.0
	if angles.has(module["id"]):
		current = float(angles[module["id"]])
	if target == null:
		return {"in_arc": false, "err": PI}
	var want := ring_angle_to(vehicle, module, target)
	var goal: Dictionary = arc_goal(current, want, turret)
	var arc = arc_of(turret)
	var rate := Angle.deg(Stats.stat(vehicle, "traverseRate", float(turret["traverseRate"]), rules, {"module": str(module["id"])}))
	var next: Dictionary
	if arc == null:
		next = Angle.step_angle(current, float(goal["goal"]), rate, dt)
	else:
		next = Angle.step_angle_in_arc(current, float(goal["goal"]), rate, dt, float(arc["center"]), float(arc["half"]))
	angles[str(module["id"])] = float(next["angle"])
	return {"in_arc": goal["in_arc"], "err": absf(Angle.delta(float(next["angle"]), want))}


static func fire_tolerance(module: Dictionary, rules: Dictionary) -> float:
	var key := "primary" if module.get("primary", false) else "auto"
	return Angle.deg(float(rules["fireTolerance"][key]))


static func turret_target(world, vehicle: Dictionary, module: Dictionary, range: float):
	var lock = null
	if vehicle["lock"] != null:
		for other in world.vehicles:
			if int(other["id"]) == int(vehicle["lock"]) and other["alive"] and int(other["team"]) != int(vehicle["team"]):
				lock = other
				break
	if lock != null and _engagable(world, vehicle, module, lock, range):
		return lock
	var best = null
	var best_d := INF
	for other in world.vehicles:
		if int(other["team"]) == int(vehicle["team"]) or not other["alive"]:
			continue
		if not _engagable(world, vehicle, module, other, range):
			continue
		var dist := Point.distance(other["pos"], vehicle["pos"])
		if dist < best_d:
			best = other
			best_d = dist
	if best != null:
		return best
	if lock != null:
		return lock
	return world.nearest_enemy(vehicle)


static func _engagable(world, vehicle: Dictionary, module: Dictionary, other: Dictionary, range: float) -> bool:
	if Point.distance(other["pos"], vehicle["pos"]) > range:
		return false
	if not in_turret_arc(vehicle, module, other["pos"]):
		return false
	return not world.terrain.blocks(vehicle["pos"], other["pos"])
