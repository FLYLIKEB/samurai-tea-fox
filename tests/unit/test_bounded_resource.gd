extends RefCounted

const BoundedResource = preload("res://src/player/state/bounded_resource.gd")

func run(asserts) -> void:
	var resource := BoundedResource.new(10)
	var changes: Array = []
	var depleted_count := [0]
	resource.changed.connect(func(previous, current, maximum): changes.append([previous, current, maximum]))
	resource.depleted.connect(func(): depleted_count[0] += 1)

	asserts.equal(resource.decrease(14), 10, "decrease reports the applied amount")
	asserts.equal(resource.current, 0, "decrease clamps at zero")
	asserts.equal(depleted_count[0], 1, "depleted emits when crossing zero")
	asserts.equal(resource.decrease(1), 0, "decrease at zero is a no-op")
	asserts.equal(depleted_count[0], 1, "depleted does not repeat while already empty")

	asserts.equal(resource.increase(99), 10, "increase reports the clamped applied amount")
	asserts.equal(resource.current, 10, "increase clamps at maximum")
	asserts.equal(resource.increase(-1), 0, "negative increase is rejected")
	asserts.equal(resource.decrease(-1), 0, "negative decrease is rejected")
	asserts.equal(changes, [[10, 0, 10], [0, 10, 10]], "changes emit only for real transitions")

	asserts.true_value(resource.spend(4), "spend succeeds when enough value remains")
	asserts.equal(resource.current, 6, "spend subtracts the requested amount")
	asserts.false_value(resource.spend(7), "spend fails atomically when value is insufficient")
	asserts.equal(resource.current, 6, "failed spend preserves current value")
	asserts.false_value(resource.spend(-1), "negative spend is rejected")
	asserts.equal(resource.increase(9223372036854775807), 4, "huge recovery clamps without integer overflow")
	asserts.equal(resource.current, 10, "overflow-sized recovery cannot deplete the resource")
