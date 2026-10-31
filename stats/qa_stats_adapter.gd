class_name QAStatsAdapter
extends RefCounted

## Ce que les stats des joueurs (QAStats, addons/qa/stats) doivent savoir du
## jeu : un script par projet qui étend cette classe, déclaré dans le
## paramètre du projet qa/stats/adapter. Sans adaptateur, celui-ci est
## utilisé : il branche les managers standards d'un projet créé par
## project_init (GameManager, UIManager), s'ils sont là.
## Le jeu envoie ses événements avec stats.track() (événement daté, par
## exemple une mort) et stats.count() (simple compteur, par exemple un saut).

const GAME_MANAGER_PATH: NodePath = ^"/root/GameManager"
const UI_MANAGER_PATH: NodePath = ^"/root/UIManager"

## Stats en cours, posé avant attach().
var stats: QAStats = null


## Appelé une fois au lancement. Par défaut : début de partie, pause et menus
## des managers standards. Une redéfinition appelle super() pour les garder.
func attach() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var game_manager: Node = tree.root.get_node_or_null(GAME_MANAGER_PATH)
	if game_manager != null:
		if game_manager.has_signal(&"game_started"):
			game_manager.connect(&"game_started", func() -> void: stats.track("game_started"))
		if game_manager.has_signal(&"paused_changed"):
			game_manager.connect(&"paused_changed", func(paused: bool) -> void:
				if paused:
					stats.count("pause")
			)
	var ui_manager: Node = tree.root.get_node_or_null(UI_MANAGER_PATH)
	if ui_manager != null and ui_manager.has_signal(&"menu_changed"):
		ui_manager.connect(&"menu_changed", func(menu_name: StringName) -> void:
			if menu_name != &"":
				stats.track("menu", {"name": String(menu_name)})
		)


## Niveau en cours (en général son chemin), "" hors d'un niveau (menus). Lu
## plusieurs fois par seconde : le temps et les événements sont rangés par
## niveau. Par défaut : la scène en cours.
func get_level_id() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var scene: Node = tree.current_scene
	return scene.scene_file_path if scene != null else ""


## Le niveau en cours vient de changer ("" : hors d'un niveau). Le jeu y
## branche les signaux du niveau sur stats.track() et stats.count().
func level_changed(_level_id: String) -> void:
	pass


## Version du jeu envoyée avec chaque session.
func get_game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))
