extends RefCounted
class_name SimPoint

## 64-bit points stored as {x, y} dictionaries.
## Vector2 is 32-bit and will not match Game_test@33f4be8 on baked vertices.
## +X right, +Y down. Rotation is clockwise-positive:
## x' = x cos - y sin, y' = x sin + y cos.


const NORM_EPSILON := 1e-9


static func xy(x: float, y: float) -> Dictionary:
	return {"x": x, "y": y}


static func copy(p: Dictionary) -> Dictionary:
	return {"x": float(p["x"]), "y": float(p["y"])}


static func hypot(x: float, y: float) -> float:
	x = absf(x)
	y = absf(y)
	if x < y:
		var swap := x
		x = y
		y = swap
	if x == 0.0:
		return 0.0
	var ratio := y / x
	return x * sqrt(1.0 + ratio * ratio)


static func length(v: Dictionary) -> float:
	return hypot(float(v["x"]), float(v["y"]))


static func distance(a: Dictionary, b: Dictionary) -> float:
	return hypot(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"]))


static func dot(a: Dictionary, b: Dictionary) -> float:
	return float(a["x"]) * float(b["x"]) + float(a["y"]) * float(b["y"])


static func cross(a: Dictionary, b: Dictionary) -> float:
	return float(a["x"]) * float(b["y"]) - float(a["y"]) * float(b["x"])


static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"x": float(a["x"]) + float(b["x"]), "y": float(a["y"]) + float(b["y"])}


static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"x": float(a["x"]) - float(b["x"]), "y": float(a["y"]) - float(b["y"])}


static func mul(v: Dictionary, scale: float) -> Dictionary:
	return {"x": float(v["x"]) * scale, "y": float(v["y"]) * scale}


static func rotated(v: Dictionary, radians: float) -> Dictionary:
	var c := cos(radians)
	var s := sin(radians)
	var x := float(v["x"])
	var y := float(v["y"])
	return {"x": x * c - y * s, "y": x * s + y * c}


static func from_angle(radians: float, radius: float = 1.0) -> Dictionary:
	return {"x": cos(radians) * radius, "y": sin(radians) * radius}


static func lerp(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"x": float(a["x"]) + (float(b["x"]) - float(a["x"])) * t,
		"y": float(a["y"]) + (float(b["y"]) - float(a["y"])) * t,
	}
