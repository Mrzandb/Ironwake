extends SceneTree

## Headless balance batch, same shape as Game_test `npm run balance`.
## Default is 8 symmetric 3v3 matches plus 6 duels of every pairing.
## This is not part of the CI suite.
##
##   godot --headless --path . --script res://tools/balance.gd
##   BAL_MATCHES=1 BAL_DUELS=0 BAL_SECONDS=30 godot --headless --path . --script res://tools/balance.gd

const Clock := preload("res://sim/clock.gd")
const CatalogScript := preload("res://sim/data/catalog.gd")
const FightScript := preload("res://sim/fight.gd")
const MatchScript := preload("res://sim/match/match.gd")
const NavScript := preload("res://sim/ai/nav.gd")
const Team := preload("res://sim/ai/team.gd")
const Simple := preload("res://sim/ai/simple.gd")

const IDS := ["bulwark", "swarm", "hawk"]
const DUEL_SECONDS := 180.0


func _initialize() -> void:
	var info := Engine.get_version_info()
	print("ENGINE %s.%s.%s.%s.%s" % [info.major, info.minor, info.patch, info.status, info.hash])
	var config := _config()
	var cat = CatalogScript.new()
	var params := Simple.with_params({
		"hold_dist": config["hold_dist"],
		"keep_distance": config["keep_distance"],
		"orbit_radius": config["orbit_radius"],
		"stalemate": config["stalemate"],
		"push_time": config["push_time"],
	})
	var stats := {}
	for id in IDS:
		stats[id] = _blank()
	var matches: Array = []
	for i in int(config["matches"]):
		print("MATCH %d / %d" % [i + 1, int(config["matches"])])
		matches.append(_play_match(cat, params, i + 1, i % 2 == 1, float(config["seconds"]), stats))
	var duels := {}
	for a_id in IDS:
		for b_id in IDS:
			var row := {"wins": 0, "losses": 0, "draws": 0, "time": 0.0}
			for s in int(config["duels"]):
				var duel := _duel(cat, a_id, b_id, s + 1, float(config["duel_keep"]))
				if duel["winner"] == null:
					row["draws"] = int(row["draws"]) + 1
				elif a_id == b_id or str(duel["winner"]) == a_id:
					row["wins"] = int(row["wins"]) + 1
				else:
					row["losses"] = int(row["losses"]) + 1
				row["time"] = float(row["time"]) + float(duel["time"])
			duels["%s>%s" % [a_id, b_id]] = row
			print("DUEL %s>%s %d/%d/%d" % [a_id, b_id, int(row["wins"]), int(row["losses"]), int(row["draws"])])
	var text := _report(cat, config, params, matches, stats, duels)
	print(text)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	var markdown := FileAccess.open("res://reports/balance-report.md", FileAccess.WRITE)
	markdown.store_string(text)
	markdown.close()
	var payload := {
		"config": config,
		"matches": matches,
		"stats": stats,
		"duels": duels,
	}
	var json := FileAccess.open("res://reports/balance-report.json", FileAccess.WRITE)
	json.store_string(JSON.stringify(payload, "  "))
	json.close()
	quit(0)


func _config() -> Dictionary:
	var config := {
		"matches": _env_int("BAL_MATCHES", 8),
		"duels": _env_int("BAL_DUELS", 6),
		"seconds": _env_float("BAL_SECONDS", 600.0),
		"duel_keep": _env_float("BAL_DUEL_KEEP", 900.0),
		"hold_dist": _env_float("BAL_HOLD_DIST", 2400.0),
		"keep_distance": _env_float("BAL_KEEP_DIST", 1800.0),
		"orbit_radius": _env_float("BAL_ORBIT", 420.0),
		"stalemate": _env_float("BAL_STALEMATE", 30.0),
		"push_time": _env_float("BAL_PUSH_TIME", 30.0),
	}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i])
		if arg == "--smoke":
			config["matches"] = 1
			config["duels"] = 0
			config["seconds"] = 30.0
		elif arg == "--matches" and i + 1 < args.size():
			i += 1
			config["matches"] = int(args[i])
		elif arg == "--duels" and i + 1 < args.size():
			i += 1
			config["duels"] = int(args[i])
		elif arg == "--seconds" and i + 1 < args.size():
			i += 1
			config["seconds"] = float(args[i])
		i += 1
	return config


func _play_match(cat, params: Dictionary, seed: int, swap: bool, seconds: float, stats: Dictionary) -> Dictionary:
	var hills = cat.map_def("hills")
	var world = FightScript.new({"w": float(hills["size"]["w"]), "h": float(hills["size"]["h"])}, seed, hills, cat)
	var roster: Array = []
	var number := 1
	for team in [0, 1]:
		for id in IDS:
			var side: int = (1 - int(team)) if swap else int(team)
			roster.append({"team": side, "name": "AI-%d" % number, "ai": true, "def": id})
			number += 1
	var fixture = MatchScript.new(world, hills, cat, roster, seconds)
	var nav = NavScript.new(world)
	var def_of := {}
	var last_hit := {}
	var seen := {}
	while fixture.result == null:
		var cmds := {}
		for slot in fixture.players:
			var body = fixture.vehicle_of(slot)
			if body == null:
				continue
			var id := int(body["id"])
			if not seen.has(id):
				seen[id] = true
				def_of[id] = str(slot["def"])
				stats[str(slot["def"])]["lives"] = int(stats[str(slot["def"])]["lives"]) + 1
			if body["alive"]:
				cmds[id] = Team.think(world, nav, body, params)
				stats[str(slot["def"])]["lifetime"] = float(stats[str(slot["def"])]["lifetime"]) + Clock.DT
		world.step(cmds)
		_tally(world, stats, def_of, last_hit)
		fixture.step()
	var hp: Array = []
	for team in [0, 1]:
		for base in fixture.bases:
			if int(base["team"]) == team:
				hp.append(float(base["modules"]["core"]["structure"]))
	return {
		"result": fixture.result,
		"time": seconds - float(fixture.time_left),
		"hp": hp,
		"seed": seed,
		"swap": swap,
	}


func _tally(world, stats: Dictionary, def_of: Dictionary, last_hit: Dictionary) -> void:
	for event in world.events:
		var kind := str(event.get("t", ""))
		if kind == "fire":
			var shooter = def_of.get(int(event["vehicle"]), "")
			if shooter != "":
				stats[shooter]["shots"] = int(stats[shooter]["shots"]) + 1
			continue
		if kind != "hit" and kind != "beamDamage":
			if kind == "vehicleDestroyed":
				var victim = def_of.get(int(event["vehicle"]), "")
				if victim == "":
					continue
				stats[victim]["deaths"] = int(stats[victim]["deaths"]) + 1
				var killer_id = last_hit.get(int(event["vehicle"]), -1)
				var killer = def_of.get(int(killer_id), "")
				if killer != "":
					stats[killer]["kills"] = int(stats[killer]["kills"]) + 1
			continue
		var struct := 0.0
		if kind == "hit":
			struct = float(event["log"]["struct"])
		else:
			struct = float(event["struct"])
		if struct <= 0.0 and kind == "beamDamage":
			continue
		var by = def_of.get(int(event["by"]), "")
		var target = null
		for vehicle in world.vehicles:
			if int(vehicle["id"]) == int(event["vehicle"]):
				target = vehicle
				break
		if kind == "hit" and by != "" and str(event.get("result", "")) != "splash":
			stats[by]["hits"] = int(stats[by]["hits"]) + 1
			var result := str(event.get("result", ""))
			if result == "pen" or result == "overmatch":
				stats[by]["pens"] = int(stats[by]["pens"]) + 1
		if target == null:
			continue
		if str(target["def"]["locomotion"]) == "static":
			if by != "":
				stats[by]["base_damage"] = float(stats[by]["base_damage"]) + struct
			continue
		if by != "":
			stats[by]["dealt"] = float(stats[by]["dealt"]) + struct
		var victim = def_of.get(int(target["id"]), "")
		if victim != "":
			stats[victim]["taken"] = float(stats[victim]["taken"]) + struct
		if struct > 0.0:
			last_hit[int(target["id"])] = int(event["by"])


func _duel(cat, a_id: String, b_id: String, seed: int, keep: float) -> Dictionary:
	var world = FightScript.new({"w": 14000.0, "h": 14000.0}, seed, null, cat)
	var flip := seed % 2 == 1
	var left = world.spawn(cat.vehicle(a_id), 0, {"x": 9500.0 if flip else 4500.0, "y": 7000.0}, PI if flip else 0.0)
	var right = world.spawn(cat.vehicle(b_id), 1, {"x": 4500.0 if flip else 9500.0, "y": 7000.0 + float(seed % 3) * 200.0}, 0.0 if flip else PI)
	var params := Simple.with_params({"keep_distance": keep})
	var limit := int(DUEL_SECONDS * 60.0)
	for i in limit:
		var cmds := {}
		cmds[int(left["id"])] = Simple.think(left, right, params, world.table, world.rules)
		cmds[int(right["id"])] = Simple.think(right, left, params, world.table, world.rules)
		world.step(cmds)
		if not left["alive"] or not right["alive"]:
			var winner = null
			if left["alive"]:
				winner = a_id
			elif right["alive"]:
				winner = b_id
			return {"winner": winner, "time": float(i) / 60.0}
	return {"winner": null, "time": DUEL_SECONDS}


func _report(cat, config: Dictionary, params: Dictionary, matches: Array, stats: Dictionary, duels: Dictionary) -> String:
	var wins := [0, 0]
	var draws := 0
	var by_base := 0
	var time_sum := 0.0
	for fixture in matches:
		time_sum += float(fixture["time"])
		var result: Dictionary = fixture["result"]
		if str(result["reason"]) == "base":
			by_base += 1
		if result["winner"] == null:
			draws += 1
		else:
			wins[int(result["winner"])] = int(wins[int(result["winner"])]) + 1
	var count := maxi(matches.size(), 1)
	var lines: PackedStringArray = []
	lines.append("# 数值平衡批跑报告")
	lines.append("")
	lines.append("- 3v3 对局：%d 局（每局上限 %s s，阵容对称，奇数局交换出生边）" % [int(config["matches"]), _f0(float(config["seconds"]))])
	lines.append("- 单挑：每对载具 %d 场（上限 %s s）" % [int(config["duels"]), _f0(DUEL_SECONDS)])
	lines.append("- AI：holdDist %s · keepDist %s · orbit %s · 单挑保持 %s" % [_f0(float(params["hold_dist"])), _f0(float(params["keep_distance"])), _f0(float(params["orbit_radius"])), _f0(float(config["duel_keep"]))])
	lines.append("")
	lines.append("## 对局结果")
	lines.append("")
	lines.append("| 指标 | 数值 |")
	lines.append("|---|---|")
	lines.append("| 蓝方胜 / 红方胜 / 平局 | %d / %d / %d |" % [wins[0], wins[1], draws])
	lines.append("| 摧毁基地结束的比例 | %s |" % _pct(float(by_base) / float(count)))
	lines.append("| 平均对局时长 | %s s |" % _f0(time_sum / float(count)))
	lines.append("")
	lines.append("## 各载具（3v3 汇总）")
	lines.append("")
	lines.append("| 载具 | 出场条命 | 击杀 | 阵亡 | K/D | 造成伤害 | 承受伤害 | 打基地 | 开火 | 命中率 | 击穿占命中 | 平均存活 s |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for id in IDS:
		var row: Dictionary = stats[id]
		var deaths := maxi(int(row["deaths"]), 1)
		var shots := maxi(int(row["shots"]), 1)
		var hits := maxi(int(row["hits"]), 1)
		var lives := maxi(int(row["lives"]), 1)
		lines.append("| %s | %d | %d | %d | %.2f | %s | %s | %s | %d | %s | %s | %s |" % [
			str(cat.vehicle(id)["name"]),
			int(row["lives"]),
			int(row["kills"]),
			int(row["deaths"]),
			float(row["kills"]) / float(deaths),
			_f0(float(row["dealt"])),
			_f0(float(row["taken"])),
			_f0(float(row["base_damage"])),
			int(row["shots"]),
			_pct(float(row["hits"]) / float(shots)),
			_pct(float(row["pens"]) / float(hits)),
			_f0(float(row["lifetime"]) / float(lives)),
		])
	lines.append("")
	lines.append("## 单挑胜率矩阵（行 vs 列，胜 / 负 / 平）")
	lines.append("")
	var header := "| |"
	var rule := "|---|"
	for id in IDS:
		header += " %s |" % str(cat.vehicle(id)["name"])
		rule += "---|"
	lines.append(header)
	lines.append(rule)
	for a_id in IDS:
		var row := "| %s |" % str(cat.vehicle(a_id)["name"])
		for b_id in IDS:
			var cell: Dictionary = duels["%s>%s" % [a_id, b_id]]
			row += " %d/%d/%d |" % [int(cell["wins"]), int(cell["losses"]), int(cell["draws"])]
		lines.append(row)
	lines.append("")
	lines.append("> 命中率 = 直接命中（不含溅射）÷ 开火次数；激光是持续照射，只计伤害，开火 / 命中只统计炮弹与导弹。")
	lines.append("> 击杀归属：最后一次对其造成结构伤害的载具。同型单挑（对角线）记为「分出胜负 / 0 / 平局」。")
	lines.append("")
	return "\n".join(lines)


func _blank() -> Dictionary:
	return {
		"lives": 0,
		"kills": 0,
		"deaths": 0,
		"dealt": 0.0,
		"taken": 0.0,
		"base_damage": 0.0,
		"shots": 0,
		"hits": 0,
		"pens": 0,
		"lifetime": 0.0,
	}


func _env_int(name: String, fallback: int) -> int:
	var raw := OS.get_environment(name)
	if raw == "":
		return fallback
	return int(raw)


func _env_float(name: String, fallback: float) -> float:
	var raw := OS.get_environment(name)
	if raw == "":
		return fallback
	return float(raw)


func _pct(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


func _f0(value: float) -> String:
	return str(int(round(value)))
