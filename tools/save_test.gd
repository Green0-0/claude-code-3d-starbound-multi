## Runs the persistence module's own round-trip harness.
##   godot --headless --path . tools/save_test.tscn
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not SaveManager.has_method(&"run_self_test"):
		print("no self-test available")
		get_tree().quit(1)
		return
	var r: Dictionary = SaveManager.run_self_test()
	print("\n=== SAVE SELF-TEST ===")
	var failed := 0
	for case: Dictionary in (r.get("cases", []) as Array):
		var case_ok: bool = bool(case.get("ok", false))
		if not case_ok:
			failed += 1
		print("  %-28s %s %s" % [case.get("name", "?"),
			"OK  " if case_ok else "FAIL", case.get("detail", "")])
	print("=== %d passed, %d failed (%d ms) ===" % [
		int(r.get("passed", 0)), failed, int(r.get("ms", 0))])
	get_tree().quit(0 if failed == 0 else 1)
