extends RefCounted
class_name SimMobility

## Movement-side stub of Game_test mobilityOf (src/sim/combat/modules.ts).
## Module timers, damage and host-cascade destruction are not ported.
## Callers pass `down`: module ids that are not working (destroyed or disabled).
## A missing power module counts as powered, matching powerOk. Bases have none.
## Combat should fill `down` from module state later. Do not reimplement damage here.


static func of_vehicle(vehicle: Dictionary, down: Dictionary, alive: bool = true) -> Dictionary:
	if not alive:
		return {"speed_mul": 0.0, "turn_mul": 0.0, "turn_bias": 0.0}
	var found_power := false
	var power_id := ""
	var locos: Array = []
	for module in vehicle["modules"]:
		if str(module["kind"]) == "power":
			found_power = true
			power_id = str(module["id"])
		elif str(module["kind"]) == "locomotion":
			locos.append(module)
	if found_power and down.has(power_id):
		return {"speed_mul": 0.0, "turn_mul": 0.0, "turn_bias": 0.0}
	if locos.is_empty():
		return {"speed_mul": 1.0, "turn_mul": 1.0, "turn_bias": 0.0}
	var penalty := 0.0
	var bias := 0.0
	var working := 0
	for side in [-1, 1]:
		var mine: Array = []
		for module in locos:
			if _side(module) == side:
				mine.append(module)
		if mine.is_empty():
			continue
		var ok := 0
		for module in mine:
			if not down.has(str(module["id"])):
				ok += 1
		working += ok
		var lost := mine.size() - ok
		if lost == 0:
			continue
		if mine.size() >= 2:
			penalty += 0.75 if ok == 0 else 0.25 * float(lost)
		else:
			penalty += 0.5
		bias += 0.25 * float(side) * float(lost)
	if working == 0:
		return {"speed_mul": 0.0, "turn_mul": 0.0, "turn_bias": 0.0}
	return {"speed_mul": maxf(0.0, 1.0 - penalty), "turn_mul": 1.0, "turn_bias": bias}


static func _side(module: Dictionary) -> int:
	if module.has("leg"):
		return int(signf(float(module["leg"]["hip"]["y"])))
	var parts: Array = module["parts"]
	if parts.is_empty():
		return 0
	var sum := 0.0
	for vertex in parts[0]:
		sum += float(vertex["y"])
	return int(signf(sum))
