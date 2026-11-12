extends RefCounted

const Clock := preload("res://sim/clock.gd")
const WorldScript := preload("res://sim/world.gd")
const Loop := preload("res://sim/loop.gd")
const Fixed := preload("res://game/fixed_step.gd")


static func run(a) -> void:
	print("RUN clock")
	a.eq(Clock.HZ, 60, "hz")
	a.eq(Clock.DT, 1.0 / 60.0, "dt literal")
	a.ok(is_equal_approx(Clock.DT * float(Clock.HZ), 1.0), "dt * hz")
	var world = WorldScript.new(4)
	a.eq(world.DT, Clock.DT, "world uses clock dt")
	a.eq(world.tick, 0, "tick starts at 0")
	world.step()
	world.step()
	world.step()
	a.eq(world.tick, 3, "three steps")
	var other = WorldScript.new(4)
	a.eq(other.tick, 0, "instances do not share tick")
	var loop = Loop.new(func(_tick):
		pass
	)
	a.eq(loop.advance(0.0), 0.0, "zero frame alpha")
	a.eq(loop.tick, 0, "zero frame does not tick")
	a.eq(loop.advance(-0.5), 0.0, "negative frame alpha")
	a.eq(loop.tick, 0, "negative frame does not tick")
	var paced = Loop.new(func(_tick):
		pass
	)
	for _i in 10:
		paced.advance(0.1)
	a.eq(paced.tick, 60, "one second is 60 ticks")
	paced.advance(5.0)
	a.eq(paced.tick, 75, "a stalled frame adds at most 0.25 s")
	var driver = Fixed.new()
	var total := 0
	for _i in 120:
		total += driver.consume(Clock.DT)
	a.eq(total, 120, "driver counts one tick per exact frame")
	a.eq(driver.consume(1.0), 15, "driver clamps one frame to 15 ticks")
