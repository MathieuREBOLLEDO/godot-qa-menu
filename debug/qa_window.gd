extends "res://addons/debug_menu/ui/debug_window.gd"

## QA > Testeur de niveau (debug menu) : enregistrer une partie du niveau en
## cours, la rejouer, voir son parcours, enregistrer sa vidéo. Ajoutée par
## l'autoload QA si le debug menu est là.

const QA_PATH: NodePath = ^"/root/QA"
const QAScript = preload("res://addons/qa/qa.gd")

var _selected: int = 0


func _ready() -> void:
	super()
	var qa: Node = get_node_or_null(QA_PATH)
	if qa != null:
		qa.state_changed.connect(rebuild)
		qa.runs_changed.connect(rebuild)


func _build() -> void:
	var qa: Node = get_node_or_null(QA_PATH)
	if qa == null:
		add_note("Autoload QA absent : activer l'addon QA.")
		return
	if qa.adapter == null:
		add_note("Pas d'adaptateur : renseigner le paramètre du projet qa/adapter (voir addons/qa/README.md).")
		return
	add_live_label(Callable(qa, "status_text"))
	var level_id: String = qa.adapter.get_level_id()
	add_note("Niveau : %s" % (level_id if level_id != "" else "aucun niveau testable (niveau non enregistré ?)"))

	add_section("Enregistrer")
	if qa.state == QAScript.State.IDLE:
		var record: Button = add_button("Enregistrer une partie", func() -> void: qa.start_recording())
		record.disabled = level_id == ""
		add_hint("Recharge le niveau à son départ et enregistre la partie jusqu'à sa fin (sortie...). Jouer normalement.")
	else:
		add_buttons("", ["Arrêter", "Annuler"], func(index: int) -> void: qa.stop(index == 0))
		add_hint("Arrêter garde la partie (non réussie) ; Annuler la jette.")
	add_check("Afficher le parcours", func() -> bool: return qa.show_trace, func(value: bool) -> void: qa.show_trace = value)

	add_section("Parties enregistrées")
	var runs: Array[String] = qa.list_runs(level_id)
	if runs.is_empty():
		add_note("Aucune partie enregistrée pour ce niveau.")
	else:
		_selected = clampi(_selected, 0, runs.size() - 1)
		var names: Array = []
		for path: String in runs:
			names.append(_run_name(path))
		add_option("Partie", names, _selected, func(index: int) -> void: _selected = index)
		if qa.state == QAScript.State.IDLE:
			add_buttons("", ["Rejouer", "Parcours", "Vidéo"], func(index: int) -> void:
				var path: String = runs[_selected]
				match index:
					0: qa.replay_file(path)
					1: qa.show_run_trace(path)
					2: qa.record_video(path)
			)
		add_hint("Rejouer : recharge le niveau et rejoue les entrées (ne pas toucher au clavier). Parcours : le montre sans rejouer. Vidéo : rejoue la partie dans une deuxième fenêtre du jeu, en Movie Maker.")

	add_section("Dernière lecture")
	add_live_label(func() -> String: return QAScript.report_text(qa.last_report))

	add_section("Vidéos")
	add_live_label(func() -> String:
		var count: int = qa.videos_in_progress()
		return "%d en cours d'enregistrement." % count if count > 0 else "Aucune en cours."
	)
	add_button("Ouvrir le dossier des vidéos", func() -> void:
		DirAccess.make_dir_recursive_absolute(QAScript.VIDEO_DIR)
		OS.shell_open(ProjectSettings.globalize_path(QAScript.VIDEO_DIR))
	)


# « date — réussie (sortie), 12.3 s ».
func _run_name(path: String) -> String:
	var run: QARun = load(path) as QARun
	if run == null:
		return path.get_file()
	return "%s — %s (%s), %.1f s" % [run.created, "réussie" if run.success else "non réussie", run.reason, run.duration()]
