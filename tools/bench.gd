extends SceneTree

const SimWorldScript := preload("res://sim/world.gd")
const CatalogScript := preload("res://sim/data/catalog.gd")
const MotionScript := preload("res://sim/motion.gd")
const FightScript := preload("res://sim/fight.gd")
const Command := preload("res://sim/command.gd")

const WARMUP := 1000
const TICKS := 20000
const MOVE_WARMUP := 200
const MOVE_TICKS := 4000


func _initialize() -> void:
	var info := Engine.get_version_info()
	print("ENGINE %s.%s.%s.%s.%s" % [info.major, info.minor, info.patch, info.status, info.hash])
	_empty_world()
	_motion()
	_fight()
	quit(0)


func _empty_world() -> void:
	var world = SimWorldScript.new(1)
	for _i in WARMUP:
		world.step()
	var elapsed := _time_calls(func():
		world.step()
	, TICKS)
	_report("sim_world_step", TICKS, WARMUP, elapsed, world.tick)


func _motion() -> void:
	var cat = CatalogScript.new()
	var hills = cat.map_def("hills")
	var world = MotionScript.new(
		{"w": float(hills["size"]["w"]), "h": float(hills["size"]["h"])},
		hills,
		float(cat.rules["terrain"]["wallHp"])
	)
	var kinds := ["bulwark", "swarm", "hawk", "bulwark", "swarm", "hawk"]
	var spawned: Array = []
	var spawns: Array = hills["spawns"]
	for i in kinds.size():
		var spawn: Dictionary = spawns[i]
		var vehicle = world.spawn(cat.vehicle(kinds[i]), int(spawn["team"]), spawn["pos"], float(spawn["heading"]))
		spawned.append(vehicle)
	for _i in MOVE_WARMUP:
		world.step(_commands(spawned))
	var elapsed := _time_calls(func():
		world.step(_commands(spawned))
	, MOVE_TICKS)
	_report("motion_hills_6", MOVE_TICKS, MOVE_WARMUP, elapsed, world.tick)


func _fight() -> void:
	var cat = CatalogScript.new()
	var hills = cat.map_def("hills")
	var world = FightScript.new(
		{"w": float(hills["size"]["w"]), "h": float(hills["size"]["h"])},
		1,
		hills,
		cat
	)
	var kinds := ["bulwark", "swarm", "hawk", "bulwark", "swarm", "hawk"]
	var spawned: Array = []
	var spawns: Array = hills["spawns"]
	for i in kinds.size():
		var spawn: Dictionary = spawns[i]
		var vehicle = world.spawn(cat.vehicle(kinds[i]), int(spawn["team"]), spawn["pos"], float(spawn["heading"]))
		spawned.append(vehicle)
	for _i in MOVE_WARMUP:
		world.step(_fight_commands(spawned))
	var elapsed := _time_calls(func():
		world.step(_fight_commands(spawned))
	, MOVE_TICKS)
	_report("fight_hills_6", MOVE_TICKS, MOVE_WARMUP, elapsed, world.tick)


func _fight_commands(spawned: Array) -> Dictionary:
	var cmds := {}
	for i in spawned.size():
		var foe: Dictionary = spawned[(i + 3) % spawned.size()]
		var turn := 0.35 if i % 2 == 0 else -0.35
		cmds[spawned[i]["id"]] = Command.merge({
			"throttle": 1.0,
			"turn": turn,
			"strafe": 0.25 if i % 3 == 2 else 0.0,
			"aim": {"x": float(foe["pos"]["x"]), "y": float(foe["pos"]["y"])},
			"fire": true,
			"secondaries": true,
		})
	return cmds


func _commands(spawned: Array) -> Dictionary:
	var cmds := {}
	for i in spawned.size():
		var turn := 0.35 if i % 2 == 0 else -0.35
		var strafe := 0.25 if i % 3 == 2 else 0.0
		cmds[spawned[i]["id"]] = Command.merge({
			"throttle": 1.0,
			"turn": turn,
			"strafe": strafe,
		})
	return cmds


func _time_calls(step: Callable, count: int) -> int:
	var t0 := Time.get_ticks_usec()
	for _i in count:
		step.call()
	var elapsed := Time.get_ticks_usec() - t0
	if elapsed < 0:
		return 0
	return elapsed


func _report(name: String, ticks: int, warmup: int, elapsed: int, final_tick: int) -> void:
	var avg_us := float(elapsed) / float(ticks)
	var steps_per_sec := 0.0
	if avg_us > 0.0:
		steps_per_sec = 1000000.0 / avg_us
	print("BENCH %s ticks=%d warmup=%d total_us=%d avg_us_per_tick=%.6f steps_per_sec=%.1f final_tick=%d" % [name, ticks, warmup, elapsed, avg_us, steps_per_sec, final_tick])
