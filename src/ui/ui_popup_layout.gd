class_name UiPopupLayout
extends RefCounted

const WIDE_WIDTH_RATIO := 0.82

static func fitted_size(preferred: Vector2, available: Vector2) -> Vector2:
	var width := available.x
	if available.x > preferred.x:
		width = minf(preferred.x, floorf(available.x * WIDE_WIDTH_RATIO))
	return Vector2(maxf(1.0, width), maxf(1.0, minf(preferred.y, available.y)))
