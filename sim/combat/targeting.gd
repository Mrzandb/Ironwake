extends RefCounted
class_name SimTarget

## Game_test@33f4be8 src/sim/combat/targeting.ts.
## Lock range is the longest primary weapon, measured to the target's edge.
## Exposed modules are the ones a ray from the muzzle hits first.

const Point := preload("res://sim/point.gd")
const Poly := preload("res://sim/geometry/poly.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Pen := preload("res://sim/combat/penetration.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Stats := preload("res://sim/stats/resolver.gd")

const LOCK_KEEP := 1.1
const RETARGET_INTERVAL := 0.5


static func lock_range(vehicle: Dictionary, table: Dictionary, rules: Dictionary) -> float:
	var best := 0.0
	for module in vehicle["def"]["modules"]:
		if not module.get("primary", false) or not module.has("weapon"):
			continue
		var weapon_id := str(module["weapon"])
		var weapon_range := float(table[weapon_id]["range"])
		var got := Stats.stat(vehicle, "range", weapon_range, rules, {"module": str(module["id"]), "weapon": weapon_id})
		best = maxf(best, got)
	return best


static func lock_distance(world, vehicle: Dictionary, target: Dictionary) -> float:
	return maxf(0.0, Point.distance(target["pos"], vehicle["pos"]) - world.radius_of(target))


static func can_lock(world, vehicle: Dictionary, target: Dictionary, keep: bool) -> bool:
	if not target["alive"] or int(target["team"]) == int(vehicle["team"]):
		return false
	var scale := LOCK_KEEP if keep else 1.0
	return lock_distance(world, vehicle, target) <= lock_range(vehicle, world.table, world.rules) * scale


static func locked_target(world, vehicle: Dictionary):
	if vehicle["lock"] == null:
		return null
	for other in world.vehicles:
		if int(other["id"]) != int(vehicle["lock"]):
			continue
		if other["alive"] and int(other["team"]) != int(vehicle["team"]):
			return other
		return null
	return null


static func engage_target(world, vehicle: Dictionary):
	var locked = locked_target(world, vehicle)
	if locked != null:
		return locked
	return world.nearest_enemy(vehicle)


static func module_center(world, target: Dictionary, module: Dictionary, part: int) -> Dictionary:
	var parts := Pose.module_world_parts(target["def"], module, world.pose(target))
	var index := part
	if index < 0 or index >= parts.size():
		index = 0
	return Poly.centroid(parts[index])


static func pick_module(world, muzzle: Dictionary, target: Dictionary, weapon: Dictionary):
	var pose: Dictionary = world.pose(target)
	var he = null
	for ammo in weapon["ammo"]:
		if str(ammo["kind"]) == "HE":
			he = ammo
			break
	var min_factor := float(world.rules["heMinFactor"])
	var best = null
	var best_score := -INF
	for module in target["def"]["modules"]:
		var id := str(module["id"])
		if not Modules.is_solid(target, id):
			continue
		var parts := Pose.module_world_parts(target["def"], module, pose)
		var part := -1
		for index in parts.size():
			var hit = Pose.first_hit(target["def"], pose, muzzle, Poly.centroid(parts[index]), _solid_filter(target))
			if hit != null and str(hit["module"]["id"]) == id:
				part = index
				break
		if part < 0:
			continue
		var center: Dictionary = Poly.centroid(parts[part])
		var soft := 0.0
		if he != null:
			soft = Pen.he_factor(float(he["hePen"]), float(target["modules"][id]["armor"]), min_factor)
		var score := float(_priority(target, module)) * 1000.0 + soft * 100.0 - Point.distance(center, muzzle) * 0.01
		if score > best_score:
			best_score = score
			best = {"module": module, "part": part}
	return best


static func _priority(target: Dictionary, module: Dictionary) -> int:
	var light := str(target["def"]["size"]) == "small" or str(target["def"]["locomotion"]) == "hover"
	var kind := str(module["kind"])
	if light:
		if kind == "locomotion":
			return 3
		if kind == "weapon":
			return 2
		return 1
	if kind == "weapon":
		return 3
	if kind == "locomotion":
		return 2
	return 1


static func _solid_filter(vehicle: Dictionary) -> Callable:
	return func(module: Dictionary) -> bool:
		return Modules.is_solid(vehicle, str(module["id"]))
