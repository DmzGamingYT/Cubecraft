<!-- Page de documentation Cubecraft : Menu de diagnostic et suites de tests.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

## Menu de diagnostic

`F4` (ou `Ctrl`+`Alt`+`D`) ouvre un panneau de diagnostic **depuis la partie en
cours**, à l'écran titre comme en jeu. Il n'invente rien : il rassemble ce que le
jeu evaluait jusqu'ici dans une console invisible.

- **Informations** : graine, portée, FPS, position, chunks, torches, mémoire,
  draws, durée de session.
- **Vérifications du jeu** : les 93 vérifications d'inventaire, de fabrication,
  de survie, de mobs, d'enchantement, de météo, puis de retour au titre et de
  relance d'une partie. Le résultat s'affiche ligne à ligne pendant l'exécution
  (vert, rouge, gris), le rapport est épinglé en haut, et la liste défile seule.
  **La séquence détruit la partie** — elle vide l'inventaire, déplace et tue le
  joueur, démonte le monde et en crée un nouveau. Le menu l'annonce, et
  « Sauvegarder » est juste au-dessus.
- **Sonde de rendu** : lit les sommets du chunk sous la caméra — position,
  UV, couleur de sommet — seul moyen de distinguer un problème de texture d'un
  problème de teinte. C'est le code qui servait à la capture ASCII.
- **Actions** : retour au point d'apparition, monter de 20 blocs, kit de survie,
  soigner et nourrir, heure, météo, sauvegarde, quitter.

Le menu est modal (souris visible, joueur immobile) mais ne fige pas le monde :
la séquence a besoin de déplacer et de tuer le joueur pour le vérifier. Il vit
dans sa propre `CanvasLayer` et survit au démontage de la partie, ce qui permet
de lire le rapport de la séquence qui vient justement de tout démonter.

Deux modes en ligne de commande rejouent ce chemin : `--debugshot` capture le
menu et vidage son arborescence (rectangles et textes de chaque contrôle) dans
la console, `--debugrun` clique le bouton et vérifie que le menu survit, que ses
vérifications se remplissent et que la partie repart.

## Tests

```bash
godot --headless --import                    # compile tout le projet
godot --headless --script res://tools/SmokeTest.gd   # 575 verifications
godot --headless --uitest --distance=3       # 93 verifications d'interface
godot --headless --script res://tools/NetTest.gd     # 68 verifications reseau
godot --headless --script res://tools/CheckContent.gd # 30 : contenu atteignable
godot --headless --script res://tools/CheckLights.gd  # 15 : eclairage dynamique
godot --headless --script res://tools/CheckTitle.gd   # 22 : relief du menu
godot --headless --script res://tools/TileDump.gd -- grass_side   # une tuile en ASCII
godot --headless --script res://tools/TreeDump.gd                   # un arbre en coupe
godot --headless --script res://tools/IconDump.gd                    # les icones de blocs
```

Le test de fumée vérifie le registre de blocs, la génération (dont son
déterminisme), le maillage d'un cube isolé et de ses cas limites, l'orientation
de chaque triangle, les bornes des UV, l'exclusion de l'eau de la collision, le
raycast DDA, les recettes, l'inventaire, le codec de sauvegarde et l'atlas. Puis
il démarre un vrai `World` et joue le rôle du joueur : chargement du disque,
cassage d'un bloc, pose d'une torche, remaillage, sauvegarde et déchargement. Il
verrouille aussi le **feuillage plein** : la règle de cullage, la tuile de
feuillage sans pixel transparent, et le nombre de faces qu'un volume de feuilles
doit produire (162 pour 27 blocs, faces internes comprises — 54 serait une
coque creuse, c'est-à-dire du ciel au milieu de l'arbre).

Le test d'interface (`--uitest`) joue dans le vrai jeu : glisser-déposer et
partage de piles, fabrication 2×2 et 3×3, ouverture et fermeture des écrans,
dégâts de chute, pomme, mort et réapparition, règles d'apparition des mobs,
retour à l'écran titre puis relance d'une partie depuis ce même écran titre. Il
partage son code avec le menu de diagnostic (`Diagnostics` + `Checklist`) : un
seul test, deux portes d'entrée — la console au démarrage, le menu en partie.

Le test réseau (`NetTest`) lance de **vrais processus** — un hôte et deux
clients, car deux `MultiplayerAPI` ne peuvent pas coexister dans un seul
`SceneTree` — et vérifie l'admission, l'annonce de tenue, les positions
diffusées, le salon d'attente, le chat, et le **retour arrière** d'une édition
que l'hôte refuse : le client doit avoir reçu l'ordre de revenir, et son calque
ne doit plus porter le bloc refusé.

Trois tests de plus, plus courts, répondent à des questions que les trois
premiers ne posent pas. Les checks d'une suite vérifient des invariants de
structure — un bloc déclaré mais que rien ne génère, une recette que
`match` ne reconnaît jamais, une lumière qui saute de torche à chaque pas :
tout cela passe le test de fumée.

- **`CheckContent.gd`** fait tourner le générateur et compte vraiment. Il génère
  une grille de chunks et vérifie que l'or et le diamant y sont, **et qu'ils
  n'y sont qu'à la bonne profondeur** : un minerai présent à y = 90 ne
  rendrait pas la descente payante. Puis il fait passer les quatre nouvelles recettes
  dans le moteur d'appariement, dont les briques dans une disposition en S —
  qu'aucun schéma en ligne ou en colonne ne peut décrire, et qui ne passerait
  donc pas si la recette avait été écrite en forme. Enfin il rejoue la règle de
  `Game.on_block_broken` palier par palier : le diamant se refuse bien à la
  pioche en fer, s'accepte à la pioche en diamant, et l'escalier des minerais
  reste croissant.
- **`CheckLights.gd`** pilote le vrai composant : il pose des blocs dans un
  monde factice et appelle `_reassign` et `_advance` comme le jeu le ferait. Il
  vérifie qu'une torche garde sa lumière sur cinq cases de marche, qu'une
  source retirée s'éteint **sur place** et ne libère son emplacement qu'une
  fois noire, qu'une torche lointaine n'évince pas une proche, et que la lave
  et la torche n'ont ni la même couleur ni la même portée.
- **`CheckTitle.gd`** instancie l'écran titre, fabrique l'atlas pour que le
  relief ait ses vraies tuiles, et regarde ce qui est réellement dessiné : le
  profil boucle-t-il sur une période, les arbres sont-ils posés sur des
  sommets et espacés, les deux plans se distinguent-ils, et le relief repose-t-il
  sur la même ligne de sol que la bande d'herbe.

Tous trois se lancent en `--script`, où il n'y a pas d'autoload : c'est aussi
pourquoi `TorchLights` prend sa cible dans un champ `follow` plutôt que de lire
`Game.player`.

## Options en ligne de commande

Au-delà des cinq options de jeu (`--seed`, `--load`, `--distance`, `--shader`),
qui sont sur la [page d'accueil](../README.md#lancer-le-jeu), le projet accepte
des modes de diagnostic et de capture :

```bash
godot --screenshot --seconds=10        # diagnostic : monde en ASCII puis sortie
godot --loadingshot                    # capture l'ecran de chargement
godot --titletest --seconds=2          # capture les 5 panneaux du titre
godot --fpshot                         # capture la vue subjective (design)
godot --pauseshot                      # capture pause et inventaire (2 PNG)
godot --titletest                      # idem, 5 PNG (voir plus bas)
godot --debugshot                      # capture le menu de debug (F4)
godot --debugrun                       # lance les verifications par le menu
godot --uitest                         # 93 verifications d'interface
```

godot --screenshot --seconds=10        # diagnostic : monde en ASCII puis sortie
godot --loadingshot                    # capture l'ecran de chargement
godot --titletest --seconds=2          # capture les 5 panneaux du titre
godot --fpshot                         # capture la vue subjective (design)
godot --pauseshot                      # capture pause et inventaire (2 PNG)
godot --titletest                      # idem, 5 PNG (voir plus bas)
godot --debugshot                      # capture le menu de debug (F4)
godot --debugrun                       # lance les verifications par le menu
godot --uitest                         # 93 verifications d'interface
```

Les cinq modes de capture exigent une fenetre : en `--headless`,
`RenderingServer.frame_post_draw` ne se declenche jamais et la capture n'a rien
a lire. Le PNG est ecrit dans `user://cubecraft_capture.png`
(`~/Library/Application Support/Godot/app_userdata/Cubecraft` sur macOS).
`--pauseshot` en ecrit deux, nommes : `cubecraft_pause.png` et
`cubecraft_inventory.png` — c'est la seule facon de verifier a l'œil le design
des icones d'inventaire. `--titletest` en ecrit cinq, un par panneau du menu de
lancement (`cubecraft_titre_main.png`, `..._new`, `..._worlds`, `..._options`,
`..._net`) : les reglages et la liste des mondes ne s'ouvrent qu'au clic, et sans
ce mode ils ne seraient jamais regardes.

`--fpshot` est la capture de **contrôle du design** et non de diagnostic : elle
place le joueur debout devant la forêt la plus proche, à la même hauteur d'œil
que dans une partie, y pose un cochon et un zombie (gelés : leur IA les
éloignerait et le soleil brûlerait le zombie), et fige les fissures de minage sur
le bloc visé — une cassure ne dure qu'une fraction de seconde, elle ne se
capture pas au hasard.

## Codes de sortie

Les cinq suites de `tools/`, ainsi que `--uitest`, rendent un code de sortie
exploitable : `0` si tout est passé, `1` sinon. C'est ce que lit la CI, et ce qui
lui permet de tomber sur un échec au lieu d'afficher un succès.

Deux suites sont **sensibles au temps qui passe** : sous charge CPU — deux
tournes en parallèle, ou un simple `godot` lancé juste avant — l'interface peut
rater le contrôle des fissures de minage, et le réseau dépasser son délai. Un
échec isolé là-dessus est du bruit : la CI réessaie chaque suite trois fois, et
seule une répétition fait tomber le build.
