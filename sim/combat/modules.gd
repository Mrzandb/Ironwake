extends RefCounted
class_name SimModules

## Game_test@33f4be8 src/sim/combat/modules.ts.
## Structure and stun are separate. Destroyed and rebooting modules are not
## solid. A destroyed host destroys everything mounted on it. Core destruction
## kills the vehicle. Repair waits for a calm stretch, then restores half.
## mobility_of fills the down-set from is_working and uses SimMobility.

const Mob := preload("res://sim/movement/mobility.gd")


static func init_modules(vehicle: Dictionary) -> Dictionary:
	var out := {}
	for module in vehicle["modules"]:
		out[str(module["id"])] = {
			"armor": float(module["armor"]),
			"structure": float(module["structure"]),
			"stun": 0.0,
			"state": "NORMAL",
			"reboot": 0.0,
			"immune": 0.0,
			"last_stun_at": -INF,
		}
	return out


static func module_def(vehicle: Dictionary, id: String) -> Dictionary:
	for module in vehicle["def"]["modules"]:
		if str(module["id"]) == id:
			return module
	push_error("unknown module " + id)
	return {}


static func is_working(vehicle: Dictionary, id: String) -> bool:
	var modules: Dictionary = vehicle["modules"]
	if not modules.has(id):
		return false
	return str(modules[id]["state"]) == "NORMAL"


static func is_solid(vehicle: Dictionary, id: String) -> bool:
	return is_working(vehicle, id)


static func down_of(vehicle: Dictionary) -> Dictionary:
	var down := {}
	for module in vehicle["def"]["modules"]:
		var id := str(module["id"])
		if not is_working(vehicle, id):
			down[id] = true
	return down


static func power_ok(vehicle: Dictionary) -> bool:
	if not vehicle["alive"]:
		return false
	for module in vehicle["def"]["modules"]:
		if str(module["kind"]) == "power":
			return is_working(vehicle, str(module["id"]))
	return true


static func mobility_of(vehicle: Dictionary) -> Dictionary:
	return Mob.of_vehicle(vehicle["def"], down_of(vehicle), bool(vehicle["alive"]))


static func apply_damage(vehicle: Dictionary, module: Dictionary, damage: Dictionary, now: float, events: Array, rules: Dictionary) -> void:
	var id := str(module["id"])
	var rt: Dictionary = vehicle["modules"][id]
	if str(rt["state"]) != "NORMAL":
		return
	vehicle["calm"] = 0.0
	var erode := float(damage["erode"])
	if erode > 0.0:
		var floor_armor := float(module["armor"]) * float(rules["armorFloor"])
		rt["armor"] = maxf(floor_armor, float(rt["armor"]) - erode)
	var struct := float(damage["struct"])
	if struct > 0.0:
		rt["structure"] = float(rt["structure"]) - struct
		if float(rt["structure"]) <= 0.0:
			destroy_module(vehicle, module, events)
			return
	var stun := float(damage["stun"])
	if stun > 0.0 and module.has("stunMax") and str(rt["state"]) == "NORMAL" and float(rt["immune"]) <= 0.0:
		rt["stun"] = float(rt["stun"]) + stun
		rt["last_stun_at"] = now
		if float(rt["stun"]) >= float(module["stunMax"]):
			rt["state"] = "DISABLED"
			rt["reboot"] = float(rules["reboot"][str(vehicle["def"]["size"])])
			rt["stun"] = float(module["stunMax"])
			events.append({"t": "moduleState", "vehicle": vehicle["id"], "module": id, "to": "DISABLED"})


static func destroy_module(vehicle: Dictionary, module: Dictionary, events: Array) -> void:
	var id := str(module["id"])
	var rt: Dictionary = vehicle["modules"][id]
	if str(rt["state"]) == "DESTROYED":
		return
	rt["state"] = "DESTROYED"
	rt["structure"] = 0.0
	events.append({"t": "moduleState", "vehicle": vehicle["id"], "module": id, "to": "DESTROYED"})
	for child in vehicle["def"]["modules"]:
		if child.has("host") and str(child["host"]) == id:
			destroy_module(vehicle, child, events)
	if str(module["kind"]) == "core" and vehicle["alive"]:
		vehicle["alive"] = false
		events.append({"t": "vehicleDestroyed", "vehicle": vehicle["id"]})


static func repair_time(vehicle: Dictionary, rules: Dictionary) -> float:
	return float(rules["reboot"][str(vehicle["def"]["size"])]) * float(rules["repair"]["timeMul"])


static func can_repair(vehicle: Dictionary, module: Dictionary) -> bool:
	if not vehicle["alive"] or not module.has("stunMax"):
		return false
	var host := ""
	if module.has("host"):
		host = str(module["host"])
	while host != "":
		if str(vehicle["modules"][host]["state"]) == "DESTROYED":
			return false
		var host_def := module_def(vehicle, host)
		host = str(host_def["host"]) if host_def.has("host") else ""
	return true


static func tick_modules(vehicle: Dictionary, dt: float, now: float, events: Array, rules: Dictionary) -> void:
	vehicle["calm"] = float(vehicle["calm"]) + dt
	var needed := repair_time(vehicle, rules)
	for module in vehicle["def"]["modules"]:
		var id := str(module["id"])
		var rt: Dictionary = vehicle["modules"][id]
		if str(rt["state"]) == "DESTROYED":
			if float(vehicle["calm"]) >= needed and can_repair(vehicle, module):
				rt["state"] = "NORMAL"
				rt["structure"] = float(module["structure"]) * float(rules["repair"]["restore"])
				rt["armor"] = float(module["armor"]) * float(rules["repair"]["restore"])
				rt["stun"] = 0.0
				rt["reboot"] = 0.0
				rt["immune"] = float(rules["immunity"])
				events.append({
					"t": "moduleState",
					"vehicle": vehicle["id"],
					"module": id,
					"to": "NORMAL",
					"repaired": true,
				})
			continue
		if module.has("armorRegen") and str(rt["state"]) == "NORMAL" and float(rt["armor"]) < float(module["armor"]):
			rt["armor"] = minf(float(module["armor"]), float(rt["armor"]) + float(module["armorRegen"]) * dt)
		if float(rt["immune"]) > 0.0:
			rt["immune"] = maxf(0.0, float(rt["immune"]) - dt)
		if str(rt["state"]) == "DISABLED":
			rt["reboot"] = float(rt["reboot"]) - dt
			if float(rt["reboot"]) <= 0.0:
				rt["state"] = "NORMAL"
				rt["reboot"] = 0.0
				rt["stun"] = 0.0
				rt["immune"] = float(rules["immunity"])
				events.append({"t": "moduleState", "vehicle": vehicle["id"], "module": id, "to": "NORMAL"})
		elif float(rt["stun"]) > 0.0 and module.has("stunMax") and now - float(rt["last_stun_at"]) >= float(rules["stunDecayDelay"]):
			rt["stun"] = maxf(0.0, float(rt["stun"]) - float(module["stunMax"]) * float(rules["stunDecayRate"]) * dt)
