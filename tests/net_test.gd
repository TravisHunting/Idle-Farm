extends SceneTree
## Entry point for the two-copy multiplayer test (see net_runner.gd). Start a host and a guest:
##   Godot --headless --path . -s tests/net_test.gd -- role=host port=24690
##   Godot --headless --path . -s tests/net_test.gd -- role=guest port=24690 profile=2
## (tests/run_net_test.sh starts both and waits for them.) Like sim_test, the real test is only
## loaded at runtime, once the autoloads exist.


func _initialize() -> void:
	var runner: Script = load("res://tests/net_runner.gd")
	if runner == null or not runner.can_instantiate():
		printerr("FAIL: tests/net_runner.gd did not compile")
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
