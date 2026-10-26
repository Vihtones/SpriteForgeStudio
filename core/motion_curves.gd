extends RefCounted
## Timing curves for spacing between authored keys. Every curve is exact at both ends
## (0 -> 0, 1 -> 1); only "overshoot" leaves the [0, 1] range between them.
## A curve is stored as a short string so projects stay readable and diffable:
## a preset name, or "cubic_bezier:x1,y1,x2,y2" with x1/x2 in [0, 1] and y1/y2 in [-1, 2].

const DEFAULT := "linear"
const PRESETS := ["linear", "ease_in", "ease_out", "ease_in_out", "hold", "overshoot"]
const LABELS := {
	"linear": "Linear (espaçamento uniforme)",
	"ease_in": "Ease in (sai devagar, acelera)",
	"ease_out": "Ease out (chega devagar)",
	"ease_in_out": "Ease in-out (acomoda nas duas chaves)",
	"hold": "Hold (mantém a pose até a próxima chave)",
	"overshoot": "Overshoot contido (passa e volta)",
}
const BEZIER_PREFIX := "cubic_bezier:"
## Back-out constant reduced from the usual 1.70158 so the peak passes the key by ~3%.
const OVERSHOOT := 0.85

static func is_valid(spec: Variant) -> bool:
	if not spec is String: return false
	if spec in PRESETS: return true
	return not _bezier_points(spec).is_empty()

static func evaluate(spec: String, t: float) -> float:
	if not is_finite(t): return 0.0
	t = clampf(t, 0.0, 1.0)
	if t <= 0.0: return 0.0
	if t >= 1.0: return 1.0
	match spec:
		"linear": return t
		"ease_in": return t * t
		"ease_out": return 1.0 - (1.0 - t) * (1.0 - t)
		"ease_in_out": return 2.0 * t * t if t < 0.5 else 1.0 - 2.0 * (1.0 - t) * (1.0 - t)
		"hold": return 0.0
		"overshoot":
			var u := t - 1.0
			return 1.0 + (OVERSHOOT + 1.0) * u * u * u + OVERSHOOT * u * u
	var points := _bezier_points(spec)
	if points.is_empty(): return t
	return _bezier_y_for_x(points[0], points[1], points[2], points[3], t)

static func bezier(x1: float, y1: float, x2: float, y2: float) -> String:
	return BEZIER_PREFIX + "%s,%s,%s,%s" % [_number(x1), _number(y1), _number(x2), _number(y2)]

static func label(spec: String) -> String:
	if LABELS.has(spec): return str(LABELS[spec])
	return "Bézier cúbica (%s)" % spec.trim_prefix(BEZIER_PREFIX) if is_valid(spec) else spec

## Normalized position of each clip slot between two keys, measured in elapsed time.
## Slot k starts after the durations of slots [left, k) have played, so the left key is 0
## and the right key is 1. With "frames" timing every slot counts as one unit.
static func segment_times(doc: RefCounted, clip: Dictionary, left_position: int, right_position: int, timing: String = "frames") -> Array[float]:
	var times: Array[float] = []
	var frames: Array = clip.get("frames", [])
	var span := right_position - left_position
	if span < 1 or left_position < 0 or right_position >= frames.size(): return times
	var elapsed: Array[float] = [0.0]
	for position in range(left_position, right_position):
		var step := 1.0
		if timing == "duration": step = maxf(0.001, float(doc.frame_seconds(int(frames[position]), clip)))
		elapsed.append(elapsed.back() + step)
	var total: float = elapsed.back()
	for value in elapsed: times.append(value / total)
	return times

static func _bezier_points(spec: String) -> Array[float]:
	var points: Array[float] = []
	if not spec.begins_with(BEZIER_PREFIX) or spec.length() > 64: return points
	var parts := spec.trim_prefix(BEZIER_PREFIX).split(",")
	if parts.size() != 4: return points
	for part in parts:
		if not part.is_valid_float(): return []
		points.append(float(part))
	for value in points:
		if not is_finite(value): return []
	if points[0] < 0.0 or points[0] > 1.0 or points[2] < 0.0 or points[2] > 1.0: return []
	if points[1] < -1.0 or points[1] > 2.0 or points[3] < -1.0 or points[3] > 2.0: return []
	return points

static func _bezier_axis(a: float, b: float, s: float) -> float:
	var inverse := 1.0 - s
	return 3.0 * inverse * inverse * s * a + 3.0 * inverse * s * s * b + s * s * s

static func _bezier_y_for_x(x1: float, y1: float, x2: float, y2: float, x: float) -> float:
	# x(s) is monotonic because x1/x2 stay in [0, 1], so bisection always converges.
	var low := 0.0
	var high := 1.0
	var s := x
	for iteration in 32:
		var current := _bezier_axis(x1, x2, s)
		if absf(current - x) < 0.000001: break
		if current < x: low = s
		else: high = s
		s = (low + high) * 0.5
	return _bezier_axis(y1, y2, s)

static func _number(value: float) -> String:
	return String.num(value, 3)
