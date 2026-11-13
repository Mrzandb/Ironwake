extends RefCounted

const Util := preload("res://tests/world_util.gd")
const MatchScript := preload("res://sim/match/match.gd")
const Command := preload("res://sim/command.gd")
const Stats := preload("res://sim/stats/resolver.gd")


static func run(a) -> void:
	print("RUN match")
	var cat = Util.catalog()
	_roster(a, cat)
	_opening(a, cat)
	_respawn(a, cat)
	_choice(a, cat)
	_fee(a, cat)
	_result(a, cat)
	_friendly(a, cat)


static func _lineup() -> Array:
	return ["bulwark", "swarm", "hawk"]


static func _roster(a, cat) -> void:
	var quota := int(cat.rules["match"]["quotaPerType"])
	var roster := MatchScript.default_roster(0, "bulwark", _lineup(), 3, quota)
	a.eq(roster.size(), 6, "roster length")
	a.eq(int(roster[0]["team"]), 0, "player team")
	a.eq(str(roster[0]["name"]), "Player", "player name")
	a.eq(bool(roster[0]["ai"]), false, "player is not ai")
	a.eq(str(roster[0]["def"]), "bulwark", "player vehicle")
	for team in [0, 1]:
		for id in _lineup():
			var count := 0
			for entry in roster:
				if int(entry["team"]) == team and str(entry["def"]) == id:
					count += 1
			a.ok(count <= quota, "quota " + id)
	var red := MatchScript.default_roster(1, "hawk", _lineup(), 3, quota)
	a.eq(int(red[0]["team"]), 1, "red player team")
	var red_count := 0
	for entry in red:
		if int(entry["team"]) == 1:
			red_count += 1
	a.eq(red_count, 3, "red side size")


static func _open(cat, duration: float = -1.0) -> Dictionary:
	var hills = cat.map_def("hills")
	var world = Util.fight(cat, float(hills["size"]["w"]), float(hills["size"]["h"]), 1, "hills")
	var roster := MatchScript.default_roster(0, "bulwark", _lineup(), 3, int(cat.rules["match"]["quotaPerType"]))
	var fixture = MatchScript.new(world, hills, cat, roster, duration)
	return {"world": world, "match": fixture, "hills": hills}


static func _run(box: Dictionary, seconds: float) -> void:
	var ticks := int(round(seconds * 60.0))
	for _i in ticks:
		box["world"].step({})
		box["match"].step()
		if box["match"].result != null:
			return


static func _opening(a, cat) -> void:
	var box := _open(cat)
	var fixture = box["match"]
	var world = box["world"]
	a.eq(fixture.bases.size(), 2, "two bases")
	var mobile := 0
	for vehicle in world.vehicles:
		if str(vehicle["def"]["locomotion"]) != "static":
			mobile += 1
	a.eq(mobile, 6, "six vehicles")
	for slot in fixture.players:
		var body = fixture.vehicle_of(slot)
		var near := false
		for spawn in box["hills"]["spawns"]:
			if int(spawn["team"]) != int(slot["team"]):
				continue
			var dx := float(spawn["pos"]["x"]) - float(body["pos"]["x"])
			var dy := float(spawn["pos"]["y"]) - float(body["pos"]["y"])
			if dx * dx + dy * dy < 1.0:
				near = true
		a.ok(near, "spawned on a friendly point")


static func _respawn(a, cat) -> void:
	var box := _open(cat)
	var fixture = box["match"]
	var slot: Dictionary = fixture.players[0]
	var old = fixture.vehicle_of(slot)
	var old_id := int(old["id"])
	Util.kill(old)
	_run(box, 1.0)
	var rules: Dictionary = cat.rules["match"]
	a.near(fixture.respawn_left(slot), float(rules["respawn"]["large"]) - 1.0, "respawn left after 1s", 0.5)
	_run(box, float(rules["respawn"]["large"]))
	a.eq(slot["died_at"], null, "respawn clears the timer")
	var still := false
	for vehicle in box["world"].vehicles:
		if int(vehicle["id"]) == old_id:
			still = true
	a.ok(not still, "wreck is removed")
	a.eq(bool(fixture.vehicle_of(slot)["alive"]), true, "new body is alive")
	slot["died_at"] = 0.0
	slot["deaths"] = 1
	a.near(fixture.respawn_total(slot), 20.0, "first death uses the base time", Util.TOL)
	slot["deaths"] = 3
	a.near(fixture.respawn_total(slot), 20.0 * 1.3, "third death slows respawn", Util.TOL)
	slot["deaths"] = 50
	a.near(fixture.respawn_total(slot), 20.0 * float(rules["deathCap"]), "death multiplier is capped", Util.TOL)


static func _choice(a, cat) -> void:
	var box := _open(cat)
	var fixture = box["match"]
	var slot: Dictionary = fixture.players[0]
	Util.kill(fixture.vehicle_of(slot))
	_run(box, 0.1)
	a.eq(fixture.choose(slot, "hawk"), true, "waiting player can change vehicle")
	var rules: Dictionary = cat.rules["match"]
	a.near(fixture.respawn_total(slot), float(rules["respawn"]["small"]) + float(rules["changePenalty"]), "change adds the penalty", Util.TOL)
	var mates: Array = []
	for other in fixture.players:
		if int(other["team"]) == int(slot["team"]) and other != slot:
			mates.append(other)
	mates[0]["choice"] = "hawk"
	a.eq(fixture.can_choose(mates[1], "hawk"), false, "a third hawk is over quota")
	_run(box, float(rules["respawn"]["small"]) + float(rules["changePenalty"]) + 0.5)
	a.eq(str(fixture.vehicle_of(slot)["def"]["id"]), "hawk", "respawn uses the chosen vehicle")
	mates[1]["choice"] = "hawk"
	a.eq(MatchScript.pick_within_quota(fixture, 0, ["hawk", "bulwark"], slot), "bulwark", "quota picker skips a full type")


static func _fee(a, cat) -> void:
	var box := _open(cat)
	var fixture = box["match"]
	var slot: Dictionary = fixture.players[0]
	var seen := {"n": 0, "fee": -1.0}
	fixture.depart_gate = func(_slot, _id, fee):
		seen["n"] = int(seen["n"]) + 1
		seen["fee"] = float(fee)
		return false
	Util.kill(fixture.vehicle_of(slot))
	_run(box, 0.1)
	var before := str(slot["choice"])
	a.eq(fixture.choose(slot, "hawk"), false, "a refused departure does not change the choice")
	a.eq(str(slot["choice"]), before, "choice stays")
	a.eq(float(seen["fee"]), 0.0, "quoted departure fee is zero")
	a.ok(int(seen["n"]) >= 1, "the gate was consulted")
	var wreck_id := int(slot["vehicle"])
	_run(box, 30.0)
	a.ok(slot["died_at"] != null, "refused respawn keeps the player dead")
	var wreck = null
	for vehicle in box["world"].vehicles:
		if int(vehicle["id"]) == wreck_id:
			wreck = vehicle
	a.ok(wreck != null, "refused respawn keeps the wreck")
	a.eq(fixture.quoted_fee(slot, "hawk"), 0.0, "fee quote stays zero")


static func _result(a, cat) -> void:
	var box := _open(cat)
	for base in box["match"].bases:
		if int(base["team"]) == 1:
			Util.kill(base)
	_run(box, 0.1)
	a.eq(box["match"].result["winner"], 0, "destroying a base wins")
	a.eq(str(box["match"].result["reason"]), "base", "base reason")
	var both := _open(cat)
	for base in both["match"].bases:
		Util.kill(base)
	_run(both, 0.1)
	a.eq(both["match"].result["winner"], null, "both bases in one tick draw")
	a.eq(str(both["match"].result["reason"]), "base", "mutual base reason")
	var timed := _open(cat, 2.0)
	var hurt = null
	for base in timed["match"].bases:
		if int(base["team"]) == 0:
			hurt = base
	hurt["modules"]["core"]["structure"] = float(cat.structure_stats["baseStats"]["structure"]) - 100.0
	_run(timed, 3.0)
	a.eq(timed["match"].result["winner"], 1, "higher structure wins on time")
	a.eq(str(timed["match"].result["reason"]), "time", "time reason")
	var draw := _open(cat, 2.0)
	_run(draw, 3.0)
	a.eq(draw["match"].result["winner"], null, "equal structures draw")
	a.eq(str(draw["match"].result["reason"]), "time", "draw reason")


static func _friendly(a, cat) -> void:
	var world = Util.fight(cat, 20000.0, 20000.0, 1)
	var host = world.spawn(cat.vehicle("bulwark"), 0, {"x": 5000.0, "y": 10000.0}, 0.0)
	var friend = world.spawn(cat.vehicle("swarm"), 0, {"x": 6200.0, "y": 10000.0}, 0.0)
	var foe = world.spawn(cat.vehicle("hawk"), 1, {"x": 8000.0, "y": 10000.0}, 0.0)
	Stats.add_modifier(host, {"id": "nodisp", "stat": "dispersion", "op": {"kind": "set", "v": 0}, "source": "test", "appliesTo": "self", "stack": "stack"})
	var friend_hits := 0
	var foe_hits := 0
	var hold := Command.merge({"secondaries": false})
	var fire := Command.merge({"aim": {"x": float(foe["pos"]["x"]), "y": float(foe["pos"]["y"])}, "fire": true, "secondaries": false})
	for _i in 60 * 10:
		var cmds := {}
		cmds[int(host["id"])] = fire
		cmds[int(friend["id"])] = hold
		world.step(cmds)
		for event in world.events:
			if str(event.get("t", "")) != "hit":
				continue
			if int(event["vehicle"]) == int(friend["id"]):
				friend_hits += 1
			if int(event["vehicle"]) == int(foe["id"]):
				foe_hits += 1
	a.eq(friend_hits, 0, "friendly fire does not hit")
	a.ok(foe_hits > 0, "the round reaches the enemy")
	var lock_world = Util.fight(cat, 20000.0, 20000.0, 1)
	var shooter = lock_world.spawn(cat.vehicle("bulwark"), 0, {"x": 5000.0, "y": 10000.0}, 0.0)
	var ally = lock_world.spawn(cat.vehicle("swarm"), 0, {"x": 6200.0, "y": 10000.0}, 0.0)
	var cmds := {}
	cmds[int(shooter["id"])] = Command.merge({"lock": int(ally["id"])})
	lock_world.step(cmds)
	a.eq(shooter["lock"], null, "cannot lock an ally")
