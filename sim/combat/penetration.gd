extends RefCounted
class_name SimPen

## Game_test@33f4be8 src/sim/combat/penetration.ts.
## AP falloff, sloped armor, ricochet, overmatch, HE factor. No RNG.

const Angle := preload("res://sim/angle.gd")

const RICOCHET_ANGLE := (68.0 * PI) / 180.0
const SLOPE_EXPONENT := 0.8
const FALLOFF := 0.85
const FALLOFF_EXPONENT := 0.8


static func at_distance(p0: float, range: float, dist: float) -> float:
	var r := clampf(dist, 0.0, range) / range
	return p0 * (1.0 - FALLOFF * pow(r, FALLOFF_EXPONENT))


static func effective_armor(armor_current: float, theta: float) -> float:
	return armor_current / pow(cos(theta), SLOPE_EXPONENT)


## overmatch_k is NAN when the caller does not supply D38.
static func resolve_hit(penetration: float, armor_current: float, theta: float, overmatch_k: float = NAN) -> String:
	if not is_nan(overmatch_k) and penetration >= overmatch_k * armor_current:
		return "overmatch"
	if absf(theta) > RICOCHET_ANGLE:
		return "ricochet"
	if penetration > effective_armor(armor_current, theta):
		return "pen"
	return "nonpen"


static func ap_pen_damage(base: float, penetration: float, eff_armor: float) -> float:
	return base * minf(1.5, 1.0 + (0.5 * (penetration - eff_armor)) / maxf(eff_armor, 1e-6))


static func he_factor(he_pen: float, armor_current: float, min_factor: float) -> float:
	return maxf(min_factor, (he_pen - armor_current) / he_pen)


static func max_pen_distance(p0: float, range: float, armor_current: float, theta: float) -> float:
	var need := effective_armor(armor_current, theta)
	if need >= p0:
		return 0.0
	var ratio := (1.0 - need / p0) / FALLOFF
	if ratio >= 1.0:
		return range
	return range * pow(ratio, 1.0 / FALLOFF_EXPONENT)


static func ricochet_deg() -> float:
	return Angle.to_deg(RICOCHET_ANGLE)
