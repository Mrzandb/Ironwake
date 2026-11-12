extends RefCounted
class_name SimValidate

## Game_test@33f4be8 src/sim/vehicle/validate.ts.
## Convex parts, host chains, and the D29 coverage ray fan.
## Static structures (bases) are not required to have a power module.
## The prototype's validateVehicle demanded one power module, and it was
## never called on bases. A base is a single core, so the coverage fan
## would also report the core as exposed. Callers skip bases.

const Poly := preload("res://sim/geometry/poly.gd")
const Pose := preload("res://sim/vehicle/pose.gd")


static func _count_kind(vehicle: Dictionary, kind: String) -> int:
	var n := 0
	for module in vehicle["modules"]:
		if str(module["kind"]) == kind:
			n += 1
	return n


static func _covers_core(module: Dictionary) -> bool:
	return not bool(module.get("movingPart", false))


static func vehicle_radius(vehicle: Dictionary) -> float:
	var pose := Pose.zero()
	var radius := 0.0
	for module in vehicle["modules"]:
		for part in Pose.module_world_parts(vehicle, module, pose):
			for vertex in part:
				radius = maxf(radius, sqrt(float(vertex["x"]) * float(vertex["x"]) + float(vertex["y"]) * float(vertex["y"])))
	return radius


static func probe_shell(vehicle: Dictionary, opts: Dictionary = {}) -> Array:
	var step := 1
	if opts.has("angle_step"):
		step = int(opts["angle_step"])
	var spacing := 3.0
	if opts.has("spacing"):
		spacing = float(opts["spacing"])
	var filter: Callable = func(module):
		return _covers_core(module)
	if opts.has("filter") and opts["filter"] is Callable and (opts["filter"] as Callable).is_valid():
		filter = opts["filter"]
	var radius := vehicle_radius(vehicle) + 10.0
	var pose := Pose.zero()
	var out: Array = []
	var deg := 0
	while deg < 360:
		var a := float(deg) * PI / 180.0
		var dx := cos(a)
		var dy := sin(a)
		var nx := -dy
		var ny := dx
		var s := -radius
		while s <= radius:
			var frm := {"x": -dx * radius + nx * s, "y": -dy * radius + ny * s}
			var to := {"x": dx * radius + nx * s, "y": dy * radius + ny * s}
			var hit = Pose.first_hit(vehicle, pose, frm, to, filter)
			if hit != null:
				var t := float(hit["t"])
				out.append({
					"from": frm,
					"hit": {
						"x": float(frm["x"]) + (float(to["x"]) - float(frm["x"])) * t,
						"y": float(frm["y"]) + (float(to["y"]) - float(frm["y"])) * t,
					},
					"module": hit["module"],
				})
			s += spacing
		deg += step
	return out


static func _fixed1(value: float) -> String:
	var scaled := value * 10.0
	var rounded: float = roundf(scaled)
	return String.num(rounded / 10.0, 1)


static func validate_vehicle(vehicle: Dictionary) -> Dictionary:
	var errors: Array = []
	var ids := {}
	for module in vehicle["modules"]:
		var module_id := str(module["id"])
		if ids.has(module_id):
			errors.append("模块 id 重复")
		ids[module_id] = module
	if _count_kind(vehicle, "core") != 1:
		errors.append("核心舱必须恰好 1 个")
	if str(vehicle.get("locomotion", "")) != "static":
		if _count_kind(vehicle, "power") != 1:
			errors.append("动力舱必须恰好 1 个")
	for module in vehicle["modules"]:
		var module_id := str(module["id"])
		var parts: Array = module["parts"]
		for i in parts.size():
			if not Poly.is_convex(parts[i]):
				errors.append("%s 第 %d 块不是严格凸多边形" % [module_id, i])
		if module.has("host") and not ids.has(str(module["host"])):
			errors.append("%s 的宿主 %s 不存在" % [module_id, str(module["host"])])
		if str(module["kind"]) == "locomotion" and str(module["ring"]) != "chassis":
			errors.append("%s：机械腿必须固定在底盘（D32）" % module_id)
	for module in vehicle["modules"]:
		var seen := {}
		var current = module
		while current != null and current.has("host"):
			var current_id := str(current["id"])
			if seen.has(current_id):
				errors.append("%s 的宿主链有环" % str(module["id"]))
				break
			seen[current_id] = true
			current = ids.get(str(current["host"]), null)
	if errors.is_empty():
		var exposed := 0
		var sample = null
		for probe in probe_shell(vehicle):
			var kind := str(probe["module"]["kind"])
			if kind == "core" or kind == "power":
				exposed += 1
				if sample == null:
					sample = probe
		if exposed > 0:
			errors.append(
				"包覆失败（D29）：%d 条射线首先命中 %s，例如命中点 (%s, %s)"
				% [exposed, str(sample["module"]["label"]), _fixed1(float(sample["hit"]["x"])), _fixed1(float(sample["hit"]["y"]))]
			)
	return {"errors": errors}
