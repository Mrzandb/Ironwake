extends RefCounted

const Vec := preload("res://sim/vec2_math.gd")
const Ang := preload("res://sim/angle.gd")
const Hash := preload("res://sim/hash.gd")

## FNV-1a of the screen-space samples in screen_hash().
## Quantized at 1e-6. Locks +Y down and clockwise-positive.
const SCREEN_HASH := 3738939676


static func run(a) -> void:
	print("RUN math")
	a.eq(Vec.dot(Vector2(1, 0), Vector2(0, 1)), 0.0, "dot perpendicular")
	a.eq(Vec.cross(Vector2(1, 0), Vector2(0, 1)), 1.0, "cross of right then down is clockwise-positive")
	a.eq(Vec.cross(Vector2(0, 1), Vector2(1, 0)), -1.0, "cross of down then right is counterclockwise")
	a.eq(Vec.cross(Vector2(2, 0), Vector2(2, 0)), 0.0, "cross parallel")
	a.near(Vec.length(Vector2(3, 4)), 5.0, "length 3-4-5")
	a.eq(Vec.distance(Vector2.ZERO, Vector2(3, 4)), 5.0, "distance 3-4-5")
	a.near_v(Vec.normalized(Vector2(3, 4)), Vector2(0.6, 0.8), "normalize 3-4-5", 1e-12)
	a.eq(Vec.normalized(Vector2.ZERO), Vector2.ZERO, "normalize zero")
	a.near_v(Vec.rotated(Vector2(1, 0), PI / 2.0), Vector2(0, 1), "clockwise quarter from right is down", 1e-12)
	a.near_v(Vec.rotated(Vector2(0, 1), PI / 2.0), Vector2(-1, 0), "clockwise quarter from down is left", 1e-12)
	a.near_v(Vec.rotated(Vector2(1, 0), -PI / 2.0), Vector2(0, -1), "negative quarter from right is up", 1e-12)
	# Official Vector2 is single precision. 1e-5 still rejects a flipped rotation sign.
	var sample := Vector2(3, -2)
	a.near_v(Vec.rotated(sample, 0.7), sample.rotated(0.7), "rotated matches Godot clockwise", 1e-5)
	a.eq(Vec.clamp_length(Vector2(3, 4), 0.0), Vector2.ZERO, "clamp zero")
	a.eq(Vec.clamp_length(Vector2(1, 1), 10.0), Vector2(1, 1), "clamp under max")
	a.near_v(Vec.clamp_length(Vector2(3, 4), 2.5), Vector2(1.5, 2.0), "clamp length", 1e-12)
	a.near_v(Vec.lerp(Vector2(0, 0), Vector2(10, 4), 0.25), Vector2(2.5, 1), "vec lerp")
	a.near(Ang.wrap_signed(0.0), 0.0, "wrap 0")
	a.near(Ang.wrap_signed(PI), PI, "wrap pi")
	a.near(Ang.wrap_signed(-PI), PI, "wrap -pi")
	a.near(Ang.wrap_signed(TAU), 0.0, "wrap tau")
	a.near(Ang.wrap_signed(-TAU), 0.0, "wrap -tau")
	a.near(Ang.wrap_signed(-0.4), -0.4, "wrap small negative")
	a.near(Ang.wrap_signed(3.0 * PI), PI, "wrap 3pi", 1e-9)
	a.near(Ang.delta(0.0, PI), PI, "delta half turn")
	a.near(Ang.delta(0.0, PI / 2.0), PI / 2.0, "clockwise quarter is positive")
	a.near(Ang.delta(0.0, -0.2), -0.2, "counterclockwise nudge is negative")
	a.near(Ang.lerp(0.0, PI / 2.0, 0.5), PI / 4.0, "angle lerp toward down")
	a.near_v(Ang.direction(0.0), Vector2(1, 0), "0 rad faces right")
	a.near_v(Ang.direction(PI / 2.0), Vector2(0, 1), "positive quarter faces down", 1e-12)
	a.near_v(Ang.direction(PI), Vector2(-1, 0), "half turn faces left", 1e-12)
	a.near_v(Ang.direction(-PI / 2.0), Vector2(0, -1), "negative quarter faces up", 1e-12)
	a.near_v(Ang.direction(0.4), Vector2.from_angle(0.4), "direction matches Godot from_angle", 1e-12)
	a.near(Ang.from_direction(Vector2(0, 1)), PI / 2.0, "down is positive quarter")
	a.near(Ang.from_direction(Vector2(0, -1)), -PI / 2.0, "up is negative quarter")
	a.near(Ang.from_direction(Vector2(2, 3)), Vector2(2, 3).angle(), "from_direction matches Vector2.angle", 1e-5)
	a.eq(screen_hash(), SCREEN_HASH, "screen convention hash")


static func screen_hash() -> int:
	var h := Hash.begin()
	var samples := [
		Ang.direction(0.0),
		Ang.direction(PI / 2.0),
		Ang.direction(PI),
		Ang.direction(-PI / 2.0),
		Vec.rotated(Vector2(1, 0), PI / 2.0),
		Vec.rotated(Vector2(0, 1), PI / 2.0),
		Vec.rotated(Vector2(1, 0), -PI / 2.0),
		Vec.rotated(Vector2(3, -2), 0.7),
	]
	for sample in samples:
		h = _mix(h, sample.x)
		h = _mix(h, sample.y)
	h = _mix(h, Ang.from_direction(Vector2(0, 1)))
	h = _mix(h, Ang.from_direction(Vector2(0, -1)))
	h = _mix(h, Ang.delta(0.0, PI / 2.0))
	h = _mix(h, Vec.cross(Vector2(1, 0), Vector2(0, 1)))
	return h


static func _mix(h: int, value: float) -> int:
	return Hash.mix_u32(h, int(round(value * 1000000.0)))
