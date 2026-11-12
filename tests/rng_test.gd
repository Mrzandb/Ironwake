extends RefCounted

const Bits := preload("res://sim/bits.gd")
const Hash := preload("res://sim/hash.gd")
const SplitMix := preload("res://sim/splitmix32.gd")
const Sfc := preload("res://sim/sfc32.gd")
const RngScript := preload("res://sim/rng.gd")


static func run(a) -> void:
	print("RUN rng")
	_bits(a)
	_hash(a)
	_splitmix(a)
	_sfc(a)
	_streams(a)


static func _seq(a, rng, expected: Array, label: String) -> void:
	for i in expected.size():
		a.eq(rng.next_u32(), int(expected[i]), "%s[%d]" % [label, i])


static func _bits(a) -> void:
	a.eq(Bits.u32(-1), 4294967295, "u32 -1")
	a.eq(Bits.to_int32(4294967295), -1, "to_int32 high")
	a.eq(Bits.to_int32(-2147483649), 2147483647, "to_int32 below int32")
	a.eq(Bits.u32(-5), 4294967291, "u32 -5")
	a.eq(Bits.imul(-1, -1), 1, "imul -1*-1")
	a.eq(Bits.u32(Bits.imul(4294967295, 4294967295)), 1, "imul ff*ff")
	a.eq(Bits.imul(2147483647, 2), -2, "imul max*2 signed")
	a.eq(Bits.u32(Bits.imul(2147483647, 2)), 4294967294, "imul max*2")
	a.eq(Bits.u32(Bits.imul(2147483648, 2)), 0, "imul signbit*2")
	a.eq(Bits.u32(Bits.imul(2147483647, 2147483647)), 1, "imul max*max")
	a.eq(Bits.u32(Bits.imul(2147483648, 2147483648)), 0, "imul sign*sign")
	a.eq(Bits.u32(Bits.imul(3735928559, 305419896)), 1445054984, "imul deadbeef")
	a.eq(Bits.u32(Bits.imul(4294967294, 3)), 4294967290, "imul -2*3")
	a.eq(Bits.u32(Bits.imul(569420461, 1935289751)), 180819211, "imul splitmix constants")
	a.eq(Bits.u32(Bits.imul(123456789, 3307312975)), 67153019, "imul mixed signs")
	a.eq(Bits.shl32(4294967295, 3) & 0xFFFFFFFF, 4294967288, "shl -1 << 3")
	a.eq(Bits.shl32(2147483648, 1) & 0xFFFFFFFF, 0, "shl signbit << 1")
	a.eq(Bits.usr32(-1, 9), 8388607, "usr -1 >>> 9")
	a.eq(Bits.u32(Bits.add32(-1, 0x9e3779b9)), 2654435768, "add32 -1+golden")
	a.eq(Bits.u32(Bits.xor32(4294967295, Bits.usr32(4294967295, 9))), 4286578688, "xor usr9")


static func _hash(a) -> void:
	a.eq(Hash.fnv1a32("spread"), 1229586638, "fnv spread")
	a.eq(Hash.fnv1a32("ai"), 1143273375, "fnv ai")
	a.eq(Hash.fnv1a32("map"), 3751997361, "fnv map")
	a.eq(Hash.mix_u32(Hash.begin(), 1), 4218009092, "fnv mix 1")
	a.eq(Hash.mix_u32(Hash.begin(), 1684164658), 2614005209, "fnv mix word")


static func _splitmix(a) -> void:
	_seq(a, SplitMix.new(0), [1684164658, 3653269916, 2939563536, 2141751570, 3295091513, 4057132772, 2256158761, 2742494325], "splitmix0")
	_seq(a, SplitMix.new(1), [1580013426, 350525680, 3524174333, 3011703609, 643872864, 2282937712, 2300340400, 3453518249], "splitmix1")
	_seq(a, SplitMix.new(0xDEADBEEF), [46217145, 304148291, 1711218402, 2692075039, 4098511199, 697799442, 3097768831, 151972181], "splitmix dead")


static func _sfc(a) -> void:
	_seq(a, Sfc.from_words(1, 2, 3, 4), [7, 34, 56623200, 188882296, 3431242869, 399395954, 785775158, 3843710725], "sfc raw")
	# Game_test Rng(seed): four splitmix words, no discarded warmup.
	_seq(a, RngScript.new(1), [647275419, 720736219, 2935747679, 3959590554, 1760388915, 3582062282, 2612835515, 2422708869], "rng seed 1")
	_seq(a, RngScript.new(42), [3730666837, 1786513705, 1450338100, 2191736338, 3785014133, 2792630042, 2559606165, 3613948625], "rng seed 42")
	_seq(a, RngScript.new(123456789), [217360464, 2253230431, 58752542, 3715117548, 1770330342, 875172997, 2128053491, 3492597773], "rng seed 123456789")
	_seq(a, RngScript.new(0xDEADBEEF), [3042440475, 1217913670, 1425216775, 3941981854], "rng seed deadbeef")
	var seeded = RngScript.new(1)
	var words: Array = seeded.state()
	a.eq(words[0], 1580013426, "state a")
	a.eq(words[1], 350525680, "state b")
	a.eq(words[2], 3524174333, "state c")
	a.eq(words[3], 3011703609, "state d")
	a.eq(seeded.next(), 647275419.0 / 4294967296.0, "next() of seed 1")
	seeded = RngScript.new(1)
	seeded.next_u32()
	var after: Array = seeded.state()
	a.eq(after[3], -1283263686, "state d is signed after a draw")
	a.near(RngScript.new(7).range(-2.0, 3.0), -0.7108627834822983, "range seed 7", 1e-12)
	var gauss = RngScript.new(9)
	a.near(gauss.truncated_gauss(1.0, 2.0), 0.09666007543816074, "gauss 0", 1e-12)
	a.eq(gauss.truncated_gauss(1.0, 2.0), 2.0, "gauss clamped high")
	a.near(gauss.truncated_gauss(1.0, 2.0), -0.38433387577880573, "gauss 2", 1e-12)
	a.near(gauss.truncated_gauss(1.0, 2.0), -1.3655130015633719, "gauss 3", 1e-12)
	var same_a = RngScript.new(42)
	var same_b = RngScript.new(42)
	var matched := true
	for _i in 1000:
		if same_a.next_u32() != same_b.next_u32():
			matched = false
	a.ok(matched, "same seed same 1000 outputs")
	a.ok(RngScript.new(1).next_u32() != RngScript.new(2).next_u32(), "different seeds differ")
	var unit = RngScript.new(7)
	var inside := true
	for _i in 1000:
		var v: float = unit.next()
		if v < 0.0 or v >= 1.0:
			inside = false
	a.ok(inside, "next() stays in [0, 1)")
	var limited = RngScript.new(9)
	var bounded := true
	for _i in 1000:
		if absf(limited.truncated_gauss(1.0, 2.0)) > 2.0:
			bounded = false
	a.ok(bounded, "truncated gauss stays inside the limit")
	a.eq(RngScript.new(-1).next_u32(), RngScript.new(4294967295).next_u32(), "negative seed matches uint32 seed")


static func _streams(a) -> void:
	a.eq(RngScript.stream_seed(1, RngScript.SPREAD_SALT), 1597463006, "spread salt")
	a.eq(RngScript.stream_seed(1, RngScript.AI_SALT), 461845906, "ai salt")
	a.eq(RngScript.stream_seed(1, RngScript.MAP_SALT), 668265262, "map salt")
	var streams = RngScript.make_streams(1)
	a.eq(streams.spread.next_u32(), 3999759398, "spread first")
	a.eq(streams.ai.next_u32(), 3188684842, "ai first")
	a.eq(streams.map.next_u32(), 3116959923, "map first")
	var used = RngScript.make_streams(5)
	var fresh = RngScript.make_streams(5)
	used.spread.next()
	used.spread.next()
	var ai_value: int = used.ai.next_u32()
	a.eq(ai_value, 3516040939, "ai of seed 5")
	a.eq(ai_value, fresh.ai.next_u32(), "extra spread draws do not move ai")
