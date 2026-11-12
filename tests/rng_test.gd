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
	_seq(a, Sfc.from_seed(1), [1130556604, 2591592147, 3014952990, 960850752, 2734082507, 3058966613, 1454546984, 2701238177], "sfc seed 1")
	_seq(a, Sfc.from_seed(123456789), [3802896128, 80434582, 3894707069, 3900334430, 1534057038, 1158050898, 2509234537, 3646982613], "sfc seed 123456789")
	var unit_rng = Sfc.from_words(1, 2, 3, 4)
	a.eq(unit_rng.next_unit(), 7.0 / 4294967296.0, "unit of first raw")
	var ints = Sfc.from_seed(1)
	for i in [4, 3, 0, 0, 5, 5]:
		a.eq(ints.next_int(6), i, "next_int(6)")
	a.eq(Sfc.from_seed(1).next_int(1), 0, "next_int(1)")
	var bounded = Sfc.from_seed(3)
	var in_range := true
	for _i in 64:
		var n: int = bounded.next_int(10)
		if n < 0 or n > 9:
			in_range = false
	a.ok(in_range, "next_int(10) stays in range")
	var sm = SplitMix.new(1)
	var warmed = Sfc.from_words(sm.next_u32(), sm.next_u32(), sm.next_u32(), sm.next_u32())
	for _i in Sfc.WARMUP:
		warmed.next_u32()
	a.eq(warmed.next_u32(), Sfc.from_seed(1).next_u32(), "warmup discards 12")


static func _streams(a) -> void:
	a.eq(RngScript.derive_stream_seed(1, "spread"), 937888819, "derive spread")
	a.eq(RngScript.derive_stream_seed(1, "ai"), 1192993052, "derive ai")
	a.eq(RngScript.derive_stream_seed(1, "map"), 3896133553, "derive map")
	a.eq(RngScript.derive_stream_seed(42, "spread"), 1845062590, "derive spread 42")
	var rng = RngScript.new(1)
	a.eq(rng.spread().next_u32(), 4129030414, "spread first")
	a.eq(rng.ai().next_u32(), 3728779727, "ai first")
	a.eq(rng.map().next_u32(), 2296329134, "map first")
	var map_first = RngScript.new(1)
	a.eq(map_first.map().next_u32(), 2296329134, "map independent of creation order")
	var again = RngScript.new(1)
	var cached = again.spread()
	a.ok(cached == again.stream("spread"), "stream cached")
	var neg = RngScript.new(-1)
	var wide = RngScript.new(4294967295)
	a.eq(neg.seed, 4294967295, "negative seed stored as u32")
	a.eq(neg.ai().next_u32(), wide.ai().next_u32(), "negative seed matches uint32 seed")
	var live = RngScript.new(5)
	live.spread().next_u32()
	var snap: Dictionary = live.export_state()
	var continued: int = live.spread().next_u32()
	var restored = RngScript.new(0)
	restored.import_state(snap)
	a.eq(restored.seed, 5, "import keeps seed")
	a.eq(restored.spread().next_u32(), continued, "import resumes stream")
