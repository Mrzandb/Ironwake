extends RefCounted
class_name SimAiTeam

## Game_test@33f4be8 src/sim/ai/team.ts.
## One command per vehicle. Brains live on the vehicle, advanced by sim time.
## Ground vehicles march until hold_dist, then hand off to think().
## Hover vehicles hand off as soon as a target is visible.
## The same opponent for stalemate seconds starts a push.

const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Command := preload("res://sim/command.gd")
const Slots := preload("res://sim/combat/slots.gd")
const Stats := preload("res://sim/stats/resolver.gd")
const Simple := preload("res://sim/ai/simple.gd")

const REPLAN := 2.0
const STUCK_WINDOW := 2.0
const STUCK_DIST := 40.0


static func think(world, nav, me: Dictionary, params: Dictionary = {}) -> Dictionary:
	if params.is_empty():
		params = Simple.with_params()
	if not me["alive"]:
		return Command.idle()
	var now := float(world.sim_time())
	var brain: Dictionary = me.get("brain", {})
	if brain.is_empty():
		brain = {
			"path": [],
			"replan_at": 0.0,
			"check_at": now + STUCK_WINDOW,
			"check_pos": Point.copy(me["pos"]),
			"reverse_until": -1.0,
			"origin": Point.copy(me["pos"]),
			"foe": null,
			"engaged_since": now,
			"push_until": -1.0,
		}
		me["brain"] = brain
	var gun_range := _main_range(me, world.table, world.rules)
	var enemies: Array = []
	for other in world.vehicles:
		if not other["alive"] or int(other["team"]) == int(me["team"]):
			continue
		if str(other["def"]["locomotion"]) == "static":
			continue
		enemies.append(other)
	var visible: Array = []
	for other in enemies:
		if Point.distance(other["pos"], me["pos"]) > gun_range * 0.85:
			continue
		if world.terrain.blocks(me["pos"], other["pos"]):
			continue
		visible.append(other)
	visible.sort_custom(func(a, b):
		var da := Point.distance(a["pos"], me["pos"])
		var db := Point.distance(b["pos"], me["pos"])
		if da < db:
			return true
		if da > db:
			return false
		return int(a["id"]) < int(b["id"])
	)
	var base = null
	for other in world.vehicles:
		if str(other["def"]["locomotion"]) == "static" and int(other["team"]) != int(me["team"]) and other["alive"]:
			base = other
			break
	var foe = visible[0] if not visible.is_empty() else null
	var foe_id = int(foe["id"]) if foe != null else null
	if foe_id != brain["foe"]:
		brain["foe"] = foe_id
		brain["engaged_since"] = now
	if foe != null and now - float(brain["engaged_since"]) > float(params["stalemate"]) and now >= float(brain["push_until"]):
		brain["push_until"] = now + float(params["push_time"])
		brain["engaged_since"] = now + float(params["push_time"])
	var pushing := now < float(brain["push_until"])
	if foe != null:
		var dist := Point.distance(foe["pos"], me["pos"])
		var hover := str(me["def"]["locomotion"]) == "hover"
		if hover or base == null or (dist < float(params["hold_dist"]) and not pushing):
			var tuned: Dictionary = params.duplicate()
			tuned["keep_distance"] = float(params["engage_dist"])
			return Simple.think(me, foe, tuned, world.table, world.rules)
		var moving := _march(world, nav, me, brain, base["pos"], foe["pos"])
		moving["aim"] = Point.copy(foe["pos"])
		moving["fire"] = bool(params["fire"]) and _main_laid(me, foe["pos"])
		moving["lock"] = int(foe["id"])
		return moving
	if base == null:
		return Command.idle()
	var base_dist := Point.distance(base["pos"], me["pos"])
	if base_dist <= gun_range * 0.8 and not world.terrain.blocks(me["pos"], base["pos"]):
		var siege: Dictionary = params.duplicate()
		siege["keep_distance"] = gun_range * 0.6
		siege["orbit_radius"] = maxf(float(params["orbit_radius"]), 600.0)
		return Simple.think(me, base, siege, world.table, world.rules)
	var aim = base["pos"]
	if not enemies.is_empty():
		aim = enemies[0]["pos"]
	return _march(world, nav, me, brain, base["pos"], aim)


static func _main_laid(me: Dictionary, target: Dictionary) -> bool:
	var main = null
	for module in me["def"]["modules"]:
		if module.get("primary", false) and module.has("weapon"):
			main = module
			break
	if main == null:
		return false
	var bearing := atan2(float(target["y"]) - float(me["pos"]["y"]), float(target["x"]) - float(me["pos"]["x"]))
	if main.has("turret"):
		var runtime: Dictionary = me["weapons"][str(main["id"])]
		return bool(runtime["in_arc"]) and float(runtime["aim_err"]) < (1.0 * PI) / 180.0
	return absf(Angle.delta(float(me["heading"]) + float(me["crown_angle"]), bearing)) < (1.0 * PI) / 180.0


static func _main_range(vehicle: Dictionary, table: Dictionary, rules: Dictionary) -> float:
	var slots := Slots.weapon_slots(vehicle["def"], table)
	if slots.is_empty():
		return 0.0
	var slot: Dictionary = slots[0]
	var weapon: Dictionary = table[str(slot["weapon"])]
	return Stats.stat(vehicle, "range", float(weapon["range"]), rules, {"module": str(slot["modules"][0]), "weapon": str(slot["weapon"])})


static func _march(world, nav, me: Dictionary, brain: Dictionary, goal: Dictionary, aim: Dictionary) -> Dictionary:
	var now := float(world.sim_time())
	if now >= float(brain["check_at"]):
		if Point.distance(me["pos"], brain["check_pos"]) < STUCK_DIST:
			brain["reverse_until"] = now + 1.0
			brain["replan_at"] = now + 1.0
		brain["check_at"] = now + STUCK_WINDOW
		brain["check_pos"] = Point.copy(me["pos"])
	var aim_copy := Point.copy(aim)
	if now < float(brain["reverse_until"]):
		return Command.merge({"throttle": -1.0, "turn": 1.0, "aim": aim_copy, "slot": 0})
	var path: Array = brain["path"]
	if now >= float(brain["replan_at"]) or path.is_empty():
		var found = nav.find_path(me["pos"], goal, nav.style_of(me), brain["origin"])
		path = found if found != null else []
		brain["path"] = path
		brain["replan_at"] = now + REPLAN
	while path.size() > 1 and Point.distance(path[0], me["pos"]) < 160.0:
		path.pop_front()
	var waypoint: Dictionary = goal
	if not path.is_empty():
		waypoint = path[0]
	var err := Angle.delta(float(me["heading"]), atan2(float(waypoint["y"]) - float(me["pos"]["y"]), float(waypoint["x"]) - float(me["pos"]["x"])))
	var throttle := 0.0
	if absf(err) < 0.5:
		throttle = 1.0
	elif absf(err) < 1.2:
		throttle = 0.35
	return Command.merge({
		"throttle": throttle,
		"turn": Angle.clamp_value(err * 3.0, -1.0, 1.0),
		"aim": aim_copy,
		"slot": 0,
	})
