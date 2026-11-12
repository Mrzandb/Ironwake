extends SceneTree

const SimWorldScript := preload("res://sim/world.gd")

const WARMUP := 1000
const TICKS := 20000


func _initialize() -> void:
	var info := Engine.get_version_info()
	print("ENGINE %s.%s.%s.%s.%s" % [info.major, info.minor, info.patch, info.status, info.hash])
	var world = SimWorldScript.new(1)
	for _i in WARMUP:
		world.step()
	var t0 := Time.get_ticks_usec()
	for _i in TICKS:
		world.step()
	var elapsed := Time.get_ticks_usec() - t0
	if elapsed < 0:
		elapsed = 0
	var avg_us := float(elapsed) / float(TICKS)
	var steps_per_sec := 0.0
	if avg_us > 0.0:
		steps_per_sec = 1000000.0 / avg_us
	print("BENCH sim_world_step ticks=%d warmup=%d total_us=%d avg_us_per_tick=%.6f steps_per_sec=%.1f final_tick=%d" % [TICKS, WARMUP, elapsed, avg_us, steps_per_sec, world.tick])
	quit(0)
