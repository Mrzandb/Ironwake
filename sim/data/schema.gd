extends RefCounted
class_name DataSchema

## Tables frozen from Game_test@33f4be8. Loaded by DataCatalog.
##
## Local vehicle coordinates match the prototype schema: +x is the hull's
## forward axis, +y is the hull's right, units are world units. With heading
## 0 (facing world +x), local +y is world +y. World +y is down. Do not flip y.
##
## Angle units are not uniform. Vehicle arcs, traverse rates, dispersion and
## hull turn rates are degrees. Map spawn headings are radians (the hills
## table stores -PI/4 and 3*PI/4). Keep both as baked. Gait `stepTime` and
## missile `maxTime` are seconds.
##
## Polygon rings in module "parts" are the evaluated shape constructors and,
## for bulwark legs, the rest pose from legParts(). They are 64-bit. Copying
## a point into Vector2 narrows it to 32-bit, so callers should keep {x, y}.
##
## Vehicle "cost" is reserved for a future in-match economy. The prototype
## has no such field. Default is 0. No combat, movement, quota or respawn
## rule reads it.


const MODULE_CORE := "core"
const MODULE_POWER := "power"
const MODULE_ARMOR := "armor"
const MODULE_LOCOMOTION := "locomotion"
const MODULE_WEAPON := "weapon"

const RING_CHASSIS := "chassis"
const RING_CROWN := "crown"

const LOCOMOTION_HOVER := "hover"
const LOCOMOTION_TRACKED := "tracked"
const LOCOMOTION_LEGGED := "legged"
const LOCOMOTION_STATIC := "static"

const SIZE_SMALL := "small"
const SIZE_MEDIUM := "medium"
const SIZE_LARGE := "large"

const WEAPON_KINETIC := "kinetic"
const WEAPON_LASER := "laser"
const WEAPON_MISSILE := "missile"


static func px(point: Dictionary) -> float:
	return float(point["x"])


static func py(point: Dictionary) -> float:
	return float(point["y"])
