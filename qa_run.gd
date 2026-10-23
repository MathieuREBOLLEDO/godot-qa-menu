class_name QARun
extends Resource

## Partie enregistrée par le testeur QA : les changements d'entrées, frame
## physique par frame physique, et le parcours obtenu. La rejouer depuis le
## départ du même niveau doit donner le même parcours.

## Niveau joué (QAAdapter.get_level_id()).
@export var level_id: String = ""
## Date d'enregistrement (AAAA-MM-JJ HH:MM:SS).
@export var created: String = ""
## Engine.physics_ticks_per_second à l'enregistrement.
@export var physics_ticks: int = 60
## Actions enregistrées ; les événements y renvoient par leur indice.
@export var actions: PackedStringArray = PackedStringArray()
## Événements : à la frame event_frames[i], l'action actions[event_actions[i]]
## passe à la force event_strengths[i] (0 : relâchée).
@export var event_frames: PackedInt32Array = PackedInt32Array()
@export var event_actions: PackedInt32Array = PackedInt32Array()
@export var event_strengths: PackedFloat32Array = PackedFloat32Array()
## Nombre de frames physiques jouées.
@export var frame_count: int = 0
## Position suivie au début de chaque frame (pixels, coordonnées globales).
@export var trace: PackedVector2Array = PackedVector2Array()
## Événements du jeu (QAAdapter.marked) : frame et nom.
@export var mark_frames: PackedInt32Array = PackedInt32Array()
@export var mark_labels: PackedStringArray = PackedStringArray()
## Fin de la partie : réussie (QAAdapter.finished) et raison.
@export var success: bool = false
@export var reason: String = ""


func add_event(frame: int, action_index: int, strength: float) -> void:
	event_frames.append(frame)
	event_actions.append(action_index)
	event_strengths.append(strength)


func add_mark(frame: int, label: String) -> void:
	mark_frames.append(frame)
	mark_labels.append(label)


## Durée jouée (s).
func duration() -> float:
	return float(frame_count) / float(maxi(physics_ticks, 1))


## Nombre d'événements du jeu nommés [param label].
func count_marks(label: String) -> int:
	return mark_labels.count(label)
