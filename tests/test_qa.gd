extends TestCase

## QA : partie (QARun), enregistrement puis rejeu identique avec un faux
## adaptateur (un point qui avance quand une action est appuyée), rejeu qui
## diverge, marques, mise en forme des stats.
## L'adaptateur du jeu est remis à la fin ; les parties vont dans user://.

const ACTION: StringName = &"qa_test_right"
const RUNS_DIR: String = "user://test_runner/qa/runs/"

var _qa: Node
var _game_adapter: QAAdapter
var _adapter: _FakeAdapter


func before_all() -> void:
	_qa = get_node_or_null(^"/root/QA")
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)


func after_all() -> void:
	InputMap.erase_action(ACTION)
	var dir: String = RUNS_DIR + "fake_level/"
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + file)


func before_each() -> void:
	if _qa == null:
		skip("no QA autoload")
		return
	_game_adapter = _qa.adapter
	_adapter = _FakeAdapter.new()
	_adapter.holder = add_test_node(Node2D.new())
	_adapter.finished.connect(_qa._on_finished)
	_adapter.marked.connect(_qa._on_marked)
	_qa.adapter = _adapter


func after_each() -> void:
	if _qa == null:
		return
	_qa.stop(false)
	_qa.adapter = _game_adapter
	Input.action_release(ACTION)


# --- Partie ---

func test_run_events_and_marks() -> void:
	var run: QARun = QARun.new()
	run.physics_ticks = 60
	run.frame_count = 120
	run.add_event(3, 0, 1.0)
	run.add_mark(10, "chili")
	run.add_mark(50, "chili")
	assert_eq(run.event_frames, PackedInt32Array([3]))
	assert_almost(run.duration(), 2.0, 0.0001)
	assert_eq(run.count_marks("chili"), 2)
	assert_eq(run.count_marks("death"), 0)


func test_default_actions_skip_ui_and_debug_menu() -> void:
	var actions: PackedStringArray = QAAdapter.new().get_actions()
	for action: String in actions:
		assert_false(action.begins_with("ui_") or action.begins_with("debug_menu_"), "%s excluded" % action)
	assert_has(actions, String(ACTION))


# --- Enregistrement et rejeu ---

# Enregistre : l'action tenue hold_frames images, puis fin quand le point
# arrive au but. Rend le chemin de la partie.
func _record(hold_frames: int) -> String:
	var input: TestInput = add_test_node(TestInput.new()) as TestInput
	# Avant QA (priorité -1000) : l'appui de l'image est vu par QA dans la même image.
	input.process_physics_priority = -2000
	assert_true(_qa.start_recording(), "recording started")
	assert_true(await until(func() -> bool: return _qa.state == _qa.State.RECORDING, 1.0), "level attached")
	input.tap(ACTION, hold_frames)
	await physics_frames(5)
	_adapter.marked.emit("halfway")
	assert_true(await until(func() -> bool: return _qa.state == _qa.State.IDLE, 5.0), "recording finished by the adapter")
	# Plus d'appui du test pendant le rejeu : seul QA appuie.
	input.release_all()
	input.queue_free()
	await physics_frames(1)
	return _qa.run_path


func _replay(path: String) -> Dictionary:
	var reports: Array[Dictionary] = []
	var record: Callable = func(report: Dictionary) -> void: reports.append(report)
	_qa.replay_finished.connect(record)
	assert_true(_qa.replay_file(path), "replay started")
	await until(func() -> bool: return not reports.is_empty(), 10.0)
	_qa.replay_finished.disconnect(record)
	return reports[0] if not reports.is_empty() else {}


func test_record_then_replay_identically() -> void:
	var path: String = await _record(40)
	if not assert_true(path.begins_with(RUNS_DIR), "saved in the adapter folder: %s" % path):
		return
	var run: QARun = load(path) as QARun
	assert_true(run.success, "recorded as a success")
	assert_eq(run.count_marks("halfway"), 1, "mark recorded")
	assert_eq(run.trace.size(), run.frame_count, "one trace point per frame")
	assert_has(_qa.list_runs("fake_level"), path)
	var report: Dictionary = await _replay(path)
	assert_true(report.get("ok", false), "replay identical: %s" % _qa.report_text(report))


func test_replay_detects_a_different_path() -> void:
	var path: String = await _record(40)
	# Le jeu change : le point va deux fois plus vite.
	_adapter.speed = 2.0
	var report: Dictionary = await _replay(path)
	assert_false(report.get("ok", true), "replay differs")
	assert_gt(report.get("divergence_frame", -1), -1, "divergence found")


func test_cannot_start_twice() -> void:
	assert_true(_qa.start_recording())
	assert_false(_qa.start_recording(), "already recording")


func test_stopped_recording_is_kept_as_not_successful() -> void:
	assert_true(_qa.start_recording())
	assert_true(await until(func() -> bool: return _qa.state == _qa.State.RECORDING, 1.0), "level attached")
	await physics_frames(5)
	_qa.stop(true)
	assert_eq(_qa.state, _qa.State.IDLE)
	var run: QARun = load(_qa.run_path) as QARun
	if assert_not_null(run, "kept: %s" % _qa.run_path):
		assert_false(run.success, "not a success")
		assert_eq(run.frame_count, run.trace.size(), "trace up to the stop")


func test_cancelled_recording_is_not_saved() -> void:
	var before: int = _qa.list_runs("fake_level").size()
	assert_true(_qa.start_recording())
	await until(func() -> bool: return _qa.state == _qa.State.RECORDING, 1.0)
	_qa.stop(false)
	assert_eq(_qa.list_runs("fake_level").size(), before, "nothing saved")


func test_missing_run_is_refused() -> void:
	expect_error("Cannot open file")
	expect_error("Failed loading resource")
	expect_error("QA : partie introuvable")
	assert_false(_qa.replay_file(RUNS_DIR + "fake_level/missing.tres"))
	assert_eq(_qa.state, _qa.State.IDLE)


func test_report_text() -> void:
	assert_eq(_qa.report_text({}), "Aucune lecture.")
	var report: Dictionary = {"ok": false, "success": false, "reason": "pas de fin", "frames": 90, "expected_frames": 60,
			"expected_success": true, "divergence_frame": 12, "divergence_distance": 3.0}
	var text: String = _qa.report_text(report)
	assert_true(text.begins_with("ÉCHEC"), text)
	assert_true(text.contains("frame 12"), "divergence frame shown")


# --- Stats ---

func test_stats_text_helpers() -> void:
	assert_eq(QAStats._format_time(75.0), "1:15")
	assert_eq(QAStats._format_time(3725.0), "1h02")
	assert_eq(QAStats._counts_text({"jump": 3, "stomp": 1}), "jump 3, stomp 1")


# Faux jeu : un point qui avance vers la droite quand ACTION est appuyée ;
# fin (réussie) quand il passe GOAL.
class _FakeAdapter:
	extends QAAdapter
	const GOAL: float = 30.0
	var holder: Node2D
	var speed: float = 1.0
	var mover: _Mover

	func get_level_id() -> String:
		return "fake_level"

	func load_level(_level_id: String) -> void:
		if mover != null:
			mover.free()
		mover = _Mover.new()
		mover.adapter = self
		holder.add_child(mover)

	func attach() -> bool:
		return mover != null and mover.is_inside_tree()

	func get_tracked_position() -> Vector2:
		return mover.position

	func get_trace_parent() -> Node:
		return holder

	func get_actions() -> PackedStringArray:
		return PackedStringArray([String(ACTION)])

	func get_runs_dir() -> String:
		return RUNS_DIR


class _Mover:
	extends Node2D
	var adapter: _FakeAdapter
	var done: bool = false

	func _physics_process(_delta: float) -> void:
		if Input.is_action_pressed(ACTION):
			position.x += adapter.speed
		if not done and position.x >= _FakeAdapter.GOAL:
			done = true
			adapter.finished.emit(true, "goal")
