extends RefCounted
class_name SplitMix32

## bryc improved splitmix32 (Math.imul constants 0x21f0aaad / 0x735a2d97).
## https://github.com/bryc/code/blob/master/jshash/PRNGs.md

const Bits := preload("res://sim/bits.gd")
const GOLDEN := 0x9e3779b9

var _a: int = 0


func _init(seed_value: int = 0) -> void:
	_a = Bits.to_int32(seed_value)


func next_u32() -> int:
	_a = Bits.add32(_a, GOLDEN)
	var t := Bits.xor32(_a, Bits.usr32(_a, 16))
	t = Bits.imul(t, 0x21f0aaad)
	t = Bits.xor32(t, Bits.usr32(t, 15))
	t = Bits.imul(t, 0x735a2d97)
	t = Bits.xor32(t, Bits.usr32(t, 15))
	return Bits.u32(t)
