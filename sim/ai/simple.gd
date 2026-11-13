extends RefCounted
class_name SimAiSimple

## Game_test@33f4be8 src/sim/ai/simple.ts.
## Commands only. The same weapon checks apply as for a player.
## A ready missile pulls the nose onto the target; otherwise the hover nose
## stays 50 degrees off the bearing so the orbit can use forward thrust.
## Laser heat hysteresis is stored on the vehicle and is not part of the world hash.

const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Command := preload("res://sim/command.gd")
const Slots := preload("res://sim/combat/slots.gd")
const Stats := preload("res://sim/stats/resolver.gd")

const NOSE_OFFSET := (50.0 * PI) / 180.0
const SIDE_PRESENT := (40.0 * PI) / 180.0

const DEFAULT_AI := {
	"enabled": true,
	"orbit_radius": 420.0,
	"orbit_dir": 1.0,
	"orbit_speed": 0.85,
	"keep_distance": 1800.0,
	"fire": true,
	"hold_dist": 2400.0,
	"engage_dist": 1800.0,
	"stalemate": 30.0,
	"push_time": 30.0,
}


static func with_params(overrides: Dictionary = {}) -> Dictionary:
	var params := {}
	for key in DEFAULT_AI.keys():
		params[key] = DEFAULT_AI[key]
	for key in overrides.keys():
		params[key] = overrides[key]
	return params


static func think(me: Dictionary, target: Dictionary, params: Dictionary, table: Dictionary, rules: Dictionary) -> Dictionary:
	var aim := Point.copy(target["pos"])
	var lock := int(target["id"])
	if not params["enabled"] or not me["alive"]:
		return Command.merge({"aim": aim, "lock": lock})
	var dx := float(target["pos"]["x"]) - float(me["pos"]["x"])
	var dy := float(target["pos"]["y"]) - float(me["pos"]["y"])
	var dist := Point.hypot(dx, dy)
	if dist == 0.0:
		dist = 1.0
	var bearing := atan2(dy, dx)
	if str(me["def"]["locomotion"]) == "hover":
		return _hover(me, params, table, rules, dx, dy, dist, bearing, aim, lock)
	var turret_main = _turret_main(me)
	if turret_main != null:
		return _turret_body(me, turret_main, params, table, rules, dist, bearing, aim, lock)
	return _crown_body(me, params, table, rules, dist, bearing, aim, lock)


static func _hover(me: Dictionary, params: Dictionary, table: Dictionary, rules: Dictionary, dx: float, dy: float, dist: float, bearing: float, aim: Dictionary, lock: int) -> Dictionary:
	var move: Dictionary = me["def"]["move"]
	var vmax := Stats.stat(me, "maxSpeed", float(move["maxSpeed"]), rules)
	var rx := dx / dist
	var ry := dy / dist
	var orbit_dir := float(params["orbit_dir"])
	var tx := -ry * orbit_dir
	var ty := rx * orbit_dir
	var radial := Angle.clamp_value((dist - float(params["orbit_radius"])) * 1.5, -vmax, vmax)
	var vt := vmax * float(params["orbit_speed"])
	var want_x := tx * vt + rx * radial
	var want_y := ty * vt + ry * radial
	var fx := cos(float(me["heading"]))
	var fy := sin(float(me["heading"]))
	var along := want_x * fx + want_y * fy
	var side := -want_x * fy + want_y * fx
	var throttle := along / vmax
	if along < 0.0:
		throttle = along / (vmax * float(move["reverseRatio"]))
	var strafe := 0.0
	if float(move["strafeRatio"]) > 0.0:
		strafe = side / (vmax * float(move["strafeRatio"]))
	var missile = _first_kind(me, table, "missile")
	var missile_ready := false
	if missile != null:
		var runtime: Dictionary = me["weapons"][str(missile["id"])]
		var state := str(me["modules"][str(missile["id"])]["state"])
		missile_ready = float(runtime["reload"]) <= 0.0 and state == "NORMAL" and dist < _range_of(me, missile, table, rules) * 0.8
	var nose := bearing
	if not missile_ready:
		nose = bearing + NOSE_OFFSET * orbit_dir
	var turn := Angle.delta(float(me["heading"]), nose) * 3.0
	var launch := bool(params["fire"]) and missile_ready and absf(Angle.delta(float(me["heading"]), bearing)) < (4.0 * PI) / 180.0
	var lasers := _kind_modules(me, table, "laser")
	var hot := false
	var cool := true
	var laser_range := INF
	for module in lasers:
		var runtime: Dictionary = me["weapons"][str(module["id"])]
		if float(runtime["heat"]) > 85.0 or float(runtime["lockout"]) > 0.0:
			hot = true
		if not (float(runtime["heat"]) < 30.0 and float(runtime["lockout"]) <= 0.0):
			cool = false
		laser_range = minf(laser_range, _range_of(me, module, table, rules))
	var hold := bool(me.get("heat_hold", false))
	if hot:
		hold = true
	elif cool:
		hold = false
	me["heat_hold"] = hold
	var fire := bool(params["fire"]) and not hold and dist <= laser_range and absf(Angle.delta(float(me["heading"]), bearing)) < (60.0 * PI) / 180.0
	var slots := Slots.weapon_slots(me["def"], table)
	var laser_slot := 0
	var found_laser := false
	var missile_slot := -1
	for i in slots.size():
		var kind := str(slots[i]["kind"])
		if not found_laser and kind == "laser":
			laser_slot = i
			found_laser = true
		if missile_slot < 0 and kind == "missile":
			missile_slot = i
	if launch and missile_slot >= 0:
		return Command.merge({
			"throttle": Angle.clamp_value(throttle, -1.0, 1.0),
			"turn": Angle.clamp_value(turn, -1.0, 1.0),
			"strafe": Angle.clamp_value(strafe, -1.0, 1.0),
			"aim": aim,
			"fire": true,
			"slot": missile_slot,
			"lock": lock,
		})
	return Command.merge({
		"throttle": Angle.clamp_value(throttle, -1.0, 1.0),
		"turn": Angle.clamp_value(turn, -1.0, 1.0),
		"strafe": Angle.clamp_value(strafe, -1.0, 1.0),
		"aim": aim,
		"fire": fire,
		"slot": laser_slot,
		"lock": lock,
	})


static func _turret_body(me: Dictionary, turret_main: Dictionary, params: Dictionary, table: Dictionary, rules: Dictionary, dist: float, bearing: float, aim: Dictionary, lock: int) -> Dictionary:
	var want := bearing + SIDE_PRESENT
	var err := Angle.delta(float(me["heading"]), want)
	var go := absf(err) < 0.6
	var throttle := 0.0
	if go:
		var keep := float(params["keep_distance"])
		if dist > keep + 80.0:
			throttle = 1.0
		elif dist < keep - 80.0:
			throttle = -0.6
	var runtime: Dictionary = me["weapons"][str(turret_main["id"])]
	var fire := bool(params["fire"]) and dist <= _range_of(me, turret_main, table, rules) and bool(runtime["in_arc"]) and float(runtime["aim_err"]) < (1.0 * PI) / 180.0
	return Command.merge({
		"throttle": throttle,
		"turn": Angle.clamp_value(err * 3.0, -1.0, 1.0),
		"aim": aim,
		"fire": fire,
		"lock": lock,
	})


static func _crown_body(me: Dictionary, params: Dictionary, table: Dictionary, rules: Dictionary, dist: float, bearing: float, aim: Dictionary, lock: int) -> Dictionary:
	var turn_err := Angle.delta(float(me["heading"]), bearing)
	var facing := absf(turn_err) < 0.5
	var throttle := 0.0
	if facing:
		var keep := float(params["keep_distance"])
		if dist > keep + 80.0:
			throttle = 1.0
		elif dist < keep - 80.0:
			throttle = -0.6
	var main = null
	for module in me["def"]["modules"]:
		if module.get("primary", false) and module.has("weapon"):
			main = module
			break
	var gun_range := 0.0
	if main != null:
		gun_range = _range_of(me, main, table, rules)
	var gun_err := absf(Angle.delta(float(me["heading"]) + float(me["crown_angle"]), bearing))
	var fire := bool(params["fire"]) and dist <= gun_range and gun_err < (1.0 * PI) / 180.0
	return Command.merge({
		"throttle": throttle,
		"turn": Angle.clamp_value(turn_err * 3.0, -1.0, 1.0),
		"aim": aim,
		"fire": fire,
		"lock": lock,
	})


static func _turret_main(me: Dictionary):
	for module in me["def"]["modules"]:
		if module.get("primary", false) and module.has("weapon") and module.has("turret"):
			return module
	return null


static func _first_kind(me: Dictionary, table: Dictionary, kind: String):
	var found := _kind_modules(me, table, kind)
	if found.is_empty():
		return null
	return found[0]


static func _kind_modules(me: Dictionary, table: Dictionary, kind: String) -> Array:
	var out: Array = []
	for module in me["def"]["modules"]:
		if not module.has("weapon"):
			continue
		if str(table[str(module["weapon"])]["kind"]) == kind:
			out.append(module)
	return out


static func _range_of(me: Dictionary, module: Dictionary, table: Dictionary, rules: Dictionary) -> float:
	var weapon: Dictionary = table[str(module["weapon"])]
	return Stats.stat(me, "range", float(weapon["range"]), rules, {"module": str(module["id"]), "weapon": str(module["weapon"])})
