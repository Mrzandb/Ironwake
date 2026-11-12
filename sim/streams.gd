extends RefCounted

## Game_test makeStreams(): three independent Rng instances.

var seed: int = 0
var spread
var ai
var map


func duplicate():
	var copy = load("res://sim/streams.gd").new()
	copy.seed = seed
	copy.spread = spread.duplicate()
	copy.ai = ai.duplicate()
	copy.map = map.duplicate()
	return copy
