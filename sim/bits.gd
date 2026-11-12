extends RefCounted
class_name Bits32

## JS ToInt32 / ToUint32 / Math.imul on Godot's 64-bit int.
## The product is split into 16-bit halves so the low 32 bits do not depend on signed overflow.
## 4.7.2 wraps 0xFFFFFFFF * 0xFFFFFFFF to -8589934591; its low 32 bits are still 1.
## Keep the golden vectors in tests/rng_test.gd if this is ever simplified.


static func to_int32(x: int) -> int:
	var m := x & 0xFFFFFFFF
	if m >= 0x80000000:
		return m - 0x100000000
	return m


static func u32(x: int) -> int:
	return x & 0xFFFFFFFF


static func add32(a: int, b: int) -> int:
	return to_int32(to_int32(a) + to_int32(b))


static func xor32(a: int, b: int) -> int:
	return to_int32((a & 0xFFFFFFFF) ^ (b & 0xFFFFFFFF))


static func or32(a: int, b: int) -> int:
	return to_int32((a & 0xFFFFFFFF) | (b & 0xFFFFFFFF))


static func shl32(x: int, n: int) -> int:
	return to_int32(to_int32(x) << (n & 31))


static func usr32(x: int, n: int) -> int:
	return (x & 0xFFFFFFFF) >> (n & 31)


static func imul(a: int, b: int) -> int:
	var ua := a & 0xFFFFFFFF
	var ub := b & 0xFFFFFFFF
	var al := ua & 0xFFFF
	var ah := (ua >> 16) & 0xFFFF
	var bl := ub & 0xFFFF
	var bh := (ub >> 16) & 0xFFFF
	var low := al * bl
	var mid := ah * bl + al * bh
	var prod := (low + ((mid & 0xFFFF) << 16)) & 0xFFFFFFFF
	return to_int32(prod)
