extends RefCounted

## Textes du module Stats : l'anglais sert de clé (tr()), les traductions
## sont ici, une table par langue. Le réglage de langue du jeu
## (TranslationServer.set_locale) les choisit.

const TABLES: Dictionary = {
	"fr": {
		"Help improve the game": "Aider à améliorer le jeu",
		"Can the game send anonymous play stats? Play time, levels reached, where you get stuck and crashes. Nothing personal, and you can change your mind in the settings.": "Le jeu peut-il envoyer des statistiques de jeu anonymes ? Temps de jeu, niveaux atteints, passages difficiles et plantages. Rien de personnel, et tu peux changer d'avis dans les réglages.",
		"Yes, share": "Oui, partager",
		"No thanks": "Non merci",
		"Stats inactive (disabled, headless or QA replay).": "Stats inactives (désactivées, headless ou lecture QA).",
		"not asked yet": "pas encore demandé",
		"yes": "oui",
		"no": "non",
		"Session %s, play %s, level %s. Consent: %s.": "Session %s, jeu %s, niveau %s. Consentement : %s.",
		"No level played yet.": "Aucun niveau joué.",
		"Events: %d. FPS: avg %d, min %d.": "Événements : %d. FPS : moyenne %d, min %d.",
		"This session": "Cette session",
		"All sessions on this computer": "Toutes les sessions de ce poste",
		"%d sessions, %s played, %d crashes, %d not sent yet.": "%d sessions, %s de jeu, %d plantages, %d pas encore envoyées.",
		"Upload URL: %s": "Adresse d'envoi : %s",
		"none (qa/stats/upload_url)": "aucune (qa/stats/upload_url)",
		"Send now": "Envoyer",
		"Open folder": "Ouvrir le dossier",
		"Ask consent": "Demander le consentement",
		"Quit as crash": "Quitter comme un crash",
		"Sessions are never sent from the Godot editor. Quit as crash leaves the session open: the next launch marks it as a crash.": "Les sessions ne sont jamais envoyées depuis l'éditeur Godot. Quitter comme un crash laisse la session ouverte : le lancement suivant la marque comme plantée.",
		"Time and counters per level, for this launch.": "Temps et compteurs par niveau, pour ce lancement.",
		"QA autoload missing: enable the QA addon.": "Autoload QA absent : activer l'addon QA.",
	},
}


static func register() -> void:
	for locale: String in TABLES:
		var translation: Translation = Translation.new()
		translation.locale = locale
		var table: Dictionary = TABLES[locale]
		for key: String in table:
			translation.add_message(key, table[key])
		TranslationServer.add_translation(translation)
