extends TestCase

## Fumée de QA : chaque fichier de l'addon se charge, l'autoload a son
## adaptateur si le projet en déclare un, les fenêtres du debug menu (QA >
## Testeur de niveau, QA > Stats) se construisent, et la question du
## consentement répond puis se ferme.

const ADDON_DIR: String = "res://addons/qa"
const LOADED_EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]
const SKIPPED_DIRS: PackedStringArray = ["tests"]
## Fenêtres du debug menu : chargées seulement s'il est là.
const DEBUG_MENU_SCRIPT: String = "res://addons/debug_menu/ui/debug_window.gd"
const WINDOWS: Array[String] = ["res://addons/qa/debug/qa_window.tscn", "res://addons/qa/stats/debug/stats_window.tscn"]
const QAStatsConsent = preload("res://addons/qa/stats/qa_stats_consent.gd")


func test_addon_files_load() -> void:
	var with_debug_menu: bool = ResourceLoader.exists(DEBUG_MENU_SCRIPT)
	var paths: PackedStringArray = []
	_collect(ADDON_DIR, paths)
	assert_gt(paths.size(), 10, "files found in %s" % ADDON_DIR)
	for path: String in paths:
		if path.contains("/debug/") and not with_debug_menu:
			continue
		assert_not_null(load(path), path)


func test_autoload_has_its_adapter() -> void:
	var qa: Node = get_node_or_null(^"/root/QA")
	if not assert_not_null(qa, "QA autoload"):
		return
	assert_not_null(qa.stats, "stats child")
	if ProjectSettings.get_setting(qa.ADAPTER_SETTING, "") != "":
		assert_not_null(qa.adapter, "adapter of %s loaded" % qa.ADAPTER_SETTING)


func test_debug_windows_build() -> void:
	if not ResourceLoader.exists(DEBUG_MENU_SCRIPT):
		skip("no debug menu")
		return
	for path: String in WINDOWS:
		var window: Window = (load(path) as PackedScene).instantiate() as Window
		if not assert_not_null(window, path):
			continue
		add_test_node(window)
		await frames(3)
		assert_gt(window.get_child_count(), 0, "%s built" % path.get_file())


func test_consent_dialog_answers_and_closes() -> void:
	var dialog: CanvasLayer = add_test_node(QAStatsConsent.new()) as CanvasLayer
	var answers: Array = []
	dialog.answered.connect(func(accepted: bool) -> void: answers.append(accepted))
	await frames(2)
	var buttons: Array[Node] = dialog.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2, "Yes and No")
	(buttons[1] as Button).pressed.emit()
	assert_eq(answers, [true], "Yes answers true")
	await frames(1)
	assert_false(is_instance_valid(dialog), "closed after the answer")


func _collect(dir: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		if dir == ADDON_DIR and sub in SKIPPED_DIRS:
			continue
		_collect(dir.path_join(sub), out)
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() in LOADED_EXTENSIONS:
			out.append(dir.path_join(file))
