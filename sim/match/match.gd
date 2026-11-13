extends RefCounted
class_name SimMatch

## Game_test@33f4be8 src/sim/match/match.ts.
## Called once after each SimFight.step. Opening spawns, wrecks, respawn,
## vehicle choice, and the base or time result. No currency is spent.
## quoted_fee is 0 and the blueprint fee field is not read. depart_gate may
## refuse a later choice or a respawn; the default gate allows every departure.

const Clock := preload("res://sim/clock.gd")
const Point := preload("res://sim/point.gd")
const CatalogScript := preload("res://sim/data/catalog.gd")

var world
var map_def: Dictionary
var catalog
var defs := {}
var players: Array = []
var bases: Array = []
var time_left: float
var result = null
var events: Array = []
var depart_gate: Callable = Callable()


func _init(battle, hills: Dictionary, data, roster: Array, duration: float = -1.0) -> void:
	world = battle
	map_def = hills
	catalog = data
	for id in data.lineup_ids():
		defs[str(id)] = data.vehicle(str(id))
	var rules: Dictionary = battle.rules
	time_left = float(rules["match"]["duration"]) if duration < 0.0 else duration
	for base in hills["bases"]:
		var team := int(base["team"])
		bases.append(battle.spawn(data.vehicle("base%d" % team), team, base["pos"], 0.0))
	for index in roster.size():
		var entry: Dictionary = roster[index]
		var team := int(entry["team"])
		var def_id := str(entry["def"])
		var body: Dictionary = _spawn_for(team, def_id, index)
		players.append({
			"index": index,
			"team": team,
			"name": str(entry["name"]),
			"ai": bool(entry["ai"]),
			"def": def_id,
			"choice": def_id,
			"vehicle": int(body["id"]),
			"deaths": 0,
			"died_at": null,
		})


func quoted_fee(_slot: Dictionary, _def_id: String) -> float:
	return 0.0


func departure_allowed(slot: Dictionary, def_id: String) -> bool:
	var fee := quoted_fee(slot, def_id)
	if depart_gate.is_valid():
		return bool(depart_gate.call(slot, def_id, fee))
	return fee <= 0.0


func vehicle_of(slot: Dictionary) -> Variant:
	var id := int(slot["vehicle"])
	for vehicle in world.vehicles:
		if int(vehicle["id"]) == id:
			return vehicle
	return null


func player_of(vehicle_id: int) -> Variant:
	for slot in players:
		if int(slot["vehicle"]) == vehicle_id:
			return slot
	return null


func count(team: int, def_id: String, except = null) -> int:
	var total := 0
	for slot in players:
		if except != null and slot == except:
			continue
		if int(slot["team"]) == team and str(slot["choice"]) == def_id:
			total += 1
	return total


func can_choose(slot: Dictionary, def_id: String) -> bool:
	if not defs.has(def_id):
		return false
	if str(slot["choice"]) == def_id:
		return true
	return count(int(slot["team"]), def_id, slot) < int(world.rules["match"]["quotaPerType"])


func choose(slot: Dictionary, def_id: String) -> bool:
	if not can_choose(slot, def_id):
		return false
	if not departure_allowed(slot, def_id):
		return false
	slot["choice"] = def_id
	return true


func respawn_total(slot: Dictionary) -> float:
	var rules: Dictionary = world.rules["match"]
	var blueprint: Dictionary = defs[str(slot["choice"])]
	var base := float(rules["respawn"][str(blueprint["size"])])
	if blueprint.has("respawn"):
		base = float(blueprint["respawn"])
	var deaths := maxi(0, int(slot["deaths"]) - 1)
	var mult := minf(float(rules["deathCap"]), 1.0 + float(rules["deathK"]) * float(deaths))
	var penalty := 0.0
	if str(slot["choice"]) != str(slot["def"]):
		penalty = float(rules["changePenalty"])
	return base * mult + penalty


func respawn_left(slot: Dictionary) -> float:
	if slot["died_at"] == null:
		return 0.0
	return maxf(0.0, float(slot["died_at"]) + respawn_total(slot) - world.sim_time())


func step() -> void:
	events = []
	if result != null:
		return
	time_left = maxf(0.0, time_left - Clock.DT)
	for slot in players:
		var body = vehicle_of(slot)
		if body != null and not bool(body["alive"]) and slot["died_at"] == null:
			slot["deaths"] = int(slot["deaths"]) + 1
			slot["died_at"] = world.sim_time()
			events.append({"t": "died", "player": int(slot["index"]), "respawn_in": respawn_total(slot)})
		if slot["died_at"] != null and respawn_left(slot) <= 0.0:
			if not departure_allowed(slot, str(slot["choice"])):
				continue
			if body != null:
				world.despawn(body)
			var spawned: Dictionary = _spawn_for(int(slot["team"]), str(slot["choice"]), int(slot["index"]))
			slot["vehicle"] = int(spawned["id"])
			slot["def"] = str(slot["choice"])
			slot["died_at"] = null
			events.append({"t": "respawned", "player": int(slot["index"]), "vehicle": int(spawned["id"])})
	var dead: Array = []
	for base in bases:
		if not base["alive"]:
			dead.append(int(base["team"]))
	if not dead.is_empty():
		var winner = null
		if dead.size() == 1:
			for base in bases:
				if int(base["team"]) != int(dead[0]):
					winner = int(base["team"])
		_end({"winner": winner, "reason": "base"})
		return
	if time_left <= 0.0:
		var scores: Array = []
		for base in bases:
			var module_id := str(base["def"]["modules"][0]["id"])
			scores.append({"team": int(base["team"]), "s": float(base["modules"][module_id]["structure"])})
		var top := -INF
		for score in scores:
			top = maxf(top, float(score["s"]))
		var leaders: Array = []
		for score in scores:
			if float(score["s"]) == top:
				leaders.append(score)
		var winner = null
		if leaders.size() == 1:
			winner = int(leaders[0]["team"])
		_end({"winner": winner, "reason": "time"})


func _end(next: Dictionary) -> void:
	result = next
	events.append({"t": "matchEnd", "result": next})


func _spawn_for(team: int, def_id: String, index: int) -> Dictionary:
	var points: Array = []
	for spawn in map_def["spawns"]:
		if int(spawn["team"]) == team:
			points.append(spawn)
	for k in points.size():
		var spawn: Dictionary = points[(index + k) % points.size()]
		var blocked := false
		for vehicle in world.vehicles:
			if not vehicle["alive"] or str(vehicle["def"]["locomotion"]) == "static":
				continue
			if Point.distance(vehicle["pos"], spawn["pos"]) < 250.0:
				blocked = true
				break
		if blocked:
			continue
		return world.spawn(defs[def_id], team, spawn["pos"], float(spawn["heading"]))
	var fallback: Dictionary = points[index % points.size()]
	return world.spawn(defs[def_id], team, fallback["pos"], float(fallback["heading"]))


static func pick_within_quota(battle, team: int, prefer: Array, except = null) -> String:
	var quota := int(battle.world.rules["match"]["quotaPerType"])
	for id in prefer:
		if battle.count(team, str(id), except) < quota:
			return str(id)
	return str(prefer[0])


static func default_roster(player_team: int, player_def: String, lineup: Array, per_team: int = 3, quota: int = -1) -> Array:
	if quota < 0:
		quota = int(CatalogScript.new().rules["match"]["quotaPerType"])
	var out: Array = [{"team": player_team, "name": "Player", "ai": false, "def": player_def}]
	var number := 1
	for team in [0, 1]:
		var cursor: int = int(team)
		while _team_count(out, team) < per_team:
			var def_id := str(lineup[cursor % lineup.size()])
			var tries := 0
			while _used(out, team, def_id) >= quota and tries < lineup.size():
				cursor += 1
				def_id = str(lineup[cursor % lineup.size()])
				tries += 1
			out.append({"team": team, "name": "AI-%d" % number, "ai": true, "def": def_id})
			number += 1
			cursor += 1
	return out


static func _team_count(roster: Array, team: int) -> int:
	var total := 0
	for entry in roster:
		if int(entry["team"]) == team:
			total += 1
	return total


static func _used(roster: Array, team: int, def_id: String) -> int:
	var total := 0
	for entry in roster:
		if int(entry["team"]) == team and str(entry["def"]) == def_id:
			total += 1
	return total
