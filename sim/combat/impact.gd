extends RefCounted
class_name SimImpact

## Game_test@33f4be8 src/sim/combat/impact.ts.
## AP, HE and EMP share one resolver. Splash only hits exposed modules.
## Wall HE and laser multipliers are applied by the caller before terrain.damage.
## HE on terrain is multiplied here, because this is the impact caller.

const Point := preload("res://sim/point.gd")
const Poly := preload("res://sim/geometry/poly.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Pen := preload("res://sim/combat/penetration.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Stats := preload("res://sim/stats/resolver.gd")
const Angle := preload("res://sim/angle.gd")


static func resolve_impact(world, source: Dictionary, vehicle: Dictionary, module: Dictionary, at: Dictionary, normal, events: Array) -> void:
	var raw: Dictionary = source["warhead"]
	var runtime: Dictionary = vehicle["modules"][str(module["id"])]
	var module_events: Array = []
	var shooter := _shooter(world, int(source["owner"]))
	var scaled := func(key: String, base: float) -> float:
		return Stats.stat(shooter, key, base, world.rules, {"weapon": str(source.get("weapon", ""))}, vehicle)
	var warhead := _boosted(raw, scaled)
	var armor_of := func(owner: Dictionary, part: Dictionary, rt: Dictionary) -> float:
		return Stats.stat(owner, "armor", float(rt["armor"]), world.rules, {"module": str(part["id"])}, shooter)
	var base := {
		"shooter": _shooter_name(world, int(source["owner"])),
		"weapon": str(source["weaponName"]),
		"ammo": str(warhead["kind"]),
		"dist": float(source["dist"]),
	}
	var kind := str(warhead["kind"])
	if kind == "AP":
		var cos_t := 1.0
		if normal != null:
			cos_t = clampf(-(float(source["dir"]["x"]) * float(normal["x"]) + float(source["dir"]["y"]) * float(normal["y"])), 0.0, 1.0)
		var theta := acos(cos_t)
		var pen_range = source["penRange"]
		var pen := float(warhead["p0"])
		if not warhead.get("fixedPen", false) and pen_range != null:
			pen = Pen.at_distance(float(warhead["p0"]), float(pen_range), float(source["dist"]))
		var armor_before: float = armor_of.call(vehicle, module, runtime)
		var result := Pen.resolve_hit(pen, armor_before, theta, float(world.rules["overmatchK"]))
		var eff := Pen.effective_armor(armor_before, theta)
		var penetrated := result == "pen" or result == "overmatch"
		var struct := 0.0
		if penetrated:
			var denom: float = armor_before if result == "overmatch" else eff
			struct = Pen.ap_pen_damage(float(warhead["damage"]), pen, denom)
		var erode := 0.0
		if result == "nonpen":
			erode = float(warhead["erodeNonpen"])
		elif result == "ricochet":
			erode = float(warhead["erodeRicochet"])
		_hit(world, events, module_events, vehicle, module, at, source, base, result, {"struct": struct, "stun": struct * float(world.rules["apStunMul"]), "erode": erode}, {
			"pen": pen,
			"thetaDeg": Angle.to_deg(theta),
			"effArmor": eff,
		})
	elif kind == "HE":
		var struct := float(warhead["damage"]) * Pen.he_factor(float(warhead["hePen"]), armor_of.call(vehicle, module, runtime), float(world.rules["heMinFactor"]))
		_hit(world, events, module_events, vehicle, module, at, source, base, "he", {"struct": struct, "stun": struct * float(world.rules["heStunMul"]), "erode": float(warhead["erode"])}, {"pen": float(warhead["hePen"])})
		events.append({"t": "blast", "kind": "HE", "at": at, "radius": float(warhead["radius"])})
		_area(world, source, at, float(warhead["radius"]), int(vehicle["id"]), str(module["id"]), events, module_events, func(owner: Dictionary, part: Dictionary, rt: Dictionary, fall: float):
			var splash := float(warhead["damage"]) * Pen.he_factor(float(warhead["hePen"]), armor_of.call(owner, part, rt), float(world.rules["heMinFactor"])) * fall
			if splash <= 0.0:
				return null
			return {"struct": splash, "stun": splash * float(world.rules["heStunMul"]), "erode": 0.0}
		)
	else:
		_hit(world, events, module_events, vehicle, module, at, source, base, "emp", {"struct": float(warhead["damage"]), "stun": float(warhead["stun"]), "erode": 0.0}, {})
		events.append({"t": "blast", "kind": "EMP", "at": at, "radius": float(warhead["radius"])})
		_area(world, source, at, float(warhead["radius"]), int(vehicle["id"]), str(module["id"]), events, module_events, func(_owner: Dictionary, _part: Dictionary, _rt: Dictionary, fall: float):
			return {"struct": float(warhead["damage"]) * fall, "stun": float(warhead["stun"]) * fall, "erode": 0.0}
		)
	for item in module_events:
		events.append(item)


static func resolve_terrain(world, source: Dictionary, obstacle: Dictionary, at: Dictionary, events: Array) -> void:
	var shooter := _shooter(world, int(source["owner"]))
	var scaled := func(key: String, base: float) -> float:
		return Stats.stat(shooter, key, base, world.rules, {"weapon": str(source.get("weapon", ""))}, null)
	var warhead := _boosted(source["warhead"], scaled)
	var armor_of := func(owner: Dictionary, part: Dictionary, rt: Dictionary) -> float:
		return Stats.stat(owner, "armor", float(rt["armor"]), world.rules, {"module": str(part["id"])}, shooter)
	var kind := str(warhead["kind"])
	var amount := 0.0
	if kind == "AP":
		amount = float(warhead["damage"])
	elif kind == "HE":
		amount = float(warhead["damage"]) * float(world.rules["terrain"]["heMul"])
	var terrain_events: Array = []
	world.terrain.damage(obstacle, amount, at, terrain_events)
	for item in terrain_events:
		events.append(item)
	var module_events: Array = []
	if kind == "HE":
		events.append({"t": "blast", "kind": "HE", "at": at, "radius": float(warhead["radius"])})
		_area(world, source, at, float(warhead["radius"]), -1, "", events, module_events, func(owner: Dictionary, part: Dictionary, rt: Dictionary, fall: float):
			var splash := float(warhead["damage"]) * Pen.he_factor(float(warhead["hePen"]), armor_of.call(owner, part, rt), float(world.rules["heMinFactor"])) * fall
			if splash <= 0.0:
				return null
			return {"struct": splash, "stun": splash * float(world.rules["heStunMul"]), "erode": 0.0}
		)
	elif kind == "EMP":
		events.append({"t": "blast", "kind": "EMP", "at": at, "radius": float(warhead["radius"])})
		_area(world, source, at, float(warhead["radius"]), -1, "", events, module_events, func(_owner: Dictionary, _part: Dictionary, _rt: Dictionary, fall: float):
			return {"struct": float(warhead["damage"]) * fall, "stun": float(warhead["stun"]) * fall, "erode": 0.0}
		)
	for item in module_events:
		events.append(item)


static func _hit(world, events: Array, module_events: Array, vehicle: Dictionary, module: Dictionary, at: Dictionary, source: Dictionary, base: Dictionary, result: String, damage: Dictionary, extra: Dictionary) -> void:
	Modules.apply_damage(vehicle, module, damage, world.sim_time(), module_events, world.rules)
	var log := base.duplicate(true)
	log["pen"] = null
	log["thetaDeg"] = null
	log["effArmor"] = null
	log["result"] = result
	log["struct"] = float(damage["struct"])
	log["stun"] = float(damage["stun"])
	log["erode"] = float(damage["erode"])
	for key in extra.keys():
		log[key] = extra[key]
	var runtime: Dictionary = vehicle["modules"][str(module["id"])]
	log["target"] = str(vehicle["def"]["name"])
	log["module"] = str(module["label"])
	log["armorAfter"] = float(runtime["armor"])
	log["structAfter"] = float(runtime["structure"])
	log["structMax"] = float(module["structure"])
	log["stateAfter"] = str(runtime["state"])
	events.append({
		"t": "hit",
		"by": int(source["owner"]),
		"vehicle": vehicle["id"],
		"at": at,
		"result": result,
		"log": log,
	})


static func _area(world, source: Dictionary, at: Dictionary, radius: float, direct_vehicle: int, direct_module: String, events: Array, module_events: Array, effect: Callable) -> void:
	var origin := {
		"x": float(at["x"]) - float(source["dir"]["x"]) * 1.5,
		"y": float(at["y"]) - float(source["dir"]["y"]) * 1.5,
	}
	var team = source.get("team", null)
	if team == null:
		var owner = _find(world, int(source["owner"]))
		team = owner["team"] if owner != null else null
	for other in world.vehicles:
		if int(other["id"]) == int(source["owner"]):
			continue
		if team != null and int(other["team"]) == int(team):
			continue
		if Point.distance(other["pos"], at) > world.radius_of(other) + radius:
			continue
		var pose: Dictionary = world.pose(other)
		for module in other["def"]["modules"]:
			var id := str(module["id"])
			if int(other["id"]) == direct_vehicle and id == direct_module:
				continue
			if not Modules.is_solid(other, id):
				continue
			var parts := Pose.module_world_parts(other["def"], module, pose)
			var dist := INF
			for part in parts:
				dist = minf(dist, Poly.distance_to_convex(origin, part))
			if dist >= radius:
				continue
			var center: Dictionary = Poly.centroid(parts[0])
			var first = Pose.first_hit(other["def"], pose, origin, center, _solid_filter(other))
			if first == null or str(first["module"]["id"]) != id:
				continue
			var dealt = effect.call(other, module, other["modules"][id], 1.0 - dist / radius)
			if dealt == null:
				continue
			Modules.apply_damage(other, module, dealt, world.sim_time(), module_events, world.rules)
			var runtime: Dictionary = other["modules"][id]
			var pen = null
			if str(source["warhead"]["kind"]) == "HE":
				pen = float(source["warhead"]["hePen"])
			events.append({
				"t": "hit",
				"by": int(source["owner"]),
				"vehicle": other["id"],
				"at": center,
				"result": "splash",
				"log": {
					"shooter": _shooter_name(world, int(source["owner"])),
					"weapon": str(source["weaponName"]),
					"ammo": str(source["warhead"]["kind"]),
					"dist": float(source["dist"]),
					"pen": pen,
					"thetaDeg": null,
					"effArmor": null,
					"result": "splash",
					"struct": float(dealt["struct"]),
					"stun": float(dealt["stun"]),
					"erode": 0.0,
					"target": str(other["def"]["name"]),
					"module": str(module["label"]),
					"armorAfter": float(runtime["armor"]),
					"structAfter": float(runtime["structure"]),
					"structMax": float(module["structure"]),
					"stateAfter": str(runtime["state"]),
				},
			})


static func _boosted(warhead: Dictionary, scaled: Callable) -> Dictionary:
	var copy: Dictionary = warhead.duplicate(true)
	var kind := str(copy["kind"])
	if kind == "AP":
		copy["p0"] = scaled.call("penetration", float(copy["p0"]))
		copy["damage"] = scaled.call("damage", float(copy["damage"]))
	elif kind == "HE":
		copy["hePen"] = scaled.call("penetration", float(copy["hePen"]))
		copy["damage"] = scaled.call("damage", float(copy["damage"]))
	else:
		copy["damage"] = scaled.call("damage", float(copy["damage"]))
		copy["stun"] = scaled.call("stunDamage", float(copy["stun"]))
	return copy


static func _shooter(world, id: int) -> Dictionary:
	var found = _find(world, id)
	if found == null:
		return {"mods": []}
	return found


static func _shooter_name(world, id: int) -> String:
	var found = _find(world, id)
	if found == null:
		return "?"
	return str(found["def"]["name"])


static func _find(world, id: int):
	for vehicle in world.vehicles:
		if int(vehicle["id"]) == id:
			return vehicle
	return null


static func _solid_filter(vehicle: Dictionary) -> Callable:
	return func(module: Dictionary) -> bool:
		return Modules.is_solid(vehicle, str(module["id"]))
