extends RefCounted
class_name ConnectivityValidator

func validate(world: Dictionary) -> Dictionary:
	var required_landmarks := []
	for landmark in world.get("landmarks", []):
		if landmark.get("required", false):
			required_landmarks.append(landmark.id)

	return {
		"valid": not required_landmarks.is_empty(),
		"reachable_required_landmarks": required_landmarks,
		"note": "Initial scaffold validates required landmark presence. Tile connectivity checks belong to the TileMap renderer slice."
	}

