extends RefCounted
class_name SimStats

## Game_test@33f4be8 src/sim/stats/resolver.ts.
## flat, then mul, then set, then clamp to rules.statLimits.
## Purchase-origin modifiers live on holder["purchase"]. Combat never writes
## that array. An empty array is the default, and stat() then matches a holder
## that only has "mods". Economy code can append modifiers whose source is
## PURCHASE_SOURCE. appliesTo is still honored.

const PURCHASE_SOURCE := "purchase"


static func stat(holder: Dictionary, key: String, base: float, rules: Dictionary, scope: Dictionary = {}, target = null) -> float:
	var purchase: Array = holder.get("purchase", [])
	var target_purchase: Array = []
	var target_mods: Array = []
	if target != null:
		target_purchase = target.get("purchase", [])
		target_mods = target["mods"]
	if holder["mods"].is_empty() and purchase.is_empty() and target_mods.is_empty() and target_purchase.is_empty():
		return base
	var box := {"flat": 0.0, "mul": 1.0, "has_set": false, "set_value": 0.0, "any": false}
	for mod in holder["mods"]:
		if str(mod["appliesTo"]) == "self" and _matches(mod, key, scope):
			_take(box, mod)
	for mod in purchase:
		if str(mod["appliesTo"]) == "self" and _matches(mod, key, scope):
			_take(box, mod)
	if target != null and target != holder:
		for mod in target_mods:
			if str(mod["appliesTo"]) == "target" and _matches(mod, key, scope):
				_take(box, mod)
		for mod in target_purchase:
			if str(mod["appliesTo"]) == "target" and _matches(mod, key, scope):
				_take(box, mod)
	if not box["any"]:
		return base
	var value := (base + float(box["flat"])) * float(box["mul"])
	if box["has_set"]:
		value = float(box["set_value"])
	return _clamp(rules, key, value)


static func _take(box: Dictionary, mod: Dictionary) -> void:
	box["any"] = true
	var op: Dictionary = mod["op"]
	var kind := str(op["kind"])
	if kind == "flat":
		box["flat"] = float(box["flat"]) + float(op["v"])
	elif kind == "mul":
		box["mul"] = float(box["mul"]) * float(op["v"])
	else:
		box["has_set"] = true
		box["set_value"] = float(op["v"])


static func add_modifier(holder: Dictionary, mod: Dictionary) -> void:
	var left := INF
	if mod.has("duration"):
		left = float(mod["duration"])
	var stack := str(mod["stack"])
	if stack == "refresh":
		for old in holder["mods"]:
			if str(old["id"]) == str(mod["id"]):
				old["op"] = (mod["op"] as Dictionary).duplicate(true)
				old["left"] = left
				return
	elif stack == "exclusive":
		var kept: Array = []
		for old in holder["mods"]:
			if str(old["source"]) == str(mod["source"]) and str(old["stat"]) == str(mod["stat"]):
				continue
			kept.append(old)
		holder["mods"] = kept
	holder["mods"].append(_active(mod, left))


## Reserved economy entry. Same stacking rules as add_modifier, stored apart
## from combat modifiers. Nothing in this step calls it.
static func add_purchase(holder: Dictionary, mod: Dictionary) -> void:
	if not holder.has("purchase"):
		holder["purchase"] = []
	var stamped: Dictionary = mod.duplicate(true)
	stamped["source"] = PURCHASE_SOURCE
	var saved: Array = holder["mods"]
	holder["mods"] = holder["purchase"]
	add_modifier(holder, stamped)
	holder["purchase"] = holder["mods"]
	holder["mods"] = saved


static func remove_modifiers(holder: Dictionary, source: String) -> void:
	var kept: Array = []
	for mod in holder["mods"]:
		if str(mod["source"]) != source:
			kept.append(mod)
	holder["mods"] = kept


static func tick_modifiers(holder: Dictionary, dt: float) -> void:
	if holder["mods"].is_empty():
		return
	for mod in holder["mods"]:
		mod["left"] = float(mod["left"]) - dt
	var kept: Array = []
	for mod in holder["mods"]:
		if float(mod["left"]) > 0.0:
			kept.append(mod)
	holder["mods"] = kept


static func _active(mod: Dictionary, left: float) -> Dictionary:
	var out := {
		"id": str(mod["id"]),
		"stat": str(mod["stat"]),
		"op": (mod["op"] as Dictionary).duplicate(true),
		"source": str(mod["source"]),
		"appliesTo": str(mod["appliesTo"]),
		"stack": str(mod["stack"]),
		"left": left,
	}
	if mod.has("module"):
		out["module"] = str(mod["module"])
	if mod.has("weapon"):
		out["weapon"] = str(mod["weapon"])
	if mod.has("duration"):
		out["duration"] = float(mod["duration"])
	return out


static func _matches(mod: Dictionary, key: String, scope: Dictionary) -> bool:
	if str(mod["stat"]) != key:
		return false
	if mod.has("module") and str(mod["module"]) != str(scope.get("module", "")):
		return false
	if mod.has("weapon") and str(mod["weapon"]) != str(scope.get("weapon", "")):
		return false
	return true


static func _clamp(rules: Dictionary, key: String, value: float) -> float:
	var limits: Dictionary = rules["statLimits"]
	var pair: Array = limits["default"]
	if limits.has(key):
		pair = limits[key]
	return minf(float(pair[1]), maxf(float(pair[0]), value))
