extends RefCounted
class_name SimAngle

## Screen angles, matching Godot 2D and Game_test@33f4be8.
## +X is right, +Y is down, 0 radians faces +X, and clockwise is positive.
## direction(PI/2) is (0, 1), which is down. A negative angle points up.
## wrap_signed returns (-PI, PI]. -PI folds onto +PI so a half-turn has one value.


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
