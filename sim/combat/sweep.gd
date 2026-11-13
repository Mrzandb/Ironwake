extends RefCounted
class_name SimSweep

## Nearest solid hit along a segment. Same team as the shooter is transparent.
## Terrain is not included; callers compare segment_hit themselves.

const Point := preload("res://sim/point.gd")
const Pose := preload("res://sim/vehicle/pose.gd")
const Modules := preload("res://sim/combat/modules.gd")


static func sweep(world, owner: int, team: int, a: Dictionary, b: Dictionary):
	var best = null
	for other in world.vehicles:
		if int(other["id"]) == owner or int(other["team"]) == team:
			continue
		if _point_seg_dist(other["pos"], a, b) > world.radius_of(other) + 1.0:
			continue
		var hit = Pose.first_hit(other["def"], world.pose(other), a, b, _solid_filter(other))
		if hit != null and (best == null or float(hit["t"]) < float(best["t"])):
			best = {"v": other, "m": hit["module"], "t": hit["t"], "normal": hit["normal"]}
	return best


static func _point_seg_dist(point: Dictionary, a: Dictionary, b: Dictionary) -> float:
	var ex := float(b["x"]) - float(a["x"])
	var ey := float(b["y"]) - float(a["y"])
	var l2 := ex * ex + ey * ey
	if l2 == 0.0:
		l2 = 1e-12
	var t := clampf(((float(point["x"]) - float(a["x"])) * ex + (float(point["y"]) - float(a["y"])) * ey) / l2, 0.0, 1.0)
	return Point.hypot(float(point["x"]) - (float(a["x"]) + ex * t), float(point["y"]) - (float(a["y"]) + ey * t))


static func _solid_filter(vehicle: Dictionary) -> Callable:
	return func(module: Dictionary) -> bool:
		return Modules.is_solid(vehicle, str(module["id"]))
