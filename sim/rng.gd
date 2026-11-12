extends RefCounted
class_name SimRng

## Seeded simulation RNG.
##
## 2026-11-12: Game_test@33f4be8 was not readable from this environment
## (GitHub 404). This file follows the public sfc32 step and the improved
## splitmix32 (Math.imul). Stream names "spread", "ai" and "map" are reserved.
## Derivation is FNV-1a of the name, XOR the root seed, one splitmix32 mix,
## then Sfc32.from_seed (4 words + 12 discarded outputs).
## Re-check src/core/rng.ts and tests/unit/rng.test.ts before porting combat numbers.
## If those vectors differ, change this file — do not patch gameplay on top.

const Bits := preload("res://sim/bits.gd")
const Hash := preload("res://sim/hash.gd")
const SplitMix := preload("res://sim/splitmix32.gd")
const Sfc := preload("res://sim/sfc32.gd")

const STREAM_SPREAD := "spread"
const STREAM_AI := "ai"
const STREAM_MAP := "map"

var seed: int = 1
var _streams: Dictionary = {}


func _init(root_seed: int = 1) -> void:
	seed = Bits.u32(root_seed)


static func derive_stream_seed(root_seed: int, name: String) -> int:
	var mixed := Bits.u32(Bits.xor32(Hash.fnv1a32(name), root_seed))
	return SplitMix.new(mixed).next_u32()


func stream(name: String):
	if not _streams.has(name):
		_streams[name] = Sfc.from_seed(derive_stream_seed(seed, name))
	return _streams[name]


func spread():
	return stream(STREAM_SPREAD)


func ai():
	return stream(STREAM_AI)


func map():
	return stream(STREAM_MAP)


func duplicate():
	var copy = load("res://sim/rng.gd").new(seed)
	for name in _streams.keys():
		copy._streams[name] = _streams[name].duplicate()
	return copy


func export_state() -> Dictionary:
	var names: Array = _streams.keys()
	names.sort()
	var packed := {}
	for name in names:
		packed[name] = _streams[name].export_state()
	return {"seed": seed, "streams": packed}


func import_state(state: Dictionary) -> void:
	seed = Bits.u32(int(state["seed"]))
	_streams = {}
	var packed: Dictionary = state["streams"]
	for name in packed.keys():
		var words: Dictionary = packed[name]
		_streams[name] = Sfc.from_words(int(words["a"]), int(words["b"]), int(words["c"]), int(words["d"]))
