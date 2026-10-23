# QA : testeur de niveaux

Addon Godot 4 (GDScript), indépendant du jeu. Il enregistre une partie
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
