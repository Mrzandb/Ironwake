extends "res://sim/sfc32.gd"
class_name Rng

## Game_test@33f4be8 src/core/rng.ts.
## splitmix32 fills a,b,c,d with no discarded outputs.
## spread/ai/map are separate generators: seed XOR a fixed salt.

const Bits32 := preload("res://sim/bits.gd")
const Streams := preload("res://sim/streams.gd")

const SPREAD_SALT := 0x5f3759df
const AI_SALT := 0x1b873593
const MAP_SALT := 0x27d4eb2f


func _init(seed_value: int = 1) -> void:
	var seeded = load("res://sim/sfc32.gd").from_seed(seed_value)
	_a = seeded._a
	_b = seeded._b
	_c = seeded._c
	_d = seeded._d


func next() -> float:
	return next_unit()


func range(lo: float, hi: float) -> float:
	return lo + next() * (hi - lo)


func truncated_gauss(sigma: float, limit: float) -> float:
	var u := maxf(1e-9, next())
	var v := next()
	var g := sqrt(-2.0 * log(u)) * cos(TAU * v) * sigma
	if g < -limit:
		return -limit
	if g > limit:
		return limit
	return g


func state() -> Array:
	return [_a, _b, _c, _d]


func duplicate():
	var copy = load("res://sim/rng.gd").new(0)
	copy._a = _a
	copy._b = _b
	copy._c = _c
	copy._d = _d
	return copy


static func stream_seed(seed_value: int, salt: int) -> int:
	return Bits32.u32(Bits32.xor32(seed_value, salt))


static func make_streams(seed_value: int):
	var streams = Streams.new()
	streams.seed = seed_value
	var Script = load("res://sim/rng.gd")
	streams.spread = Script.new(stream_seed(seed_value, SPREAD_SALT))
	streams.ai = Script.new(stream_seed(seed_value, AI_SALT))
	streams.map = Script.new(stream_seed(seed_value, MAP_SALT))
	return streams
