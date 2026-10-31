@tool
extends EditorPlugin

## Active l'addon QA : déclare l'autoload QA et les paramètres du projet
## qa/adapter (adaptateur du testeur, voir qa_adapter.gd) et qa/stats/*
## (stats des joueurs, voir stats/qa_stats.gd).

const AUTOLOAD_NAME: String = "QA"
const AUTOLOAD_PATH: String = "res://addons/qa/qa.gd"
const ADAPTER_SETTING: String = "qa/adapter"
## Paramètres : nom, valeur par défaut, type, indication, texte d'indication.
const SETTINGS: Array = [
	[ADAPTER_SETTING, "", TYPE_STRING, PROPERTY_HINT_FILE, "*.gd"],
	["qa/stats/enabled", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	["qa/stats/adapter", "", TYPE_STRING, PROPERTY_HINT_FILE, "*.gd"],
	["qa/stats/upload_url", "", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	["qa/stats/ask_consent", true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
]


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
