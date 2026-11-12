extends Node

const SimWorldScript := preload("res://sim/world.gd")

var _world


func _ready() -> void:
	_world = SimWorldScript.new(1)
	if DisplayServer.get_name() == "headless":
		print("Ironwake main: headless placeholder tick=%d" % _world.tick)
		get_tree().quit()
