extends RefCounted

const Clock := preload("res://sim/clock.gd")
const WorldScript := preload("res://sim/world.gd")
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
	var driver = Fixed.new()
	a.eq(driver.consume(0.0), 0, "zero frame")
	a.eq(driver.consume(-0.5), 0, "negative frame")
	var total := 0
	for _i in 120:
		total += driver.consume(Clock.DT)
	a.eq(total, 120, "one tick per exact frame")
	a.near(driver.accumulator, 0.0, "accumulator drained")
	var capped = Fixed.new()
	a.eq(capped.consume(1.0), capped.max_steps, "spiral cap")
	a.eq(capped.accumulator, 0.0, "cap drops leftover")
