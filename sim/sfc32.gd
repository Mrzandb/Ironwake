extends RefCounted
class_name Sfc32

## sfc32 step from Game_test@33f4be8 src/core/rng.ts.
## The constructor stores four splitmix32 words and does not discard outputs.

const Bits := preload("res://sim/bits.gd")
const SplitMix := preload("res://sim/splitmix32.gd")

var _a: int = 0
var _b: int = 0
var _c: int = 0
var _d: int = 0


static func from_words(a: int, b: int, c: int, d: int):
	var rng = load("res://sim/sfc32.gd").new()
	rng._a = a
	rng._b = b
	rng._c = c
	rng._d = d
	return rng


static func from_seed(seed_value: int):
	var sm := SplitMix.new(seed_value)
	return from_words(sm.next_u32(), sm.next_u32(), sm.next_u32(), sm.next_u32())


func next_u32() -> int:
	var a := Bits.to_int32(_a)
	var b := Bits.to_int32(_b)
	var c := Bits.to_int32(_c)
	var d := Bits.to_int32(_d)
	var t := Bits.add32(Bits.add32(a, b), d)
	d = Bits.add32(d, 1)
	a = Bits.xor32(b, Bits.usr32(b, 9))
	b = Bits.add32(c, Bits.shl32(c, 3))
	c = Bits.or32(Bits.shl32(c, 21), Bits.usr32(c, 11))
	c = Bits.add32(c, t)
	_a = a
	_b = b
	_c = c
	_d = d
	return Bits.u32(t)


func next_unit() -> float:
	return float(next_u32()) / 4294967296.0


func next_int(n: int) -> int:
	if n <= 0 or n > 4294967296:
		return 0
	var threshold := 0
	if n < 4294967296:
		threshold = 4294967296 % n
	while true:
		var x := next_u32()
		if x >= threshold:
			if n == 4294967296:
				return x
			return x % n
	return 0


func duplicate():
	return from_words(_a, _b, _c, _d)
