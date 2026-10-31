extends CanvasLayer

## Question du consentement aux stats (QAStats.show_consent()) : fond assombri,
## un panneau, Oui (bouton principal) ou Non. Se ferme après la réponse.
## Thème : les constantes ci-dessous ; la police est celle du thème du jeu.

signal answered(accepted: bool)

const BACKDROP: Color = Color(0.03, 0.03, 0.05, 0.72)
const PANEL: Color = Color(0.11, 0.10, 0.09)
const BORDER: Color = Color(0.93, 0.62, 0.25)
const TEXT: Color = Color(0.94, 0.91, 0.85)
const MUTED: Color = Color(0.70, 0.66, 0.60)
const WIDTH: float = 460.0
const FADE_TIME: float = 0.2


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.border_width_top = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24.0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size.x = WIDTH
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = tr("Help improve the game")
	title.add_theme_color_override("font_color", BORDER)
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var body: Label = Label.new()
	body.text = tr("Can the game send anonymous play stats? Play time, levels reached, where you get stuck and crashes. Nothing personal, and you can change your mind in the settings.")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", TEXT)
	box.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	var no: Button = Button.new()
	no.text = tr("No thanks")
	no.flat = true
	no.add_theme_color_override("font_color", MUTED)
	no.pressed.connect(_answer.bind(false))
	buttons.add_child(no)
	var yes: Button = Button.new()
	yes.text = tr("Yes, share")
	yes.pressed.connect(_answer.bind(true))
	buttons.add_child(yes)
	yes.grab_focus.call_deferred()

	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, FADE_TIME)


func _answer(accepted: bool) -> void:
	answered.emit(accepted)
	queue_free()
