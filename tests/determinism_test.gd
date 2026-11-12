extends RefCounted

const Hash := preload("res://sim/hash.gd")
const WorldScript := preload("res://sim/world.gd")


static func fingerprint(root_seed: int, ticks: int) -> int:
	var world = WorldScript.new(root_seed)
	var h := Hash.begin()
	for _i in ticks:
		world.step()
		h = Hash.mix_u32(h, world.tick)
		h = Hash.mix_u32(h, world.rng.spread().next_u32())
		h = Hash.mix_u32(h, world.rng.ai().next_u32())
		h = Hash.mix_u32(h, world.rng.map().next_u32())
	return h


static func run(a) -> void:
	print("RUN determinism")
	var first := fingerprint(42, 1000)
	var second := fingerprint(42, 1000)
	a.eq(first, second, "same seed same hash")
	a.eq(first, 2591209380, "golden hash seed 42 x 1000")
	a.eq(fingerprint(43, 1000), 3932325036, "golden hash seed 43 x 1000")
	a.eq(fingerprint(42, 1), 295808853, "golden hash seed 42 x 1")
	a.ok(first != fingerprint(43, 1000), "different seed differs")
	var world = WorldScript.new(9)
	world.step()
	var copy = world.duplicate()
	a.eq(copy.tick, world.tick, "duplicate keeps tick")
	var left: int = world.rng.map().next_u32()
	var right: int = copy.rng.map().next_u32()
	a.eq(left, right, "duplicate draws match")
	var left_again: int = world.rng.map().next_u32()
	var right_again: int = copy.rng.map().next_u32()
	a.eq(left_again, right_again, "copies stay aligned")
	var advanced: int = world.rng.map().next_u32()
	var held: int = copy.rng.map().next_u32()
	a.eq(advanced, held, "copies stay independent and aligned")
	var only_left: int = world.rng.map().next_u32()
	a.ok(only_left != advanced, "later draw is a new value")
