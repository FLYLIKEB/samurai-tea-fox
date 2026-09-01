extends RefCounted
class_name RunEndProcessor

func apply_run_end(meta_state: Dictionary, run_summary: Dictionary) -> Dictionary:
	var next_meta := meta_state.duplicate(true)
	if not next_meta.has("unlocked_meta_flags"):
		next_meta["unlocked_meta_flags"] = []

	next_meta["run_count"] = int(next_meta.get("run_count", 0)) + 1
	next_meta["best_reached_biome_order"] = max(
		int(next_meta.get("best_reached_biome_order", 0)),
		int(run_summary.get("best_reached_biome_order", 0))
	)

	for flag in run_summary.get("earned_meta_flags", []):
		if not next_meta.get("unlocked_meta_flags", []).has(flag):
			next_meta.unlocked_meta_flags.append(flag)

	return next_meta
