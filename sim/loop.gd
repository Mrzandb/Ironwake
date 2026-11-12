extends RefCounted
class_name FixedStepLoop

## Game_test@33f4be8 src/core/loop.ts.
## Caller passes the real frame delta. One frame is clamped to [0, 0.25] s.
## advance() returns the render alpha in [0, 1).

const HZ := 60
const DT := 1.0 / 60.0
const MAX_FRAME := 0.25

var tick: int = 0
var _acc: float = 0.0
var _step: Callable


func _init(step: Callable = Callable()) -> void:
	_step = step


func advance(real_dt: float) -> float:
	var clamped := real_dt
	if clamped < 0.0:
		clamped = 0.0
	if clamped > MAX_FRAME:
		clamped = MAX_FRAME
	_acc += clamped
	while _acc >= DT:
		if _step.is_valid():
			_step.call(tick)
		tick += 1
		_acc -= DT
	return _acc / DT
