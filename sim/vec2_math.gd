extends RefCounted
class_name SimVec

## Screen vectors, matching Godot 2D and Game_test@33f4be8.
## +X is right and +Y is down. Vector2 is a value type, not a scene node.
## rotated() takes a clockwise-positive angle:
## x' = x cos(a) - y sin(a), y' = x sin(a) + y cos(a).
## cross() is positive when b is clockwise from a.


const NORM_EPSILON := 1e-9


static func length_squared(v: Vector2) -> float:
	return v.x * v.x + v.y * v.y


static func add(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x + b.x, a.y + b.y)


static func sub(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x - b.x, a.y - b.y)


static func mul(v: Vector2, scale: float) -> Vector2:
	return Vector2(v.x * scale, v.y * scale)


static func hypot(x: float, y: float) -> float:
	x = absf(x)
	y = absf(y)
	if x < y:
		var swap := x
		x = y
		y = swap
	if x == 0.0:
		return 0.0
	var ratio := y / x
	return x * sqrt(1.0 + ratio * ratio)


static func length(v: Vector2) -> float:
	return hypot(v.x, v.y)


static func normalized(v: Vector2) -> Vector2:
	var mag := length(v)
	if mag > NORM_EPSILON:
		return Vector2(v.x / mag, v.y / mag)
	return Vector2.ZERO


static func from_angle(radians: float, radius: float = 1.0) -> Vector2:
	return Vector2(cos(radians) * radius, sin(radians) * radius)


static func dot(a: Vector2, b: Vector2) -> float:
	return a.x * b.x + a.y * b.y


static func cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


static func rotated(v: Vector2, radians: float) -> Vector2:
	var c := cos(radians)
	var s := sin(radians)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


static func clamp_length(v: Vector2, max_len: float) -> Vector2:
	if max_len <= 0.0:
		return Vector2.ZERO
	var len_sq := length_squared(v)
	var max_sq := max_len * max_len
	if len_sq <= max_sq:
		return v
	var inv := max_len / sqrt(len_sq)
	return Vector2(v.x * inv, v.y * inv)


static func lerp(a: Vector2, b: Vector2, t: float) -> Vector2:
	return Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)


static func distance_squared(a: Vector2, b: Vector2) -> float:
	return length_squared(b - a)


static func distance(a: Vector2, b: Vector2) -> float:
	return hypot(a.x - b.x, a.y - b.y)
