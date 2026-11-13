extends RefCounted
class_name SimNav

## Game_test@33f4be8 src/sim/ai/nav.ts.
## Coarse A* shared by every vehicle. Cell size is 100.
## Rocks and the map border are closed. A wall cell opens when that wall dies.
## Ties break on the cell index. No engine physics and no unseeded random.

const Point := preload("res://sim/point.gd")
const Terrain := preload("res://sim/terrain/terrain.gd")

const CELL := 100.0
const LATERAL_SCALE := 2500.0
const MIN_MULT := 0.5
const DIRECT := {
	"lateral": 0.8,
	"offset": 0.0,
	"side": 1.0,
	"hug": -0.15,
	"max_leg": INF,
}
const TRACKED := {
	"lateral": 0.6,
	"offset": 1200.0,
	"side": 1.0,
	"hug": 0.15,
	"max_leg": 2500.0,
}
const HOVER := {
	"lateral": 0.9,
	"offset": 2600.0,
	"side": 1.0,
	"hug": 0.35,
	"max_leg": 1200.0,
}

var world
var clearance: float
var cols: int
var rows: int
var _rock: PackedByteArray
var _wall: PackedInt32Array
var _rock_dist: PackedByteArray


func _init(battle, body_clearance: float = 170.0) -> void:
	world = battle
	clearance = body_clearance
	cols = int(ceil(float(battle.arena_w) / CELL))
	rows = int(ceil(float(battle.arena_h) / CELL))
	var count := cols * rows
	_rock = PackedByteArray()
	_rock.resize(count)
	_wall = PackedInt32Array()
	_wall.resize(count)
	_wall.fill(-1)
	var obstacles: Array = battle.terrain.obstacles
	for j in rows:
		for i in cols:
			var center := _center(i, j)
			var k := j * cols + i
			var edge := minf(float(center["x"]), float(center["y"]))
			edge = minf(edge, float(battle.arena_w) - float(center["x"]))
			edge = minf(edge, float(battle.arena_h) - float(center["y"]))
			if edge < clearance:
				_rock[k] = 1
				continue
			for idx in obstacles.size():
				if _rock[k] != 0:
					break
				var obstacle: Dictionary = obstacles[idx]
				var box: Dictionary = obstacle["box"]
				if float(center["x"]) < float(box["x0"]) - clearance or float(center["x"]) > float(box["x1"]) + clearance:
					continue
				if float(center["y"]) < float(box["y0"]) - clearance or float(center["y"]) > float(box["y1"]) + clearance:
					continue
				var poly: Array = obstacle["def"]["poly"]
				var near := Terrain.point_in_polygon(center, poly) or float(Terrain.closest_on_polygon(center, poly)["d"]) < clearance
				if not near:
					continue
				if str(obstacle["def"]["kind"]) == "rock":
					_rock[k] = 1
				elif _wall[k] == -1:
					_wall[k] = idx
	_rock_dist = PackedByteArray()
	_rock_dist.resize(count)
	_rock_dist.fill(255)
	var queue: Array = []
	for k in count:
		if _rock[k] != 0:
			_rock_dist[k] = 0
			queue.append(k)
	var qi := 0
	while qi < queue.size():
		var k: int = queue[qi]
		qi += 1
		var i := k % cols
		var j := int(k / cols)
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = i + int(step[0])
			var nj: int = j + int(step[1])
			if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
				continue
			var nk := nj * cols + ni
			if int(_rock_dist[nk]) <= int(_rock_dist[k]) + 1:
				continue
			_rock_dist[nk] = mini(255, int(_rock_dist[k]) + 1)
			queue.append(nk)


func style_of(vehicle: Dictionary) -> Dictionary:
	var loco := str(vehicle["def"]["locomotion"])
	var base := DIRECT
	if loco == "tracked":
		base = TRACKED
	elif loco == "hover":
		base = HOVER
	var style: Dictionary = base.duplicate()
	style["side"] = 1.0 if int(vehicle["id"]) % 2 == 0 else -1.0
	return style


func _center(i: int, j: int) -> Dictionary:
	return {"x": (float(i) + 0.5) * CELL, "y": (float(j) + 0.5) * CELL}


func _cell_of(point: Dictionary) -> Vector2i:
	var i := int(floor(float(point["x"]) / CELL))
	var j := int(floor(float(point["y"]) / CELL))
	i = clampi(i, 0, cols - 1)
	j = clampi(j, 0, rows - 1)
	return Vector2i(i, j)


func passable(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return false
	var k := j * cols + i
	if _rock[k] != 0:
		return false
	var wall := int(_wall[k])
	if wall < 0:
		return true
	return not bool(world.terrain.obstacles[wall]["alive"])


func clear_line(a: Dictionary, b: Dictionary) -> bool:
	var dist := Point.distance(a, b)
	var n := maxi(1, int(ceil(dist / (CELL / 2.0))))
	for s in n + 1:
		var point := {
			"x": float(a["x"]) + ((float(b["x"]) - float(a["x"])) * float(s)) / float(n),
			"y": float(a["y"]) + ((float(b["y"]) - float(a["y"])) * float(s)) / float(n),
		}
		var cell := _cell_of(point)
		if not passable(cell.x, cell.y):
			return false
	return true


func _nearest(i0: int, j0: int):
	for radius in 12:
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				if maxi(absi(di), absi(dj)) != radius:
					continue
				if passable(i0 + di, j0 + dj):
					return Vector2i(i0 + di, j0 + dj)
	return null


func find_path(from: Dictionary, to: Dictionary, style = null, origin = null):
	if style == null:
		style = DIRECT
	if origin == null:
		origin = from
	var start_cell: Vector2i = _cell_of(from)
	var goal_cell: Vector2i = _cell_of(to)
	var start_pass = _nearest(start_cell.x, start_cell.y)
	var goal_pass = _nearest(goal_cell.x, goal_cell.y)
	if start_pass == null or goal_pass == null:
		return null
	var width := cols
	var start: int = start_pass.y * width + start_pass.x
	var goal: int = goal_pass.y * width + goal_pass.x
	var count := width * rows
	var score := PackedFloat64Array()
	score.resize(count)
	score.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var lx := float(to["x"]) - float(origin["x"])
	var ly := float(to["y"]) - float(origin["y"])
	var length := Point.hypot(lx, ly)
	if length == 0.0:
		length = 1.0
	var ux := lx / length
	var uy := ly / length
	var goal_i: int = goal_pass.x
	var goal_j: int = goal_pass.y
	var heap: Array = []
	score[start] = 0.0
	_heap_push(heap, _heuristic(start, width, goal_i, goal_j), start)
	while not heap.is_empty():
		var popped: Array = _heap_pop(heap)
		var k: int = int(popped[1])
		if closed[k] != 0:
			continue
		closed[k] = 1
		if k == goal:
			break
		var i := k % width
		var j := int(k / width)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if di == 0 and dj == 0:
					continue
				var ni: int = i + di
				var nj: int = j + dj
				if not passable(ni, nj):
					continue
				if di != 0 and dj != 0 and (not passable(i + di, j) or not passable(i, j + dj)):
					continue
				var nk := nj * width + ni
				var step := 1.0
				if di != 0 and dj != 0:
					step = sqrt(2.0)
				var next_score := float(score[k]) + step * _mult(nk, width, origin, ux, uy, length, style)
				if next_score < float(score[nk]):
					score[nk] = next_score
					came[nk] = k
					_heap_push(heap, next_score + _heuristic(nk, width, goal_i, goal_j), nk)
	if int(came[goal]) == -1 and goal != start:
		return null
	var cells: Array = []
	var cursor := goal
	while cursor != -1 and cursor != start:
		cells.append(_center(cursor % width, int(cursor / width)))
		cursor = int(came[cursor])
	cells.reverse()
	cells.append({"x": float(to["x"]), "y": float(to["y"])})
	var out: Array = []
	var anchor: Dictionary = {"x": float(from["x"]), "y": float(from["y"])}
	var max_leg := float(style["max_leg"])
	for index in cells.size():
		var nxt = cells[index + 1] if index + 1 < cells.size() else null
		var leg := 0.0
		if nxt != null:
			leg = Point.distance(anchor, nxt)
		if nxt != null and leg <= max_leg and clear_line(anchor, nxt):
			continue
		var kept: Dictionary = cells[index]
		out.append(kept)
		anchor = kept
	return out


func _mult(k: int, width: int, origin: Dictionary, ux: float, uy: float, length: float, style: Dictionary) -> float:
	var center := _center(k % width, int(k / width))
	var rx := float(center["x"]) - float(origin["x"])
	var ry := float(center["y"]) - float(origin["y"])
	var along := (rx * ux + ry * uy) / length
	if along < 0.0:
		along = 0.0
	elif along > 1.0:
		along = 1.0
	var lateral := rx * -uy + ry * ux
	var want := float(style["offset"]) * float(style["side"]) * sin(PI * along)
	var weight := 1.0 + float(style["lateral"]) * minf(1.0, absf(lateral - want) / LATERAL_SCALE)
	var rock_dist := int(_rock_dist[k])
	if rock_dist >= 1 and rock_dist <= 4:
		weight *= 1.0 - float(style["hug"])
	return maxf(MIN_MULT, weight)


func _heuristic(k: int, width: int, goal_i: int, goal_j: int) -> float:
	var dx := absi((k % width) - goal_i)
	var dy := absi(int(k / width) - goal_j)
	return (float(maxi(dx, dy)) + (sqrt(2.0) - 1.0) * float(mini(dx, dy))) * MIN_MULT


static func _heap_less(heap: Array, a: int, b: int) -> bool:
	var af: float = heap[a][0]
	var bf: float = heap[b][0]
	if af < bf:
		return true
	if af == bf and int(heap[a][1]) < int(heap[b][1]):
		return true
	return false


static func _heap_push(heap: Array, score: float, cell: int) -> void:
	heap.append([score, cell])
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		var parent_score: float = heap[parent][0]
		var parent_cell := int(heap[parent][1])
		if parent_score < score or (parent_score == score and parent_cell <= cell):
			break
		var swapped = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swapped
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var left := 2 * i + 1
			var right := left + 1
			var best := i
			if left < heap.size() and _heap_less(heap, left, best):
				best = left
			if right < heap.size() and _heap_less(heap, right, best):
				best = right
			if best == i:
				break
			var swapped = heap[best]
			heap[best] = heap[i]
			heap[i] = swapped
			i = best
	return top
