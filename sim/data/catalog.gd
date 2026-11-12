extends RefCounted
class_name DataCatalog

## Pure loader for res://data JSON. No nodes, scenes, or res://game.
## Infinity in stat limits is stored as {"$": "inf"} and returned as INF.

var index: Dictionary
var rules: Dictionary
var weapon_table: Dictionary
var structure_stats: Dictionary
var blueprints: Dictionary
var map_docs: Dictionary


func _init() -> void:
	index = _ready(_read("res://data/index.json"))
	rules = _ready(_read("res://data/rules.json"))
	weapon_table = _ready(_read("res://data/weapons.json"))
	structure_stats = _ready(_read("res://data/structures.json"))
	blueprints = {}
	for group in ["lineup", "concepts", "structures"]:
		for id in index[group]:
			var key := str(id)
			blueprints[key] = _ready(_read("res://data/vehicles/%s.json" % key))
	map_docs = {}
	for id in index["maps"]:
		var key := str(id)
		map_docs[key] = _ready(_read("res://data/maps/%s.json" % key))


func lineup_ids() -> Array:
	return index["lineup"]


func concept_ids() -> Array:
	return index["concepts"]


func structure_ids() -> Array:
	return index["structures"]


func vehicle_ids() -> Array:
	var ids: Array = []
	ids.append_array(lineup_ids())
	ids.append_array(concept_ids())
	ids.append_array(structure_ids())
	return ids


func vehicle(id: String) -> Dictionary:
	return blueprints[id]["vehicle"]


func blueprint(id: String) -> Dictionary:
	return blueprints[id]


func weapon_ids() -> Array:
	return weapon_table["weapons"].keys()


func weapon(id: String) -> Dictionary:
	return weapon_table["weapons"][id]


func map_ids() -> Array:
	return index["maps"]


func map_doc(id: String) -> Dictionary:
	return map_docs[id]


func map_def(id: String) -> Dictionary:
	return map_docs[id]["map"]


func look_range() -> float:
	return float(index["sight"]["lookRange"])


func min_passage(id: String = "hills") -> float:
	return float(map_docs[id]["minPassage"])


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing " + path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("bad json " + path)
		return {}
	return parsed


func _ready(value):
	if typeof(value) == TYPE_DICTIONARY:
		if value.size() == 1 and value.has("$"):
			var marker := str(value["$"])
			if marker == "inf":
				return INF
			if marker == "-inf":
				return -INF
		var out := {}
		for key in value.keys():
			out[key] = _ready(value[key])
		return out
	if typeof(value) == TYPE_ARRAY:
		var out: Array = []
		for item in value:
			out.append(_ready(item))
		return out
	return value
