extends SceneTree

const AssertScript := preload("res://tests/assert.gd")
const RngTest := preload("res://tests/rng_test.gd")
const MathTest := preload("res://tests/math_test.gd")
const ClockTest := preload("res://tests/clock_test.gd")
const DeterminismTest := preload("res://tests/determinism_test.gd")
const DataTest := preload("res://tests/data_test.gd")
const GeometryTest := preload("res://tests/geometry_test.gd")
const MovementTest := preload("res://tests/movement_test.gd")
const TerrainTest := preload("res://tests/terrain_test.gd")
const VehicleTest := preload("res://tests/vehicle_test.gd")
const TrackingTest := preload("res://tests/tracking_test.gd")
const ConstraintsTest := preload("res://tests/constraints_test.gd")
const CombatTest := preload("res://tests/combat_test.gd")
const CombatScenarioTest := preload("res://tests/combat_scenario_test.gd")
const MatchTest := preload("res://tests/match_test.gd")
const ReplayTest := preload("res://tests/replay_test.gd")
const AiTest := preload("res://tests/ai_test.gd")
const LayerTest := preload("res://tests/layer_test.gd")


var _finished := false


func _initialize() -> void:
	var info := Engine.get_version_info()
	print("ENGINE %s.%s.%s.%s.%s" % [info.major, info.minor, info.patch, info.status, info.hash])
	var a = AssertScript.new()
	RngTest.run(a)
	MathTest.run(a)
	ClockTest.run(a)
	DeterminismTest.run(a)
	DataTest.run(a)
	GeometryTest.run(a)
	MovementTest.run(a)
	TerrainTest.run(a)
	VehicleTest.run(a)
	TrackingTest.run(a)
	ConstraintsTest.run(a)
	CombatTest.run(a)
	CombatScenarioTest.run(a)
	MatchTest.run(a)
	ReplayTest.run(a)
	AiTest.run(a)
	LayerTest.run(a)
	print("TESTS: %d failed" % a.failed)
	print("TESTS: %d passed, %d failed" % [a.passed, a.failed])
	_finished = true
	quit(0 if a.failed == 0 else 1)


func _process(_delta: float) -> bool:
	# If _initialize errors before quit(), SceneTree would otherwise run forever.
	if not _finished:
		print("TESTS: runner did not finish")
		quit(1)
	return true
