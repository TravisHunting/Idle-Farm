extends SceneTree
## Entry point for the headless simulation test (see sim_runner.gd for what it checks):
##   C:/Dev/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/sim_test.gd -- days=8
## In -s mode this script compiles before the autoloads (Game, Art) are registered, so the real
## test lives in sim_runner.gd and is only loaded at runtime, once they exist.


func _initialize() -> void:
	var runner: Script = load("res://tests/sim_runner.gd")
	if runner == null or not runner.can_instantiate():
		printerr("FAIL: tests/sim_runner.gd did not compile")
		quit(1)
		return
	root.add_child.call_deferred(runner.new())
