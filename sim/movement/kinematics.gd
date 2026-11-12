extends RefCounted
class_name SimKin

## Game_test@33f4be8 src/sim/movement/kinematics.ts.
## Legged, hover and tracked. Deterministic. No RNG.
## Turn rates in the blueprint are degrees per second. Heading is radians.
## stat() multipliers are not applied here. With no modifiers they are 1.
## Combat can scale speed_mul and turn_mul before calling step_body.

const Point := preload("res://sim/point.gd")
const Angle := preload("res://sim/angle.gd")

const TRACK_TURN_DRAG := 0.25


static func full_mobility() -> Dictionary:
	return {"speed_mul": 1.0, "turn_mul": 1.0, "turn_bias": 0.0}


static func stopped_mobility() -> Dictionary:
	return {"speed_mul": 0.0, "turn_mul": 0.0, "turn_bias": 0.0}


static func _approach(x: float, target: float, max_step: float) -> float:
	if x < target:
		return minf(target, x + max_step)
	return maxf(target, x - max_step)


static func _step_turn(body: Dictionary, input: float, throttle: float, move: Dictionary, mods: Dictionary, dt: float) -> void:
	var mixed := clampf(input + float(mods["turn_bias"]) * absf(throttle), -1.0, 1.0)
	var target := mixed * Angle.deg(float(move["turnRate"])) * float(mods["turn_mul"])
	body["ang_vel"] = _approach(float(body["ang_vel"]), target, Angle.deg(float(move["turnAccel"])) * dt)
	body["heading"] = float(body["heading"]) + float(body["ang_vel"]) * dt


static func _integrate(body: Dictionary, dt: float) -> void:
	var vel: Dictionary = body["vel"]
	body["pos"] = {
		"x": float(body["pos"]["x"]) + float(vel["x"]) * dt,
		"y": float(body["pos"]["y"]) + float(vel["y"]) * dt,
	}


static func step_legged(body: Dictionary, cmd: Dictionary, move: Dictionary, mods: Dictionary, dt: float) -> void:
	var throttle := float(cmd["throttle"])
	_step_turn(body, float(cmd["turn"]), throttle, move, mods, dt)
	var t := clampf(throttle, -1.0, 1.0)
	var vmax := float(move["maxSpeed"]) * float(mods["speed_mul"])
	var target := t * vmax if t >= 0.0 else t * vmax * float(move["reverseRatio"])
	var speed := float(body["speed"])
	var speeding := absf(target) > absf(speed) and (speed == 0.0 or signf(target) == signf(speed))
	var rate := float(move["accel"]) if speeding else float(move["brake"])
	speed = _approach(speed, target, rate * dt)
	body["speed"] = speed
	var heading := float(body["heading"])
	body["vel"] = {"x": cos(heading) * speed, "y": sin(heading) * speed}
	_integrate(body, dt)


static func step_hover(body: Dictionary, cmd: Dictionary, move: Dictionary, mods: Dictionary, dt: float) -> void:
	var throttle := float(cmd["throttle"])
	_step_turn(body, float(cmd["turn"]), throttle, move, mods, dt)
	var t := clampf(throttle, -1.0, 1.0)
	var strafe := clampf(float(cmd["strafe"]), -1.0, 1.0)
	var vmax := float(move["maxSpeed"]) * float(mods["speed_mul"])
	var heading := float(body["heading"])
	var fx := cos(heading)
	var fy := sin(heading)
	var rx := -fy
	var ry := fx
	var along := t * vmax if t >= 0.0 else t * vmax * float(move["reverseRatio"])
	var side := strafe * vmax * float(move["strafeRatio"])
	var vx := float(body["vel"]["x"])
	var vy := float(body["vel"]["y"])
	if (t == 0.0 and strafe == 0.0) or float(mods["speed_mul"]) == 0.0:
		var sp := Point.hypot(vx, vy)
		var k := 0.0
		if sp > 1e-6:
			k = maxf(0.0, sp - float(move["brake"]) * dt) / sp
		body["vel"] = {"x": vx * k, "y": vy * k}
	else:
		var want_x := fx * along + rx * side
		var want_y := fy * along + ry * side
		var dx := want_x - vx
		var dy := want_y - vy
		var dist := Point.hypot(dx, dy)
		var step := float(move["accel"]) * dt
		var k := 1.0 if dist <= step else step / dist
		body["vel"] = {"x": vx + dx * k, "y": vy + dy * k}
	var vel: Dictionary = body["vel"]
	body["speed"] = float(vel["x"]) * fx + float(vel["y"]) * fy
	_integrate(body, dt)


static func step_tracked(body: Dictionary, cmd: Dictionary, move: Dictionary, mods: Dictionary, dt: float) -> void:
	var throttle := float(cmd["throttle"])
	var turn := float(cmd["turn"])
	_step_turn(body, turn, throttle, move, mods, dt)
	var t := clampf(throttle, -1.0, 1.0)
	var drag := 1.0 - TRACK_TURN_DRAG * minf(1.0, absf(turn))
	var vmax := float(move["maxSpeed"]) * float(mods["speed_mul"]) * drag
	var target := t * vmax if t >= 0.0 else t * vmax * float(move["reverseRatio"])
	var speed := float(body["speed"])
	var speeding := absf(target) > absf(speed) and (speed == 0.0 or signf(target) == signf(speed))
	var rate := float(move["accel"]) if speeding else float(move["brake"])
	speed = _approach(speed, target, rate * dt)
	body["speed"] = speed
	var heading := float(body["heading"])
	body["vel"] = {"x": cos(heading) * speed, "y": sin(heading) * speed}
	_integrate(body, dt)


static func step_body(vehicle: Dictionary, body: Dictionary, cmd: Dictionary, mods: Dictionary, dt: float) -> void:
	var kind := str(vehicle["locomotion"])
	if kind == "static":
		return
	var move: Dictionary = vehicle["move"]
	if kind == "hover":
		step_hover(body, cmd, move, mods, dt)
	elif kind == "tracked":
		step_tracked(body, cmd, move, mods, dt)
	else:
		step_legged(body, cmd, move, mods, dt)
