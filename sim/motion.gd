extends RefCounted
class_name SimMotion

## Movement slice of Game_test World.step, in the same order:
## command, body step, vehicle and terrain push, arena clamp, gait.
## No crown aim, weapons, missiles, module timers, or stat modifiers.
## `down` on a vehicle is the not-working module set consumed by mobility and gait.
## Turn rates are degrees per second. Spawn headings are radians.

const Clock := preload("res://sim/clock.gd")
const Hash := preload("res://sim/hash.gd")
const Kin := preload("res://sim/movement/kinematics.gd")
const Mob := preload("res://sim/movement/mobility.gd")
const Gait := preload("res://sim/movement/gait.gd")
const Separate := preload("res://sim/movement/separate.gd")
const TerrainScript := preload("res://sim/terrain/terrain.gd")
const Command := preload("res://sim/command.gd")
const Point := preload("res://sim/point.gd")

var arena_w: float
var arena_h: float
var terrain
var vehicles: Array = []
var events: Array = []
var tick: int = 0
var _next_id: int = 1


func _init(arena: Dictionary, map_def = null, wall_hp: float = 1800.0) -> void:
	arena_w = float(arena["w"])
	arena_h = float(arena["h"])
	terrain = TerrainScript.new(map_def, wall_hp)


func spawn(vehicle: Dictionary, team: int, pos: Dictionary, heading: float) -> Dictionary:
	var body := {
		"id": _next_id,
		"def": vehicle,
		"team": team,
		"alive": true,
		"pos": Point.copy(pos),
		"vel": {"x": 0.0, "y": 0.0},
		"heading": heading,
		"ang_vel": 0.0,
		"speed": 0.0,
		"legs": [],
		"down": {},
		"cmd": Command.idle(),
	}
	_next_id += 1
	body["legs"] = Gait.init_gait(vehicle, body)
	vehicles.append(body)
	return body


func step(cmds: Dictionary) -> void:
	events = []
	var dt := Clock.DT
	for vehicle in vehicles:
		if vehicle["alive"] and cmds.has(vehicle["id"]):
			vehicle["cmd"] = cmds[vehicle["id"]]
		else:
			vehicle["cmd"] = Command.idle()
		if str(vehicle["def"]["locomotion"]) == "static":
			continue
		var mods := Mob.of_vehicle(vehicle["def"], vehicle["down"], vehicle["alive"])
		Kin.step_body(vehicle["def"], vehicle, vehicle["cmd"], mods, dt)
	_collide()
	for vehicle in vehicles:
		var planted: Array = []
		Gait.step_gait(vehicle["def"], vehicle, vehicle["legs"], dt, planted, vehicle["down"], vehicle["alive"])
		for planted_event in planted:
			var tagged: Dictionary = planted_event.duplicate()
			tagged["vehicle"] = vehicle["id"]
			events.append(tagged)
	tick += 1


func _collide() -> void:
	Separate.resolve(vehicles, terrain, arena_w, arena_h)


func to_world(vehicle: Dictionary, local_pt: Dictionary) -> Dictionary:
	return Gait.to_world(vehicle, local_pt)


func state_hash() -> int:
	var h := Hash.begin()
	for vehicle in vehicles:
		h = _mix_point(h, vehicle["pos"])
		h = _mix_point(h, vehicle["vel"])
		h = Hash.mix_u32(h, _nano(vehicle["heading"]))
		h = Hash.mix_u32(h, _nano(vehicle["ang_vel"]))
		h = Hash.mix_u32(h, _nano(vehicle["speed"]))
		for leg in vehicle["legs"]:
			h = _mix_point(h, leg["foot"])
			h = Hash.mix_u32(h, _nano(leg["t"]))
			h = Hash.mix_u32(h, 1 if leg["stepping"] else 0)
	for obstacle in terrain.obstacles:
		if str(obstacle["def"]["kind"]) == "wall":
			h = Hash.mix_u32(h, _nano(obstacle["hp"]))
	h = Hash.mix_u32(h, tick)
	return h


func _mix_point(h: int, point: Dictionary) -> int:
	h = Hash.mix_u32(h, _nano(point["x"]))
	return Hash.mix_u32(h, _nano(point["y"]))


func _nano(value: float) -> int:
	return int(round(float(value) * 1.0e9))


