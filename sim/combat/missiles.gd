extends RefCounted
class_name SimMissiles

## Game_test@33f4be8 src/sim/combat/missiles.ts.
## Boost wiggles with the spread stream. Cruise turns toward the locked body
## without a lead solution. Impact uses the same resolver as shells.

const Angle := preload("res://sim/angle.gd")
const Point := preload("res://sim/point.gd")
const Sweep := preload("res://sim/combat/sweep.gd")
const Impact := preload("res://sim/combat/impact.gd")

const WIGGLE_PERIOD := 0.15


static func launch(world, owner: int, module_id: String, weapon: Dictionary, from: Dictionary, angle: float, target, rng) -> void:
	var off := 0.0
	if float(weapon["spread"]) > 0.0:
		off = Angle.deg(rng.truncated_gauss(float(weapon["spread"]) / 2.0, float(weapon["spread"])))
	var team := -1
	for vehicle in world.vehicles:
		if int(vehicle["id"]) == owner:
			team = int(vehicle["team"])
			break
	world.missiles.append({
		"owner": owner,
		"team": team,
		"module": module_id,
		"weapon": str(weapon["id"]),
		"pos": Point.copy(from),
		"heading": angle + off,
		"speed": float(weapon["launchSpeed"]),
		"age": 0.0,
		"travelled": 0.0,
		"target": target if weapon.get("guided", false) else null,
		"wiggle": 0.0,
		"wiggle_t": 0.0,
	})


static func step(world, dt: float, rng, events: Array) -> void:
	var keep: Array = []
	for missile in world.missiles:
		var weapon: Dictionary = world.table[str(missile["weapon"])]
		var turn := Angle.deg(float(weapon["turnRate"]))
		missile["age"] = float(missile["age"]) + dt
		var age := float(missile["age"])
		if age < float(weapon["boostTime"]):
			missile["speed"] = float(weapon["launchSpeed"]) + (float(weapon["speed"]) - float(weapon["launchSpeed"])) * (age / float(weapon["boostTime"]))
			if turn > 0.0 and age >= float(missile["wiggle_t"]):
				missile["wiggle"] = rng.range(-turn, turn)
				missile["wiggle_t"] = age + WIGGLE_PERIOD
			missile["heading"] = float(missile["heading"]) + float(missile["wiggle"]) * dt
		else:
			missile["speed"] = float(weapon["speed"])
			var guided = null
			if missile["target"] != null:
				for vehicle in world.vehicles:
					if int(vehicle["id"]) == int(missile["target"]) and vehicle["alive"]:
						guided = vehicle
						break
			if guided != null and turn > 0.0:
				var err := Angle.delta(float(missile["heading"]), atan2(float(guided["pos"]["y"]) - float(missile["pos"]["y"]), float(guided["pos"]["x"]) - float(missile["pos"]["x"])))
				missile["heading"] = float(missile["heading"]) + signf(err) * minf(absf(err), turn * dt)
		var step_len := float(missile["speed"]) * dt
		var direction := {"x": cos(float(missile["heading"])), "y": sin(float(missile["heading"]))}
		var end := {
			"x": float(missile["pos"]["x"]) + float(direction["x"]) * step_len,
			"y": float(missile["pos"]["y"]) + float(direction["y"]) * step_len,
		}
		var hit = Sweep.sweep(world, int(missile["owner"]), int(missile["team"]), missile["pos"], end)
		var terrain_hit = world.terrain.segment_hit(missile["pos"], end)
		if hit != null or terrain_hit != null:
			var terrain_first := terrain_hit != null and (hit == null or float(terrain_hit["t"]) < float(hit["t"]))
			var t := float(terrain_hit["t"]) if terrain_first else float(hit["t"])
			var at := {
				"x": float(missile["pos"]["x"]) + (float(end["x"]) - float(missile["pos"]["x"])) * t,
				"y": float(missile["pos"]["y"]) + (float(end["y"]) - float(missile["pos"]["y"])) * t,
			}
			var source := {
				"owner": missile["owner"],
				"team": missile["team"],
				"weapon": str(weapon["id"]),
				"weaponName": str(weapon["name"]),
				"warhead": weapon["warhead"],
				"dir": direction,
				"dist": float(missile["travelled"]) + step_len * t,
				"penRange": null,
			}
			if terrain_first:
				Impact.resolve_terrain(world, source, terrain_hit["obstacle"], at, events)
			else:
				Impact.resolve_impact(world, source, hit["v"], hit["m"], at, hit["normal"], events)
			continue
		missile["pos"] = end
		missile["travelled"] = float(missile["travelled"]) + step_len
		var outside: bool = float(end["x"]) < 0.0 or float(end["y"]) < 0.0 or float(end["x"]) > float(world.arena_w) or float(end["y"]) > float(world.arena_h)
		if age >= float(weapon["maxTime"]) or outside:
			events.append({"t": "missileGone", "at": end})
		else:
			keep.append(missile)
	world.missiles = keep
