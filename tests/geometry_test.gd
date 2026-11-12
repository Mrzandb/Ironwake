extends RefCounted

const Poly := preload("res://sim/geometry/poly.gd")
const Util := preload("res://tests/motion_util.gd")


static func run(a) -> void:
	print("RUN geometry")
	var square: Array = [
		{"x": 0.0, "y": 0.0},
		{"x": 10.0, "y": 0.0},
		{"x": 10.0, "y": 10.0},
		{"x": 0.0, "y": 10.0},
	]
	var reversed := square.duplicate()
	reversed.reverse()
	var arrow: Array = [
		{"x": 0.0, "y": 0.0},
		{"x": 10.0, "y": 5.0},
		{"x": 0.0, "y": 10.0},
		{"x": 4.0, "y": 5.0},
	]
	var flat: Array = [
		{"x": 0.0, "y": 0.0},
		{"x": 5.0, "y": 0.0},
		{"x": 10.0, "y": 0.0},
		{"x": 5.0, "y": 5.0},
	]
	a.ok(Poly.is_convex(square), "square convex")
	a.ok(Poly.is_convex(reversed), "reversed square convex")
	a.ok(not Poly.is_convex(arrow), "arrow is concave")
	a.ok(not Poly.is_convex(flat), "collinear edge is not strict convex")
	a.ok(Poly.point_in_convex({"x": 5.0, "y": 5.0}, square), "center inside")
	a.ok(Poly.point_in_convex({"x": 5.0, "y": 5.0}, reversed), "center inside reversed")
	a.ok(not Poly.point_in_convex({"x": 15.0, "y": 5.0}, square), "outside")
	var inset := Poly.inset_convex(square, 2.0)
	var golden: Dictionary = Util.golden()
	var geom: Dictionary = golden["geometry"]
	a.near(absf(Poly.signed_area(inset)), float(geom["insetArea"]), "inset area", Util.TOL)
	var hit = Poly.segment_vs_convex({"x": -10.0, "y": 5.0}, {"x": 20.0, "y": 5.0}, square)
	a.ok(hit != null, "segment enters")
	a.near(float(hit["t"]) * 30.0 - 10.0, 0.0, "entry x", Util.TOL)
	a.near(float(hit["t"]), float(geom["segmentT"]), "segment t", Util.TOL)
	a.near(float(hit["normal"]["x"]), float(geom["normalX"]), "normal x", Util.TOL)
	a.near(float(hit["normal"]["y"]), float(geom["normalY"]), "normal y", Util.TOL)
	a.ok(Poly.segment_vs_convex({"x": -10.0, "y": 5.0}, {"x": -1.0, "y": 5.0}, square) == null, "segment stops short")
	a.ok(Poly.segment_vs_convex({"x": -10.0, "y": 15.0}, {"x": 20.0, "y": 15.0}, square) == null, "segment misses")
	a.near(Poly.distance_to_convex({"x": 5.0, "y": 5.0}, square), 0.0, "inside distance", Util.TOL)
	a.near(Poly.distance_to_convex({"x": 15.0, "y": 5.0}, square), 5.0, "outside distance", Util.TOL)
	var center := Poly.centroid(square)
	a.near(float(center["x"]), 5.0, "centroid x", Util.TOL)
	a.near(float(center["y"]), 5.0, "centroid y", Util.TOL)
