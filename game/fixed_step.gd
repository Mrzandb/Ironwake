extends RefCounted
class_name FixedStepDriver

## Turns real frame deltas into a count of sim ticks.
## Lives in game/ because it reads frame time. sim/ only sees step().

const Clock := preload("res://sim/clock.gd")

var accumulator: float = 0.0
var max_steps: int = 8


func consume(frame_dt: float) -> int:
	if frame_dt < 0.0:
		frame_dt = 0.0
	accumulator += frame_dt
	var steps := 0
	var dt := float(Clock.DT)
	while accumulator >= dt and steps < max_steps:
		accumulator -= dt
		steps += 1
	if steps == max_steps:
		accumulator = 0.0
	return steps
