extends RefCounted

const Util := preload("res://tests/motion_util.gd")
const Command := preload("res://sim/command.gd")
const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")

## Movement half of thinkSimple's hover orbit. Missile nose-lock is omitted:
## weapons are not ported, so the missile is never treated as ready.


static func run(a) -> void:
	print("RUN tracking")
	print("DEFER thinkSimple missile nose-lock; AI steering belongs to the match step")
	var cat = Util.catalog()
	var hawk = cat.vehicle("hawk")
	var radius := float(hawk["move"]["maxSpeed"]) / Angle.deg(float(hawk["move"]["turnRate"]))
	a.ok(radius <= 600.0, "hawk minimum turn radius")
	var golden: Dictionary = Util.golden()
	var average := _orbit(cat, 600.0)
	a.ok(absf(average - 600.0) < 120.0, "hawk holds the orbit")
	a.near(average, float(golden["orbit"]["average"]), "orbit average", Util.TOL)


static func _orbit(cat, orbit_radius: float) -> float:
	var world = Util.arena(cat)
	world.arena_w = 8000.0
	world.arena_h = 8000.0
	var anchor = world.spawn(cat.vehicle("bulwark"), 0, {"x": 4000.0, "y": 4000.0}, 0.0)
	var flyer = world.spawn(cat.vehicle("hawk"), 1, {"x": 4000.0, "y": 4000.0 - orbit_radius - 200.0}, PI / 2.0)
	var nose := (50.0 * PI) / 180.0
	var dist_sum := 0.0
	var samples := 0
	var hold := Command.merge({"secondaries": false})
	for i in 30 * 60:
		var order := _hover_orbit(flyer, anchor["pos"], orbit_radius, nose)
		var cmds := {}
		cmds[anchor["id"]] = hold
		cmds[flyer["id"]] = order
		world.step(cmds)
		if i > 10 * 60:
			samples += 1
			dist_sum += Point.distance(flyer["pos"], anchor["pos"])
	return dist_sum / float(samples)


static func _hover_orbit(flyer: Dictionary, target: Dictionary, orbit_radius: float, nose: float) -> Dictionary:
	var dx := float(target["x"]) - float(flyer["pos"]["x"])
	var dy := float(target["y"]) - float(flyer["pos"]["y"])
	var dist := Point.hypot(dx, dy)
	if dist == 0.0:
		dist = 1.0
	var bearing := atan2(dy, dx)
	var move: Dictionary = flyer["def"]["move"]
	var vmax := float(move["maxSpeed"])
	var rx := dx / dist
	var ry := dy / dist
	var tx := -ry
	var ty := rx
	var radial := clampf((dist - orbit_radius) * 1.5, -vmax, vmax)
	var vt := vmax * 0.85
	var want_x := tx * vt + rx * radial
	var want_y := ty * vt + ry * radial
	var fx := cos(float(flyer["heading"]))
	var fy := sin(float(flyer["heading"]))
	var along := want_x * fx + want_y * fy
	var side := -want_x * fy + want_y * fx
	var throttle := along / vmax if along >= 0.0 else along / (vmax * float(move["reverseRatio"]))
	var strafe := side / (vmax * float(move["strafeRatio"]))
	var turn := Angle.delta(float(flyer["heading"]), bearing + nose) * 3.0
	return Command.merge({
		"throttle": clampf(throttle, -1.0, 1.0),
		"turn": clampf(turn, -1.0, 1.0),
		"strafe": clampf(strafe, -1.0, 1.0),
	})
