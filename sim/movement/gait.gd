extends RefCounted
class_name SimGait

## Game_test@33f4be8 src/sim/movement/gait.ts.
## Procedural gait. Planted feet stay fixed in the world.
## `down` is the not-working set (see sim/movement/mobility.gd). A leg in
## `down`, or a dead vehicle, freezes its foot in chassis space and then
## rides with the hull. Module reboot timers are not simulated here.

const Point := preload("res://sim/point.gd")

const MIN_STEP := 0.22


static func _to_world_at(pos: Dictionary, heading: float, local_pt: Dictionary) -> Dictionary:
	var c := cos(heading)
	var s := sin(heading)
	var x := float(local_pt["x"])
	var y := float(local_pt["y"])
	return {
		"x": float(pos["x"]) + x * c - y * s,
		"y": float(pos["y"]) + x * s + y * c,
	}


static func to_world(body: Dictionary, local_pt: Dictionary) -> Dictionary:
	return _to_world_at(body["pos"], float(body["heading"]), local_pt)


static func _to_local(body: Dictionary, world_pt: Dictionary) -> Dictionary:
	var dx := float(world_pt["x"]) - float(body["pos"]["x"])
	var dy := float(world_pt["y"]) - float(body["pos"]["y"])
	var c := cos(float(body["heading"]))
	var s := sin(float(body["heading"]))
	return {"x": dx * c + dy * s, "y": -dx * s + dy * c}


static func _leg_modules(vehicle: Dictionary) -> Array:
	var out: Array = []
	for module in vehicle["modules"]:
		if module.has("leg"):
			out.append(module)
	return out


static func init_gait(vehicle: Dictionary, body: Dictionary) -> Array:
	var step_time := 0.5
	if vehicle.has("gait"):
		step_time = float(vehicle["gait"]["stepTime"])
	var out: Array = []
	for module in _leg_modules(vehicle):
		var foot := to_world(body, module["leg"]["foot"])
		out.append({
			"id": str(module["id"]),
			"group": int(module["leg"]["group"]),
			"foot": foot,
			"stepping": false,
			"t": 0.0,
			"dur": step_time,
			"from": foot,
			"frozen": null,
		})
	return out


static func _target_of(module: Dictionary, body: Dictionary, gait: Dictionary) -> Dictionary:
	var ahead := float(gait["stepTime"]) * float(gait["lead"])
	var future := {
		"x": float(body["pos"]["x"]) + float(body["vel"]["x"]) * ahead,
		"y": float(body["pos"]["y"]) + float(body["vel"]["y"]) * ahead,
	}
	var heading := float(body["heading"]) + float(body["ang_vel"]) * ahead
	return _to_world_at(future, heading, module["leg"]["foot"])


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _active(leg: Dictionary, down: Dictionary, alive: bool) -> bool:
	return alive and not down.has(leg["id"])


static func _group_busy(legs: Array, group: int) -> bool:
	for leg in legs:
		if int(leg["group"]) == group and leg["stepping"]:
			return true
	return false


static func step_gait(vehicle: Dictionary, body: Dictionary, legs: Array, dt: float, events: Array, down: Dictionary, alive: bool = true) -> void:
	if not vehicle.has("gait") or legs.is_empty():
		return
	var gait: Dictionary = vehicle["gait"]
	var by_id := {}
	for module in _leg_modules(vehicle):
		by_id[str(module["id"])] = module
	var targets := {}
	for leg in legs:
		targets[leg["id"]] = _target_of(by_id[leg["id"]], body, gait)
	for leg in legs:
		if not _active(leg, down, alive):
			if leg["frozen"] == null:
				leg["frozen"] = _to_local(body, leg["foot"])
				leg["stepping"] = false
				leg["t"] = 0.0
			leg["foot"] = _to_world_at(body["pos"], float(body["heading"]), leg["frozen"])
		elif leg["frozen"] != null:
			leg["frozen"] = null
	var foot_speed := 0.0
	for leg in legs:
		var target: Dictionary = targets[leg["id"]]
		var rx := float(target["x"]) - float(body["pos"]["x"])
		var ry := float(target["y"]) - float(body["pos"]["y"])
		var vx := float(body["vel"]["x"]) - float(body["ang_vel"]) * ry
		var vy := float(body["vel"]["y"]) + float(body["ang_vel"]) * rx
		foot_speed = maxf(foot_speed, Point.hypot(vx, vy))
	var need := minf(float(gait["stepTime"]), maxf(MIN_STEP, (2.0 * float(gait["threshold"])) / maxf(foot_speed, 1e-6)))
	for leg in legs:
		if not leg["stepping"] or leg["frozen"] != null:
			continue
		leg["dur"] = minf(float(leg["dur"]), need)
		leg["t"] = minf(1.0, float(leg["t"]) + dt / float(leg["dur"]))
		var target: Dictionary = targets[leg["id"]]
		var k := _smooth(float(leg["t"]))
		var origin: Dictionary = leg["from"]
		leg["foot"] = {
			"x": float(origin["x"]) + (float(target["x"]) - float(origin["x"])) * k,
			"y": float(origin["y"]) + (float(target["y"]) - float(origin["y"])) * k,
		}
		if float(leg["t"]) >= 1.0:
			leg["stepping"] = false
			events.append({"t": "footPlant", "leg": leg["id"], "at": leg["foot"]})
	var err := {}
	for leg in legs:
		if not _active(leg, down, alive):
			continue
		var gap := Point.distance(leg["foot"], targets[leg["id"]])
		var group := int(leg["group"])
		var prev := 0.0
		if err.has(group):
			prev = float(err[group])
		err[group] = maxf(prev, gap)
	var any_stepping := false
	for leg in legs:
		if leg["stepping"]:
			any_stepping = true
			break
	var pick := -1
	var worst := 0.0
	var threshold := float(gait["threshold"])
	for group in err.keys():
		var gap := float(err[group])
		var stuck := gap > threshold * 5.0
		var free := (not any_stepping) or stuck
		if free and not _group_busy(legs, int(group)) and gap > threshold and gap > worst:
			worst = gap
			pick = int(group)
	if pick >= 0:
		for leg in legs:
			if int(leg["group"]) != pick or not _active(leg, down, alive):
				continue
			leg["stepping"] = true
			leg["t"] = 0.0
			leg["dur"] = need
			leg["from"] = leg["foot"]


static func feet_pose(body: Dictionary, legs: Array) -> Dictionary:
	var out := {}
	for leg in legs:
		var lift := 0.0
		if leg["stepping"]:
			lift = sin(PI * float(leg["t"]))
		out[leg["id"]] = {"foot": _to_local(body, leg["foot"]), "lift": lift}
	return out
