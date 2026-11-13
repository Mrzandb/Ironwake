extends RefCounted

const Util := preload("res://tests/world_util.gd")
const ReplayScript := preload("res://sim/replay.gd")
const Simple := preload("res://sim/ai/simple.gd")
const Command := preload("res://sim/command.gd")


static func run(a) -> void:
	print("RUN replay")
	var cat = Util.catalog()
	_roundtrip(a, cat)
	_delta(a, cat)
	_tamper(a, cat)
	_snapshot(a, cat)
	_map(a, cat)


static func _record(cat, seconds: int, reset_at = null, idle_b: bool = false) -> Dictionary:
	var world = Util.fight(cat, 16000.0, 16000.0, 7)
	var left = world.spawn(cat.vehicle("bulwark"), 0, {"x": 8000.0, "y": 8600.0}, -PI / 2.0)
	var right = world.spawn(cat.vehicle("hawk"), 1, {"x": 8000.0, "y": 7400.0}, PI / 2.0)
	var recorder = ReplayScript.new(world)
	var params := Simple.with_params()
	for i in seconds * 60:
		if reset_at != null and i == int(reset_at) * 60:
			world.place(left, {"x": 8000.0, "y": 8600.0}, -PI / 2.0)
			recorder.place(world, int(left["id"]), {"x": 8000.0, "y": 8600.0}, -PI / 2.0)
		var cmds := {}
		cmds[int(left["id"])] = Simple.think(left, right, params, world.table, world.rules)
		if idle_b:
			cmds[int(right["id"])] = Command.idle()
		else:
			cmds[int(right["id"])] = Simple.think(right, left, params, world.table, world.rules)
		recorder.record(world, cmds)
		world.step(cmds)
		recorder.after(world)
	return {"replay": recorder.snapshot(), "hash": world.replay_hash()}


static func _roundtrip(a, cat) -> void:
	var recorded := _record(cat, 45, 10)
	var replay: Dictionary = recorded["replay"]
	a.eq(replay["hashes"].size(), 45, "hash every second for 45s")
	a.eq(replay["ops"].size(), 1, "one place op")
	var checked: Dictionary = ReplayScript.verify(replay)
	a.eq(checked["error"], "", "verify error")
	a.eq(int(checked["ticks"]), 45 * 60, "replay length")
	a.eq(checked["desync_at"], null, "45s replay matches")
	var text := JSON.stringify(replay, "", false, true)
	var back = JSON.parse_string(text)
	var again: Dictionary = ReplayScript.verify(back)
	a.eq(again["desync_at"], null, "json roundtrip matches")


static func _delta(a, cat) -> void:
	var replay: Dictionary = _record(cat, 15, null, true)["replay"]
	var kept := 0
	for entry in replay["cmds"]:
		if int(entry["vehicle"]) == 2:
			kept += 1
	a.eq(kept, 0, "an idle vehicle stores no commands")
	a.eq(ReplayScript.verify(replay)["desync_at"], null, "idle replay matches")


static func _tamper(a, cat) -> void:
	var replay: Dictionary = _record(cat, 15)["replay"]
	var index := -1
	for i in replay["cmds"].size():
		if int(replay["cmds"][i]["tick"]) > 300:
			index = i
			break
	a.ok(index >= 0, "a command exists after tick 300")
	var entry: Dictionary = replay["cmds"][index]
	var cmd: Dictionary = (entry["cmd"] as Dictionary).duplicate(true)
	cmd["throttle"] = -1.0 if float(cmd["throttle"]) == 1.0 else 1.0
	cmd["turn"] = 1.0
	replay["cmds"][index] = {"tick": entry["tick"], "vehicle": entry["vehicle"], "cmd": cmd}
	var checked: Dictionary = ReplayScript.verify(replay)
	a.ok(checked["desync_at"] != null, "tamper is detected")
	a.ok(int(checked["desync_at"]) > int(entry["tick"]), "desync is after the edit")
	a.ok(int(checked["desync_at"]) <= int(entry["tick"]) + ReplayScript.HASH_EVERY, "desync is at the next hash")


static func _snapshot(a, cat) -> void:
	var replay: Dictionary = _record(cat, 8)["replay"]
	a.ok(not is_same(replay["defs"]["hawk"], cat.vehicle("hawk")), "blueprint snapshot is its own object")
	var speed := float(cat.vehicle("hawk")["move"]["maxSpeed"])
	replay["defs"]["hawk"]["move"]["maxSpeed"] = speed
	a.eq(ReplayScript.verify(replay)["desync_at"], null, "snapshot with the same numbers replays")
	a.eq(float(cat.vehicle("hawk")["move"]["maxSpeed"]), speed, "catalog blueprint unchanged")


static func _map(a, cat) -> void:
	var hills = cat.map_def("hills")
	var world = Util.fight(cat, float(hills["size"]["w"]), float(hills["size"]["h"]), 3, "hills")
	var gun = world.spawn(cat.vehicle("bulwark"), 0, {"x": 7300.0, "y": 5700.0}, 0.0)
	var recorder = ReplayScript.new(world)
	var cmd := Command.merge({"aim": {"x": 8200.0, "y": 5700.0}, "fire": true, "slot": 1})
	for _i in 60 * 12:
		var cmds := {}
		cmds[int(gun["id"])] = cmd
		recorder.record(world, cmds)
		world.step(cmds)
		recorder.after(world)
	var wall_hp := 0.0
	for obstacle in world.terrain.obstacles:
		if str(obstacle["def"]["id"]) == "w3":
			wall_hp = float(obstacle["hp"])
	a.ok(wall_hp < float(cat.rules["terrain"]["wallHp"]), "the recorded volley damages the wall")
	var replay: Dictionary = recorder.snapshot()
	a.eq(str(replay["map"]), "hills", "replay stores the map id")
	var back = JSON.parse_string(JSON.stringify(replay, "", false, true))
	a.eq(ReplayScript.verify(back)["desync_at"], null, "map replay matches")
