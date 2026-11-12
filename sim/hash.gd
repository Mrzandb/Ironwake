extends RefCounted
class_name SimHash

const Bits := preload("res://sim/bits.gd")

const OFFSET := 0x811c9dc5
const PRIME := 0x01000193


static func begin() -> int:
	return OFFSET


static func fnv1a32(text: String) -> int:
	var h := Bits.to_int32(OFFSET)
	for i in text.length():
		h = Bits.imul(Bits.xor32(h, text.unicode_at(i)), PRIME)
	return Bits.u32(h)


static func mix_u32(h: int, word: int) -> int:
	var x := word & 0xFFFFFFFF
	for _i in 4:
		h = Bits.u32(Bits.imul(Bits.xor32(h, x & 0xFF), PRIME))
		x >>= 8
	return h
