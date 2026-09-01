extends RefCounted
class_name TestAssert

var failures: Array[String] = []

func equal(actual, expected, message: String) -> void:
	if actual != expected:
		fail("%s expected=%s actual=%s" % [message, str(expected), str(actual)])

func true_value(actual: bool, message: String) -> void:
	if not actual:
		fail(message)

func false_value(actual: bool, message: String) -> void:
	if actual:
		fail(message)

func fail(message: String) -> void:
	failures.append(message)

func ok() -> bool:
	return failures.is_empty()

