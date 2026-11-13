extends RefCounted
class_name SimReplay

## Game_test@33f4be8 src/sim/replay.ts.
## Records commands, place ops, and a replay_hash every 60 ticks.
## Playback builds a new SimFight and checks those hashes.
## The byte layout is not required to match a JS recording.

const Command := preload("res://sim/command.gd")
const FightScript := preload("res://sim/fight.gd")
const CatalogScript := preload("res://sim/data/catalog.gd")
const PlayerScript := preload("res://sim/replay_player.gd")

const FORMAT := "game-replay"
const VERSION := 2
const HASH_EVERY := 60


var _data: Dictionary
var _last := {}
var error := ""


func _init(world) -> void:
	if int(world.tick) != 0:
		error = "replay must start at tick 0"
		_data = {}
		return
	var defs := {}
	for vehicle in world.vehicles:
		var id := str(vehicle["def"]["id"])
		if not defs.has(id):
			defs[id] = (vehicle["def"] as Dictionary).duplicate(true)
	var spawns: Array = []
	for vehicle in world.vehicles:
		spawns.append({
			"def": str(vehicle["def"]["id"]),
			"team": int(vehicle["team"]),
			"pos": {"x": float(vehicle["pos"]["x"]), "y": float(vehicle["pos"]["y"])},
			"heading": float(vehicle["heading"]),
		})
	_data = {
		"format": FORMAT,
		"version": VERSION,
		"arena": {"w": float(world.arena_w), "h": float(world.arena_h)},
		"seed": int(world.root_seed),
		"map": world.map_id,
		"defs": defs,
		"spawns": spawns,
		"ticks": 0,
		"cmds": [],
		"ops": [],
		"hashes": [],
	}


func record(world, cmds: Dictionary) -> void:
	if error != "":
		return
	for vehicle in world.vehicles:
		var id := int(vehicle["id"])
		var cmd: Dictionary = cmds[id] if cmds.has(id) else Command.idle()
		var prev: Dictionary = _last[id] if _last.has(id) else Command.idle()
		if _same(prev, cmd):
			continue
		var cloned := _clone_cmd(cmd)
		_last[id] = cloned
		_data["cmds"].append({"tick": int(world.tick), "vehicle": id, "cmd": _clone_cmd(cloned)})


func place(world, vehicle_id: int, pos: Dictionary, heading: float) -> void:
	if error != "":
		return
	_data["ops"].append({
		"tick": int(world.tick),
		"op": "place",
		"vehicle": vehicle_id,
		"pos": {"x": float(pos["x"]), "y": float(pos["y"])},
		"heading": heading,
	})


func after(world) -> void:
	if error != "":
		return
	_data["ticks"] = int(world.tick)
	if int(world.tick) % HASH_EVERY == 0:
		_data["hashes"].append({"tick": int(world.tick), "hash": world.replay_hash()})


func ticks() -> int:
	return int(_data.get("ticks", 0))


func snapshot() -> Dictionary:
	return _data.duplicate(true)


static func world_from(replay: Dictionary, catalog = null):
	if str(replay.get("format", "")) != FORMAT:
		return null
	if int(replay.get("version", -1)) != VERSION:
		return null
	if catalog == null:
		catalog = CatalogScript.new()
	var map_def = null
	if replay.get("map", null) != null:
		var map_id := str(replay["map"])
		if not catalog.map_ids().has(map_id):
			return null
		map_def = catalog.map_def(map_id)
	var arena: Dictionary = replay["arena"]
	var world = FightScript.new({"w": float(arena["w"]), "h": float(arena["h"])}, int(replay["seed"]), map_def, catalog)
	var defs: Dictionary = replay["defs"]
	for spawn in replay["spawns"]:
		var def_id := str(spawn["def"])
		if not defs.has(def_id):
			return null
		world.spawn(defs[def_id], int(spawn["team"]), spawn["pos"], float(spawn["heading"]))
	return world


static func verify(replay: Dictionary, catalog = null) -> Dictionary:
	var player = PlayerScript.new(replay, world_from(replay, catalog))
	if player.world == null:
		return {"desync_at": 0, "ticks": 0, "hashes": 0, "error": player.error}
	while not player.done():
		player.step()
	return {"desync_at": player.desync_at, "ticks": int(player.world.tick), "hashes": replay["hashes"].size(), "error": ""}


static func _same(a: Dictionary, b: Dictionary) -> bool:
	if float(a["throttle"]) != float(b["throttle"]) or float(a["turn"]) != float(b["turn"]) or float(a["strafe"]) != float(b["strafe"]):
		return false
	if bool(a["fire"]) != bool(b["fire"]) or int(a["slot"]) != int(b["slot"]) or bool(a["secondaries"]) != bool(b["secondaries"]):
		return false
	if not _same_id(a["lock"], b["lock"]) or not _same_aim(a["aim"], b["aim"]):
		return false
	return true


static func _same_id(a, b) -> bool:
	if a == null or b == null:
		return a == b
	return int(a) == int(b)


static func _same_aim(a, b) -> bool:
	if a == null or b == null:
		return a == b
	return float(a["x"]) == float(b["x"]) and float(a["y"]) == float(b["y"])


static func _clone_cmd(cmd: Dictionary) -> Dictionary:
	var aim = null
	if cmd["aim"] != null:
		aim = {"x": float(cmd["aim"]["x"]), "y": float(cmd["aim"]["y"])}
	var lock = null
	if cmd["lock"] != null:
		lock = int(cmd["lock"])
	return {
		"throttle": float(cmd["throttle"]),
		"turn": float(cmd["turn"]),
		"strafe": float(cmd["strafe"]),
		"aim": aim,
		"fire": bool(cmd["fire"]),
		"slot": int(cmd["slot"]),
		"secondaries": bool(cmd["secondaries"]),
		"lock": lock,
	}
