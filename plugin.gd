@tool
extends EditorPlugin

## Active l'addon QA : déclare l'autoload QA et le paramètre du projet
## qa/adapter (script de l'adaptateur du jeu, voir qa_adapter.gd).

const AUTOLOAD_NAME: String = "QA"
const AUTOLOAD_PATH: String = "res://addons/qa/qa.gd"
const ADAPTER_SETTING: String = "qa/adapter"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	if not ProjectSettings.has_setting(ADAPTER_SETTING):
		ProjectSettings.set_setting(ADAPTER_SETTING, "")
	ProjectSettings.set_initial_value(ADAPTER_SETTING, "")
	ProjectSettings.add_property_info({
		"name": ADAPTER_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.gd",
	})
	ProjectSettings.save()


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
