extends RefCounted

var passed: int = 0
var failed: int = 0


func eq(actual, expected, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		print("FAIL %s actual=%s expected=%s" % [label, str(actual), str(expected)])


func near(actual: float, expected: float, label: String, eps: float = 1e-9) -> void:
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > eps:
		failed += 1
		print("FAIL %s actual=%s expected=%s" % [label, str(actual), str(expected)])
	else:
		passed += 1


func near_v(actual: Vector2, expected: Vector2, label: String, eps: float = 1e-9) -> void:
	near(actual.x, expected.x, label + ".x", eps)
	near(actual.y, expected.y, label + ".y", eps)


func ok(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL %s" % label)
