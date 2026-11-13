extends RefCounted
class_name SimWeapons

## Game_test@33f4be8 src/sim/combat/weapons.ts.
## Slots, dispersion, shells, lasers and missile launches. The same checks
## apply to a player command and to a later AI command.

const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Impact := preload("res://sim/combat/impact.gd")
const Sweep := preload("res://sim/combat/sweep.gd")
const Missiles := preload("res://sim/combat/missiles.gd")
const Target := preload("res://sim/combat/targeting.gd")
const Turret := preload("res://sim/combat/turret.gd")
const Slots := preload("res://sim/combat/slots.gd")
const Stats := preload("res://sim/stats/resolver.gd")


static func init_weapons(vehicle: Dictionary, table: Dictionary) -> Dictionary:
	var out := {}
	for module in vehicle["def"]["modules"]:
		if not module.has("weapon"):
			continue
		var weapon: Dictionary = table[str(module["weapon"])]
		var reload := 0.0
		var disp := 0.0
		if str(weapon["kind"]) == "missile":
			reload = float(weapon["reload"])
		elif str(weapon["kind"]) == "kinetic":
			disp = float(weapon["dispersion"]["base"])
		out[str(module["id"])] = {
			"reload": reload,
			"ammo": 0,
			"disp": disp,
			"last_angle": null,
			"heat": 0.0,
			"lockout": 0.0,
			"beaming": false,
			"aim_vehicle": null,
			"aim_module": null,
			"aim_part": 0,
			"aim_point": null,
			"retarget": 0.0,
			"in_arc": not module.has("turret"),
			"aim_err": PI if module.has("turret") else 0.0,
			"pending": 0,
			"pending_t": 0.0,
		}
	return out


static func lead_point(from: Dictionary, pos: Dictionary, vel: Dictionary, speed: float) -> Dictionary:
	var point := Point.copy(pos)
	for _i in 3:
		var flight := Point.distance(point, from) / speed
		point = {
			"x": float(pos["x"]) + float(vel["x"]) * flight,
			"y": float(pos["y"]) + float(vel["y"]) * flight,
		}
	return point


static func update_auto_aim(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, from: Dictionary, dt: float):
	var runtime: Dictionary = vehicle["weapons"][str(module["id"])]
	var range := Stats.stat(vehicle, "range", float(weapon["range"]), world.rules, {"module": str(module["id"]), "weapon": str(weapon["id"])})
	var target = Turret.turret_target(world, vehicle, module, range)
	if target == null:
		runtime["aim_vehicle"] = null
		runtime["aim_module"] = null
		runtime["aim_point"] = null
		return null
	runtime["retarget"] = float(runtime["retarget"]) - dt
	var lost := runtime["aim_module"] != null and not Modules.is_solid(target, str(runtime["aim_module"]))
	if runtime["aim_vehicle"] != target["id"] or float(runtime["retarget"]) <= 0.0 or lost:
		var pick = Target.pick_module(world, from, target, weapon)
		runtime["aim_module"] = str(pick["module"]["id"]) if pick != null else null
		runtime["aim_part"] = int(pick["part"]) if pick != null else 0
		runtime["aim_vehicle"] = target["id"]
		runtime["retarget"] = Target.RETARGET_INTERVAL
	var aimed = null
	if runtime["aim_module"] != null:
		for part in target["def"]["modules"]:
			if str(part["id"]) == str(runtime["aim_module"]):
				aimed = part
				break
	var center: Dictionary = target["pos"]
	if aimed != null:
		center = Target.module_center(world, target, aimed, int(runtime["aim_part"]))
	var speed := Stats.stat(vehicle, "shellSpeed", float(weapon["shellSpeed"]), world.rules, {"module": str(module["id"]), "weapon": str(weapon["id"])}, target)
	runtime["aim_point"] = lead_point(from, center, target["vel"], speed)
	return runtime["aim_point"]


static func step(world, vehicle: Dictionary, dt: float, rng, events: Array) -> void:
	var pose: Dictionary = world.pose(vehicle)
	var slots := Slots.weapon_slots(vehicle["def"], world.table)
	var selected = null
	if vehicle["slot"] >= 0 and int(vehicle["slot"]) < slots.size():
		selected = slots[int(vehicle["slot"])]
	var ripple: Dictionary = vehicle["ripple"]
	for key in ripple.keys():
		ripple[key] = maxf(0.0, float(ripple[key]) - dt)
	var fired_single := {}
	for module in vehicle["def"]["modules"]:
		if not module.has("weapon"):
			continue
		var weapon: Dictionary = world.table[str(module["weapon"])]
		var runtime: Dictionary = vehicle["weapons"][str(module["id"])]
		var working := bool(vehicle["alive"]) and Modules.is_working(vehicle, str(module["id"]))
		var angle := Pose.mount_angle(module, pose)
		var trigger := bool(module.get("primary", false)) and bool(vehicle["cmd"]["fire"]) and selected != null and str(selected["weapon"]) == str(weapon["id"])
		var laid: bool = (not module.has("turret")) or (bool(runtime["in_arc"]) and float(runtime["aim_err"]) <= Turret.fire_tolerance(module, world.rules))
		var foe = null
		if module.get("primary", false):
			foe = Target.locked_target(world, vehicle)
		elif runtime["aim_vehicle"] != null:
			for other in world.vehicles:
				if int(other["id"]) == int(runtime["aim_vehicle"]):
					foe = other
					break
		var scope := {"module": str(module["id"]), "weapon": str(weapon["id"])}
		var read := func(key: String, base: float) -> float:
			return Stats.stat(vehicle, key, base, world.rules, scope, foe)
		var kind := str(weapon["kind"])
		if kind == "laser":
			_step_laser(world, vehicle, module, weapon, runtime, pose, angle, dt, events, working, trigger, laid, read)
		elif kind == "missile":
			_step_missile(world, vehicle, module, weapon, runtime, pose, angle, dt, rng, events, working, trigger, fired_single, read)
		else:
			_step_kinetic(world, vehicle, module, weapon, runtime, pose, angle, dt, rng, events, working, trigger, laid, selected, fired_single, read)


static func step_projectiles(world, dt: float, events: Array) -> void:
	var keep: Array = []
	for projectile in world.projectiles:
		var speed := Point.hypot(float(projectile["vel"]["x"]), float(projectile["vel"]["y"]))
		var step_len := minf(speed * dt, float(projectile["range"]) - float(projectile["travelled"]))
		var scale := step_len / speed
		var end := {
			"x": float(projectile["pos"]["x"]) + float(projectile["vel"]["x"]) * scale,
			"y": float(projectile["pos"]["y"]) + float(projectile["vel"]["y"]) * scale,
		}
		var hit = Sweep.sweep(world, int(projectile["owner"]), int(projectile["team"]), projectile["pos"], end)
		var terrain_hit = world.terrain.segment_hit(projectile["pos"], end)
		if hit != null or terrain_hit != null:
			var weapon: Dictionary = world.table[str(projectile["weapon"])]
			var terrain_first := terrain_hit != null and (hit == null or float(terrain_hit["t"]) < float(hit["t"]))
			var t := float(terrain_hit["t"]) if terrain_first else float(hit["t"])
			var at := {
				"x": float(projectile["pos"]["x"]) + (float(end["x"]) - float(projectile["pos"]["x"])) * t,
				"y": float(projectile["pos"]["y"]) + (float(end["y"]) - float(projectile["pos"]["y"])) * t,
			}
			var ammo: Dictionary = weapon["ammo"][int(projectile["ammo"])]
			var source := {
				"owner": projectile["owner"],
				"team": projectile["team"],
				"weapon": str(weapon["id"]),
				"weaponName": str(weapon["name"]),
				"warhead": ammo,
				"dir": {"x": float(projectile["vel"]["x"]) / speed, "y": float(projectile["vel"]["y"]) / speed},
				"dist": float(projectile["travelled"]) + step_len * t,
				"penRange": projectile["range"],
			}
			if terrain_first:
				Impact.resolve_terrain(world, source, terrain_hit["obstacle"], at, events)
			else:
				Impact.resolve_impact(world, source, hit["v"], hit["m"], at, hit["normal"], events)
			continue
		projectile["pos"] = end
		projectile["travelled"] = float(projectile["travelled"]) + step_len
		if float(projectile["travelled"]) < float(projectile["range"]) - 1e-6:
			keep.append(projectile)
	world.projectiles = keep


static func _step_laser(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, runtime: Dictionary, pose: Dictionary, angle: float, dt: float, events: Array, working: bool, trigger: bool, laid: bool, read: Callable) -> void:
	runtime["beaming"] = false
	var heat: Dictionary = weapon["heat"]
	if float(runtime["lockout"]) > 0.0:
		runtime["lockout"] = maxf(0.0, float(runtime["lockout"]) - dt)
		runtime["heat"] = maxf(0.0, float(runtime["heat"]) - (float(heat["max"]) / float(heat["lockout"])) * dt)
		return
	var firing := trigger and working and Modules.power_ok(vehicle) and laid
	if not firing:
		runtime["heat"] = maxf(0.0, float(runtime["heat"]) - float(heat["cool"]) * dt)
		return
	runtime["heat"] = float(runtime["heat"]) + float(heat["perSec"]) * dt
	if float(runtime["heat"]) >= float(heat["max"]):
		runtime["heat"] = float(heat["max"])
		runtime["lockout"] = float(heat["lockout"])
		events.append({"t": "overheat", "vehicle": vehicle["id"], "module": str(module["id"])})
	runtime["beaming"] = true
	_fire_beam(world, vehicle, module, weapon, _muzzle(vehicle, module, pose), angle, dt, events, read)


static func _step_missile(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, runtime: Dictionary, pose: Dictionary, angle: float, dt: float, rng, events: Array, working: bool, trigger: bool, fired_single: Dictionary, read: Callable) -> void:
	if float(runtime["reload"]) > 0.0:
		runtime["reload"] = maxf(0.0, float(runtime["reload"]) - dt)
	var volley := maxi(1, int(weapon.get("volley", 1)))
	if int(runtime["pending"]) > 0:
		runtime["pending_t"] = float(runtime["pending_t"]) - dt
		if not working:
			runtime["pending"] = 0
		elif float(runtime["pending_t"]) <= 0.0:
			_launch_one(world, vehicle, module, weapon, pose, angle, volley, volley - int(runtime["pending"]), rng, events)
			_mark_single(vehicle, weapon, fired_single)
			runtime["pending"] = int(runtime["pending"]) - 1
			runtime["pending_t"] = Slots.RIPPLE
		return
	if not working or float(runtime["reload"]) > 0.0 or not trigger or not _single_ready(vehicle, weapon, fired_single):
		return
	_mark_single(vehicle, weapon, fired_single)
	runtime["reload"] = read.call("reload", float(weapon["reload"]))
	_launch_one(world, vehicle, module, weapon, pose, angle, volley, 0, rng, events)
	runtime["pending"] = volley - 1
	runtime["pending_t"] = Slots.RIPPLE


static func _launch_one(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, pose: Dictionary, angle: float, volley: int, index: int, rng, events: Array) -> void:
	var fan := 0.0
	if volley > 1:
		fan = Angle.deg(float(weapon.get("volleyFan", 0.0)) * (-1.0 + (2.0 * float(index)) / float(volley - 1)))
	var muzzle := _muzzle(vehicle, module, pose)
	var locked = Target.locked_target(world, vehicle)
	var target_id = locked["id"] if locked != null else null
	Missiles.launch(world, int(vehicle["id"]), str(module["id"]), weapon, muzzle, angle + fan, target_id, rng)
	events.append({
		"t": "fire",
		"vehicle": vehicle["id"],
		"module": str(module["id"]),
		"at": muzzle,
		"angle": angle + fan,
		"ammo": "MSL-" + str(weapon["warhead"]["kind"]),
	})


static func _step_kinetic(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, runtime: Dictionary, pose: Dictionary, angle: float, dt: float, rng, events: Array, working: bool, trigger: bool, laid: bool, selected, fired_single: Dictionary, read: Callable) -> void:
	if float(runtime["reload"]) > 0.0:
		runtime["reload"] = maxf(0.0, float(runtime["reload"]) - dt)
	if module.get("primary", false) and selected != null and str(selected["weapon"]) == str(weapon["id"]) and int(selected["ammo"]) != int(runtime["ammo"]) and int(selected["ammo"]) < weapon["ammo"].size():
		runtime["ammo"] = int(selected["ammo"])
		runtime["reload"] = read.call("reload", float(weapon["reload"]))
	var ang_vel := 0.0
	if runtime["last_angle"] != null:
		ang_vel = absf(Angle.delta(float(runtime["last_angle"]), angle)) / dt
	runtime["last_angle"] = angle
	var traverse := 0.0
	if module.has("turret"):
		traverse = Stats.stat(vehicle, "traverseRate", float(module["turret"]["traverseRate"]), world.rules, {"module": str(module["id"])})
	var ref_rate := Angle.deg(Stats.stat(vehicle, "turnRate", float(vehicle["def"]["move"]["turnRate"]), world.rules) + Stats.stat(vehicle, "crownRate", float(vehicle["def"]["crownRate"]), world.rules) + traverse)
	var speed_frac := minf(1.0, Point.hypot(float(vehicle["vel"]["x"]), float(vehicle["vel"]["y"])) / Stats.stat(vehicle, "maxSpeed", float(vehicle["def"]["move"]["maxSpeed"]), world.rules))
	var dispersion: Dictionary = weapon["dispersion"]
	var sigma: float = float(dispersion["sigmaRatio"]) if dispersion.has("sigmaRatio") else float(world.default_sigma)
	var spread_target: float = read.call("dispersion", float(dispersion["base"])) * (1.0 + float(dispersion["kV"]) * speed_frac + float(dispersion["kT"]) * minf(1.0, ang_vel / ref_rate))
	runtime["disp"] = float(runtime["disp"]) + (spread_target - float(runtime["disp"])) * minf(1.0, dt / float(dispersion["settle"]))
	if not working or float(runtime["reload"]) > 0.0:
		return
	var muzzle := _muzzle(vehicle, module, pose)
	var wants := false
	if module.get("primary", false):
		wants = trigger and laid and _single_ready(vehicle, weapon, fired_single)
	elif bool(vehicle["cmd"]["secondaries"]) and runtime["aim_point"] != null and laid:
		var aim: Dictionary = runtime["aim_point"]
		wants = Point.distance(aim, muzzle) <= read.call("range", float(weapon["range"])) and not world.terrain.blocks(muzzle, aim)
	if not wants:
		return
	var off: float = Angle.deg(rng.truncated_gauss(float(runtime["disp"]) * sigma, float(runtime["disp"])))
	var direction: float = angle + off
	var shell_speed: float = read.call("shellSpeed", float(weapon["shellSpeed"]))
	world.projectiles.append({
		"owner": vehicle["id"],
		"team": vehicle["team"],
		"module": str(module["id"]),
		"weapon": str(weapon["id"]),
		"ammo": int(runtime["ammo"]),
		"pos": muzzle,
		"vel": {"x": cos(direction) * shell_speed, "y": sin(direction) * shell_speed},
		"travelled": 0.0,
		"range": read.call("range", float(weapon["range"])),
	})
	runtime["reload"] = read.call("reload", float(weapon["reload"]))
	if module.get("primary", false):
		_mark_single(vehicle, weapon, fired_single)
	var ammo: Dictionary = weapon["ammo"][int(runtime["ammo"])]
	events.append({
		"t": "fire",
		"vehicle": vehicle["id"],
		"module": str(module["id"]),
		"at": muzzle,
		"angle": direction,
		"ammo": str(ammo["kind"]),
	})


static func _fire_beam(world, vehicle: Dictionary, module: Dictionary, weapon: Dictionary, from: Dictionary, angle: float, dt: float, events: Array, read: Callable) -> void:
	var beam_range: float = read.call("range", float(weapon["range"]))
	var to := {"x": float(from["x"]) + cos(angle) * beam_range, "y": float(from["y"]) + sin(angle) * beam_range}
	var hit = Sweep.sweep(world, int(vehicle["id"]), int(vehicle["team"]), from, to)
	var terrain_hit = world.terrain.segment_hit(from, to)
	if terrain_hit != null and (hit == null or float(terrain_hit["t"]) < float(hit["t"])):
		var at := {
			"x": float(from["x"]) + (float(to["x"]) - float(from["x"])) * float(terrain_hit["t"]),
			"y": float(from["y"]) + (float(to["y"]) - float(from["y"])) * float(terrain_hit["t"]),
		}
		world.beams.append({"owner": vehicle["id"], "module": str(module["id"]), "from": from, "to": at, "hit": true})
		var terrain_events: Array = []
		var dealt: float = float(weapon["structPerSec"]) * read.call("damage", 1.0) * float(world.rules["terrain"]["laserMul"]) * dt
		world.terrain.damage(terrain_hit["obstacle"], dealt, at, terrain_events, true)
		for item in terrain_events:
			events.append(item)
		return
	if hit == null:
		world.beams.append({"owner": vehicle["id"], "module": str(module["id"]), "from": from, "to": to, "hit": false})
		return
	var at := {
		"x": float(from["x"]) + (float(to["x"]) - float(from["x"])) * float(hit["t"]),
		"y": float(from["y"]) + (float(to["y"]) - float(from["y"])) * float(hit["t"]),
	}
	world.beams.append({"owner": vehicle["id"], "module": str(module["id"]), "from": from, "to": at, "hit": true})
	var victim: Dictionary = hit["v"]
	var part: Dictionary = hit["m"]
	var runtime: Dictionary = victim["modules"][str(part["id"])]
	var open := Stats.stat(victim, "armor", float(runtime["armor"]), world.rules, {"module": str(part["id"])}, vehicle) < float(weapon["gate"])
	var damage_mul := Stats.stat(vehicle, "damage", 1.0, world.rules, {"module": str(module["id"]), "weapon": str(weapon["id"])}, victim)
	var stun_mul := Stats.stat(vehicle, "stunDamage", 1.0, world.rules, {"module": str(module["id"]), "weapon": str(weapon["id"])}, victim)
	var struct := float(weapon["structPerSec"]) * damage_mul * dt if open else 0.0
	var module_events: Array = []
	Modules.apply_damage(victim, part, {
		"erode": float(weapon["erodePerSec"]) * dt,
		"struct": struct,
		"stun": float(weapon["stunPerSec"]) * stun_mul * dt,
	}, world.sim_time(), module_events, world.rules)
	events.append({"t": "beamDamage", "vehicle": victim["id"], "by": vehicle["id"], "struct": struct})
	for item in module_events:
		events.append(item)


static func _muzzle(vehicle: Dictionary, module: Dictionary, pose: Dictionary) -> Dictionary:
	var local := {"x": 0.0, "y": 0.0}
	if module.has("muzzle"):
		local = module["muzzle"]
	return Pose.mount_to_world(vehicle["def"], module, pose, local)


static func _single_ready(vehicle: Dictionary, weapon: Dictionary, fired_single: Dictionary) -> bool:
	if Slots.salvo_of(weapon) != "single":
		return true
	var weapon_id := str(weapon["id"])
	return float(vehicle["ripple"].get(weapon_id, 0.0)) <= 0.0 and not fired_single.has(weapon_id)


static func _mark_single(vehicle: Dictionary, weapon: Dictionary, fired_single: Dictionary) -> void:
	if Slots.salvo_of(weapon) != "single":
		return
	var weapon_id := str(weapon["id"])
	fired_single[weapon_id] = true
	vehicle["ripple"][weapon_id] = Slots.RIPPLE
