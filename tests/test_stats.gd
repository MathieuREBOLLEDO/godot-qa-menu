extends TestCase

## Stats des joueurs (stats/qa_stats.gd) : événements et compteurs rangés
## par niveau, limite d'événements, textes. Sur un QAStats à part, session
## démarrée à la main et marquée fermée : rien n'est écrit dans user://qa/
## (les vraies sessions du poste ne sont pas touchées).

var _stats: QAStats


func before_each() -> void:
	_stats = add_test_node(QAStats.new()) as QAStats # inactif en headless
	_stats.adapter = QAStatsAdapter.new()
	_stats._closed = true # _save() n'écrit rien
	_stats._profile.set_value("player", "id", "test_player") # profil du poste pas lu
	_stats._start_session()
	_stats.active = true


func test_inactive_stats_record_nothing() -> void:
	var idle: QAStats = add_test_node(QAStats.new()) as QAStats
	await frames(1)
	assert_false(idle.active, "inactive in headless")
	idle.track("death")
	idle.count("jump")
	assert_true(idle.session.is_empty(), "nothing recorded")


func test_events_and_counts_go_to_the_current_level() -> void:
	_stats._enter_level("res://levels/one.tres")
	_stats.track("death", {"pos": [1, 2]})
	_stats.count("jump", 3)
	_stats._enter_level("")
	_stats.count("jump")
	_stats._enter_level("res://levels/one.tres")
	var level: Dictionary = _stats.session["levels"]["res://levels/one.tres"]
	assert_eq(level["entries"], 2, "entered twice")
	assert_eq(level["counts"]["jump"], 3, "jumps of the level")
	assert_eq(level["counts"]["death"], 1, "an event also counts")
	assert_eq(_stats.session["counts"]["jump"], 4, "jumps of the session")
	assert_eq(_stats.session["last_level"], "res://levels/one.tres")
	var death: Dictionary = _stats.session["events"].filter(func(event: Dictionary) -> bool: return event["type"] == "death")[0]
	assert_eq(death["level"], "res://levels/one.tres", "event tagged with its level")
	assert_eq(death["data"], {"pos": [1, 2]})


func test_events_over_the_limit_are_only_counted() -> void:
	for i: int in QAStats.MAX_EVENTS + 5:
		_stats.track("step")
	assert_eq(_stats.session["events"].size(), QAStats.MAX_EVENTS)
	assert_eq(_stats.session["events_dropped"], 5)
	assert_eq(_stats.session["counts"]["step"], QAStats.MAX_EVENTS + 5, "all counted")


func test_texts() -> void:
	_stats._enter_level("res://levels/one.tres")
	_stats.count("jump", 2)
	assert_true(_stats.session_text().contains("one.tres"), "level line")
	assert_true(_stats.session_text().contains("jump 2"), "its counters")
	assert_true(_stats.status_text().contains("one.tres"), "status names the level")
