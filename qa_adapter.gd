class_name QAAdapter
extends RefCounted

## Ce que le testeur QA doit savoir du jeu : un script par projet qui étend
## cette classe, déclaré dans le paramètre du projet qa/adapter.
## Le jeu émet finished quand la partie se termine (sortie atteinte, échec
## définitif) et marked pour un événement à placer sur le parcours (saut,
## mort...). Seules les méthodes marquées « à redéfinir » sont obligatoires.

## La partie est finie : réussie ou non, avec la raison (« sortie »...).
signal finished(success: bool, reason: String)
## Événement à placer sur le parcours, à la frame en cours.
signal marked(label: String)


## À redéfinir : identifiant du niveau en cours, que load_level() sait
## recharger (en général son chemin), ou "" si aucun niveau testable.
func get_level_id() -> String:
	return ""


## À redéfinir : charge le niveau [param level_id] dans son état de départ
## (changement de scène, valeurs de la partie remises à zéro). Le testeur
## appelle ensuite attach() à chaque frame physique jusqu'à ce qu'il
## réponde vrai.
func load_level(_level_id: String) -> void:
	pass


## À redéfinir : vrai quand le niveau chargé est prêt ; branche ici les
## signaux du jeu sur finished et marked. Appelé une fois par niveau chargé
## une fois qu'il a répondu vrai.
func attach() -> bool:
	return false


## À redéfinir : position suivie (coordonnées globales 2D), lue à chaque
## frame physique.
func get_tracked_position() -> Vector2:
	return Vector2.ZERO


## À redéfinir : nœud 2D du niveau sous lequel dessiner le parcours (il
## disparaît avec le niveau).
func get_trace_parent() -> Node:
	return null


## Actions de l'InputMap enregistrées. Par défaut toutes, sauf celles de
## l'interface (ui_*) et du debug menu (debug_menu_*).
func get_actions() -> PackedStringArray:
	var actions: PackedStringArray = PackedStringArray()
	for action: StringName in InputMap.get_actions():
		var action_name: String = action
		if action_name.begins_with("ui_") or action_name.begins_with("debug_menu_"):
			continue
		actions.append(action_name)
	return actions


## Dossier des parties enregistrées (un sous-dossier par niveau).
func get_runs_dir() -> String:
	return "user://qa/runs/"
