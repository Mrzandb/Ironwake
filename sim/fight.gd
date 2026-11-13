extends RefCounted
class_name SimFight

## Game_test World.step. Match, replay and AI call this; they do not step on their own.
## Order: command and lock, body, collide, crown and turrets, gait, weapons,
## projectiles, missiles, module timers, modifier timers.
## Events are the broadcast. hit carries damage and stun, moduleState to
## DISABLED is a paralysis, vehicleDestroyed is a kill. sinks receive each
## event after the tick is assembled. Purchase modifiers stay empty here.
## D29 coverage is not sampled on this loop.

const Clock := preload("res://sim/clock.gd")
const Command := preload("res://sim/command.gd")
const Hash := preload("res://sim/hash.gd")
const RngScript := preload("res://sim/rng.gd")
const Point := preload("res://sim/point.gd")
const Angle := preload("res://sim/angle.gd")
const Kin := preload("res://sim/movement/kinematics.gd")
const Gait := preload("res://sim/movement/gait.gd")
const Separate := preload("res://sim/movement/separate.gd")
const TerrainScript := preload("res://sim/terrain/terrain.gd")
const Validate := preload("res://sim/vehicle/validate.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Weapons := preload("res://sim/combat/weapons.gd")
const Missiles := preload("res://sim/combat/missiles.gd")
const Slots := preload("res://sim/combat/slots.gd")
const Stats := preload("res://sim/stats/resolver.gd")
const Target := preload("res://sim/combat/targeting.gd")
const Turret := preload("res://sim/combat/turret.gd")
const CatalogScript := preload("res://sim/data/catalog.gd")

var arena_w: float
var arena_h: float
var rules: Dictionary
var table: Dictionary
var default_sigma: float
var terrain
var vehicles: Array = []
var projectiles: Array = []
var missiles: Array = []
var beams: Array = []
var events: Array = []
var sinks: Array = []
var rng
var tick: int = 0
var root_seed: int = 1
var map_id = null
var arena: Dictionary = {}
var _next_id: int = 1
var _radii := {}


func _init(arena_size: Dictionary, seed: int = 1, map_def = null, catalog = null) -> void:
	arena_w = float(arena_size["w"])
	arena_h = float(arena_size["h"])
	arena = {"w": arena_w, "h": arena_h}
	root_seed = seed
	if typeof(map_def) == TYPE_DICTIONARY and map_def.has("id"):
		map_id = str(map_def["id"])
	if catalog == null:
		catalog = CatalogScript.new()
	rules = catalog.rules
	table = catalog.weapon_table["weapons"]
	default_sigma = float(catalog.weapon_table["defaultSigmaRatio"])
	terrain = TerrainScript.new(map_def, float(rules["terrain"]["wallHp"]))
	rng = RngScript.make_streams(seed)


func sim_time() -> float:
	return float(tick) * Clock.DT


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
		"crown_angle": 0.0,
		"turret_angles": {},
		"legs": [],
		"modules": Modules.init_modules(vehicle),
		"weapons": {},
		"lock": null,
		"cmd": Command.idle(),
		"mods": [],
		"purchase": [],
		"slot": 0,
		"ripple": {},
		"calm": 0.0,
	}
	_next_id += 1
	body["weapons"] = Weapons.init_weapons(body, table)
	body["legs"] = Gait.init_gait(vehicle, body)
	vehicles.append(body)
	return body


func despawn(vehicle: Dictionary) -> void:
	var id := int(vehicle["id"])
	var kept: Array = []
	for other in vehicles:
		if int(other["id"]) != id:
			kept.append(other)
	vehicles = kept


func place(vehicle: Dictionary, pos: Dictionary, heading: float) -> void:
	vehicle["pos"] = Point.copy(pos)
	vehicle["vel"] = {"x": 0.0, "y": 0.0}
	vehicle["heading"] = heading
	vehicle["ang_vel"] = 0.0
	vehicle["speed"] = 0.0
	vehicle["crown_angle"] = 0.0
	vehicle["turret_angles"] = {}
	vehicle["alive"] = true
	vehicle["modules"] = Modules.init_modules(vehicle["def"])
	vehicle["weapons"] = Weapons.init_weapons(vehicle, table)
	vehicle["legs"] = Gait.init_gait(vehicle["def"], vehicle)
	vehicle["lock"] = null
	vehicle["mods"] = []
	vehicle["purchase"] = []
	vehicle["slot"] = 0
	vehicle["ripple"] = {}
	vehicle["calm"] = 0.0
	var owner := int(vehicle["id"])
	var shells: Array = []
	for projectile in projectiles:
		if int(projectile["owner"]) != owner:
			shells.append(projectile)
	projectiles = shells
	var flying: Array = []
	for missile in missiles:
		if int(missile["owner"]) != owner:
			flying.append(missile)
	missiles = flying


func radius_of(vehicle: Dictionary) -> float:
	var key := str(vehicle["def"]["id"])
	if not _radii.has(key):
		_radii[key] = Validate.vehicle_radius(vehicle["def"])
	return float(_radii[key])


func pose(vehicle: Dictionary) -> Dictionary:
	return {
		"pos": vehicle["pos"],
		"chassis_angle": vehicle["heading"],
		"crown_angle": vehicle["crown_angle"],
		"turret_angles": vehicle["turret_angles"],
		"feet": Gait.feet_pose(vehicle, vehicle["legs"]),
	}


func gun_angle(vehicle: Dictionary) -> float:
	return float(vehicle["heading"]) + float(vehicle["crown_angle"])


static func tracking_error(gun: float, from: Dictionary, to: Dictionary) -> float:
	return absf(Angle.delta(gun, atan2(float(to["y"]) - float(from["y"]), float(to["x"]) - float(from["x"]))))


func to_world(vehicle: Dictionary, local_pt: Dictionary) -> Dictionary:
	return Gait.to_world(vehicle, local_pt)


## World.hash() text: six decimals, projectile count, missile pose, wall HP.
## Replay compares this string with itself. It is not the 1e-9 state_hash.
func replay_hash() -> String:
	var parts: Array = []
	for vehicle in vehicles:
		var nums: Array = [
			vehicle["pos"]["x"],
			vehicle["pos"]["y"],
			vehicle["heading"],
			vehicle["crown_angle"],
		]
		for leg in vehicle["legs"]:
			nums.append(leg["foot"]["x"])
			nums.append(leg["foot"]["y"])
		for module in vehicle["def"]["modules"]:
			var runtime: Dictionary = vehicle["modules"][str(module["id"])]
			nums.append(runtime["armor"])
			nums.append(runtime["structure"])
			nums.append(runtime["stun"])
		for mod in vehicle["mods"]:
			nums.append(mod["left"])
		for module in vehicle["def"]["modules"]:
			if not module.has("weapon"):
				continue
			var weapon_rt: Dictionary = vehicle["weapons"][str(module["id"])]
			nums.append(weapon_rt["pending"])
			nums.append(weapon_rt["pending_t"])
		nums.append(vehicle["slot"])
		nums.append(vehicle["calm"])
		var bits: PackedStringArray = []
		for number in nums:
			bits.append(_fixed(float(number), 6))
		parts.append(",".join(bits))
	var missile_bits: PackedStringArray = []
	for missile in missiles:
		missile_bits.append(",".join(PackedStringArray([
			_fixed(float(missile["pos"]["x"]), 6),
			_fixed(float(missile["pos"]["y"]), 6),
			_fixed(float(missile["heading"]), 6),
		])))
	var wall_bits: PackedStringArray = []
	for obstacle in terrain.obstacles:
		if str(obstacle["def"]["kind"]) == "wall":
			wall_bits.append(_fixed(float(obstacle["hp"]), 3))
	return "%s#%d#%s#%s" % ["|".join(parts), projectiles.size(), ";".join(missile_bits), ",".join(wall_bits)]


func nearest_enemy(vehicle: Dictionary):
	var best = null
	var best_d := INF
	for other in vehicles:
		if int(other["team"]) == int(vehicle["team"]) or not other["alive"]:
			continue
		var dist := Point.distance(other["pos"], vehicle["pos"])
		if dist < best_d:
			best = other
			best_d = dist
	return best


func step(cmds: Dictionary) -> void:
	events = []
	beams = []
	var dt := Clock.DT
	for vehicle in vehicles:
		if vehicle["alive"] and cmds.has(vehicle["id"]):
			vehicle["cmd"] = cmds[vehicle["id"]]
		else:
			vehicle["cmd"] = Command.idle()
		var requested = null
		if vehicle["cmd"]["lock"] != null:
			requested = _find(int(vehicle["cmd"]["lock"]))
		var keep := false
		if requested != null:
			keep = Target.can_lock(self, vehicle, requested, vehicle["lock"] != null and int(vehicle["lock"]) == int(requested["id"]))
		vehicle["lock"] = requested["id"] if keep else null
		vehicle["slot"] = Slots.clamp_slot(vehicle["def"], table, float(vehicle["cmd"]["slot"]))
		if str(vehicle["def"]["locomotion"]) == "static":
			continue
		var mobility := Modules.mobility_of(vehicle)
		var move: Dictionary = vehicle["def"]["move"]
		var max_speed := float(move["maxSpeed"])
		var turn_rate := float(move["turnRate"])
		mobility["speed_mul"] = float(mobility["speed_mul"]) * Stats.stat(vehicle, "maxSpeed", max_speed, rules) / max_speed
		mobility["turn_mul"] = float(mobility["turn_mul"]) * Stats.stat(vehicle, "turnRate", turn_rate, rules) / turn_rate
		Kin.step_body(vehicle["def"], vehicle, vehicle["cmd"], mobility, dt)
	Separate.resolve(vehicles, terrain, arena_w, arena_h)
	for vehicle in vehicles:
		_aim(vehicle, dt)
	for vehicle in vehicles:
		var planted: Array = []
		Gait.step_gait(vehicle["def"], vehicle, vehicle["legs"], dt, planted, Modules.down_of(vehicle), vehicle["alive"])
		for planted_event in planted:
			var tagged: Dictionary = planted_event.duplicate()
			tagged["vehicle"] = vehicle["id"]
			events.append(tagged)
	var combat: Array = []
	for vehicle in vehicles:
		Weapons.step(self, vehicle, dt, rng.spread, combat)
	Weapons.step_projectiles(self, dt, combat)
	Missiles.step(self, dt, rng.spread, combat)
	var module_events: Array = []
	for vehicle in vehicles:
		Modules.tick_modules(vehicle, dt, sim_time(), module_events, rules)
		Stats.tick_modifiers(vehicle, dt)
		if not vehicle["purchase"].is_empty():
			var saved: Array = vehicle["mods"]
			vehicle["mods"] = vehicle["purchase"]
			Stats.tick_modifiers(vehicle, dt)
			vehicle["purchase"] = vehicle["mods"]
			vehicle["mods"] = saved
	for item in combat:
		events.append(item)
	for item in module_events:
		events.append(item)
	for event in events:
		for sink in sinks:
			sink.call(event)
	tick += 1


func state_hash() -> int:
	var h := Hash.begin()
	for vehicle in vehicles:
		h = _mix_point(h, vehicle["pos"])
		h = _mix_point(h, vehicle["vel"])
		h = Hash.mix_u32(h, _nano(vehicle["heading"]))
		h = Hash.mix_u32(h, _nano(vehicle["crown_angle"]))
		h = Hash.mix_u32(h, 1 if vehicle["alive"] else 0)
		var angle_ids: Array = vehicle["turret_angles"].keys()
		angle_ids.sort()
		for module_id in angle_ids:
			h = Hash.mix_u32(h, Hash.fnv1a32(str(module_id)))
			h = Hash.mix_u32(h, _nano(vehicle["turret_angles"][module_id]))
		for module in vehicle["def"]["modules"]:
			var runtime: Dictionary = vehicle["modules"][str(module["id"])]
			h = Hash.mix_u32(h, _nano(runtime["armor"]))
			h = Hash.mix_u32(h, _nano(runtime["structure"]))
			h = Hash.mix_u32(h, _nano(runtime["stun"]))
			h = Hash.mix_u32(h, Hash.fnv1a32(str(runtime["state"])))
		for leg in vehicle["legs"]:
			h = _mix_point(h, leg["foot"])
	for projectile in projectiles:
		h = _mix_point(h, projectile["pos"])
		h = _mix_point(h, projectile["vel"])
		h = Hash.mix_u32(h, _nano(projectile["travelled"]))
	for missile in missiles:
		h = _mix_point(h, missile["pos"])
		h = Hash.mix_u32(h, _nano(missile["heading"]))
		h = Hash.mix_u32(h, _nano(missile["speed"]))
	for obstacle in terrain.obstacles:
		if str(obstacle["def"]["kind"]) == "wall":
			h = Hash.mix_u32(h, _nano(obstacle["hp"]))
	h = Hash.mix_u32(h, tick)
	return h


func _aim(vehicle: Dictionary, dt: float) -> void:
	if not vehicle["alive"]:
		return
	var blueprint: Dictionary = vehicle["def"]
	var aim = vehicle["cmd"]["aim"]
	if float(blueprint["crownRate"]) > 0.0 and aim != null and Modules.power_ok(vehicle):
		var pivot := Gait.to_world(vehicle, blueprint["crownPivot"])
		var want := atan2(float(aim["y"]) - float(pivot["y"]), float(aim["x"]) - float(pivot["x"])) - float(vehicle["heading"])
		var rate := Angle.deg(Stats.stat(vehicle, "crownRate", float(blueprint["crownRate"]), rules))
		vehicle["crown_angle"] = float(Angle.step_angle(float(vehicle["crown_angle"]), want, rate, dt)["angle"])
	var current := pose(vehicle)
	for module in blueprint["modules"]:
		if not module.has("turret"):
			continue
		var runtime = null
		if module.has("weapon"):
			runtime = vehicle["weapons"][str(module["id"])]
		if not Modules.is_working(vehicle, str(module["id"])):
			if runtime != null:
				runtime["in_arc"] = false
			continue
		var target = aim
		if not module.get("primary", false):
			var weapon = null
			if module.has("weapon"):
				weapon = table[str(module["weapon"])]
			var from := Pose.mount_to_world(blueprint, module, current, {"x": 0.0, "y": 0.0})
			if weapon != null and str(weapon["kind"]) == "kinetic":
				target = Weapons.update_auto_aim(self, vehicle, module, weapon, from, dt)
			else:
				var enemy = nearest_enemy(vehicle)
				target = enemy["pos"] if enemy != null else null
		var stepped: Dictionary = Turret.step_turret(vehicle, module, target, dt, rules)
		if runtime != null:
			runtime["in_arc"] = stepped["in_arc"]
			runtime["aim_err"] = stepped["err"]


func _find(id: int):
	for vehicle in vehicles:
		if int(vehicle["id"]) == id:
			return vehicle
	return null


func _mix_point(h: int, point: Dictionary) -> int:
	h = Hash.mix_u32(h, _nano(point["x"]))
	return Hash.mix_u32(h, _nano(point["y"]))


func _nano(value: float) -> int:
	return int(round(float(value) * 1.0e9))


static func _fixed(value: float, digits: int) -> String:
	var negative := value < 0.0
	var scale := 1.0
	for _i in digits:
		scale *= 10.0
	var scale_i := int(round(scale))
	var rounded := int(floor(absf(value) * scale + 0.5))
	var whole := int(float(rounded) / float(scale_i))
	var frac := rounded % scale_i
	if whole == 0 and frac == 0:
		negative = false
	var text := str(whole) + "." + str(frac).pad_zeros(digits)
	if negative:
		return "-" + text
	return text
