extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const Command := preload("res://sim/command.gd")
const Angle := preload("res://sim/angle.gd")
const Pen := preload("res://sim/combat/penetration.gd")
const Modules := preload("res://sim/combat/modules.gd")
const Stats := preload("res://sim/stats/resolver.gd")
const Turret := preload("res://sim/combat/turret.gd")
const FightScript := preload("res://sim/fight.gd")
const Missiles := preload("res://sim/combat/missiles.gd")

## Absolute tolerance against Game_test@33f4be8, from tools/golden_combat.mjs.
## The generator rounds stored numbers to 1e-12. Comparisons use 1e-9.

const TOL := 1e-9


static func run(a) -> void:
	print("RUN combat")
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/combat_golden.json"))
	var cat = CatalogScript.new()
	_formulas(a, cat, golden)
	_stats(a, cat, golden)
	_modules(a, cat, golden)
	_arcs(a, cat, golden)
	_world(a, cat, golden)
	_determinism(a, cat)


static func _formulas(a, cat, golden) -> void:
	var rules: Dictionary = cat.rules
	for row in golden["pen"]:
		var got := Pen.at_distance(float(row["p0"]), float(row["range"]), float(row["dist"]))
		var label := "pen %s %s" % [row.get("id", "bulwarkAp"), row["dist"]]
		a.near(got, float(row["value"]), label, TOL)
		if float(row["dist"]) == float(row["range"]) and float(row["range"]) > 0.0:
			a.ok(got > 0.0, label + " stays positive at max range")
	for row in golden["eff"]:
		var got := Pen.effective_armor(float(row["armor"]), Angle.deg(float(row["deg"])))
		a.near(got, float(row["value"]), "eff %s" % row["deg"], TOL)
	for row in golden["hits"]:
		var penetration := float(row["pen"]) if row.has("pen") else Pen.at_distance(620.0, 1600.0, float(row["dist"]))
		var k := NAN
		if row.has("k"):
			k = float(row["k"])
		var got := Pen.resolve_hit(penetration, float(row["armor"]), Angle.deg(float(row["deg"])), k)
		a.eq(got, str(row["result"]), "hit %s/%s/%s" % [row["dist"], row["deg"], row["armor"]])
	for row in golden["maxPen"]:
		var got := Pen.max_pen_distance(620.0, 1600.0, float(row["armor"]), 0.0)
		a.near(got, float(row["value"]), "max pen %s" % row["armor"], TOL)
	var min_factor := float(rules["heMinFactor"])
	for row in golden["he"]:
		var got := Pen.he_factor(float(row["hePen"]), float(row["armor"]), min_factor)
		a.near(got, float(row["value"]), "he %s/%s" % [row["hePen"], row["armor"]], TOL)
	a.near(Pen.ap_pen_damage(100.0, 500.0, 320.0), float(golden["apDamage"]), "ap pen damage", TOL)


static func _stats(a, cat, golden) -> void:
	var rules: Dictionary = cat.rules
	var expect: Dictionary = golden["stats"]
	a.near(Stats.stat(_holder(), "reload", 7.0, rules), float(expect["plain"]), "stat plain", TOL)
	var stacked := _holder()
	Stats.add_modifier(stacked, _mod({"stat": "range", "op": {"kind": "flat", "v": 100}}))
	Stats.add_modifier(stacked, _mod({"stat": "range", "op": {"kind": "mul", "v": 2}}))
	Stats.add_modifier(stacked, _mod({"stat": "range", "op": {"kind": "mul", "v": 1.5}}))
	a.near(Stats.stat(stacked, "range", 1000.0, rules), float(expect["flatMul"]), "stat flat mul", TOL)
	Stats.add_modifier(stacked, _mod({"stat": "range", "op": {"kind": "set", "v": 500}}))
	a.near(Stats.stat(stacked, "range", 1000.0, rules), float(expect["set"]), "stat set", TOL)
	var clamped := _holder()
	Stats.add_modifier(clamped, _mod({"stat": "reload", "op": {"kind": "mul", "v": 0}}))
	a.near(Stats.stat(clamped, "reload", 7.0, rules), float(expect["clamp"]), "stat clamp", TOL)
	var scoped := _holder()
	Stats.add_modifier(scoped, _mod({"stat": "reload", "op": {"kind": "mul", "v": 0.5}, "module": "main"}))
	a.near(Stats.stat(scoped, "reload", 8.0, rules, {"module": "main"}), float(expect["scoped"]), "stat scoped", TOL)
	a.near(Stats.stat(scoped, "reload", 8.0, rules, {"module": "secL"}), float(expect["other"]), "stat other module", TOL)
	var marked := _holder()
	var shooter := _holder()
	Stats.add_modifier(marked, _mod({"stat": "dispersion", "op": {"kind": "mul", "v": 0.8}, "appliesTo": "target", "source": "hawk.lock"}))
	a.near(Stats.stat(shooter, "dispersion", 1.0, rules, {}, marked), float(expect["marked"]), "stat target mod", TOL)
	a.near(Stats.stat(shooter, "dispersion", 1.0, rules), float(expect["unmarked"]), "stat no target", TOL)
	a.near(Stats.stat(marked, "dispersion", 1.0, rules), float(expect["selfMarked"]), "stat target mod ignores self", TOL)
	var refresh := _holder()
	Stats.add_modifier(refresh, _mod({"id": "r", "stat": "damage", "op": {"kind": "mul", "v": 1.2}, "stack": "refresh", "duration": 1}))
	Stats.tick_modifiers(refresh, 0.8)
	Stats.add_modifier(refresh, _mod({"id": "r", "stat": "damage", "op": {"kind": "mul", "v": 1.2}, "stack": "refresh", "duration": 1}))
	a.eq(refresh["mods"].size(), int(expect["refreshCount"]), "refresh count")
	a.near(float(refresh["mods"][0]["left"]), float(expect["refreshLeft"]), "refresh left", TOL)
	var exclusive := _holder()
	Stats.add_modifier(exclusive, _mod({"id": "a", "stat": "damage", "op": {"kind": "mul", "v": 1.5}, "stack": "exclusive", "source": "siege"}))
	Stats.add_modifier(exclusive, _mod({"id": "b", "stat": "damage", "op": {"kind": "mul", "v": 1.2}, "stack": "exclusive", "source": "siege"}))
	a.near(Stats.stat(exclusive, "damage", 100.0, rules), float(expect["exclusive"]), "exclusive", TOL)
	var timed := _holder()
	Stats.add_modifier(timed, _mod({"stat": "damage", "op": {"kind": "mul", "v": 2}, "duration": 0.5}))
	Stats.add_modifier(timed, _mod({"stat": "range", "op": {"kind": "mul", "v": 2}, "source": "perm"}))
	Stats.tick_modifiers(timed, 0.3)
	a.near(Stats.stat(timed, "damage", 10.0, rules), float(expect["timedMid"]), "timed mid", TOL)
	Stats.tick_modifiers(timed, 0.3)
	a.near(Stats.stat(timed, "damage", 10.0, rules), float(expect["timedEnd"]), "timed end", TOL)
	Stats.remove_modifiers(timed, "perm")
	a.eq(timed["mods"].size(), int(expect["timedLeft"]), "timed removed")
	var bought := _holder()
	a.eq(bought["purchase"].size(), 0, "purchase modifiers start empty")
	a.eq(Stats.PURCHASE_SOURCE, "purchase", "purchase source name")


static func _modules(a, cat, golden) -> void:
	var rules: Dictionary = cat.rules
	var expect: Dictionary = golden["modules"]
	var bulwark = cat.vehicle("bulwark")
	var leg_vehicle := _damageable(bulwark)
	var events: Array = []
	Modules.apply_damage(leg_vehicle, _find(leg_vehicle, "legFR"), {"struct": 150, "stun": 120, "erode": 0}, 0.0, events, rules)
	_same(a, _runtime_view(leg_vehicle["modules"]["legFR"]), expect["legAfterOne"], "leg after one")
	Modules.apply_damage(leg_vehicle, _find(leg_vehicle, "legFR"), {"struct": 150, "stun": 120, "erode": 0}, 0.5, events, rules)
	_same(a, _runtime_view(leg_vehicle["modules"]["legFR"]), expect["legDisabled"], "leg disabled")
	for i in 714:
		Modules.tick_modules(leg_vehicle, 1.0 / 60.0, 0.5 + float(i) / 60.0, [], rules)
	a.eq(str(leg_vehicle["modules"]["legFR"]["state"]), str(expect["legBeforeReboot"]), "leg still down")
	for i in 12:
		Modules.tick_modules(leg_vehicle, 1.0 / 60.0, 12.4 + float(i) / 60.0, [], rules)
	_same(a, _runtime_view(leg_vehicle["modules"]["legFR"]), expect["legAfterReboot"], "leg reboot")
	Modules.apply_damage(leg_vehicle, _find(leg_vehicle, "legFR"), {"struct": 150, "stun": 120, "erode": 0}, 13.0, [], rules)
	a.eq(str(leg_vehicle["modules"]["legFR"]["state"]), str(expect["legFinal"]), "leg destroyed on the next hit")
	var decay := _damageable(bulwark)
	Modules.apply_damage(decay, _find(decay, "legFL"), {"struct": 0, "stun": 100, "erode": 0}, 0.0, [], rules)
	for i in 120:
		Modules.tick_modules(decay, 1.0 / 60.0, float(i) / 60.0, [], rules)
	a.near(float(decay["modules"]["legFL"]["stun"]), float(expect["stunAt2"]), "stun at 2s", TOL)
	for i in 60:
		Modules.tick_modules(decay, 1.0 / 60.0, 2.0 + float(i) / 60.0, [], rules)
	a.near(float(decay["modules"]["legFL"]["stun"]), float(expect["stunAt3"]), "stun at 3s", TOL)
	var host := _damageable(bulwark)
	var host_events: Array = []
	Modules.apply_damage(host, _find(host, "armR"), {"struct": 9999, "stun": 0, "erode": 0}, 0.0, host_events, rules)
	a.eq(str(host["modules"]["secR"]["state"]), str(expect["hostStates"]["secR"]), "host cascade secR")
	a.eq(str(host["modules"]["armR"]["state"]), str(expect["hostStates"]["armR"]), "host cascade armR")
	Modules.apply_damage(host, _find(host, "core"), {"struct": 9999, "stun": 0, "erode": 0}, 0.0, host_events, rules)
	a.eq(bool(host["alive"]), bool(expect["coreKill"]["alive"]), "core kill alive")
	a.eq(str(host["modules"]["mainGun"]["state"]), str(expect["coreKill"]["mainGun"]), "core kill main gun")
	var killed := false
	for event in host_events:
		if str(event["t"]) == "vehicleDestroyed":
			killed = true
	a.eq(killed, bool(expect["coreKill"]["killed"]), "vehicleDestroyed event")
	var floor_vehicle := _damageable(bulwark)
	Modules.apply_damage(floor_vehicle, _find(floor_vehicle, "armR"), {"struct": 0, "stun": 0, "erode": 10000}, 0.0, [], rules)
	a.near(float(floor_vehicle["modules"]["armR"]["armor"]), float(expect["armorFloor"]), "armor floor", TOL)
	var repair_vehicle := _damageable(bulwark)
	var leg: Dictionary = _find(repair_vehicle, "legFL")
	Modules.destroy_module(repair_vehicle, leg, [])
	repair_vehicle["calm"] = 0.0
	for i in 2130:
		Modules.tick_modules(repair_vehicle, 1.0 / 60.0, float(i) / 60.0, [], rules)
	a.eq(str(repair_vehicle["modules"]["legFL"]["state"]), str(expect["repairPending"]), "repair still waiting")
	for i in 60:
		Modules.tick_modules(repair_vehicle, 1.0 / 60.0, float(i) / 60.0, [], rules)
	_same(a, _runtime_view(repair_vehicle["modules"]["legFL"]), expect["repaired"], "repaired leg")
	a.near(float(expect["legRated"]["structure"]), float(leg["structure"]), "rated structure", TOL)
	var down := Modules.down_of(host)
	a.ok(down.has("secR") and down.has("mainGun") and down.has("core"), "down set follows destroyed modules")
	a.eq(float(Modules.mobility_of(host)["speed_mul"]), 0.0, "dead vehicle does not move")


static func _arcs(a, cat, golden) -> void:
	var bulwark = cat.vehicle("bulwark")
	var turret: Dictionary = _find_def(bulwark, "secR")["turret"]
	var goal: Dictionary = Turret.arc_goal(Angle.deg(60.0), Angle.deg(-20.0), turret)
	a.near(float(goal["goal"]), float(golden["arc"]["goal"]), "arc goal", TOL)
	a.eq(bool(goal["in_arc"]), bool(golden["arc"]["inArc"]), "arc outside")
	var held: Dictionary = Turret.arc_goal(Angle.deg(135.0), Angle.deg(-100.0), turret)
	a.near(float(held["goal"]), float(golden["arc"]["hold"]), "arc hold", TOL)
	a.eq(bool(held["in_arc"]), bool(golden["arc"]["holdIn"]), "arc hold outside")


static func _world(a, cat, golden) -> void:
	var arena := {"w": 30000.0, "h": 30000.0}
	var one = FightScript.new(arena, 1, null, cat)
	var gunner = one.spawn(cat.vehicle("bulwark"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	one.step(_cmds(gunner, {"aim": {"x": 20000.0, "y": 15000.0}, "fire": true, "secondaries": false}))
	_same(a, _body(gunner), golden["oneShot"]["shooter"], "one shot shooter")
	_same(a, _shells(one), golden["oneShot"]["projectiles"], "one shot shell")
	a.eq(one.beams.size(), int(golden["oneShot"]["beams"]), "one shot beams")
	for _i in 30:
		one.step(_cmds(gunner, {"aim": {"x": 20000.0, "y": 15000.0}, "secondaries": false}))
	_same(a, _shells(one), golden["oneLater"]["projectiles"], "shell after 30")
	_same(a, {"pos": gunner["pos"], "heading": gunner["heading"], "crown": gunner["crown_angle"]}, golden["oneLater"]["shooter"], "shooter after 30")

	var slots = FightScript.new(arena, 1, null, cat)
	var slotted = slots.spawn(cat.vehicle("bulwark"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	slots.step(_cmds(slotted, {"slot": 7}))
	a.eq(int(slotted["slot"]), int(golden["slotClamp"]), "slot clamp")
	slots.step(_cmds(slotted, {"slot": 1}))
	a.eq(int(slotted["weapons"]["mainGun"]["ammo"]), int(golden["slotAmmo"]["ammo"]), "ammo switch")
	a.near(float(slotted["weapons"]["mainGun"]["reload"]), float(golden["slotAmmo"]["reload"]), "ammo reload", TOL)

	var lasers = FightScript.new(arena, 1, null, cat)
	var hawk = lasers.spawn(cat.vehicle("hawk"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	for _i in 60:
		lasers.step(_cmds(hawk, {"aim": {"x": 14000.0, "y": 15000.0}, "fire": true}))
	a.eq(lasers.beams.size(), int(golden["laserBehind"]["beams"]), "laser behind beams")
	a.near(float(hawk["weapons"]["laserL"]["heat"]), float(golden["laserBehind"]["heatL"]), "laser behind heat L", TOL)
	a.near(float(hawk["weapons"]["laserR"]["heat"]), float(golden["laserBehind"]["heatR"]), "laser behind heat R", TOL)
	for _i in 90:
		lasers.step(_cmds(hawk, {"aim": {"x": 15500.0, "y": 15000.0}, "fire": true}))
	a.eq(lasers.beams.size(), int(golden["laserAhead"]["beams"]), "laser ahead beams")
	a.near(float(hawk["weapons"]["laserL"]["heat"]), float(golden["laserAhead"]["heatL"]), "laser ahead heat", TOL)
	var names: Array = []
	for beam in lasers.beams:
		names.append(str(beam["module"]))
	_same(a, names, golden["laserAhead"]["modules"], "laser ahead modules")

	var duel = FightScript.new({"w": 4000.0, "h": 4000.0}, 7, null, cat)
	var left = duel.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var right = duel.spawn(cat.vehicle("hawk"), 1, {"x": 1600.0, "y": 2000.0}, PI / 2.0)
	for i in 180:
		duel.step({
			left["id"]: Command.merge({
				"aim": {"x": float(right["pos"]["x"]), "y": float(right["pos"]["y"])},
				"fire": true,
				"turn": sin(float(i) / 40.0),
			}),
			right["id"]: Command.merge({
				"aim": {"x": float(left["pos"]["x"]), "y": float(left["pos"]["y"])},
				"fire": i % 200 < 120,
				"throttle": 1.0,
				"turn": 0.4,
			}),
		})
	a.eq(duel.tick, int(golden["duel"]["tick"]), "duel tick")
	a.eq(duel.projectiles.size(), int(golden["duel"]["projectiles"]), "duel shells")
	a.eq(duel.missiles.size(), int(golden["duel"]["missiles"]), "duel missiles")
	_same(a, _body(left), golden["duel"]["left"], "duel bulwark")
	_same(a, _body(right), golden["duel"]["right"], "duel hawk")

	var flight = FightScript.new(arena, 3, null, cat)
	var owner = flight.spawn(cat.vehicle("hawk"), 0, {"x": 1000.0, "y": 15000.0}, 0.0)
	var missile_weapon: Dictionary = cat.weapon("hawk_missile")
	Missiles.launch(flight, int(owner["id"]), "missile", missile_weapon, {"x": 1100.0, "y": 15000.0}, 0.0, null, flight.rng.spread)
	for _i in 60:
		flight.step({})
	var flying: Array = []
	for missile in flight.missiles:
		flying.append({
			"pos": missile["pos"],
			"heading": missile["heading"],
			"speed": missile["speed"],
			"age": missile["age"],
			"travelled": missile["travelled"],
		})
	_same(a, flying, golden["missile"], "unguided missile")

	var half := _speed(cat, 0.5)
	var full := _speed(cat, 1.0)
	a.near(half, float(golden["speed"]["half"]), "half speed", TOL)
	a.near(full, float(golden["speed"]["full"]), "full speed", TOL)


static func _determinism(a, cat) -> void:
	var first := _exchange_hash(cat, 42)
	var second := _exchange_hash(cat, 42)
	a.eq(first, second, "same seed combat hash")
	a.ok(first != _exchange_hash(cat, 43), "different seed combat hash")


static func _exchange_hash(cat, seed: int) -> int:
	var world = FightScript.new({"w": 4000.0, "h": 4000.0}, seed, null, cat)
	var left = world.spawn(cat.vehicle("bulwark"), 0, {"x": 1000.0, "y": 2000.0}, 0.0)
	var right = world.spawn(cat.vehicle("hawk"), 1, {"x": 1600.0, "y": 2000.0}, PI / 2.0)
	for i in 180:
		world.step({
			left["id"]: Command.merge({
				"aim": {"x": float(right["pos"]["x"]), "y": float(right["pos"]["y"])},
				"fire": true,
				"turn": sin(float(i) / 40.0),
			}),
			right["id"]: Command.merge({
				"aim": {"x": float(left["pos"]["x"]), "y": float(left["pos"]["y"])},
				"fire": i % 200 < 120,
				"throttle": 1.0,
				"turn": 0.4,
			}),
		})
	return world.state_hash()


static func _speed(cat, mul: float) -> float:
	var world = FightScript.new({"w": 30000.0, "h": 30000.0}, 1, null, cat)
	var hawk = world.spawn(cat.vehicle("hawk"), 0, {"x": 15000.0, "y": 15000.0}, 0.0)
	if mul != 1.0:
		Stats.add_modifier(hawk, _mod({"stat": "maxSpeed", "op": {"kind": "mul", "v": mul}}))
	for _i in 360:
		world.step(_cmds(hawk, {"throttle": 1.0}))
	return sqrt(float(hawk["vel"]["x"]) * float(hawk["vel"]["x"]) + float(hawk["vel"]["y"]) * float(hawk["vel"]["y"]))


static func _cmds(vehicle: Dictionary, partial: Dictionary) -> Dictionary:
	return {vehicle["id"]: Command.merge(partial)}


static func _holder() -> Dictionary:
	return {"mods": [], "purchase": []}


static func _mod(partial: Dictionary) -> Dictionary:
	var mod := {"id": "m", "source": "test", "appliesTo": "self", "stack": "stack"}
	for key in partial.keys():
		mod[key] = partial[key]
	return mod


static func _damageable(vehicle: Dictionary) -> Dictionary:
	return {
		"id": 1,
		"def": vehicle,
		"alive": true,
		"modules": Modules.init_modules(vehicle),
		"calm": 0.0,
		"mods": [],
		"purchase": [],
	}


static func _find(vehicle: Dictionary, id: String) -> Dictionary:
	return _find_def(vehicle["def"], id)


static func _find_def(vehicle: Dictionary, id: String) -> Dictionary:
	for module in vehicle["modules"]:
		if str(module["id"]) == id:
			return module
	return {}


static func _runtime_view(runtime: Dictionary) -> Dictionary:
	return {
		"armor": runtime["armor"],
		"structure": runtime["structure"],
		"stun": runtime["stun"],
		"state": runtime["state"],
		"reboot": runtime["reboot"],
		"immune": runtime["immune"],
		"lastStunAt": runtime["last_stun_at"],
	}


static func _body(vehicle: Dictionary) -> Dictionary:
	var modules := {}
	for module in vehicle["def"]["modules"]:
		var runtime: Dictionary = vehicle["modules"][str(module["id"])]
		modules[str(module["id"])] = {
			"armor": runtime["armor"],
			"structure": runtime["structure"],
			"stun": runtime["stun"],
			"state": runtime["state"],
		}
	var weapons := {}
	for module_id in vehicle["weapons"].keys():
		var runtime: Dictionary = vehicle["weapons"][module_id]
		weapons[str(module_id)] = {
			"reload": runtime["reload"],
			"ammo": runtime["ammo"],
			"disp": runtime["disp"],
			"heat": runtime["heat"],
			"inArc": runtime["in_arc"],
			"aimErr": runtime["aim_err"],
			"aimVehicle": runtime["aim_vehicle"],
			"aimModule": runtime["aim_module"],
			"pending": runtime["pending"],
		}
	return {
		"pos": vehicle["pos"],
		"vel": vehicle["vel"],
		"heading": vehicle["heading"],
		"crown": vehicle["crown_angle"],
		"speed": vehicle["speed"],
		"alive": vehicle["alive"],
		"slot": vehicle["slot"],
		"lock": vehicle["lock"],
		"calm": vehicle["calm"],
		"turrets": vehicle["turret_angles"],
		"modules": modules,
		"weapons": weapons,
	}


static func _shells(world) -> Array:
	var out: Array = []
	for projectile in world.projectiles:
		out.append({
			"pos": projectile["pos"],
			"vel": projectile["vel"],
			"travelled": projectile["travelled"],
			"range": projectile["range"],
			"ammo": projectile["ammo"],
			"weapon": projectile["weapon"],
		})
	return out


static func _same(a, actual, expected, label: String) -> void:
	if typeof(expected) == TYPE_STRING and (expected == "-inf" or expected == "inf"):
		var want := INF if expected == "inf" else -INF
		a.ok(actual == want, label)
		return
	if typeof(expected) == TYPE_FLOAT or typeof(expected) == TYPE_INT:
		a.near(float(actual), float(expected), label, TOL)
		return
	if typeof(expected) == TYPE_BOOL:
		a.eq(bool(actual), expected, label)
		return
	if typeof(expected) == TYPE_STRING:
		a.eq(str(actual), expected, label)
		return
	if expected == null:
		a.ok(actual == null, label + " null")
		return
	if typeof(expected) == TYPE_ARRAY:
		a.eq(actual.size(), expected.size(), label + " len")
		if actual.size() != expected.size():
			return
		for i in expected.size():
			_same(a, actual[i], expected[i], label + "[%s]" % i)
		return
	if typeof(expected) == TYPE_DICTIONARY:
		for key in expected.keys():
			if typeof(actual) != TYPE_DICTIONARY or not actual.has(key):
				a.ok(false, label + " missing " + str(key))
				continue
			_same(a, actual[key], expected[key], label + "." + str(key))
