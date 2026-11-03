@tool
extends EditorPlugin

## Active l'addon QA : déclare l'autoload QA et les paramètres du projet
## qa/adapter (adaptateur du testeur, voir qa_adapter.gd) et qa/stats/*
## (stats des joueurs, voir stats/qa_stats.gd).
## Dans un jeu sans test runner (addons/test_runner), les tests de l'addon
## sont cachés à Godot (tests/.gdignore, ignoré par git) : sans lui, leur
## classe TestCase manque et l'éditeur affiche une erreur par fichier.

const AUTOLOAD_NAME: String = "QA"
const AUTOLOAD_PATH: String = "res://addons/qa/qa.gd"
const TESTS_IGNORE: String = "res://addons/qa/tests/.gdignore"
const TEST_RUNNER: String = "res://addons/test_runner/test_case.gd"
const ADAPTER_SETTING: String = "qa/adapter"
## Paramètres : nom, valeur par défaut, type, indication, texte d'indication.
const SETTINGS: Array = [
	[ADAPTER_SETTING, "", TYPE_STRING, PROPERTY_HINT_FILE, "*.gd"],
	["qa/stats/enabled", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["qa/stats/adapter", "", TYPE_STRING, PROPERTY_HINT_FILE, "*.gd"],
	["qa/stats/upload_url", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["qa/stats/ask_consent", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
]


func _enter_tree() -> void:
	if FileAccess.file_exists(TEST_RUNNER) or FileAccess.file_exists(TESTS_IGNORE):
		return
	var file: FileAccess = FileAccess.open(TESTS_IGNORE, FileAccess.WRITE)
	if file != null:
		file.close()
		get_editor_interface().get_resource_filesystem().scan()


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	for setting: Array in SETTINGS:
		if not ProjectSettings.has_setting(setting[0]):
			ProjectSettings.set_setting(setting[0], setting[1])
		ProjectSettings.set_initial_value(setting[0], setting[1])
		ProjectSettings.add_property_info({
			"name": setting[0],
			"type": setting[2],
			"hint": setting[3],
			"hint_string": setting[4],
		})
	ProjectSettings.save()


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
