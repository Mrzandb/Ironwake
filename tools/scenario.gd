extends SceneTree

## The prototype's 6-minute all-AI hills match.
## Kept out of the default suite. A 3-second slice of the same loop is in tests/ai_test.gd.
##
##   godot --headless --path . --script res://tools/scenario.gd
##   godot --headless --path . --script res://tools/scenario.gd -- --seconds 30

const CatalogScript := preload("res://sim/data/catalog.gd")
const FightScript := preload("res://sim/fight.gd")
const MatchScript := preload("res://sim/match/match.gd")
const NavScript := preload("res://sim/ai/nav.gd")
const Team := preload("res://sim/ai/team.gd")
const Simple := preload("res://sim/ai/simple.gd")
const Point := preload("res://sim/point.gd")


func _initialize() -> void:
	var seconds := 360
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seconds" and i + 1 < args.size():
			seconds = int(args[i + 1])
	var cat = CatalogScript.new()
	var first := _play(cat, seconds, 1)
	var second := _play(cat, seconds, 1)
	var ok := true
	ok = _check(first["shots"] > 100, "shots > 100 (%d)" % int(first["shots"])) and ok
	ok = _check(float(first["deepest"][0]) < 5000.0, "blue reached (%s)" % str(first["deepest"][0])) and ok
	ok = _check(float(first["deepest"][1]) < 5000.0, "red reached (%s)" % str(first["deepest"][1])) and ok
	var deaths := 0
	for slot in first["match"].players:
		deaths += int(slot["deaths"])
	ok = _check(deaths > 0, "someone died (%d)" % deaths) and ok
	var base_hurt := false
	for base in first["match"].bases:
		var full := float(base["def"]["modules"][0]["structure"])
		if float(base["modules"]["core"]["structure"]) < full:
			base_hurt = true
	ok = _check(base_hurt, "a base lost structure") and ok
	ok = _check(second["world"].state_hash() == first["world"].state_hash(), "repeat hash") and ok
	var same_result := str(second["match"].result) == str(first["match"].result)
	ok = _check(same_result, "repeat result %s" % str(first["match"].result)) and ok
	print("SCENARIO seconds=%d shots=%d deepest=%s,%s deaths=%d result=%s" % [seconds, int(first["shots"]), str(first["deepest"][0]), str(first["deepest"][1]), deaths, str(first["match"].result)])
	quit(0 if ok else 1)


func _play(cat, seconds: int, seed: int) -> Dictionary:
	var hills = cat.map_def("hills")
	var world = FightScript.new({"w": float(hills["size"]["w"]), "h": float(hills["size"]["h"])}, seed, hills, cat)
	var roster := MatchScript.default_roster(0, "bulwark", cat.lineup_ids(), 3, int(cat.rules["match"]["quotaPerType"]))
	var fixture = MatchScript.new(world, hills, cat, roster, float(seconds))
	var nav = NavScript.new(world)
	var params := Simple.with_params()
	var shots := 0
	var deepest: Array = [INF, INF]
	for _i in seconds * 60:
		if fixture.result != null:
			break
		var cmds := {}
		for slot in fixture.players:
			var body = fixture.vehicle_of(slot)
			if body != null and body["alive"]:
				cmds[int(body["id"])] = Team.think(world, nav, body, params)
		world.step(cmds)
		fixture.step()
		for event in world.events:
			if str(event.get("t", "")) == "fire":
				shots += 1
		for slot in fixture.players:
			var body = fixture.vehicle_of(slot)
			if body == null or not body["alive"]:
				continue
			for base in fixture.bases:
				if int(base["team"]) == int(slot["team"]):
					continue
				deepest[int(slot["team"])] = minf(float(deepest[int(slot["team"])]), Point.distance(body["pos"], base["pos"]))
	return {"world": world, "match": fixture, "shots": shots, "deepest": deepest}


func _check(cond: bool, label: String) -> bool:
	print("CHECK %s %s" % ["ok" if cond else "FAIL", label])
	return cond
