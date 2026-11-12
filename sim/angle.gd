extends RefCounted
class_name SimAngle

## Angles in radians, zero on +X, counterclockwise.
## wrap_signed returns (-PI, PI]. -PI folds onto +PI so a half-turn has one value.
## 2026-11-12: not checked against Game_test src/core.


static func wrap_signed(radians: float) -> float:
	var wrapped := fposmod(radians, TAU)
	if wrapped > PI:
		wrapped -= TAU
	return wrapped


static func delta(from: float, to: float) -> float:
	return wrap_signed(to - from)


static func lerp(from: float, to: float, t: float) -> float:
	return wrap_signed(from + delta(from, to) * t)


static func direction(radians: float) -> Vector2:
	return Vector2(cos(radians), sin(radians))


static func from_direction(v: Vector2) -> float:
	return atan2(v.y, v.x)
