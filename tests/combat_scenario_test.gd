extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const Command := preload("res://sim/command.gd")
const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Slots := preload("res://sim/combat/slots.gd")
const Turret := preload("res://sim/combat/turret.gd")
const Target := preload("res://sim/combat/targeting.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Impact := preload("res://sim/combat/impact.gd")
const Missiles := preload("res://sim/combat/missiles.gd")
const Stats := preload("res://sim/stats/resolver.gd")
const FightScript := preload("res://sim/fight.gd")

## Behavioral cases from the prototype combat tests.
## Match flow, map replay, and missile nose-lock are covered by their own suites.


static func run(a) -> void:
	print("RUN combat scenarios")
	var cat = CatalogScript.new()
	_slots(a, cat)
	_turrets(a, cat)
	_lock(a, cat)
	_swarm_arcs(a, cat)
	_missiles(a, cat)
	_damage(a, cat)
	_terrain(a, cat)
	_base(a, cat)
	_purchase(a, cat)
	_broadcast(a, cat)


static func _slots(a, cat) -> void:
	var table: Dictionary = cat.weapon_table["weapons"]
	a.eq(_slot_names(cat.vehicle("bulwark"), table), ["AP", "HE"], "bulwark slots")
	a.eq(_slot_names(cat.vehicle("swarm"), table), ["AP", "HE"], "swarm slots")
	a.eq(_slot_names(cat.vehicle("hawk"), table), ["laser", "missile"], "hawk slots")
	var hawk_slots := Slots.weapon_slots(cat.vehicle("hawk"), table)
	var lasers: Array = hawk_slots[0]["modules"].duplicate()
	lasers.sort()
	a.eq(lasers, ["laserL", "laserR"], "hawk lasers share a slot")
	var arena := {"w": 30000.0, "h": 30000.0}
	var world = FightScript.new(arena, 1, null, cat)
	var hawk = world.spawn(cat.vehicle("hawk"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	hawk["weapons"]["missile"]["reload"] = 0.0
	var aim := {"x": 15600.0, "y": 15000.0}
	for _i in 60:
		world.step(_one(hawk, {"aim": aim, "fire": true, "slot": 0}))
	a.eq(world.beams.size(), 2, "slot 0 fires both lasers")
	a.eq(world.missiles.size(), 0, "slot 0 does not launch")
	world.step(_one(hawk, {"aim": aim, "fire": true, "slot": 1}))
	a.eq(world.beams.size(), 0, "slot 1 drops the beams")
	a.eq(world.missiles.size(), 1, "slot 1 launches one missile")

	var twin := _twin_gun(cat)
	a.eq(Slots.weapon_slots(twin, table)[0]["modules"], ["mainGun", "mainGun2"], "twin guns share a slot")
	var salvo = FightScript.new(arena, 1, null, cat)
	var gunner = salvo.spawn(twin, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	var left := {"aim": {"x": 15000.0, "y": 13500.0}, "secondaries": false}
	for _i in 360:
		salvo.step(_one(gunner, left))
	salvo.step(_one(gunner, _merge(left, {"fire": true})))
	var fired: Array = []
	for event in salvo.events:
		if str(event["t"]) == "fire" and int(event["vehicle"]) == int(gunner["id"]):
			fired.append(str(event["module"]))
	fired.sort()
	a.eq(fired, ["mainGun", "mainGun2"], "twin guns fire together")

	var bay := _twin_missile(cat)
	a.eq(Slots.weapon_slots(bay, table)[1]["modules"], ["missile", "missile2"], "twin bays share a slot")
	var ripple = FightScript.new(arena, 1, null, cat)
	var launcher = ripple.spawn(bay, 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	launcher["weapons"]["missile"]["reload"] = 0.0
	launcher["weapons"]["missile2"]["reload"] = 0.0
	var held := {"fire": true, "slot": 1}
	ripple.step(_one(launcher, held))
	a.eq(ripple.missiles.size(), 1, "ripple first missile")
	for _i in 16:
		ripple.step(_one(launcher, held))
	a.eq(ripple.missiles.size(), 1, "ripple waits")
	for _i in 4:
		ripple.step(_one(launcher, held))
	a.eq(ripple.missiles.size(), 2, "ripple second missile")


static func _turrets(a, cat) -> void:
	var arena := {"w": 30000.0, "h": 30000.0}
	var world = FightScript.new(arena, 1, null, cat)
	var bulwark = world.spawn(cat.vehicle("bulwark"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	world.spawn(cat.vehicle("hawk"), 1, {"x": 15000.0, "y": 14300.0}, 0.0)
	var right := 0
	var left := 0
	for _i in 360:
		world.step(_one(bulwark, {}))
		right += _fires(world, bulwark, "secR")
		left += _fires(world, bulwark, "secL")
	a.eq(right, 0, "right secondary cannot see the left target")
	a.ok(left > 0, "left secondary fires")

	var both = FightScript.new(arena, 1, null, cat)
	var host = both.spawn(cat.vehicle("bulwark"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	var foe_left = both.spawn(cat.vehicle("hawk"), 1, {"x": 15000.0, "y": 14300.0}, 0.0)
	var foe_right = both.spawn(cat.vehicle("hawk"), 1, {"x": 15000.0, "y": 15700.0}, 0.0)
	for _i in 30:
		both.step(_one(host, {"lock": foe_left["id"]}))
	a.eq(int(host["weapons"]["secR"]["aim_vehicle"]), int(foe_right["id"]), "right gun picks the gun it can see")
	a.eq(int(host["weapons"]["secL"]["aim_vehicle"]), int(foe_left["id"]), "left gun keeps the lock")

	var circle = FightScript.new(arena, 1, null, cat)
	var pivot = circle.spawn(cat.vehicle("bulwark"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	var orbiter = circle.spawn(cat.vehicle("hawk"), 1, {"x": 15800.0, "y": 15000.0}, 0.0)
	pivot["weapons"]["secR"]["reload"] = 99.0
	var last := float(pivot["turret_angles"].get("secR", 0.0))
	var max_jump := 0.0
	for i in 720:
		var ang := (float(i) / 720.0) * PI * 4.0
		circle.place(orbiter, {"x": 15000.0 + cos(ang) * 800.0, "y": 15000.0 + sin(ang) * 800.0}, 0.0)
		circle.step(_one(pivot, {}))
		var cur := float(pivot["turret_angles"]["secR"])
		a.ok(Angle.to_deg(cur) >= -0.01 and Angle.to_deg(cur) <= 135.01, "right turret stays in arc")
		max_jump = maxf(max_jump, absf(cur - last))
		last = cur
	a.ok(Angle.to_deg(max_jump) <= 120.0 / 60.0 + 1e-6, "right turret does not snap across the gap")

	var lasers = FightScript.new(arena, 1, null, cat)
	var hawk = lasers.spawn(cat.vehicle("hawk"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	for _i in 90:
		lasers.step(_one(hawk, {"aim": {"x": 15000.0 - 300.0, "y": 15000.0 + 520.0}, "fire": true}))
	var which: Array = []
	for beam in lasers.beams:
		which.append(str(beam["module"]))
	a.eq(which, ["laserR"], "only the laser that can reach fires")


static func _lock(a, cat) -> void:
	var arena := {"w": 30000.0, "h": 30000.0}
	var world = FightScript.new(arena, 1, null, cat)
	var hawk = world.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 1000.0}, 0.0)
	var missile_range := float(cat.weapon("hawk_missile")["range"])
	var laser_range := float(cat.weapon("hawk_laser")["range"])
	a.near(Target.lock_range(hawk, world.table, world.rules), missile_range, "hawk lock range", 1e-9)
	a.ok(missile_range > laser_range, "hawk missile outranges the lasers")
	var bulwark_range := Target.lock_range(world.spawn(cat.vehicle("bulwark"), 0, {"x": 5000.0, "y": 15000.0}, 0.0), world.table, world.rules)
	var setup = FightScript.new(arena, 1, null, cat)
	var shooter = setup.spawn(cat.vehicle("bulwark"), 0, {"x": 5000.0, "y": 15000.0}, 0.0)
	var target = setup.spawn(cat.vehicle("hawk"), 1, {"x": 5000.0, "y": 15000.0}, 0.0)
	var radius := setup.radius_of(target)
	setup.place(target, {"x": 5000.0 + bulwark_range + 50.0 + radius, "y": 15000.0}, 0.0)
	setup.step(_one(shooter, {"lock": target["id"]}))
	a.ok(shooter["lock"] == null, "cannot lock past range")
	setup.place(target, {"x": 5000.0 + bulwark_range - 50.0 + radius, "y": 15000.0}, 0.0)
	setup.step(_one(shooter, {"lock": target["id"]}))
	a.eq(int(shooter["lock"]), int(target["id"]), "locks inside range")
	setup.place(target, {"x": 5000.0 + bulwark_range * (Target.LOCK_KEEP - 0.02) + radius, "y": 15000.0}, 0.0)
	setup.step(_one(shooter, {"lock": target["id"]}))
	a.eq(int(shooter["lock"]), int(target["id"]), "keeps the lock inside the margin")
	setup.place(target, {"x": 5000.0 + bulwark_range * (Target.LOCK_KEEP + 0.02) + radius, "y": 15000.0}, 0.0)
	setup.step(_one(shooter, {"lock": target["id"]}))
	a.ok(shooter["lock"] == null, "drops the lock past the margin")
	setup.place(target, {"x": 5000.0 + bulwark_range - 50.0 + radius, "y": 15000.0}, 0.0)
	setup.step(_one(shooter, {"lock": null}))
	a.ok(shooter["lock"] == null, "a dropped lock stays dropped")


static func _swarm_arcs(a, cat) -> void:
	a.eq(_guns(cat, -90.0), ["mainGun", "sec4"], "swarm left")
	a.eq(_guns(cat, 0.0), ["mainGun", "sec1", "sec4"], "swarm forward")
	a.eq(_guns(cat, 90.0), ["sec1", "sec2", "sec3", "sec4"], "swarm right")
	a.eq(_guns(cat, 180.0), ["mainGun", "sec3", "sec4"], "swarm rear")
	a.ok(_guns(cat, 25.0).has("mainGun"), "swarm main near 1 o'clock")
	a.ok(_guns(cat, 155.0).has("mainGun"), "swarm main near 5 o'clock")
	a.ok(not _guns(cat, 140.0).has("mainGun"), "swarm main misses the rear-right gap")
	a.ok(not _guns(cat, 90.0).has("mainGun"), "swarm main misses 3 o'clock")


static func _missiles(a, cat) -> void:
	var arena := {"w": 30000.0, "h": 30000.0}
	var rules: Dictionary = cat.rules
	var hawk_missile: Dictionary = cat.weapon("hawk_missile")
	var fresh = FightScript.new(arena, 1, null, cat)
	var hawk = fresh.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 1000.0}, 0.0)
	a.near(float(hawk["weapons"]["missile"]["reload"]), float(hawk_missile["reload"]), "missile starts unloaded", 1e-9)
	fresh.step(_one(hawk, {"fire": true, "slot": 1}))
	a.eq(fresh.missiles.size(), 0, "unloaded missile does not launch")
	hawk["weapons"]["missile"]["reload"] = 0.0
	fresh.step(_one(hawk, {"fire": true, "slot": 1}))
	a.eq(fresh.missiles.size(), 1, "loaded missile launches")
	a.near(float(hawk["weapons"]["missile"]["reload"]), float(hawk_missile["reload"]), "launch starts the reload", 0.05)
	# One tick of boost wiggle is already in the heading. The prototype allows
	# toBeCloseTo(fan, 1), about 0.05 rad. The value below is that same step.
	a.near(float(fresh.missiles[0]["heading"]), -0.17202391808604114, "first missile fans left", 1e-9)
	a.ok(absf(float(fresh.missiles[0]["heading"]) + Angle.deg(float(hawk_missile["volleyFan"]))) < 0.05, "first missile stays near the left fan")
	for _i in 30:
		fresh.step(_one(hawk, {}))
	a.eq(fresh.missiles.size(), 2, "second missile launches after the trigger is released")
	a.ok(float(fresh.missiles[1]["heading"]) > 0.0, "second missile fans right")

	var dead = FightScript.new(arena, 1, null, cat)
	var doomed = dead.spawn(cat.vehicle("hawk"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	doomed["weapons"]["missile"]["reload"] = 0.0
	dead.step(_one(doomed, {"fire": true, "slot": 1}))
	doomed["alive"] = false
	for _i in 60:
		dead.step({})
	a.ok(dead.missiles.size() <= 1, "a dead launcher cancels the rest of the volley")
	a.eq(int(doomed["weapons"]["missile"]["pending"]), 0, "pending count clears")

	var torpedo: Dictionary = cat.weapon("torpedo_ap")
	var coast = FightScript.new(arena, 1, null, cat)
	var owner = coast.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 15000.0}, 0.0)
	var quiet: Dictionary = torpedo.duplicate(true)
	quiet["spread"] = 0.0
	Missiles.launch(coast, int(owner["id"]), "missile", quiet, {"x": 2000.0, "y": 15000.0}, 0.0, null, coast.rng.spread)
	var last := 0.0
	var guard := 0
	while coast.missiles.size() > 0 and guard < 1200:
		last = float(coast.missiles[0]["travelled"])
		coast.step({})
		guard += 1
	a.eq(coast.missiles.size(), 0, "torpedo expires")
	a.ok(absf(last - float(torpedo["range"])) < 10.0, "torpedo range is the straight-line flight")

	var guide = FightScript.new(arena, 1, null, cat)
	var pilot = guide.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 15000.0}, 0.0)
	var quarry = guide.spawn(cat.vehicle("bulwark"), 1, {"x": 3000.0, "y": 14300.0}, PI / 2.0)
	var bearing := atan2(float(quarry["pos"]["y"]) - 15000.0, float(quarry["pos"]["x"]) - 1100.0)
	Missiles.launch(guide, int(pilot["id"]), "missile", hawk_missile, {"x": 1100.0, "y": 15000.0}, bearing + Angle.deg(20.0), quarry["id"], guide.rng.spread)
	var hit := false
	for _i in 720:
		guide.step(_one(quarry, {"throttle": 1.0, "secondaries": false}))
		for event in guide.events:
			if str(event["t"]) == "hit" and str(event["log"]["weapon"]) == str(hawk_missile["name"]):
				hit = true
		if hit:
			break
	a.ok(hit, "guided missile hits a slow target from 20 degrees off")

	var dodge = FightScript.new(arena, 1, null, cat)
	var thrower = dodge.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 15000.0}, 0.0)
	var rabbit = dodge.spawn(cat.vehicle("hawk"), 1, {"x": 1900.0, "y": 14500.0}, PI / 2.0)
	rabbit["vel"] = {"x": 0.0, "y": 220.0}
	Missiles.launch(dodge, int(thrower["id"]), "missile", hawk_missile, {"x": 1100.0, "y": 15000.0}, atan2(-500.0, 800.0), rabbit["id"], dodge.rng.spread)
	var tagged := false
	var steps := 0
	while dodge.missiles.size() > 0 and steps < 720:
		dodge.step(_one(rabbit, {"throttle": 1.0}))
		for event in dodge.events:
			if str(event["t"]) == "hit" and str(event["log"]["weapon"]) == str(hawk_missile["name"]):
				tagged = true
		steps += 1
	a.ok(not tagged, "a crossing hawk outruns the missile turn rate")

	var warhead: Dictionary = hawk_missile["warhead"]
	var once := _hit_module(cat, "legFR", 1, warhead, hawk_missile)
	a.eq(str(once["modules"]["legFR"]["state"]), "NORMAL", "one missile leaves the leg working")
	var rated: Dictionary = _find_def(cat.vehicle("bulwark"), "legFR")
	a.near(float(once["modules"]["legFR"]["armor"]), maxf(float(rated["armor"]) * float(rules["armorFloor"]), float(rated["armor"]) - float(warhead["erode"])), "missile erodes the leg", 1e-9)
	var twice := _hit_module(cat, "legFR", 2, warhead, hawk_missile)
	a.ok(str(twice["modules"]["legFR"]["state"]) != "NORMAL", "the second missile disables the leg")
	var plate := _hit_module(cat, "armR", 1, warhead, hawk_missile)
	var plate_def: Dictionary = _find_def(cat.vehicle("bulwark"), "armR")
	a.near(float(plate["modules"]["armR"]["structure"]), float(plate_def["structure"]) - float(warhead["damage"]) * float(rules["heMinFactor"]), "HE floor on thick plate", 1e-6)
	var emp: Dictionary = cat.weapon("emp_missile")
	var shocked := _hit_module(cat, "armR", 1, emp["warhead"], emp)
	a.near(float(shocked["modules"]["armR"]["structure"]), float(plate_def["structure"]) - float(emp["warhead"]["damage"]), "EMP direct damage", 1e-9)
	a.near(float(shocked["modules"]["armR"]["armor"]), float(plate_def["armor"]), "EMP does not erode", 1e-9)
	a.eq(str(shocked["modules"]["armR"]["state"]), "NORMAL", "armor has no stun track")


static func _damage(a, cat) -> void:
	var small := {"w": 4000.0, "h": 4000.0}
	var world = FightScript.new(small, 1, null, cat)
	var bulwark = world.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var hawk = world.spawn(cat.vehicle("hawk"), 1, {"x": 1400.0, "y": 2000.0}, PI / 2.0)
	var results: Array = []
	var ticks := 0
	while hawk["alive"] and ticks < 1800:
		world.step({
			bulwark["id"]: Command.merge({"aim": {"x": float(hawk["pos"]["x"]), "y": float(hawk["pos"]["y"])}, "fire": true, "secondaries": false}),
		})
		for event in world.events:
			if str(event["t"]) == "hit":
				results.append(str(event["result"]))
		ticks += 1
	a.ok(not hawk["alive"], "bulwark main gun can kill a hawk")
	var clean := true
	for result in results:
		if result != "pen" and result != "overmatch":
			clean = false
	a.ok(clean and results.size() > 0, "those hits penetrate")

	var splash = FightScript.new(small, 1, null, cat)
	var host = splash.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var nose = splash.spawn(cat.vehicle("hawk"), 1, {"x": 1500.0, "y": 2000.0}, PI)
	var core_label := str(_find_def(cat.vehicle("hawk"), "core")["label"])
	var splashed := {}
	for _i in 180:
		splash.step(_one(host, {"aim": {"x": float(nose["pos"]["x"]), "y": float(nose["pos"]["y"])}, "fire": false, "secondaries": true}))
		for event in splash.events:
			if str(event["t"]) == "hit" and str(event["result"]) == "splash":
				splashed[str(event["log"]["module"])] = true
	a.ok(float(nose["modules"]["nose"]["structure"]) < 220.0, "HE secondary damages the nose")
	a.near(float(nose["modules"]["core"]["structure"]), 120.0, "splash does not reach the core", 1e-9)
	a.ok(not splashed.has(core_label), "splash log skips the core")

	var beam = FightScript.new(small, 1, null, cat)
	var plate = beam.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var laser = beam.spawn(cat.vehicle("hawk"), 1, {"x": 1450.0, "y": 2000.0}, PI)
	for _i in 120:
		beam.step({
			laser["id"]: Command.merge({"aim": {"x": float(plate["pos"]["x"]), "y": float(plate["pos"]["y"])}, "fire": true}),
			plate["id"]: Command.merge({"secondaries": false}),
		})
	var eroded := 0
	for module in cat.vehicle("bulwark")["modules"]:
		var runtime: Dictionary = plate["modules"][str(module["id"])]
		if float(runtime["armor"]) < 300.0:
			eroded += 1
			a.near(float(runtime["structure"]), float(module["structure"]), "laser does not cut thick structure", 1e-6)
	a.ok(eroded > 0, "laser erodes a thick plate")

	var stun = FightScript.new(small, 1, null, cat)
	var victim = stun.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var hunter = stun.spawn(cat.vehicle("hawk"), 1, {"x": 1600.0, "y": 2000.0}, PI)
	for module in cat.vehicle("bulwark")["modules"]:
		if str(module["id"]) == "mainGun":
			continue
		victim["modules"][str(module["id"])]["state"] = "DISABLED"
		victim["modules"][str(module["id"])]["reboot"] = 999.0
	var gun: Dictionary = _find_def(cat.vehicle("bulwark"), "mainGun")
	a.ok(float(gun["armor"]) >= float(cat.weapon("hawk_laser")["gate"]), "main gun armor is past the laser gate")
	var disabled := false
	for _i in 720:
		var aim: Dictionary = Target.module_center(stun, victim, gun, 0)
		stun.step({
			hunter["id"]: Command.merge({"aim": aim, "fire": true}),
			victim["id"]: Command.merge({"secondaries": false}),
		})
		if str(victim["modules"]["mainGun"]["state"]) == "DISABLED":
			disabled = true
			break
	a.ok(disabled, "laser stun disables the main gun through thick armor")
	a.near(float(victim["modules"]["mainGun"]["structure"]), float(gun["structure"]), "that stun does not remove structure", 1e-6)

	var open := _first_direct(cat, false)
	var closed := _first_direct(cat, true)
	a.eq(open, str(_find_def(cat.vehicle("hawk"), "podR")["label"]), "the near pod is hit when it is solid")
	a.ok(closed != "" and closed != open, "a disabled pod lets the shell through")


static func _terrain(a, cat) -> void:
	var hills: Dictionary = cat.map_def("hills")
	var size: Dictionary = hills["size"]
	var world = FightScript.new(size, 1, hills, cat)
	var shooter = world.spawn(cat.vehicle("bulwark"), 0, {"x": 5450.0, "y": 5600.0}, -PI / 2.0)
	var hidden = world.spawn(cat.vehicle("hawk"), 1, {"x": 5450.0, "y": 3700.0}, 0.0)
	var hits := 0
	var rocks := 0
	for _i in 600:
		world.step(_one(shooter, {"aim": {"x": float(hidden["pos"]["x"]), "y": float(hidden["pos"]["y"])}, "fire": true}))
		for event in world.events:
			if str(event["t"]) == "hit" and int(event["vehicle"]) == int(hidden["id"]):
				hits += 1
			if str(event["t"]) == "terrainHit" and str(event["obstacle"]) == "rF":
				rocks += 1
	a.ok(rocks > 0, "shells hit the rock")
	a.eq(hits, 0, "the rock stops the shells")

	var los = FightScript.new(size, 1, hills, cat)
	var gunner = los.spawn(cat.vehicle("bulwark"), 0, {"x": 5450.0, "y": 5600.0}, -PI / 2.0)
	los.spawn(cat.vehicle("hawk"), 1, {"x": 5450.0, "y": 3700.0}, 0.0)
	var fired := 0
	for _i in 480:
		los.step(_one(gunner, {}))
		for event in los.events:
			if str(event["t"]) == "fire" and int(event["vehicle"]) == int(gunner["id"]):
				fired += 1
	a.eq(fired, 0, "secondaries do not fire through the hill")

	var smoke = FightScript.new({"w": 30000.0, "h": 30000.0}, 1, null, cat)
	var swarm = smoke.spawn(cat.vehicle("swarm"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	var hawk = smoke.spawn(cat.vehicle("hawk"), 1, {"x": 15000.0, "y": 14000.0}, 0.0)
	var saw_fire := false
	for _i in 600:
		smoke.step(_one(swarm, {"aim": {"x": float(hawk["pos"]["x"]), "y": float(hawk["pos"]["y"])}, "fire": true, "lock": hawk["id"]}))
		for event in smoke.events:
			if str(event["t"]) == "fire":
				saw_fire = true
	a.ok(saw_fire, "swarm fires in that fight")


static func _base(a, cat) -> void:
	var hills: Dictionary = cat.map_def("hills")
	var regen := float(cat.structure_stats["baseStats"]["armorRegen"])
	var armor_max := float(cat.structure_stats["baseStats"]["armor"])
	var structure_max := float(cat.structure_stats["baseStats"]["structure"])
	var world = FightScript.new(hills["size"], 1, hills, cat)
	var base = world.spawn(cat.vehicle("base1"), 1, {"x": 9330.0, "y": 760.0}, 0.0)
	var rammer = world.spawn(cat.vehicle("swarm"), 0, {"x": 8930.0, "y": 760.0}, 0.0)
	for _i in 240:
		world.step(_one(rammer, {"throttle": 1.0, "secondaries": false}))
	a.near(float(base["pos"]["x"]), 9330.0, "base x", 1e-9)
	a.near(float(base["pos"]["y"]), 760.0, "base y", 1e-9)
	var gap := Point.distance(rammer["pos"], base["pos"])
	a.ok(gap >= float(base["def"]["collisionRadius"]) + float(rammer["def"]["collisionRadius"]) - 1.0, "the rammer is pushed off the base")
	base["modules"]["core"]["armor"] = 40.0
	base["modules"]["core"]["structure"] = 5000.0
	for _i in 600:
		world.step(_one(rammer, {"secondaries": false}))
	a.near(float(base["modules"]["core"]["armor"]), 40.0 + regen * 10.0, "base armor regens", 0.05)
	a.near(float(base["modules"]["core"]["structure"]), 5000.0, "base structure does not regen", 1e-9)
	for _i in 3600:
		world.step(_one(rammer, {"secondaries": false}))
	a.near(float(base["modules"]["core"]["armor"]), armor_max, "base armor returns to full", 1e-6)

	var siege = FightScript.new(hills["size"], 1, hills, cat)
	var fort = siege.spawn(cat.vehicle("base1"), 1, {"x": 9330.0, "y": 760.0}, 0.0)
	var gun = siege.spawn(cat.vehicle("bulwark"), 0, {"x": 8000.0, "y": 1600.0}, 0.0)
	for _i in 1200:
		siege.step(_one(gun, {"aim": {"x": float(fort["pos"]["x"]), "y": float(fort["pos"]["y"])}, "fire": true, "lock": fort["id"]}))
	a.eq(int(gun["lock"]), int(fort["id"]), "a base can be locked")
	a.ok(float(fort["modules"]["core"]["structure"]) < structure_max, "a base can be damaged")


static func _purchase(a, cat) -> void:
	var holder := {"mods": [], "purchase": []}
	Stats.add_purchase(holder, {"id": "p", "stat": "damage", "op": {"kind": "mul", "v": 2}, "appliesTo": "self", "stack": "stack"})
	a.eq(holder["mods"].size(), 0, "purchase does not enter combat modifiers")
	a.eq(str(holder["purchase"][0]["source"]), Stats.PURCHASE_SOURCE, "purchase source is reserved")
	a.near(Stats.stat(holder, "damage", 10.0, cat.rules), 20.0, "purchase modifier applies", 1e-9)


static func _broadcast(a, cat) -> void:
	var world = FightScript.new({"w": 4000.0, "h": 4000.0}, 1, null, cat)
	var seen := {"n": 0, "hit": false, "state": false}
	world.sinks.append(func(event):
		seen["n"] = int(seen["n"]) + 1
		if str(event["t"]) == "hit":
			seen["hit"] = true
		if str(event["t"]) == "moduleState":
			seen["state"] = true
	)
	var left = world.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var right = world.spawn(cat.vehicle("hawk"), 1, {"x": 1400.0, "y": 2000.0}, PI / 2.0)
	for _i in 90:
		world.step(_one(left, {"aim": {"x": float(right["pos"]["x"]), "y": float(right["pos"]["y"])}, "fire": true, "secondaries": false}))
	a.ok(int(seen["n"]) > 0, "sinks receive combat events")
	a.ok(bool(seen["hit"]), "a hit is broadcast")


static func _first_direct(cat, disabled: bool) -> String:
	var world = FightScript.new({"w": 4000.0, "h": 4000.0}, 2, null, cat)
	var bulwark = world.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var hawk = world.spawn(cat.vehicle("hawk"), 1, {"x": 1600.0, "y": 2000.0}, PI / 2.0)
	if disabled:
		hawk["modules"]["podR"]["state"] = "DISABLED"
		hawk["modules"]["podR"]["reboot"] = 99.0
	var aim := {"x": float(hawk["pos"]["x"]) - 33.0, "y": float(hawk["pos"]["y"]) - 30.0}
	var names: Array = []
	for i in 90:
		world.step({
			bulwark["id"]: Command.merge({"aim": aim, "fire": i >= 30, "secondaries": false}),
			hawk["id"]: Command.idle(),
		})
		for event in world.events:
			if str(event["t"]) == "hit" and str(event["result"]) != "splash":
				names.append(str(event["log"]["module"]))
	if names.is_empty():
		return ""
	return str(names[0])


static func _hit_module(cat, id: String, times: int, warhead: Dictionary, weapon: Dictionary) -> Dictionary:
	var world = FightScript.new({"w": 30000.0, "h": 30000.0}, 1, null, cat)
	var owner = world.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 1000.0}, 0.0)
	var target = world.spawn(cat.vehicle("bulwark"), 1, {"x": 5000.0, "y": 5000.0}, 0.0)
	var module := _find_def(target["def"], id)
	for _i in times:
		Impact.resolve_impact(world, {
			"owner": owner["id"],
			"team": 0,
			"weapon": weapon["id"],
			"weaponName": weapon["name"],
			"warhead": warhead,
			"dir": {"x": 1.0, "y": 0.0},
			"dist": 1000.0,
			"penRange": null,
		}, target, module, target["pos"], null, [])
	return target


static func _guns(cat, degrees: float) -> Array:
	var world = FightScript.new({"w": 30000.0, "h": 30000.0}, 1, null, cat)
	var swarm = world.spawn(cat.vehicle("swarm"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	var ang := Angle.deg(degrees)
	var point := {"x": 15000.0 + cos(ang) * 1000.0, "y": 15000.0 + sin(ang) * 1000.0}
	var ids: Array = []
	for module in swarm["def"]["modules"]:
		if module.has("turret") and Turret.in_turret_arc(swarm, module, point):
			ids.append(str(module["id"]))
	ids.sort()
	return ids


static func _slot_names(vehicle: Dictionary, table: Dictionary) -> Array:
	var names: Array = []
	for slot in Slots.weapon_slots(vehicle, table):
		var weapon: Dictionary = table[str(slot["weapon"])]
		if str(weapon["kind"]) == "kinetic":
			names.append(str(weapon["ammo"][int(slot["ammo"])]["kind"]))
		else:
			names.append(str(weapon["kind"]))
	return names


static func _twin_gun(cat) -> Dictionary:
	var vehicle: Dictionary = cat.vehicle("swarm").duplicate(true)
	vehicle["id"] = "swarmTwin"
	var gun: Dictionary = _find_def(vehicle, "mainGun").duplicate(true)
	gun["id"] = "mainGun2"
	gun["turret"] = (gun["turret"] as Dictionary).duplicate(true)
	gun["turret"]["pivot"] = {"x": 14.0, "y": -21.0}
	vehicle["modules"].append(gun)
	return vehicle


static func _twin_missile(cat) -> Dictionary:
	var vehicle: Dictionary = cat.vehicle("hawk").duplicate(true)
	vehicle["id"] = "hawkTwin"
	var bay: Dictionary = _find_def(vehicle, "missile").duplicate(true)
	bay["id"] = "missile2"
	vehicle["modules"].append(bay)
	return vehicle


static func _find_def(vehicle: Dictionary, id: String) -> Dictionary:
	for module in vehicle["modules"]:
		if str(module["id"]) == id:
			return module
	return {}


static func _fires(world, vehicle: Dictionary, module_id: String) -> int:
	var n := 0
	for event in world.events:
		if str(event["t"]) == "fire" and int(event["vehicle"]) == int(vehicle["id"]) and str(event["module"]) == module_id:
			n += 1
	return n


static func _one(vehicle: Dictionary, partial: Dictionary) -> Dictionary:
	return {vehicle["id"]: Command.merge(partial)}


static func _merge(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in extra.keys():
		out[key] = extra[key]
	return out
