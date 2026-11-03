# QA : testeur de niveaux et stats des joueurs

Addon Godot 4 (GDScript), indépendant du jeu. Deux outils : le testeur de
niveaux (ci-dessous) et les stats des joueurs (voir Stats des joueurs).

Le testeur enregistre une partie
depuis le départ d'un niveau, la rejoue, dessine le parcours, vérifie que la
lecture donne le même résultat et enregistre la vidéo d'une partie.

Un niveau est « faisable » quand une partie enregistrée atteint la fin. La
rejouer après une modification du niveau ou de la physique dit si elle
passe toujours : c'est un test de régression.

## Installation

1. Copier `addons/qa/` dans le projet et activer le plugin « QA ». Ça
   déclare l'autoload `QA` et le paramètre du projet `qa/adapter`. Si le
   projet a un debug menu (addons/debug_menu), placer `QA` après
   `DebugMenu` dans les autoloads.
2. Écrire l'adaptateur du jeu, un script qui étend `QAAdapter`
   (qa_adapter.gd), et mettre son chemin dans `qa/adapter`.

## Adaptateur (à redéfinir)

- `get_level_id() -> String` : niveau en cours (en général son chemin), ""
  si rien n'est testable.
- `load_level(level_id)` : charge ce niveau dans son état de départ.
- `attach() -> bool` : vrai quand le niveau chargé est prêt. Branche ici les
  signaux du jeu sur `finished.emit(success, reason)` (fin de la partie) et
  `marked.emit(label)` (événement sur le parcours).
- `get_tracked_position() -> Vector2` : position suivie (globale, 2D).
- `get_trace_parent() -> Node` : nœud 2D du niveau où dessiner le parcours.
- Facultatif : `get_actions()` (par défaut, toutes les actions de l'InputMap
  sauf `ui_*` et `debug_menu_*`), `get_runs_dir()` (par défaut
  `user://qa/runs/`).

Exemple : game/level/qa/gringo_qa_adapter.gd (ProjetGringo).

## Utilisation

- Debug menu : QA > Testeur de niveau. Enregistrer une partie (le niveau
  est rechargé), Arrêter ou Annuler, puis Rejouer, Parcours (le montrer sans
  rejouer) ou Vidéo pour une partie enregistrée.
- Code : `QA.start_recording()`, `QA.stop(keep)`, `QA.replay_file(path)`,
  `QA.show_run_trace(path)`, `QA.record_video(path)`, signal
  `QA.replay_finished(report)`.
- Ligne de commande, par exemple pour vérifier un niveau en intégration
  continue :

      godot --headless --path <projet> -- --qa-replay=res://.../partie.tres --qa-exit

  Code de sortie 0 si la partie réussit comme à l'enregistrement (même fin,
  même durée, même parcours), 1 sinon.

## Fichiers

- Partie (`QARun`, .tres) : changements d'entrées frame physique par frame
  physique, parcours, événements, fin. Dans `get_runs_dir()/<niveau>/`.
- Vidéo : `user://qa/videos/<niveau>_<partie>.avi` (MJPEG, Movie Maker de
  Godot). Elle est enregistrée par une deuxième instance du jeu, lancée avec
  `--write-movie`, qui rejoue la partie puis quitte.

## Parcours

Dessiné sous le niveau : la référence (partie enregistrée) en blanc, la
partie en cours en bleu, les événements en rose, le départ en vert,
l'arrivée en jaune et la première divergence (écart de plus de 0,5 px) en
rouge.

## Limites (V1)

- 2D seulement (position en Vector2).
- Il faut un jeu déterministe : mêmes entrées, même résultat. Il faut donc
  une logique de jeu dans `_physics_process`, pas de hasard sans graine
  fixe, et pas de réglages changés entre l'enregistrement et la lecture
  (sliders du debug menu, Engine.time_scale). La lecture signale toute
  divergence.
- Seules les actions de l'InputMap sont enregistrées, pas la souris ni les
  événements bruts.
- Un appui plus court qu'une frame physique peut être manqué.
- Pendant la lecture, ne pas toucher au clavier : une touche réelle
  s'ajoute aux entrées rejouées.
- La vidéo se lance depuis le jeu lancé par l'éditeur ou depuis un export
  qui inclut le Movie Maker.
- Pas de bot qui trouve un chemin tout seul : ça dépend de la physique de
  chaque jeu.

# Stats des joueurs

`QA.stats` (addons/qa/stats/qa_stats.gd) : ce que font les joueurs d'un jeu
sorti. Une session par lancement :

- temps de session, de jeu (hors pause) et de pause ; numéro de la session
  du joueur ; identifiant de joueur anonyme (tiré au hasard) ;
- dernier niveau atteint ; par niveau : temps, entrées, compteurs ;
- événements datés (mort avec position, sortie, menus...) et compteurs
  (sauts...) envoyés par le jeu ;
- crash : une session pas fermée proprement est marquée `crashed` au
  lancement suivant, avec la fin du log de Godot ;
- FPS (moyenne, minimum, secondes sous 30), OS, processeur, carte
  graphique, écran, langue, version du jeu.

Le temps est du temps réel : il ne suit ni `Engine.time_scale` ni l'image
par image du debug menu. La pause est `get_tree().paused`.

## Paramètres du projet

- `qa/stats/enabled` (vrai) : collecter.
- `qa/stats/adapter` : adaptateur du jeu (`QAStatsAdapter`), facultatif.
- `qa/stats/upload_url` : adresse qui reçoit chaque session en POST JSON.
  Vide : rien n'est envoyé.
- `qa/stats/ask_consent` (vrai) : demander l'accord du joueur au premier
  lancement (fenêtre de l'addon). Sans accord, rien n'est écrit ni envoyé ;
  un refus efface ce qui n'est pas parti.

Dans l'éditeur Godot, les sessions sont écrites sans question (pour la
fenêtre de debug) et marquées `editor` : elles ne sont jamais envoyées.
Inactif en headless (sauf avec `-- --qa-stats`) et pendant `--qa-replay`.

## Adaptateur (facultatif)

Sans adaptateur, `QAStatsAdapter` branche les managers d'un projet créé par
project_init : `GameManager.game_started` (événement `game_started`),
`GameManager.paused_changed` (compteur `pause`), `UIManager.menu_changed`
(événement `menu`), et prend la scène en cours comme niveau.

Un jeu l'étend pour ses propres objets (appeler `super()` dans `attach()`
pour garder les managers) :

- `get_level_id() -> String` : niveau en cours, "" hors d'un niveau. Lu
  4 fois par seconde.
- `level_changed(level_id)` : brancher ici les signaux du niveau sur
  `stats.track(type, data)` (événement daté, compté aussi) et
  `stats.count(nom)` (compteur seul).
- `get_game_version()` : par défaut `application/config/version`.

Exemple : game/level/qa/gringo_stats_adapter.gd (ProjetGringo).

## Code

- `QA.stats.track("death", {"pos": [x, y]})`, `QA.stats.count("jump")`.
- `QA.stats.set_consent(oui)`, `QA.stats.show_consent()` : pour le réglage
  du jeu.
- `QA.stats.send_pending()` : envoyer maintenant (fait au lancement).
- Debug menu : QA > Stats (session en cours, totaux du poste, Envoyer,
  Ouvrir le dossier, Quitter comme un crash pour tester).

## Fichiers

- `user://qa/stats/sessions/<session>.json` : sessions pas encore envoyées
  (celle en cours est réécrite toutes les 10 s et à chaque changement de
  niveau) ; `user://qa/stats/sent/` : envoyées.
- `user://qa/stats/profile.cfg` : identifiant anonyme, consentement,
  nombre de sessions, temps de jeu total.

## Recevoir les sessions (Google Sheet, gratuit)

1. Créer une Google Sheet, puis Extensions > Apps Script, et coller :

       function doPost(e) {
         var s = JSON.parse(e.postData.contents);
         var book = SpreadsheetApp.getActiveSpreadsheet();
         var sessions = book.getSheetByName("sessions") || book.insertSheet("sessions");
         sessions.appendRow([s.started, s.game, s.version, s.player_id, s.session_index,
           s.play_time, s.session_time, s.crashed, s.last_level, s.fps.avg, s.fps.min,
           s.platform.os, s.platform.gpu, (s.log_tail || []).join("\n")]);
         var levels = book.getSheetByName("levels") || book.insertSheet("levels");
         for (var id in s.levels) {
           var l = s.levels[id];
           levels.appendRow([s.started, s.player_id, s.version, id, l.time, l.entries,
             l.counts.death || 0, l.counts.exit || 0, JSON.stringify(l.counts)]);
         }
         var deaths = book.getSheetByName("deaths") || book.insertSheet("deaths");
         s.events.forEach(function (ev) {
           if (ev.type == "death" && ev.data && ev.data.pos)
             deaths.appendRow([s.version, ev.level, ev.data.pos[0], ev.data.pos[1]]);
         });
         var raw = book.getSheetByName("raw") || book.insertSheet("raw");
         raw.appendRow([s.session_id, e.postData.contents.substring(0, 49000)]);
         return ContentService.createTextOutput("ok");
       }

2. Déployer > Nouveau déploiement > Application Web, exécuter en tant que
   « Moi », accès « Tout le monde ». Copier l'URL dans
   `qa/stats/upload_url`.

Onglets : `sessions` (une ligne par session), `levels` (une ligne par
niveau joué : temps, morts, sorties), `deaths` (positions des morts, pour
voir les passages difficiles), `raw` (JSON complet, tronqué à 49 000
caractères).

## Limites

- Un crash perd au plus les 10 dernières secondes de la session.
- La fin du log jointe à un crash peut être incomplète : Godot n'écrit pas
  toujours son log sur le disque avant d'être tué.
- Une session refusée par le serveur (ou sans réseau) repart au lancement
  suivant.
- Le jeu fournit son propre réglage pour changer d'avis
  (`set_consent()`) : l'addon n'a que la fenêtre du premier lancement.


## Tests

Tests automatiques dans `tests/` (fichiers `test_*.gd`, qui étendent
`TestCase` de l'addon test runner, github.com/MathieuREBOLLEDO/godot-test-runner).
Ils se lancent dans un jeu qui a les deux addons :

```
godot --headless --fixed-fps 60 --path <jeu> res://addons/test_runner/runner.tscn -- --dir=res://addons/qa
```

Sans test runner dans le projet, ces fichiers ne sont pas chargés (ni à
l'import ni au lancement) ; seule leur ouverture montre une erreur de classe
de base. Ils n'utilisent aucun fichier du jeu.
