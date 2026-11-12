extends RefCounted
class_name FixedStepDriver

## Presentation adapter. The clamp and accumulator live in sim/loop.gd.

const Loop := preload("res://sim/loop.gd")

var _loop


func _init() -> void:
	_loop = Loop.new(func(_tick):
		pass
	)


func consume(frame_dt: float) -> int:
	var before: int = _loop.tick
	_loop.advance(frame_dt)
	return _loop.tick - before
