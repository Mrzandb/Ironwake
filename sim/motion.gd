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


func _collide() -> void:
	var count := vehicles.size()
	for i in count:
		for j in range(i + 1, count):
			var a: Dictionary = vehicles[i]
			var b: Dictionary = vehicles[j]
			var dx := float(b["pos"]["x"]) - float(a["pos"]["x"])
			var dy := float(b["pos"]["y"]) - float(a["pos"]["y"])
			var dist := Point.hypot(dx, dy)
			if dist == 0.0:
				dist = 1e-6
			var ra := float(a["def"]["collisionRadius"])
			var rb := float(b["def"]["collisionRadius"])
			var overlap := ra + rb - dist
			if overlap <= 0.0:
				continue
			var a_static := str(a["def"]["locomotion"]) == "static"
			var b_static := str(b["def"]["locomotion"]) == "static"
			if a_static and b_static:
				continue
			var nx := dx / dist
			var ny := dy / dist
			var wa := rb / (ra + rb)
			if a_static:
				wa = 0.0
			elif b_static:
				wa = 1.0
			a["pos"] = {
				"x": float(a["pos"]["x"]) - nx * overlap * wa,
				"y": float(a["pos"]["y"]) - ny * overlap * wa,
			}
			b["pos"] = {
				"x": float(b["pos"]["x"]) + nx * overlap * (1.0 - wa),
				"y": float(b["pos"]["y"]) + ny * overlap * (1.0 - wa),
			}
			_clip_apart(a, nx, ny, 1.0)
			_clip_apart(b, nx, ny, -1.0)
	for vehicle in vehicles:
		var radius := float(vehicle["def"]["collisionRadius"])
		if str(vehicle["def"]["locomotion"]) != "static":
			for _k in 3:
				var hit = terrain.push_circle(vehicle["pos"], radius)
				if hit == null:
					break
				vehicle["pos"] = hit["pos"]
				var nx := float(hit["n"]["x"])
				var ny := float(hit["n"]["y"])
				var vn := float(vehicle["vel"]["x"]) * nx + float(vehicle["vel"]["y"]) * ny
				if vn < 0.0:
					vehicle["vel"] = {
						"x": float(vehicle["vel"]["x"]) - nx * vn,
						"y": float(vehicle["vel"]["y"]) - ny * vn,
					}
		var x := clampf(float(vehicle["pos"]["x"]), radius, arena_w - radius)
		var y := clampf(float(vehicle["pos"]["y"]), radius, arena_h - radius)
		var vx := float(vehicle["vel"]["x"])
		var vy := float(vehicle["vel"]["y"])
		if x != float(vehicle["pos"]["x"]):
			vx = 0.0
		if y != float(vehicle["pos"]["y"]):
			vy = 0.0
		vehicle["vel"] = {"x": vx, "y": vy}
		vehicle["pos"] = {"x": x, "y": y}


func _clip_apart(vehicle: Dictionary, nx: float, ny: float, side: float) -> void:
	var vn := (float(vehicle["vel"]["x"]) * nx + float(vehicle["vel"]["y"]) * ny) * side
	if vn > 0.0:
		vehicle["vel"] = {
			"x": float(vehicle["vel"]["x"]) - nx * vn * side,
			"y": float(vehicle["vel"]["y"]) - ny * vn * side,
		}
