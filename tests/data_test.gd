extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const Schema := preload("res://sim/data/schema.gd")

## sha256 of tests/golden/sha256.json. That file hashes every baked table,
## so this one constant locks the Game_test@33f4be8 export.
const SHA_LOCK := "83012f1faac02d3ab757cf406adb771700f8dd933545499faca62cd344205843"


static func run(a) -> void:
	print("RUN data")
	var cat = CatalogScript.new()
	_files(a)
	_golden(cat, a)
	_anchors(cat, a)
	_shapes(cat, a)
	_omissions(cat, a)
	_cost(cat, a)
	_precision(cat, a)


static func _files(a) -> void:
	var manifest_path := "res://tests/golden/sha256.json"
	a.eq(FileAccess.get_sha256(manifest_path), SHA_LOCK, "golden sha256.json frozen")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	a.ok(typeof(manifest) == TYPE_DICTIONARY, "sha256 manifest is an object")
	if typeof(manifest) != TYPE_DICTIONARY:
		return
	var present := {}
	_collect_files("res://data", "data", present)
	_collect_files("res://tests/golden", "tests/golden", present)
	for rel in manifest.keys():
		var rel_s := str(rel)
		var hash := FileAccess.get_sha256("res://" + rel_s)
		a.eq(hash, str(manifest[rel]), "sha256 " + rel_s)
		a.ok(present.has(rel_s), "baked file exists " + rel_s)
	for rel in present.keys():
		if str(rel) == "tests/golden/sha256.json":
			continue
		a.ok(manifest.has(rel), "baked file is hashed " + str(rel))


static func _collect_files(dir_path: String, prefix: String, acc: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var file_name := str(name)
		if file_name.begins_with("."):
			continue
		if file_name.ends_with(".import"):
			continue
		acc[prefix + "/" + file_name] = true
	for sub in dir.get_directories():
		var sub_name := str(sub)
		if sub_name.begins_with("."):
			continue
		_collect_files(dir_path.path_join(sub_name), prefix + "/" + sub_name, acc)


static func _golden(cat, a) -> void:
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/scalars.json"))
	a.ok(typeof(golden) == TYPE_DICTIONARY, "scalar golden is an object")
	if typeof(golden) != TYPE_DICTIONARY:
		return
	var got := {}
	_flatten(cat.index, "index", got)
	_flatten(cat.rules, "rules", got)
	_flatten(cat.weapon_table, "weapons", got)
	_flatten(cat.structure_stats, "structures", got)
	var ids: Array = cat.blueprints.keys()
	ids.sort()
	for id in ids:
		_flatten(cat.blueprints[id], "vehicles." + str(id), got)
	for id in cat.map_docs.keys():
		_flatten(cat.map_docs[id], "maps." + str(id), got)
	var mismatches := 0
	for key in golden.keys():
		if not got.has(key):
			mismatches += 1
			if mismatches <= 8:
				a.ok(false, "missing scalar " + str(key))
			continue
		if not _same(got[key], golden[key]):
			mismatches += 1
			if mismatches <= 8:
				a.eq(got[key], golden[key], "scalar " + str(key))
	for key in got.keys():
		if not golden.has(key):
			mismatches += 1
			if mismatches <= 8:
				a.ok(false, "extra scalar " + str(key))
	if mismatches == 0:
		a.ok(true, "all %d scalar leaves match the prototype export" % golden.size())
	else:
		a.ok(false, "scalar mismatches %d" % mismatches)


static func _flatten(value, leaf_path: String, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		if value.size() == 1 and value.has("$"):
			var marker := str(value["$"])
			if marker == "inf" or marker == "-inf":
				out[leaf_path] = marker
				return
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			var name := str(key)
			if name == "parts":
				var parts: Array = value[key]
				var verts := 0
				for ring in parts:
					verts += ring.size()
				# JSON numbers parse as float. Counts are synthesized here, so
				# store them as float too or the golden compare sees int vs float.
				out[leaf_path + ".partCount"] = float(parts.size())
				out[leaf_path + ".vertexCount"] = float(verts)
				continue
			var next := name if leaf_path == "" else leaf_path + "." + name
			_flatten(value[key], next, out)
		return
	if typeof(value) == TYPE_ARRAY:
		for i in value.size():
			_flatten(value[i], "%s[%d]" % [leaf_path, i], out)
		return
	if typeof(value) == TYPE_FLOAT and is_inf(value):
		out[leaf_path] = "inf" if value > 0.0 else "-inf"
		return
	out[leaf_path] = value


static func _same(actual, expected) -> bool:
	if typeof(actual) != typeof(expected):
		return false
	return actual == expected


static func _anchors(cat, a) -> void:
	a.eq(str(cat.index["prototype"]["commit"]), "33f4be8b19df7fe4137550e1da8ee38bf41aa94e", "prototype commit")
	a.eq(cat.look_range(), 7200.0, "look range")
	a.eq(cat.weapon_table["rangeScale"], 3, "range scale")
	a.near(float(cat.weapon_table["defaultSigmaRatio"]), 0.5, "default sigma", 0.0)
	a.eq(cat.weapon_table["bulwarkAp"]["p0"], 620, "bulwark AP p0")
	a.eq(cat.weapon_table["bulwarkAp"]["range"], 1600, "bulwark AP unscaled range")
	a.eq(cat.weapon_table["swarmAp"]["p0"], 380, "swarm AP p0")
	a.eq(cat.weapon_table["swarmAp"]["range"], 1400, "swarm AP unscaled range")

	_weapon(cat, a, "bulwark_main", Schema.WEAPON_KINETIC, 4800, 7.0, 1500.0)
	_weapon(cat, a, "swarm_main", Schema.WEAPON_KINETIC, 4200, 4.5, 1250.0)
	_weapon(cat, a, "swarm_sec", Schema.WEAPON_KINETIC, 2400, 1.4, 1550.0)
	_weapon(cat, a, "bulwark_he_sec", Schema.WEAPON_KINETIC, 2700, 1.7, 1300.0)
	_weapon(cat, a, "hawk_laser", Schema.WEAPON_LASER, 2100, 0.0, 0.0)
	_weapon(cat, a, "hawk_missile", Schema.WEAPON_MISSILE, 3416, 34.0, 0.0)
	_weapon(cat, a, "torpedo_ap", Schema.WEAPON_MISSILE, 3026, 45.0, 0.0)
	_weapon(cat, a, "emp_missile", Schema.WEAPON_MISSILE, 2904, 40.0, 0.0)

	var main = cat.weapon("bulwark_main")
	a.eq(main["ammo"][0]["p0"], 620, "bulwark AP ammo p0")
	a.eq(main["ammo"][0]["damage"], 100, "bulwark AP damage")
	a.eq(main["ammo"][1]["hePen"], 260, "bulwark HE pen")
	a.near(float(main["dispersion"]["base"]), 2.4, "bulwark dispersion", 0.0)
	a.near(float(main["dispersion"]["sigmaRatio"]), 0.3, "bulwark sigma", 0.0)
	var laser = cat.weapon("hawk_laser")
	a.eq(laser["erodePerSec"], 6, "laser erode")
	a.eq(laser["structPerSec"], 16, "laser structure")
	a.eq(laser["stunPerSec"], 10, "laser stun")
	a.eq(laser["gate"], 90, "laser gate")
	a.eq(laser["heat"]["max"], 100, "laser heat max")
	a.eq(laser["heat"]["perSec"], 14, "laser heat rate")
	a.eq(laser["heat"]["cool"], 20, "laser cool")
	a.near(float(laser["heat"]["lockout"]), 3.5, "laser lockout", 0.0)
	var missile = cat.weapon("hawk_missile")
	a.eq(missile["warhead"]["hePen"], 200, "hawk missile pen")
	a.eq(missile["warhead"]["damage"], 360, "hawk missile damage")
	a.eq(missile["warhead"]["erode"], 200, "hawk missile erode")
	a.eq(missile["volley"], 2, "hawk missile volley")
	a.eq(missile["volleyFan"], 10, "hawk missile fan")
	a.eq(missile["guided"], true, "hawk missile guided")
	var torpedo = cat.weapon("torpedo_ap")
	a.eq(torpedo["guided"], false, "torpedo unguided")
	a.eq(torpedo["warhead"]["fixedPen"], true, "torpedo fixed pen")
	a.eq(torpedo["warhead"]["p0"], 520, "torpedo p0")
	var emp = cat.weapon("emp_missile")
	a.eq(emp["warhead"]["kind"], "EMP", "emp kind")
	a.eq(emp["warhead"]["stun"], 260, "emp stun")
	a.eq(emp["warhead"]["damage"], 15, "emp damage")

	var rules = cat.rules
	a.eq(rules["overmatchK"], 3, "overmatch")
	a.near(float(rules["armorFloor"]), 0.25, "armor floor", 0.0)
	a.near(float(rules["heMinFactor"]), 0.15, "HE floor", 0.0)
	a.near(float(rules["apStunMul"]), 0.8, "AP stun mul", 0.0)
	a.near(float(rules["heStunMul"]), 1.5, "HE stun mul", 0.0)
	a.eq(rules["reboot"]["small"], 3, "reboot small")
	a.eq(rules["reboot"]["medium"], 8, "reboot medium")
	a.eq(rules["reboot"]["large"], 12, "reboot large")
	a.eq(rules["repair"]["timeMul"], 3, "repair mul")
	a.near(float(rules["repair"]["restore"]), 0.5, "repair restore", 0.0)
	a.eq(rules["immunity"], 2, "immunity")
	a.eq(rules["stunDecayDelay"], 2, "stun decay delay")
	a.near(float(rules["stunDecayRate"]), 0.2, "stun decay rate", 0.0)
	a.eq(rules["ricochetDeg"], 68, "ricochet")
	a.near(float(rules["fireTolerance"]["auto"]), 1.5, "auto tolerance", 0.0)
	a.eq(rules["fireTolerance"]["primary"], 5, "primary tolerance")
	a.eq(rules["match"]["duration"], 600, "match duration")
	a.eq(rules["match"]["quotaPerType"], 2, "quota")
	a.near(float(rules["match"]["deathK"]), 0.15, "death k", 0.0)
	a.near(float(rules["match"]["deathCap"]), 2.5, "death cap", 0.0)
	a.eq(rules["match"]["changePenalty"], 5, "change penalty")
	a.eq(rules["match"]["respawn"]["small"], 8, "respawn small")
	a.eq(rules["match"]["respawn"]["medium"], 12, "respawn medium")
	a.eq(rules["match"]["respawn"]["large"], 20, "respawn large")
	a.eq(rules["terrain"]["wallHp"], 1800, "wall hp")
	a.near(float(rules["terrain"]["heMul"]), 1.5, "wall HE mul", 0.0)
	a.near(float(rules["terrain"]["laserMul"]), 0.5, "wall laser mul", 0.0)
	a.eq(rules["statLimits"]["default"][0], 0, "stat default min")
	a.eq(rules["statLimits"]["default"][1], INF, "stat default max")
	a.eq(rules["statLimits"]["range"][1], INF, "stat range max")
	a.eq(rules["statLimits"]["reload"][1], INF, "stat reload max")
	a.eq(rules["statLimits"]["shellSpeed"][1], INF, "stat shell max")
	a.near(float(rules["statLimits"]["reload"][0]), 0.1, "stat reload min", 0.0)

	a.eq(cat.structure_stats["baseSize"], 480, "base size")
	a.eq(cat.structure_stats["baseStats"]["armor"], 100, "base armor")
	a.eq(cat.structure_stats["baseStats"]["structure"], 5000, "base structure")
	a.eq(cat.structure_stats["baseStats"]["armorRegen"], 1, "base regen")

	_vehicle(cat, a, "bulwark", "壁垒", Schema.LOCOMOTION_LEGGED, Schema.SIZE_LARGE, 110, 150, 20, 16)
	_vehicle(cat, a, "swarm", "蜂群", Schema.LOCOMOTION_TRACKED, Schema.SIZE_MEDIUM, 180, 100, 0, 14)
	_vehicle(cat, a, "hawk", "隼「刺隼」", Schema.LOCOMOTION_HOVER, Schema.SIZE_SMALL, 400, 52, 0, 11)
	_vehicle(cat, a, "hawkB", "隼 · 备选方案 B「翼隼」", Schema.LOCOMOTION_HOVER, Schema.SIZE_SMALL, 400, 52, 0, 10)
	_vehicle(cat, a, "hawkC", "隼 · 备选方案 C「双体隼」", Schema.LOCOMOTION_HOVER, Schema.SIZE_SMALL, 400, 52, 0, 12)
	_vehicle(cat, a, "base0", "我方基地", Schema.LOCOMOTION_STATIC, Schema.SIZE_LARGE, 0, 250, 0, 1)
	_vehicle(cat, a, "base1", "敌方基地", Schema.LOCOMOTION_STATIC, Schema.SIZE_LARGE, 0, 250, 0, 1)

	var gun = _mod(cat.vehicle("bulwark"), "mainGun")
	a.eq(gun["armor"], 350, "bulwark gun armor")
	a.eq(gun["structure"], 560, "bulwark gun structure")
	a.eq(gun["stunMax"], 120, "bulwark gun stun")
	a.eq(_mod(cat.vehicle("bulwark"), "armR")["armor"], 320, "bulwark shoulder armor")
	a.eq(_mod(cat.vehicle("hawk"), "nose")["armor"], 70, "hawk nose armor")
	a.eq(_mod(cat.vehicle("swarm"), "hullL")["armor"], 170, "swarm left hull armor")
	a.eq(_mod(cat.vehicle("swarm"), "hullR")["armor"], 140, "swarm right hull armor")
	a.near(float(cat.vehicle("bulwark")["gait"]["stepTime"]), 0.6, "bulwark step", 0.0)
	a.eq(cat.vehicle("bulwark")["gait"]["threshold"], 34, "bulwark step threshold")
	a.ok(not cat.vehicle("hawk").has("gait"), "hawk has no gait")
	a.ok(not cat.vehicle("swarm").has("gait"), "swarm has no gait")
	var leg = _mod(cat.vehicle("bulwark"), "legFL")["leg"]
	a.eq(leg["group"], 0, "front left leg group")
	a.eq(leg["spec"]["bend"], -1, "front left leg bend")
	a.eq(cat.blueprint("bulwark")["legSpec"]["bend"], 1, "leg template bend")
	a.eq(cat.blueprint("bulwark")["legSpec"]["upper"], 92, "leg upper")
	a.eq(cat.blueprint("bulwark")["legSpec"]["lower"], 86, "leg lower")

	var hills = cat.map_def("hills")
	a.eq(hills["id"], "hills", "map id")
	a.eq(hills["name"], "丘陵", "map name")
	a.eq(hills["size"]["w"], 10000, "map width")
	a.eq(hills["size"]["h"], 10000, "map height")
	a.eq(cat.min_passage("hills"), 520, "min passage")
	a.eq(hills["obstacles"].size(), 20, "obstacle count")
	a.eq(hills["spawns"].size(), 6, "spawn count")
	a.eq(hills["bases"].size(), 2, "base count")
	a.eq(hills["bases"][0]["team"], 0, "base team 0")
	a.eq(hills["bases"][0]["pos"]["x"], 700, "base0 x")
	a.eq(hills["bases"][0]["pos"]["y"], 9380, "base0 y")
	a.eq(hills["bases"][1]["pos"]["x"], 9330, "base1 x")
	a.eq(hills["bases"][1]["pos"]["y"], 760, "base1 y")
	var rocks := 0
	var walls := 0
	for obstacle in hills["obstacles"]:
		if str(obstacle["kind"]) == "rock":
			rocks += 1
		elif str(obstacle["kind"]) == "wall":
			walls += 1
		else:
			a.ok(false, "unknown obstacle " + str(obstacle["id"]))
		a.ok(obstacle["poly"].size() >= 3, str(obstacle["id"]) + " polygon")
	a.eq(rocks, 16, "rock count")
	a.eq(walls, 4, "wall count")
	var team0 := 0
	var team1 := 0
	for spawn in hills["spawns"]:
		if int(spawn["team"]) == 0:
			team0 += 1
		elif int(spawn["team"]) == 1:
			team1 += 1
	a.eq(team0, 3, "team 0 spawns")
	a.eq(team1, 3, "team 1 spawns")
	a.near(float(hills["spawns"][0]["heading"]), -PI / 4.0, "spawn heading", 1e-12)
	a.near(float(hills["spawns"][3]["heading"]), 3.0 * PI / 4.0, "enemy spawn heading", 1e-12)


static func _weapon(cat, a, id: String, kind: String, weapon_range: int, reload: float, shell: float) -> void:
	var weapon = cat.weapon(id)
	a.eq(weapon["id"], id, id + " id")
	a.eq(weapon["kind"], kind, id + " kind")
	a.eq(weapon["range"], weapon_range, id + " range")
	if kind == Schema.WEAPON_MISSILE or kind == Schema.WEAPON_KINETIC:
		a.near(float(weapon["reload"]), reload, id + " reload", 0.0)
	if kind == Schema.WEAPON_KINETIC:
		a.near(float(weapon["shellSpeed"]), shell, id + " shell", 0.0)


static func _vehicle(cat, a, id: String, display_name: String, locomotion: String, size: String, speed: int, radius: int, crown: int, modules: int) -> void:
	var vehicle = cat.vehicle(id)
	a.eq(vehicle["id"], id, id + " id")
	a.eq(vehicle["name"], display_name, id + " name")
	a.eq(vehicle["locomotion"], locomotion, id + " locomotion")
	a.eq(vehicle["size"], size, id + " size")
	a.eq(vehicle["move"]["maxSpeed"], speed, id + " speed")
	a.eq(vehicle["collisionRadius"], radius, id + " radius")
	a.eq(vehicle["crownRate"], crown, id + " crown")
	a.eq(vehicle["modules"].size(), modules, id + " modules")
	a.eq(vehicle["cost"], 0, id + " cost")


static func _shapes(cat, a) -> void:
	for id in cat.vehicle_ids():
		var vehicle = cat.vehicle(str(id))
		a.ok(vehicle["modules"].size() > 0, str(id) + " has modules")
		for module in vehicle["modules"]:
			var parts: Array = module["parts"]
			a.ok(parts.size() > 0, str(vehicle["id"]) + "/" + str(module["id"]) + " parts")
			for ring in parts:
				a.ok(ring.size() >= 3, str(module["id"]) + " ring")
			if module.has("weapon"):
				a.ok(cat.weapon_table["weapons"].has(str(module["weapon"])), str(module["id"]) + " weapon exists")
	_point(a, _mod(cat.vehicle("bulwark"), "mainGun")["parts"][0][0], 56.0, -15.0, "main gun root")
	_point(a, _mod(cat.vehicle("bulwark"), "secC")["parts"][0][0], 15.705952052691874, 6.505618350206526, "sec octagon")
	_point(a, _mod(cat.vehicle("bulwark"), "legFL")["parts"][0][0], 70.454912135148, -82.29924662697229, "leg rest")
	_point(a, _mod(cat.vehicle("swarm"), "power")["parts"][0][0], 34.78460969082653, -9.000000000000002, "swarm hex")
	_point(a, _mod(cat.vehicle("hawk"), "podL")["parts"][0][0], -41.0, -27.0, "hawk pod")
	_point(a, _mod(cat.vehicle("base0"), "core")["parts"][0][0], 150.0, -240.0, "base chamfer")
	var equipped := {}
	for id in cat.vehicle_ids():
		for module in cat.vehicle(str(id))["modules"]:
			if module.has("weapon"):
				equipped[str(module["weapon"])] = true
	var used: Array = equipped.keys()
	used.sort()
	a.eq(used, ["bulwark_he_sec", "bulwark_main", "hawk_laser", "hawk_missile", "swarm_main", "swarm_sec"], "equipped weapons")
	var unused: Array = []
	for id in cat.weapon_ids():
		if not equipped.has(str(id)):
			unused.append(str(id))
	unused.sort()
	a.eq(unused, ["emp_missile", "torpedo_ap"], "unequipped examples")


static func _omissions(cat, a) -> void:
	for id in cat.weapon_ids():
		a.ok(not cat.weapon(str(id)).has("salvo"), str(id) + " salvo left unset")
	var sec = cat.weapon("swarm_main")["dispersion"]
	a.ok(not sec.has("sigmaRatio"), "swarm main uses default sigma")
	a.ok(cat.weapon("bulwark_main")["dispersion"].has("sigmaRatio"), "bulwark main sets sigma")
	a.ok(not _mod(cat.vehicle("bulwark"), "secC")["turret"].has("arcCenter"), "center turret is free")
	a.eq(_mod(cat.vehicle("bulwark"), "secL")["turret"]["arcCenter"], -67.5, "left turret arc")
	a.ok(not _mod(cat.vehicle("swarm"), "sec4")["turret"].has("arcCenter"), "swarm sec4 is free")
	a.eq(_mod(cat.vehicle("swarm"), "sec1")["turret"]["arcCenter"], 37.5, "swarm sec1 arc")
	a.ok(not _mod(cat.vehicle("bulwark"), "core").has("stunMax"), "core has no stun track")
	a.eq(_mod(cat.vehicle("bulwark"), "power")["stunMax"], 220, "bulwark power stun")
	a.ok(not cat.weapon("torpedo_ap").has("volley"), "torpedo volley omitted")
	a.ok(not cat.weapon("emp_missile").has("volley"), "emp volley omitted")


static func _cost(cat, a) -> void:
	for id in cat.vehicle_ids():
		var vehicle = cat.vehicle(str(id))
		a.eq(vehicle.has("cost"), true, str(id) + " has cost")
		a.eq(vehicle["cost"], 0, str(id) + " cost is zero")
	var files: Array = []
	_gd_files("res://sim", files)
	_gd_files("res://game", files)
	for path in files:
		var code := _strip(FileAccess.get_file_as_string(str(path)))
		a.ok(not code.contains("cost"), str(path) + " does not branch on cost")


static func _precision(cat, a) -> void:
	var point = _mod(cat.vehicle("swarm"), "power")["parts"][0][0]
	var y := float(point["y"])
	var narrowed := Vector2(float(point["x"]), y).y
	a.ok(narrowed != y, "Vector2 would round a baked vertex")
	a.eq(Schema.px(point), float(point["x"]), "px keeps the parsed float")


static func _mod(vehicle: Dictionary, id: String) -> Dictionary:
	for module in vehicle["modules"]:
		if str(module["id"]) == id:
			return module
	return {}


static func _point(a, point: Dictionary, x: float, y: float, label: String) -> void:
	a.near(float(point["x"]), x, label + ".x", 0.0)
	a.near(float(point["y"]), y, label + ".y", 0.0)


static func _gd_files(dir_path: String, acc: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		var file_name := str(name)
		if file_name.ends_with(".gd"):
			acc.append(dir_path.path_join(file_name))
	for sub in dir.get_directories():
		var sub_name := str(sub)
		if sub_name.begins_with("."):
			continue
		_gd_files(dir_path.path_join(sub_name), acc)


static func _strip(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash)
		out += line + "\n"
	return out
