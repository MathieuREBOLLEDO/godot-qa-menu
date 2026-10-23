extends Node2D

## Dessin du parcours, posé par le testeur QA sous le niveau (coordonnées
## globales) : parcours de référence (partie enregistrée) en blanc, parcours
## en cours en couleur, événements en points, départ en vert, arrivée en
## jaune, première divergence en rouge.

const REFERENCE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)
const PATH_COLOR: Color = Color(0.2, 0.8, 1.0, 0.9)
const START_COLOR: Color = Color(0.3, 1.0, 0.4)
const END_COLOR: Color = Color(1.0, 0.85, 0.2)
const DIVERGENCE_COLOR: Color = Color(1.0, 0.25, 0.25)
const MARK_COLOR: Color = Color(1.0, 0.5, 0.9)
const WIDTH: float = 2.0
const DOT_RADIUS: float = 4.0

## Parcours de la partie enregistrée (vide pendant un enregistrement).
var reference: PackedVector2Array = PackedVector2Array()
## Parcours en cours (enregistrement ou lecture).
var path: PackedVector2Array = PackedVector2Array()
## Événements : frame et nom (dessinés sur le parcours en cours, ou sur la
## référence s'il est vide).
var mark_frames: PackedInt32Array = PackedInt32Array()
var mark_labels: PackedStringArray = PackedStringArray()
## Frame de la première divergence, -1 sinon.
var divergence_frame: int = -1


func _ready() -> void:
	top_level = true
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX


## Efface le parcours en cours et ses événements, et prend [param new_reference]
## comme référence.
func reset(new_reference: PackedVector2Array) -> void:
	reference = new_reference
	path = PackedVector2Array()
	mark_frames = PackedInt32Array()
	mark_labels = PackedStringArray()
	divergence_frame = -1
	queue_redraw()


func add_point(point: Vector2) -> void:
	path.append(point)
	queue_redraw()


func add_mark(frame: int, label: String) -> void:
	mark_frames.append(frame)
	mark_labels.append(label)
	queue_redraw()


func _draw() -> void:
	_draw_path(reference, REFERENCE_COLOR)
	_draw_path(path, PATH_COLOR)
	var marked: PackedVector2Array = path if not path.is_empty() else reference
	var font: Font = ThemeDB.fallback_font
	for index: int in mark_frames.size():
		var frame: int = mark_frames[index]
		if frame >= marked.size():
			continue
		draw_circle(marked[frame], DOT_RADIUS, MARK_COLOR)
		draw_string(font, marked[frame] + Vector2(6.0, -6.0), mark_labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, MARK_COLOR)
	if divergence_frame >= 0 and divergence_frame < path.size():
		var at: Vector2 = path[divergence_frame]
		var arm: Vector2 = Vector2(DOT_RADIUS * 2.0, DOT_RADIUS * 2.0)
		draw_line(at - arm, at + arm, DIVERGENCE_COLOR, WIDTH)
		draw_line(at + Vector2(-arm.x, arm.y), at + Vector2(arm.x, -arm.y), DIVERGENCE_COLOR, WIDTH)


func _draw_path(points: PackedVector2Array, color: Color) -> void:
	if points.size() >= 2:
		draw_polyline(points, color, WIDTH)
	if points.is_empty():
		return
	draw_circle(points[0], DOT_RADIUS, START_COLOR)
	draw_circle(points[points.size() - 1], DOT_RADIUS, END_COLOR)
