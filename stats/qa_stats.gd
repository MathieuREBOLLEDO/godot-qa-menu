class_name QAStats
extends Node

## Stats des joueurs (addons/qa/stats), enfant de l'autoload QA : QA.stats.
## Une session par lancement du jeu : temps de jeu (hors pause), temps et
## événements par niveau, dernier niveau atteint, FPS, plateforme, crash.
## - Fichier JSON par session dans SESSIONS_DIR, enregistré régulièrement :
##   une session restée ouverte au lancement suivant est un crash (la fin du
##   log de Godot y est jointe).
## - Envoi (POST JSON) vers le paramètre qa/stats/upload_url des sessions
##   terminées, au lancement suivant ; envoyées, elles passent dans SENT_DIR.
## - Consentement : demandé au premier lancement d'un jeu exporté
##   (qa/stats/ask_consent). Sans accord, rien n'est écrit ni envoyé. Dans
##   l'éditeur Godot : enregistré sur place, jamais envoyé, sans question.
## - Le jeu fournit un QAStatsAdapter (qa/stats/adapter), sinon celui par
##   défaut. Voir addons/qa/README.md, Stats des joueurs.
## Inactif en headless (sauf avec --qa-stats après « -- ») et pendant une
## lecture --qa-replay.

enum Consent { UNKNOWN, YES, NO }

const ENABLED_SETTING: String = "qa/stats/enabled"
const ADAPTER_SETTING: String = "qa/stats/adapter"
const UPLOAD_URL_SETTING: String = "qa/stats/upload_url"
const ASK_CONSENT_SETTING: String = "qa/stats/ask_consent"
const DIR: String = "user://qa/stats/"
const SESSIONS_DIR: String = DIR + "sessions/"
const SENT_DIR: String = DIR + "sent/"
const PROFILE_PATH: String = DIR + "profile.cfg"
const DEBUG_MENU_PATH: String = "/root/DebugMenu"
const WINDOW_PATH: String = "res://addons/qa/stats/debug/stats_window.tscn"
const QAStatsConsent = preload("res://addons/qa/stats/qa_stats_consent.gd")
const QAStatsTexts = preload("res://addons/qa/stats/qa_stats_texts.gd")
## Version du format du fichier de session.
const FORMAT: int = 1
## Temps entre deux enregistrements de la session (s).
const SAVE_INTERVAL: float = 10.0
## Temps entre deux lectures du niveau en cours (s).
const LEVEL_POLL_INTERVAL: float = 0.25
## Au-delà, les événements ne sont plus gardés (les compteurs, si).
const MAX_EVENTS: int = 5000
## Lignes de la fin du log de Godot jointes à une session plantée.
const LOG_TAIL_LINES: int = 60
## Sous ce FPS, la seconde compte dans fps.low_seconds.
const LOW_FPS: int = 30

var adapter: QAStatsAdapter = null
## Vrai si les stats sont collectées pendant ce lancement.
var active: bool = false
var consent: Consent = Consent.UNKNOWN
## Session en cours, telle qu'enregistrée en JSON.
var session: Dictionary = {}
## Niveau en cours ("" hors d'un niveau).
var level_id: String = ""

var _profile: ConfigFile = ConfigFile.new()
var _is_editor: bool = OS.has_feature("editor")
var _last_usec: int = 0
var _save_timer: float = 0.0
var _poll_timer: float = 0.0
var _fps_timer: float = 0.0
var _fps_sum: float = 0.0
var _fps_samples: int = 0
var _closed: bool = false
var _http: HTTPRequest = null
var _upload_queue: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	QAStatsTexts.register()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var headless: bool = DisplayServer.get_name() == "headless" and not args.has("--qa-stats")
	var replaying: bool = Array(args).any(func(arg: String) -> bool: return arg.begins_with("--qa-replay="))
	if not ProjectSettings.get_setting(ENABLED_SETTING, true) or headless or replaying:
		return
	_load_adapter()
	if adapter == null:
		return
	_load_profile()
	_mark_crashed_sessions()
	_start_session()
	active = true
	adapter.stats = self
	adapter.attach()
	var debug_menu: Node = get_node_or_null(DEBUG_MENU_PATH)
	if debug_menu != null:
		debug_menu.add_entry("QA", "Stats", load(WINDOW_PATH))
	if _needs_consent():
		# Après le premier affichage : la scène principale est en place.
		await get_tree().process_frame
		show_consent()
	else:
		_save()
		send_pending()


func _process(_delta: float) -> void:
	if not active or _closed:
		return
	# Temps réel : ni Engine.time_scale ni l'image par image du debug menu.
	var now: int = Time.get_ticks_usec()
	var elapsed: float = (now - _last_usec) / 1000000.0
	_last_usec = now
	session["session_time"] += elapsed
	if get_tree().paused:
		session["pause_time"] += elapsed
	else:
		session["play_time"] += elapsed
		if level_id != "":
			var level: Dictionary = _level()
			level["time"] += elapsed
		_sample_fps(elapsed)
	_poll_timer += elapsed
	if _poll_timer >= LEVEL_POLL_INTERVAL:
		_poll_timer = 0.0
		var current: String = adapter.get_level_id()
		if current != level_id:
			_enter_level(current)
	_save_timer += elapsed
	if _save_timer >= SAVE_INTERVAL:
		_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		close()


func _exit_tree() -> void:
	close()


# --- Ce que le jeu appelle (souvent par son adaptateur) ---

## Événement daté du niveau en cours, par exemple track("death", {"pos":
## [x, y]}). Il compte aussi dans les compteurs (count()).
func track(type: String, data: Dictionary = {}) -> void:
	if not active:
		return
	var event: Dictionary = {"t": snappedf(session["session_time"], 0.01), "type": type}
	if level_id != "":
		event["level"] = level_id
	if not data.is_empty():
		event["data"] = data
	var events: Array = session["events"]
	if events.size() < MAX_EVENTS:
		events.append(event)
	else:
		session["events_dropped"] += 1
	count(type)


## Compteur de la session et du niveau en cours (saut, lancer...), sans
## événement daté.
func count(counter: String, amount: int = 1) -> void:
	if not active:
		return
	var counts: Dictionary = session["counts"]
	counts[counter] = counts.get(counter, 0) + amount
	if level_id != "":
		var level_counts: Dictionary = _level()["counts"]
		level_counts[counter] = level_counts.get(counter, 0) + amount


## Réponse du joueur : oui enregistre la session (et l'envoie au prochain
## lancement), non efface ce qui a été collecté et n'enregistre plus rien.
func set_consent(accepted: bool) -> void:
	consent = Consent.YES if accepted else Consent.NO
	_profile.set_value("player", "consent", consent)
	_save_profile()
	if accepted:
		_save()
		send_pending()
	else:
		_delete_unsent()


## Fenêtre de consentement (le jeu peut l'ouvrir depuis ses réglages).
func show_consent() -> void:
	var dialog: CanvasLayer = QAStatsConsent.new()
	dialog.answered.connect(set_consent)
	get_tree().root.add_child(dialog)


## Envoie les sessions terminées pas encore envoyées, une par une.
func send_pending() -> void:
	var url: String = ProjectSettings.get_setting(UPLOAD_URL_SETTING, "")
	if url == "" or _is_editor or not _can_write() or not _upload_queue.is_empty():
		return
	for path: String in _session_files(SESSIONS_DIR):
		var data: Dictionary = _read_json(path)
		var finished: bool = data.get("clean_exit", false) or data.get("crashed", false)
		if finished and not data.get("editor", false) and data.get("session_id", "") != session.get("session_id", ""):
			_upload_queue.append(path)
	_send_next()


## Termine la session (sortie propre). Appelé à la fermeture du jeu.
func close() -> void:
	if not active or _closed:
		return
	session["clean_exit"] = true
	_save()
	_closed = true


## Pour tester la détection d'un crash : enregistre la session encore
## ouverte et quitte sans la fermer.
func quit_as_crash() -> void:
	_save()
	_closed = true
	get_tree().quit()


## État en une ligne, pour une fenêtre de debug.
func status_text() -> String:
	if not active:
		return tr("Stats inactive (disabled, headless or QA replay).")
	var consent_text: String = [tr("not asked yet"), tr("yes"), tr("no")][consent]
	return tr("Session %s, play %s, level %s. Consent: %s.") % [
		_format_time(session["session_time"]),
		_format_time(session["play_time"]),
		level_id.get_file() if level_id != "" else "-",
		consent_text,
	]


## Résumé lisible de la session en cours, un niveau par ligne.
func session_text() -> String:
	if not active:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	var levels: Dictionary = session["levels"]
	for id: String in levels:
		var level: Dictionary = levels[id]
		lines.append("%s : %s, x%d  %s" % [id.get_file(), _format_time(level["time"]), level["entries"], _counts_text(level["counts"])])
	if lines.is_empty():
		lines.append(tr("No level played yet."))
	lines.append(tr("Events: %d. FPS: avg %d, min %d.") % [session["events"].size(), session["fps"]["avg"], session["fps"]["min"]])
	return "\n".join(lines)


## Totaux de toutes les sessions sur ce poste (envoyées ou non).
func totals() -> Dictionary:
	var result: Dictionary = {"sessions": 0, "play_time": 0.0, "crashes": 0, "unsent": 0}
	for dir: String in [SESSIONS_DIR, SENT_DIR]:
		for path: String in _session_files(dir):
			var data: Dictionary = _read_json(path)
			result["sessions"] += 1
			result["play_time"] += float(data.get("play_time", 0.0))
			if data.get("crashed", false):
				result["crashes"] += 1
			if dir == SESSIONS_DIR:
				result["unsent"] += 1
	return result


# --- Session ---

func _load_adapter() -> void:
	var path: String = ProjectSettings.get_setting(ADAPTER_SETTING, "")
	if path == "":
		adapter = QAStatsAdapter.new()
		return
	var script: Script = load(path) as Script
	adapter = script.new() as QAStatsAdapter if script != null else null
	if adapter == null:
		push_error("QA Stats : %s n'est pas un QAStatsAdapter (paramètre %s)." % [path, ADAPTER_SETTING])


func _start_session() -> void:
	var now: Dictionary = Time.get_datetime_dict_from_system(true)
	var session_id: String = "%04d%02d%02d-%02d%02d%02d-%s" % [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"], _random_hex(3)]
	var window: Window = get_window()
	session = {
		"format": FORMAT,
		"session_id": session_id,
		"player_id": _profile.get_value("player", "id"),
		"session_index": int(_profile.get_value("player", "sessions", 0)) + 1,
		"game": ProjectSettings.get_setting("application/config/name", ""),
		"version": adapter.get_game_version(),
		"editor": _is_editor,
		"debug_build": OS.is_debug_build(),
		"started": Time.get_datetime_string_from_system(true) + "Z",
		"ended": "",
		"clean_exit": false,
		"crashed": false,
		"session_time": 0.0,
		"play_time": 0.0,
		"pause_time": 0.0,
		"last_level": "",
		"platform": {
			"os": OS.get_name(),
			"os_version": OS.get_version(),
			"locale": OS.get_locale(),
			"cpu": OS.get_processor_name(),
			"gpu": RenderingServer.get_video_adapter_name(),
			"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
			"screen": _vector_array(DisplayServer.screen_get_size()),
			"window": _vector_array(window.size) if window != null else [],
		},
		"fps": {"avg": 0, "min": 0, "low_seconds": 0},
		"counts": {},
		"levels": {},
		"events": [],
		"events_dropped": 0,
	}
	_profile.set_value("player", "sessions", session["session_index"])
	_last_usec = Time.get_ticks_usec()


func _enter_level(new_level_id: String) -> void:
	level_id = new_level_id
	if level_id != "":
		session["last_level"] = level_id
		var level: Dictionary = _level()
		level["entries"] += 1
		track("level")
	adapter.level_changed(level_id)
	_save()


# Résumé du niveau en cours dans la session.
func _level() -> Dictionary:
	var levels: Dictionary = session["levels"]
	if not levels.has(level_id):
		levels[level_id] = {"time": 0.0, "entries": 0, "counts": {}}
	return levels[level_id]


func _sample_fps(elapsed: float) -> void:
	_fps_timer += elapsed
	if _fps_timer < 1.0:
		return
	_fps_timer = 0.0
	var fps: int = roundi(Engine.get_frames_per_second())
	var stats_fps: Dictionary = session["fps"]
	_fps_sum += fps
	_fps_samples += 1
	stats_fps["avg"] = roundi(_fps_sum / _fps_samples)
	stats_fps["min"] = fps if _fps_samples == 1 else mini(stats_fps["min"], fps)
	if fps < LOW_FPS:
		stats_fps["low_seconds"] += 1


func _needs_consent() -> bool:
	return consent == Consent.UNKNOWN and not _is_editor and ProjectSettings.get_setting(ASK_CONSENT_SETTING, true)


func _can_write() -> bool:
	return consent == Consent.YES or _is_editor or not ProjectSettings.get_setting(ASK_CONSENT_SETTING, true)


func _save() -> void:
	_save_timer = 0.0
	if not active or _closed or not _can_write():
		return
	session["ended"] = Time.get_datetime_string_from_system(true) + "Z"
	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	_write_json(SESSIONS_DIR + session["session_id"] + ".json", session)
	_profile.set_value("player", "play_time", float(_profile.get_value("player", "play_time_before", 0.0)) + session["play_time"])
	_save_profile()


# Sessions restées ouvertes (ni sortie propre ni crash déjà noté) : crash.
# La plus récente reçoit la fin du log du lancement précédent.
func _mark_crashed_sessions() -> void:
	var paths: Array[String] = _session_files(SESSIONS_DIR)
	paths.reverse()
	var log_attached: bool = false
	for path: String in paths:
		var data: Dictionary = _read_json(path)
		if data.is_empty() or data.get("clean_exit", false) or data.get("crashed", false):
			continue
		data["crashed"] = true
		if not log_attached:
			data["log_tail"] = _previous_log_tail()
			log_attached = true
		_write_json(path, data)


# Fin du log de Godot du lancement précédent (godot<date>.log, le plus
# récent après godot.log, qui est celui de ce lancement).
func _previous_log_tail() -> PackedStringArray:
	var log_path: String = ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")
	var dir: String = log_path.get_base_dir()
	var base: String = log_path.get_file().get_basename()
	var previous: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.begins_with(base) and file != log_path.get_file() and file.ends_with(".log"):
			previous.append(file)
	if previous.is_empty():
		return PackedStringArray()
	previous.sort()
	var lines: PackedStringArray = FileAccess.get_file_as_string(dir.path_join(previous[-1])).split("\n", false)
	return lines.slice(maxi(0, lines.size() - LOG_TAIL_LINES))


# Le joueur a refusé : on efface ce qui n'est pas parti.
func _delete_unsent() -> void:
	for path: String in _session_files(SESSIONS_DIR):
		DirAccess.remove_absolute(path)


# --- Envoi ---

func _send_next() -> void:
	if _upload_queue.is_empty():
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 20.0
		_http.request_completed.connect(_on_request_completed)
		add_child(_http)
	var body: String = FileAccess.get_file_as_string(_upload_queue[0])
	var url: String = ProjectSettings.get_setting(UPLOAD_URL_SETTING, "")
	var error: Error = _http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if error != OK:
		push_warning("QA Stats : envoi impossible : %s" % error_string(error))
		_upload_queue.clear()


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var path: String = _upload_queue.pop_front()
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 400:
		# Réessayé au prochain lancement.
		push_warning("QA Stats : envoi refusé (résultat %d, code HTTP %d)." % [result, code])
		_upload_queue.clear()
		return
	DirAccess.make_dir_recursive_absolute(SENT_DIR)
	DirAccess.rename_absolute(path, SENT_DIR + path.get_file())
	_send_next()


# --- Profil (identifiant anonyme, consentement, totaux) ---

func _load_profile() -> void:
	_profile.load(PROFILE_PATH)
	if not _profile.has_section_key("player", "id"):
		_profile.set_value("player", "id", _random_hex(16))
	consent = int(_profile.get_value("player", "consent", Consent.UNKNOWN)) as Consent
	_profile.set_value("player", "play_time_before", _profile.get_value("player", "play_time", 0.0))


func _save_profile() -> void:
	if not _can_write() and consent != Consent.NO:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_profile.save(PROFILE_PATH)


# --- Outils ---

# Fichiers de session d'un dossier, du plus ancien au plus récent (le nom
# commence par la date).
func _session_files(dir: String) -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return paths
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			paths.append(dir + file)
	paths.sort()
	return paths


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("QA Stats : impossible d'écrire %s : %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()


static func _vector_array(vector: Vector2i) -> Array:
	return [vector.x, vector.y]


static func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	if total >= 3600:
		return "%dh%02d" % [total / 3600, (total % 3600) / 60]
	return "%d:%02d" % [total / 60, total % 60]


static func _counts_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for counter: String in counts:
		parts.append("%s %d" % [counter, counts[counter]])
	return ", ".join(parts)
