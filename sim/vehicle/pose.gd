extends RefCounted
class_name SimPose

## Game_test@33f4be8 src/sim/vehicle/pose.ts.
## world = chassis ∘ crown ∘ turret ∘ local parts.
## Without a foot pose, parts are the baked rings. A foot pose rebuilds that leg.

const Poly := preload("res://sim/geometry/poly.gd")
const Legs := preload("res://sim/vehicle/legs.gd")


static func zero() -> Dictionary:
	return {
		"pos": {"x": 0.0, "y": 0.0},
		"chassis_angle": 0.0,
		"crown_angle": 0.0,
		"turret_angles": {},
	}


static func module_local_parts(module: Dictionary, pose: Dictionary) -> Array:
	var feet = pose.get("feet", null)
	if module.has("leg") and typeof(feet) == TYPE_DICTIONARY and feet.has(module["id"]):
		var foot_pose: Dictionary = feet[module["id"]]
		var leg: Dictionary = module["leg"]
		return Legs.leg_parts(leg["hip"], foot_pose["foot"], leg["spec"], float(foot_pose["lift"]))
	return module["parts"]


static func _turret_angle(module: Dictionary, pose: Dictionary) -> float:
	var angles = pose.get("turret_angles", {})
	if typeof(angles) == TYPE_DICTIONARY and angles.has(module["id"]):
		return float(angles[module["id"]])
	return 0.0


static func _place(part: Array, vehicle: Dictionary, module: Dictionary, pose: Dictionary) -> Array:
	var placed := part
	if module.has("turret"):
		var turret: Dictionary = module["turret"]
		placed = Poly.transform_poly(placed, _turret_angle(module, pose), {"x": 0.0, "y": 0.0}, turret["pivot"])
	if str(module["ring"]) == "crown":
		placed = Poly.transform_poly(placed, float(pose["crown_angle"]), vehicle["crownPivot"], null)
	return Poly.transform_poly(placed, float(pose["chassis_angle"]), {"x": 0.0, "y": 0.0}, pose["pos"])


static func module_world_parts(vehicle: Dictionary, module: Dictionary, pose: Dictionary) -> Array:
	var out: Array = []
	for part in module_local_parts(module, pose):
		out.append(_place(part, vehicle, module, pose))
	return out


static func mount_to_world(vehicle: Dictionary, module: Dictionary, pose: Dictionary, point: Dictionary) -> Dictionary:
	var placed := _place([point], vehicle, module, pose)
	return placed[0]


static func mount_angle(module: Dictionary, pose: Dictionary) -> float:
	var angle := float(pose["chassis_angle"])
	if str(module["ring"]) == "crown":
		angle += float(pose["crown_angle"])
	if module.has("turret"):
		angle += _turret_angle(module, pose)
	return angle


## Smallest t along a→b. filter(module) false skips that module.
## Returns {module, t, normal} or null. normal may be null.
static func first_hit(vehicle: Dictionary, pose: Dictionary, a: Dictionary, b: Dictionary, filter: Callable = Callable()):
	var best = null
	for module in vehicle["modules"]:
		if filter.is_valid() and not filter.call(module):
			continue
		for part in module_world_parts(vehicle, module, pose):
			var hit = Poly.segment_vs_convex(a, b, part)
			if hit == null:
				continue
			if best == null or float(hit["t"]) < float(best["t"]):
				best = {"module": module, "t": hit["t"], "normal": hit["normal"]}
	return best
