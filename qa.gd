extends Node

## Testeur de niveaux (autoload QA, addons/qa) : enregistre une partie
## depuis le départ du niveau (entrées frame physique par frame physique et
## parcours), la rejoue en vérifiant qu'elle donne le même parcours, dessine
## le parcours et enregistre la vidéo d'une partie (Movie Maker, dans une
## deuxième instance du jeu).
## Le jeu fournit un QAAdapter : script dans le paramètre du projet
## qa/adapter. Voir addons/qa/README.md.
## Ligne de commande (après « -- ») :
##   --qa-replay=<partie.tres>  rejoue la partie au lancement ;
##   --qa-exit                  quitte ensuite (code 0 si la partie réussit
##                              comme à l'enregistrement, 1 sinon).

## L'état a changé (attente, enregistrement, lecture, repos).
signal state_changed
## Une partie a été enregistrée.
signal runs_changed
## Fin d'une lecture : voir report_text() pour le contenu.
signal replay_finished(report: Dictionary)

enum State { IDLE, WAITING, RECORDING, REPLAYING }

const ADAPTER_SETTING: String = "qa/adapter"
const DEBUG_MENU_PATH: String = "/root/DebugMenu"
const WINDOW_PATH: String = "res://addons/qa/debug/qa_window.tscn"
const QATrace = preload("res://addons/qa/qa_trace.gd")
const VIDEO_DIR: String = "user://qa/videos/"
## Écart de position (pixels) au-delà duquel la lecture a divergé.
const DIVERGENCE_TOLERANCE: float = 0.5
## Temps laissé après la fin de la partie enregistrée pour finir (s).
const END_GRACE_TIME: float = 2.0
## Écart de force d'une action en dessous duquel on n'enregistre pas.
const STRENGTH_STEP: float = 0.01
## Temps avant de quitter avec --qa-exit (s), pour voir la fin en vidéo.
const EXIT_DELAY: float = 1.0
## Frames laissées au démarrage du jeu avant --qa-replay.
const STARTUP_FRAMES: int = 10

var adapter: QAAdapter = null
## Stats des joueurs (addons/qa/stats), enfant « Stats ».
var stats: QAStats = null
var state: State = State.IDLE
## Frame physique de la partie en cours.
var frame: int = 0
## Partie enregistrée ou rejouée, ou null.
var run: QARun = null
## Chemin de la partie rejouée.
var run_path: String = ""
## Dernier rapport de lecture (vide avant la première).
var last_report: Dictionary = {}
## Afficher le parcours dans le niveau.
var show_trace: bool = true:
	set(value):
		show_trace = value
		if is_instance_valid(_trace):
			_trace.visible = value

var _next_state: State = State.IDLE
var _strengths: PackedFloat32Array = PackedFloat32Array() # force de chaque action, à la frame en cours
var _event_index: int = 0
var _divergence_frame: int = -1
var _trace: QATrace = null
var _exit_when_done: bool = false
var _video_pids: Array[int] = []


func _ready() -> void:
	# Avant tous les autres nœuds : les entrées rejouées sont posées avant que
	# le jeu les lise dans la même frame physique.
	process_physics_priority = -1000
	_load_adapter()
	var debug_menu: Node = get_node_or_null(DEBUG_MENU_PATH)
	if debug_menu != null:
		debug_menu.add_entry("QA", "Testeur de niveau", load(WINDOW_PATH))
	stats = QAStats.new()
	stats.name = "Stats"
	add_child(stats)

	var replay_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-replay="):
			replay_path = arg.trim_prefix("--qa-replay=")
		elif arg == "--qa-exit":
			_exit_when_done = true
	if replay_path != "":
		# Laisse le jeu démarrer : sa scène principale peut changer de scène
		# tout de suite (redirection de menu), ce qui annulerait le chargement
		# du niveau.
		for i: int in STARTUP_FRAMES:
			await get_tree().process_frame
		replay_file(replay_path)


func _physics_process(_delta: float) -> void:
	match state:
		State.WAITING:
			if not adapter.attach():
				return
			_start()
			_step()
		State.RECORDING, State.REPLAYING:
			_step()


# --- Enregistrement ---

## Recharge le niveau en cours et enregistre la partie jusqu'à sa fin
## (QAAdapter.finished) ou jusqu'à stop().
func start_recording() -> bool:
	if not _check_ready():
		return false
	var level_id: String = adapter.get_level_id()
	if level_id == "":
		push_warning("QA : aucun niveau testable en cours (niveau non enregistré ?).")
		return false
	run = QARun.new()
	run.level_id = level_id
	run.created = Time.get_datetime_string_from_system(false, true)
	run.physics_ticks = Engine.physics_ticks_per_second
	run.actions = adapter.get_actions()
	run_path = ""
	_wait_for_level(State.RECORDING)
	return true


## Arrête l'enregistrement ou la lecture. Un enregistrement arrêté est
## gardé (partie non réussie) si [param keep] est vrai.
func stop(keep: bool = true) -> void:
	match state:
		State.RECORDING:
			if keep:
				_finish_recording(false, "arrêt manuel")
			else:
				_set_state(State.IDLE)
		State.REPLAYING:
			_finish_replay(false, "arrêt manuel")
		State.WAITING:
			_set_state(State.IDLE)


# --- Lecture ---

## Rejoue la partie enregistrée dans [param path] depuis le départ de son
## niveau.
func replay_file(path: String) -> bool:
	var loaded: QARun = load(path) as QARun
	if loaded == null:
		push_error("QA : partie introuvable : %s" % path)
		_exit_if_asked(false)
		return false
	return replay(loaded, path)


func replay(replayed: QARun, path: String = "") -> bool:
	if not _check_ready():
		_exit_if_asked(false)
		return false
	if replayed.physics_ticks != Engine.physics_ticks_per_second:
		push_warning("QA : partie enregistrée à %d frames physiques par seconde, le jeu est à %d : le parcours va diverger." % [replayed.physics_ticks, Engine.physics_ticks_per_second])
	run = replayed
	run_path = path
	_wait_for_level(State.REPLAYING)
	return true


## Montre le parcours de la partie [param path] dans le niveau en cours, sans
## la rejouer.
func show_run_trace(path: String) -> void:
	var shown: QARun = load(path) as QARun
	if shown == null or adapter == null or not adapter.attach():
		return
	_make_trace()
	if _trace == null:
		return
	_trace.reset(shown.trace)
	for index: int in shown.mark_frames.size():
		_trace.add_mark(shown.mark_frames[index], shown.mark_labels[index])


# --- Vidéo ---

## Lance une deuxième instance du jeu qui rejoue la partie [param path] en
## Movie Maker et écrit la vidéo dans VIDEO_DIR. Renvoie le chemin de la
## vidéo, ou "" en cas d'échec.
func record_video(path: String) -> String:
	DirAccess.make_dir_recursive_absolute(VIDEO_DIR)
	var video: String = ProjectSettings.globalize_path(VIDEO_DIR + "%s_%s.avi" % [path.get_base_dir().get_file(), path.get_file().get_basename()])
	var args: PackedStringArray = PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--write-movie", video, "--", "--qa-replay=" + path, "--qa-exit"])
	var pid: int = OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_error("QA : impossible de lancer l'enregistrement vidéo.")
		return ""
	_video_pids.append(pid)
	print("QA : vidéo en cours d'enregistrement : %s" % video)
	return video


## Nombre de vidéos en cours d'enregistrement.
func videos_in_progress() -> int:
	_video_pids.assign(_video_pids.filter(func(pid: int) -> bool: return OS.is_process_running(pid)))
	return _video_pids.size()


# --- Parties enregistrées ---

## Chemins des parties enregistrées du niveau [param level_id], de la plus
## récente à la plus ancienne.
func list_runs(level_id: String) -> Array[String]:
	var paths: Array[String] = []
	if adapter == null or level_id == "":
		return paths
	var dir: String = _runs_dir(level_id)
	if not DirAccess.dir_exists_absolute(dir):
		return paths
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			paths.append(dir + file)
	paths.sort()
	paths.reverse()
	return paths


## État en une ligne, pour une fenêtre de debug.
func status_text() -> String:
	match state:
		State.WAITING:
			return "Chargement du niveau..."
		State.RECORDING:
			return "Enregistrement : %.1f s" % (float(frame) / Engine.physics_ticks_per_second)
		State.REPLAYING:
			return "Lecture : %.1f / %.1f s" % [float(frame) / Engine.physics_ticks_per_second, run.duration()]
	return "Au repos."


## Rapport de lecture lisible.
static func report_text(report: Dictionary) -> String:
	if report.is_empty():
		return "Aucune lecture."
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s : %s (%s)" % ["OK" if report["ok"] else "ÉCHEC", "réussie" if report["success"] else "non réussie", report["reason"]])
	lines.append("Durée : %d frames (enregistrée : %d frames, %s)." % [report["frames"], report["expected_frames"], "réussie" if report["expected_success"] else "non réussie"])
	if report["divergence_frame"] >= 0:
		lines.append("Parcours différent de l'enregistrement dès la frame %d (écart %.1f px)." % [report["divergence_frame"], report["divergence_distance"]])
	else:
		lines.append("Parcours identique à l'enregistrement.")
	return "\n".join(lines)


# --- Déroulement ---

func _load_adapter() -> void:
	var path: String = ProjectSettings.get_setting(ADAPTER_SETTING, "")
	if path == "":
		return
	var script: Script = load(path) as Script
	if script == null:
		push_error("QA : adaptateur introuvable : %s (paramètre %s)." % [path, ADAPTER_SETTING])
		return
	adapter = script.new() as QAAdapter
	if adapter == null:
		push_error("QA : %s n'étend pas QAAdapter." % path)
		return
	adapter.finished.connect(_on_finished)
	adapter.marked.connect(_on_marked)


func _check_ready() -> bool:
	if adapter == null:
		push_warning("QA : pas d'adaptateur (paramètre du projet %s)." % ADAPTER_SETTING)
		return false
	if state != State.IDLE:
		push_warning("QA : un enregistrement ou une lecture est déjà en cours.")
		return false
	return true


func _wait_for_level(next_state: State) -> void:
	_next_state = next_state
	_set_state(State.WAITING)
	adapter.load_level(run.level_id)


# Le niveau est prêt : frame 0 dans cette même frame physique.
func _start() -> void:
	frame = 0
	_event_index = 0
	_divergence_frame = -1
	_strengths.resize(run.actions.size())
	_strengths.fill(0.0)
	_make_trace()
	if _trace != null:
		_trace.reset(run.trace if _next_state == State.REPLAYING else PackedVector2Array())
	_set_state(_next_state)


func _step() -> void:
	if state == State.RECORDING:
		_record_inputs()
	else:
		_replay_inputs()
	var position: Vector2 = adapter.get_tracked_position()
	if state == State.RECORDING:
		run.trace.append(position)
	elif frame < run.trace.size() and _divergence_frame < 0 and position.distance_to(run.trace[frame]) > DIVERGENCE_TOLERANCE:
		_divergence_frame = frame
	if _has_trace():
		_trace.divergence_frame = _divergence_frame
		_trace.add_point(position)
	frame += 1
	if state == State.REPLAYING and frame > run.frame_count + roundi(END_GRACE_TIME * Engine.physics_ticks_per_second):
		_finish_replay(false, "pas de fin")


func _record_inputs() -> void:
	for index: int in run.actions.size():
		var action: StringName = run.actions[index]
		var strength: float = Input.get_action_raw_strength(action) if Input.is_action_pressed(action) else 0.0
		var previous: float = _strengths[index]
		if (strength == 0.0) != (previous == 0.0) or absf(strength - previous) >= STRENGTH_STEP:
			run.add_event(frame, index, strength)
			_strengths[index] = strength


func _replay_inputs() -> void:
	while _event_index < run.event_frames.size() and run.event_frames[_event_index] <= frame:
		var index: int = run.event_actions[_event_index]
		var strength: float = run.event_strengths[_event_index]
		if strength > 0.0:
			Input.action_press(run.actions[index], strength)
		else:
			Input.action_release(run.actions[index])
		_strengths[index] = strength
		_event_index += 1


func _finish_recording(success: bool, reason: String) -> void:
	run.frame_count = frame
	run.success = success
	run.reason = reason
	var dir: String = _runs_dir(run.level_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir + run.created.replace(":", "-").replace(" ", "_") + ".tres"
	var error: Error = ResourceSaver.save(run, path)
	if error != OK:
		push_error("QA : impossible d'enregistrer %s : %s" % [path, error_string(error)])
	else:
		run_path = path
		print("QA : partie enregistrée (%s, %.1f s) : %s" % [reason, run.duration(), path])
	_set_state(State.IDLE)
	runs_changed.emit()


func _finish_replay(success: bool, reason: String) -> void:
	_release_inputs()
	var divergence_distance: float = 0.0
	if _divergence_frame >= 0 and _has_trace():
		divergence_distance = _trace.path[_divergence_frame].distance_to(run.trace[_divergence_frame])
	var report: Dictionary = {
		"path": run_path,
		"success": success,
		"reason": reason,
		"frames": frame,
		"expected_success": run.success,
		"expected_frames": run.frame_count,
		"divergence_frame": _divergence_frame,
		"divergence_distance": divergence_distance,
	}
	# OK : même fin, au même moment, par le même parcours.
	report["ok"] = success == run.success and frame == run.frame_count and _divergence_frame < 0
	last_report = report
	print("QA : %s\n%s" % [run_path, report_text(report)])
	_set_state(State.IDLE)
	replay_finished.emit(report)
	_exit_if_asked(report["ok"] and success)


# Relâche les actions encore appuyées par la lecture.
func _release_inputs() -> void:
	for index: int in _strengths.size():
		if _strengths[index] > 0.0:
			Input.action_release(run.actions[index])
	_strengths.fill(0.0)


func _exit_if_asked(success: bool) -> void:
	if not _exit_when_done:
		return
	await get_tree().create_timer(EXIT_DELAY).timeout
	get_tree().quit(0 if success else 1)


func _on_finished(success: bool, reason: String) -> void:
	match state:
		State.RECORDING:
			_finish_recording(success, reason)
		State.REPLAYING:
			_finish_replay(success, reason)


func _on_marked(label: String) -> void:
	if state != State.RECORDING and state != State.REPLAYING:
		return
	if state == State.RECORDING:
		run.add_mark(frame, label)
	if _has_trace():
		_trace.add_mark(frame, label)


func _has_trace() -> bool:
	return _trace != null and is_instance_valid(_trace) and _trace.is_inside_tree()


func _make_trace() -> void:
	if _has_trace():
		return
	var parent: Node = adapter.get_trace_parent()
	if parent == null:
		_trace = null
		return
	_trace = QATrace.new()
	_trace.name = "QATrace"
	_trace.visible = show_trace
	parent.add_child(_trace)


func _runs_dir(level_id: String) -> String:
	return adapter.get_runs_dir().path_join(level_id.get_file().get_basename()) + "/"


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit()
