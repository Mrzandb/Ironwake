extends RefCounted
class_name SimAngle

## Game_test@33f4be8 src/core/math/angle.ts.
## +X right, +Y down, 0 rad faces +X, clockwise is positive.
## wrap_signed matches wrapAngle: [-PI, PI). +PI and -PI both land on -PI.


const DEG := PI / 180.0


static func deg(degrees: float) -> float:
	return degrees * DEG


static func to_deg(radians: float) -> float:
	return radians / DEG


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func clamp_value(v: float, lo: float, hi: float) -> float:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


static func wrap_signed(radians: float) -> float:
	return fposmod(radians + PI, TAU) - PI


static func delta(from: float, to: float) -> float:
	return wrap_signed(to - from)


static func in_arc(angle: float, center: float, half: float) -> bool:
	return absf(delta(center, angle)) <= half


static func clamp_to_arc(angle: float, center: float, half: float) -> float:
	var d: float = delta(center, angle)
	if d > half:
		return wrap_signed(center + half)
	if d < -half:
		return wrap_signed(center - half)
	return angle


static func step_angle(from: float, to: float, rate: float, dt: float) -> Dictionary:
	var d: float = delta(from, to)
	var max_step := rate * dt
	if absf(d) <= max_step:
		return {"angle": wrap_signed(to), "done": true}
	return {"angle": wrap_signed(from + signf(d) * max_step), "done": false}


static func step_angle_in_arc(from: float, to: float, rate: float, dt: float, center: float, half: float) -> Dictionary:
	if half >= PI:
		return step_angle(from, to, rate, dt)
	var cur: float = clamp_value(delta(center, from), -half, half)
	var want: float = clamp_value(delta(center, to), -half, half)
	var max_step := rate * dt
	var d: float = want - cur
	if absf(d) <= max_step:
		return {"angle": wrap_signed(center + want), "done": true}
	return {"angle": wrap_signed(center + cur + signf(d) * max_step), "done": false}


static func direction(radians: float) -> Vector2:
	return Vector2(cos(radians), sin(radians))


static func from_direction(v: Vector2) -> float:
	return atan2(v.y, v.x)
