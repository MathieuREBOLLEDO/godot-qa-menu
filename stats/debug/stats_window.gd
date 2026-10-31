extends "res://addons/debug_menu/ui/debug_window.gd"

## QA > Stats (debug menu) : la session en cours (temps, niveaux, compteurs),
## les totaux de ce poste, envoi et dossier des sessions. Ajoutée par
## QAStats si le debug menu est là.

const STATS_PATH: NodePath = ^"/root/QA/Stats"
const QAStatsScript = preload("res://addons/qa/stats/qa_stats.gd")


func _build() -> void:
	var stats: QAStats = get_node_or_null(STATS_PATH) as QAStats
	if stats == null:
		add_note(tr("QA autoload missing: enable the QA addon."))
		return
	add_live_label(Callable(stats, "status_text"))

	add_section(tr("This session"))
	add_live_label(Callable(stats, "session_text"))
	add_hint(tr("Time and counters per level, for this launch."))

	add_section(tr("All sessions on this computer"))
	var totals: Dictionary = stats.totals()
	add_note(tr("%d sessions, %s played, %d crashes, %d not sent yet.") % [totals["sessions"], QAStatsScript._format_time(totals["play_time"]), totals["crashes"], totals["unsent"]])
	var url: String = ProjectSettings.get_setting(QAStatsScript.UPLOAD_URL_SETTING, "")
	add_note(tr("Upload URL: %s") % (url if url != "" else tr("none (qa/stats/upload_url)")))
	add_buttons("", [tr("Send now"), tr("Open folder")], func(index: int) -> void:
		match index:
			0: stats.send_pending()
			1:
				DirAccess.make_dir_recursive_absolute(QAStatsScript.DIR)
				OS.shell_open(ProjectSettings.globalize_path(QAStatsScript.DIR))
	)
	add_buttons("", [tr("Ask consent"), tr("Quit as crash")], func(index: int) -> void:
		match index:
			0: stats.show_consent()
			1: stats.quit_as_crash()
	)
	add_hint(tr("Sessions are never sent from the Godot editor. Quit as crash leaves the session open: the next launch marks it as a crash."))
