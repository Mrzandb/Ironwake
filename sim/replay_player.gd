extends RefCounted
class_name SimReplayPlayer

## Plays a SimReplay snapshot one tick at a time.
## JSON numbers arrive as floats; vehicle ids are coerced back to int keys
## before SimFight.step, because a float key would miss the int id.

var replay: Dictionary
var world
var desync_at = null
var error := ""
var _cmd_index := 0
var _op_index := 0
var _hash_index := 0
var _current := {}


func _init(recording: Dictionary, battle) -> void:
	replay = recording
	world = battle
	if world == null:
		error = "replay could not build a world"


func done() -> bool:
	if world == null:
		return true
	return int(world.tick) >= int(replay["ticks"])


func step() -> void:
	if done():
		return
	var ops: Array = replay["ops"]
	while _op_index < ops.size() and int(ops[_op_index]["tick"]) <= int(world.tick):
		var op: Dictionary = ops[_op_index]
		_op_index += 1
		var body = _find(int(op["vehicle"]))
		if body != null:
			world.place(body, op["pos"], float(op["heading"]))
	var cmds: Array = replay["cmds"]
	while _cmd_index < cmds.size() and int(cmds[_cmd_index]["tick"]) <= int(world.tick):
		var entry: Dictionary = cmds[_cmd_index]
		_cmd_index += 1
		_current[int(entry["vehicle"])] = entry["cmd"]
	world.step(_current)
	var hashes: Array = replay["hashes"]
	while _hash_index < hashes.size() and int(hashes[_hash_index]["tick"]) <= int(world.tick):
		var entry: Dictionary = hashes[_hash_index]
		_hash_index += 1
		if int(entry["tick"]) == int(world.tick) and desync_at == null and str(entry["hash"]) != world.replay_hash():
			desync_at = int(world.tick)


func _find(vehicle_id: int):
	for vehicle in world.vehicles:
		if int(vehicle["id"]) == vehicle_id:
			return vehicle
	return null
