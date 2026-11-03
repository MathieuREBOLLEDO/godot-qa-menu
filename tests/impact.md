# Carte d'impact des tests

Quand un système change : lancer ses tests pendant le travail, puis tous
les tests de l'addon (environ 3 s de jeu) avant d'annoncer la tâche finie,
puis les parties QA enregistrées du jeu hôte (Gringo : `-Filter qa_replays`).

Les tests tournent dans un jeu qui a l'addon et le test runner
(ProjetGringo, sous-module addons/qa) :
`.\tests\run_tests.ps1 -Dir res://addons/qa`, ou un seul test avec
`-Filter <texte>`. On écrit et on commite dans ce sous-module.
Les parties des tests vont dans user://test_runner/qa/runs/ ; les stats
des tests n'écrivent rien (user://qa/stats/ n'est pas touché).

| Système (fichiers) | Ses tests | Touche aussi |
|---|---|---|
| Tout fichier de l'addon (chargement, compilation) | `-Filter addon_files_load` | — |
| Autoload et adaptateur (qa.gd _load_adapter, qa_adapter.gd) | `-Filter autoload`, `-Filter default_actions` | parties QA du jeu |
| Partie (qa_run.gd) | `-Filter run_events` | parties QA du jeu (format .tres) |
| Enregistrement et rejeu (qa.gd) | `-Filter record_then_replay`, `-Filter different_path`, `-Filter stopped_recording`, `-Filter cancelled`, `-Filter twice`, `-Filter missing_run` | parties QA du jeu, debug menu (pause, image par image pendant un rejeu) |
| Rapport (qa.gd report_text) | `-Filter report_text` | fenêtre QA |
| Fenêtres du debug menu (debug/, stats/debug/) | `-Filter debug_windows` | debug menu (ui/debug_window.gd, leur base) |
| Stats des joueurs (stats/qa_stats.gd, qa_stats_adapter.gd) | `-Filter test_stats`, `-Filter stats_text` | adaptateur de stats du jeu |
| Consentement (stats/qa_stats_consent.gd) | `-Filter consent` | — |

## Pas couvert (à vérifier à la main)

Vidéo (Movie Maker, deuxième instance du jeu), ligne de commande
--qa-replay / --qa-exit, dessin du parcours (QATrace, seulement créé),
fichiers de session et profil sur disque, détection d'un crash, envoi des
stats (HTTP), stats en vrai lancement (inactives en headless), tout ce qui
est affiché.
Une nouvelle fonction arrive avec ses tests et sa ligne dans ce tableau.
