extends RefCounted

const CatalogScript := preload("res://sim/data/catalog.gd")
const Schema := preload("res://sim/data/schema.gd")
const Validate := preload("res://sim/vehicle/validate.gd")

## Game_test tests/unit/constraints.test.ts, except C4.
## C4 needs penetrationAtDistance and stays deferred.
## Bases are not passed to validate_vehicle: the prototype never did, and a
## base has no power module.


static func run(a) -> void:
	print("RUN constraints")
	print("DEFER C4 penetrationAtDistance until combat")
	var cat = CatalogScript.new()
	_c1(cat, a)
	_structure(cat, a)
	_sight(cat, a)
	_map(cat, a)
	_match(cat, a)
	_gradient(cat, a)
	_sigma(cat, a)


static func _c1(cat, a) -> void:
	for id in cat.lineup_ids():
		var report: Dictionary = Validate.validate_vehicle(cat.vehicle(str(id)))
		if report["errors"].size() > 0:
			print("C1 ", id, " ", report["errors"])
		a.eq(report["errors"].size(), 0, "C1 " + str(id))


static func _structure(cat, a) -> void:
	# C1's "exactly one power" check is for combat vehicles. Bases are a single
	# core module in the prototype; validateVehicle was never run on them.
	var combat: Array = []
	combat.append_array(cat.lineup_ids())
	combat.append_array(cat.concept_ids())
	for id in combat:
		_modules(cat, str(id), a, 1)
	for id in cat.structure_ids():
		_modules(cat, str(id), a, 0)


static func _modules(cat, id: String, a, powers_expected: int) -> void:
	var vehicle = cat.vehicle(id)
	var by_id := {}
	var cores := 0
	var powers := 0
	for module in vehicle["modules"]:
		var module_id := str(module["id"])
		a.ok(not by_id.has(module_id), id + " unique " + module_id)
		by_id[module_id] = module
		if str(module["kind"]) == Schema.MODULE_CORE:
			cores += 1
		if str(module["kind"]) == Schema.MODULE_POWER:
			powers += 1
		if str(module["kind"]) == Schema.MODULE_LOCOMOTION:
			a.eq(str(module["ring"]), Schema.RING_CHASSIS, module_id + " stays on the chassis")
		if module.has("host"):
			a.ok(_has_module(vehicle, str(module["host"])), module_id + " host exists")
	a.eq(cores, 1, id + " one core")
	a.eq(powers, powers_expected, id + " power count")
	for module in vehicle["modules"]:
		a.ok(_chain_ok(by_id, module), id + "/" + str(module["id"]) + " host chain")


static func _has_module(vehicle: Dictionary, id: String) -> bool:
	for module in vehicle["modules"]:
		if str(module["id"]) == id:
			return true
	return false


static func _chain_ok(by_id: Dictionary, start: Dictionary) -> bool:
	var seen := {}
	var current: Dictionary = start
	var guard := 0
	while current.has("host"):
		var module_id := str(current["id"])
		if seen.has(module_id):
			return false
		seen[module_id] = true
		var host := str(current["host"])
		if not by_id.has(host):
			return false
		current = by_id[host]
		guard += 1
		if guard > 32:
			return false
	return true


static func _sight(cat, a) -> void:
	var look = cat.look_range()
	a.eq(look, 7200.0, "C2 look range")
	for id in cat.weapon_ids():
		var weapon_range := float(cat.weapon(str(id))["range"])
		a.ok(weapon_range <= look, "C2 " + str(id) + " range <= look range")


static func _map(cat, a) -> void:
	var passage = cat.min_passage("hills")
	for id in cat.lineup_ids():
		var radius := float(cat.vehicle(str(id))["collisionRadius"])
		a.ok(passage > 2.0 * radius + 150.0, "C3 passage " + str(id))
	var bases: Array = cat.map_def("hills")["bases"]
	var dx := float(bases[0]["pos"]["x"]) - float(bases[1]["pos"]["x"])
	var dy := float(bases[0]["pos"]["y"]) - float(bases[1]["pos"]["y"])
	var half := sqrt(dx * dx + dy * dy) / 2.0
	a.near(half, 6098.797012526323, "C3 base half-separation", 1e-9)
	for id in cat.lineup_ids():
		a.ok(_max_range(cat, cat.vehicle(str(id))) < half, "C3 " + str(id) + " range stays inside half the map")


static func _match(cat, a) -> void:
	var quota := int(cat.rules["match"]["quotaPerType"])
	a.ok(quota * cat.lineup_ids().size() >= 3, "C5 quota covers a side of 3")
	a.ok(float(cat.rules["match"]["deathCap"]) >= 1.0, "C5 death cap")
	a.ok(float(cat.rules["match"]["changePenalty"]) >= 0.0, "C5 change penalty")


static func _gradient(cat, a) -> void:
	var hawk := _primary_gun_range(cat, cat.vehicle("hawk"))
	var swarm := _primary_gun_range(cat, cat.vehicle("swarm"))
	var bulwark := _primary_gun_range(cat, cat.vehicle("bulwark"))
	a.ok(hawk < swarm and swarm < bulwark, "C6 main-gun range hawk < swarm < bulwark")
	var slow := float(cat.vehicle("bulwark")["move"]["maxSpeed"])
	var mid := float(cat.vehicle("swarm")["move"]["maxSpeed"])
	var fast := float(cat.vehicle("hawk")["move"]["maxSpeed"])
	a.ok(slow < mid and mid < fast, "C6 speed bulwark < swarm < hawk")


static func _sigma(cat, a) -> void:
	var fallback := float(cat.weapon_table["defaultSigmaRatio"])
	for id in cat.weapon_ids():
		var weapon = cat.weapon(str(id))
		if str(weapon["kind"]) != Schema.WEAPON_KINETIC:
			continue
		var ratio := fallback
		if weapon["dispersion"].has("sigmaRatio"):
			ratio = float(weapon["dispersion"]["sigmaRatio"])
		a.ok(ratio >= 0.1 and ratio <= 1.0, "C7 sigma " + str(id))


static func _max_range(cat, vehicle: Dictionary) -> float:
	var best := 0.0
	for module in vehicle["modules"]:
		if module.has("weapon"):
			best = maxf(best, float(cat.weapon(str(module["weapon"]))["range"]))
	return best


static func _primary_gun_range(cat, vehicle: Dictionary) -> float:
	for module in vehicle["modules"]:
		if not module.has("primary") or not module["primary"]:
			continue
		if not module.has("weapon"):
			continue
		var weapon = cat.weapon(str(module["weapon"]))
		if str(weapon["kind"]) == Schema.WEAPON_MISSILE:
			continue
		return float(weapon["range"])
	return -1.0
