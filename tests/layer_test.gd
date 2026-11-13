extends RefCounted

const FORBIDDEN := [
	"res://game",
	"extends Node",
	"randf",
	"randi",
	"randfn",
	"RandomNumberGenerator",
	"randomize",
	"Time.", # engine clock API; the gait key stepTime must stay writable
	"PhysicsServer",
	"move_and_slide",
	"get_tree(",
	"SceneTree",
	"static var",
	"Input.",
	"DisplayServer",
	"OS.get_",
]


static func run(a) -> void:
	print("RUN layer")
	var files: Array = []
	_collect("res://sim", files)
	a.ok(files.size() >= 9, "sim has its scripts")
	for path in files:
		_check_sim(str(path), a)
		_check_text(str(path), a)
	var extra: Array = []
	_collect("res://game", extra)
	_collect("res://tests", extra)
	_collect("res://tools", extra)
	extra.append("res://project.godot")
	extra.append("res://AGENTS.md")
	extra.append("res://README.md")
	for path in extra:
		_check_text(str(path), a)
	var baked: Array = []
	_collect_ext("res://data", baked, ["json"])
	_collect_ext("res://tests", baked, ["json"])
	_collect_ext("res://tools", baked, ["mjs"])
	a.ok(baked.size() >= 12, "baked json and the bake script are present")
	for path in baked:
		_check_text(str(path), a)
	a.ok(DirAccess.open("res://data") != null, "data directory exists")
	var project := FileAccess.get_file_as_string("res://project.godot")
	a.ok(not project.contains("[autoload]"), "no autoload singletons")
	a.ok(project.contains('run/main_scene="res://game/main.tscn"'), "main scene is in game/")


static func _collect_ext(path: String, acc: Array, exts: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if str(file_name).begins_with("."):
			continue
		var ext := str(file_name).get_extension()
		if exts.has(ext):
			acc.append(path.path_join(str(file_name)))
	for sub in dir.get_directories():
		if str(sub).begins_with("."):
			continue
		_collect_ext(path.path_join(str(sub)), acc, exts)


static func _collect(path: String, acc: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.begins_with("."):
			continue
		var full := path.path_join(file_name)
		var ext := file_name.get_extension()
		if ext == "gd" or ext == "tscn" or ext == "godot":
			acc.append(full)
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		_collect(path.path_join(sub), acc)


static func _strip(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash)
		out += line + "\n"
	return out


static func _check_sim(path: String, a) -> void:
	var code := _strip(FileAccess.get_file_as_string(path))
	var extends_sim := code.contains("extends \"res://sim/")
	if not code.contains("extends RefCounted") and not extends_sim:
		a.ok(false, path + " must extend RefCounted")
		return
	var bad := ""
	for token in FORBIDDEN:
		if code.contains(token):
			bad += token + " "
	if bad == "":
		a.ok(true, path + " layer ok")
	else:
		a.ok(false, path + " forbidden: " + bad)


static func _check_text(path: String, a) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		a.ok(false, "open " + path)
		return
	var header := file.get_buffer(3)
	var bom := header.size() >= 3 and header[0] == 0xEF and header[1] == 0xBB and header[2] == 0xBF
	file.seek(0)
	var raw := file.get_as_text()
	file.close()
	a.ok(not bom, path + " no BOM")
	a.ok(not raw.contains("\r"), path + " no CR")
