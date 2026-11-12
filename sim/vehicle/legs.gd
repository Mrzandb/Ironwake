extends RefCounted
class_name SimLegs

## Game_test@33f4be8 src/sim/vehicle/legs.ts.
## Two-bone IK. Collision polygons are rebuilt from (hip, foot) so a moving
## leg stays in the sim. Part order matches the prototype:
## 0 hip, 1 thigh strut, 2 knee, 3 shin strut, 4 foot, 5 thigh plate,
## 6 shin guard, 7 kneepad.

const Shape := preload("res://sim/vehicle/shapes.gd")


static func solve_knee(hip: Dictionary, foot: Dictionary, upper: float, lower: float, bend: float) -> Dictionary:
	var dx := float(foot["x"]) - float(hip["x"])
	var dy := float(foot["y"]) - float(hip["y"])
	var raw := sqrt(dx * dx + dy * dy)
	var reach := minf(maxf(raw, absf(upper - lower) + 1e-3), upper + lower - 1e-3)
	var denom := raw if raw != 0.0 else 1.0
	var ux := dx / denom
	var uy := dy / denom
	var along := (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper * upper - along * along))
	return {
		"x": float(hip["x"]) + ux * along - uy * height * bend,
		"y": float(hip["y"]) + uy * along + ux * height * bend,
	}


static func _lerp(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"x": float(a["x"]) + (float(b["x"]) - float(a["x"])) * t,
		"y": float(a["y"]) + (float(b["y"]) - float(a["y"])) * t,
	}


static func _ang_deg(a: Dictionary, b: Dictionary) -> float:
	return atan2(float(b["y"]) - float(a["y"]), float(b["x"]) - float(a["x"])) * 180.0 / PI


static func leg_parts(hip: Dictionary, foot: Dictionary, spec: Dictionary, lift: float = 0.0) -> Array:
	var upper := float(spec["upper"])
	var lower := float(spec["lower"])
	var knee := solve_knee(hip, foot, upper, lower, float(spec["bend"]))
	var a_up := _ang_deg(hip, knee)
	var a_lo := _ang_deg(knee, foot)
	var foot_ang := _ang_deg(hip, foot)
	var foot_spec: Dictionary = spec["foot"]
	var foot_len := float(foot_spec["len"])
	var foot_wid := float(foot_spec["wid"])
	var upper_w: Array = spec["upperWidth"]
	var lower_w: Array = spec["lowerWidth"]
	var thigh := float(spec["thighPlate"])
	var shin := float(spec["shinGuard"])
	var scale := 1.0 + 0.14 * lift
	return [
		Shape.regular(hip, float(spec["hipRadius"]), 6, foot_ang),
		Shape.strut(hip, knee, float(upper_w[0]), float(upper_w[1])),
		Shape.regular(knee, float(spec["kneeRadius"]), 6, a_up),
		Shape.strut(knee, foot, float(lower_w[0]), float(lower_w[1])),
		Shape.chamfer_rect(foot, foot_len * scale, foot_wid * scale, foot_ang, foot_wid * 0.28),
		Shape.chamfer_rect(_lerp(hip, knee, 0.55), upper * 0.6, thigh, a_up, thigh * 0.22),
		Shape.chamfer_rect(_lerp(knee, foot, 0.45), lower * 0.56, shin, a_lo, shin * 0.2),
		Shape.regular(knee, float(spec["kneeRadius"]) + 5.0, 6, a_up + 30.0),
	]
