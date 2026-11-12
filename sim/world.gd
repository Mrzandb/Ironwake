extends RefCounted
class_name SimWorld

## Tick and named RNG streams. Movement, gait and terrain live in sim/motion.gd.
## This world does not step bodies. Combat and economy are not part of it.
## rng is make_streams(seed), matching Game_test World.

const Clock := preload("res://sim/clock.gd")
const RngScript := preload("res://sim/rng.gd")

const DT: float = Clock.DT

var tick: int = 0
var rng


func _init(root_seed: int = 1) -> void:
	rng = RngScript.make_streams(root_seed)


func step() -> void:
	tick += 1


func duplicate():
	var copy = load("res://sim/world.gd").new(rng.seed)
	copy.tick = tick
	copy.rng = rng.duplicate()
	return copy
