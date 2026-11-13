extends RefCounted
class_name SimSlots

## Game_test@33f4be8 src/sim/combat/slots.ts.
## Primary weapons group by weapon id. Kinetic ammo is one slot each.
## Guns and lasers come before missiles. Sort is stable.

const RIPPLE := 0.3


static func weapon_slots(vehicle: Dictionary, table: Dictionary) -> Array:
	var groups: Array = []
	for module in vehicle["modules"]:
		if not module.get("primary", false) or not module.has("weapon"):
			continue
		var weapon_id := str(module["weapon"])
		var found = null
		for group in groups:
			if str(group["weapon"]) == weapon_id:
				found = group
				break
		if found == null:
			groups.append({"weapon": weapon_id, "modules": [str(module["id"])]})
		else:
			found["modules"].append(str(module["id"]))
	_stable_by_rank(groups, table)
	var out: Array = []
	for group in groups:
		var weapon: Dictionary = table[str(group["weapon"])]
		var count := 1
		if str(weapon["kind"]) == "kinetic":
			count = weapon["ammo"].size()
		for ammo in count:
			out.append({
				"index": out.size(),
				"weapon": str(group["weapon"]),
				"kind": str(weapon["kind"]),
				"ammo": ammo,
				"modules": group["modules"],
			})
	return out


static func salvo_of(weapon: Dictionary) -> String:
	if weapon.has("salvo"):
		return str(weapon["salvo"])
	if str(weapon["kind"]) == "missile":
		return "single"
	return "all"


static func clamp_slot(vehicle: Dictionary, table: Dictionary, slot: float) -> int:
	var count := weapon_slots(vehicle, table).size()
	if count == 0:
		return 0
	return clampi(int(floor(slot)), 0, count - 1)


static func _rank(group: Dictionary, table: Dictionary) -> int:
	if str(table[str(group["weapon"])]["kind"]) == "missile":
		return 1
	return 0


static func _stable_by_rank(groups: Array, table: Dictionary) -> void:
	for i in range(1, groups.size()):
		var item = groups[i]
		var rank := _rank(item, table)
		var j := i
		while j > 0 and _rank(groups[j - 1], table) > rank:
			groups[j] = groups[j - 1]
			j -= 1
		groups[j] = item
