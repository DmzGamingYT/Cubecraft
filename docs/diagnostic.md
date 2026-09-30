<!-- Page de documentation Cubecraft : Menu de diagnostic et suites de tests.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

## Menu de diagnostic

`F4` (ou `Ctrl`+`Alt`+`D`) ouvre un panneau de diagnostic **depuis la partie en
cours**, à l'écran titre comme en jeu. Il n'invente rien : il rassemble ce que le
jeu evaluait jusqu'ici dans une console invisible.

- **Informations** : graine, portée, FPS, position, chunks, torches, mémoire,
  draws, durée de session.
- **Performances** : ce que l'information ci-dessus ne dit pas — *ce que cela
  coûte*. Le temps d'image (moyenne glissée et pire image depuis l'ouverture),
  le coût de la planification du disque (dernier passage, moyenne, rythme par
  seconde), puis les chunks présents, maillés et en attente, et les torches que
  le monde suit face à celles que le pool de seize lumières sert réellement.
  Les compteurs repartent de zéro à chaque ouverture : sinon le pic resterait
  affiché sur le plus mauvais moment de la partie, même après un chargement
  rapide.
- **Vérifications du jeu** : les 105 vérifications d'inventaire, de fabrication,
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
godot --headless --script res://tools/SmokeTest.gd   # 686 verifications
godot --headless --uitest --distance=3       # 105 verifications d'interface
godot --headless --script res://tools/NetTest.gd     # 67 verifications reseau
godot --headless --script res://tools/CheckContent.gd # 28 : contenu atteignable
godot --headless --script res://tools/CheckLights.gd  # 15 : eclairage dynamique
godot --headless --script res://tools/CheckTitle.gd   # 26 : relief du menu
godot --headless --script res://tools/CheckWorld.gd   # 7 : cycle de vie des taches
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

C'est aussi là que se vérifie le **tableau de bord de performances**, parce que
ses quatre lignes sont des nombres, et qu'un nombre faux ne se voit pas sur une
capture d'écran : il faudrait le lire. La section ouvre le menu sur une partie
réelle, pose une torche pour que la ligne des lumières vaille autre chose que
zéro, laisse le panneau mesurer trente images, puis compare le texte affiché —
ligne par ligne — aux chiffres relevés ailleurs. Deux précautions rendent la
comparaison exacte plutôt que probable : les valeurs attendues sont relevées
juste avant l'appel, sans aucune attente au milieu (le monde ne peut pas se
recharger dans l'intervalle), et la planification est figée le temps de la
lecture. Le comptage des chunks et celui des lumières sont comparés à des
**recomptages manuels**, jamais à la fonction que le panneau appelle : sinon une
faute de cette fonction afficherait la même valeur des deux côtés, et les deux
cotes seraient d'accord pour rien.

**Observer un état à la cadence où il écrit.** Une seule vérification
était instable, et la cause était instructive : elle demandait « les fissures
sont-elles affichées ? », un simple drapeau, échantillonné une fois par image
physique. Or les fissures sont posées dans `Player._process` — une image de
rendu — et le test observait à une autre cadence. Elle lisait donc l'état en
retard, et l'overlay se déplace dès que l'ancien bloc cède : un
échantillon tardif, posé sur le bloc suivant, contaminait la position
comparée. Le bloc cédait en 3 s et le test ratait une fois sur vingt.

Le remède tient en deux gestes. On lit l'**état de progression**
(`BreakOverlay.stage()`) plutôt qu'un drapeau : un étage se lit, là où une
visibilité peut être posée et effacée entre deux lectures sans qu'aucune ne la
voie. Et on n'échantillonne que ce qui concerne la cible, au lieu de retenir la
position du dernier échantillon. Une vérification qui lit à la mauvaise
cadence n'est pas déterministe par hasard : elle est fausse une fois sur
N, et le rattrapage par un `print` la masque.

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
- **`CheckWorld.gd`** garde un invariant qui a coûté cher à retrouver : la
  destruction d'un monde **vidange ses files de tâches** avant de mourir. Cette
  boucle de deux secondes, dans `_exit_tree`, ressemble à de la politesse — le
  résultat sera de toute façon jeté avec le monde. On l'a supprimée, et le
  moteur s'est mis à pendre à la fermeture : `SmokeTest` terminait ses
  vérifications puis ne rendait jamais la main, bloqué sur une variable de
  condition du `WorkerThreadPool`. Le test appelle `_exit_tree` directement et
  vérifie que les deux files reviennent vides — le monde n'est libéré qu'après,
  une fois le travail terminé, pour qu'une régression se lise comme un échec et
  non comme un blocage.

Tous quatre se lancent en `--script`, où il n'y a pas d'autoload : c'est aussi
pourquoi `TorchLights` prend sa cible dans un champ `follow` plutôt que de lire
`Game.player`, et pourquoi la vérification du tableau de bord vit dans
`--uitest` — le menu y lit l'autoload `Game`, il n'est pas instanciable en
mode `--script`. `CheckWorld` fait exception côté CI : il rend son verdict mais
le moteur s'arrête sur un `abort` en quittant (voir
[limites.md](limites.md)), donc son code de sortie ne peut rien tenir dans le
build — il reste lancé à la main.

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
godot --uitest                         # 94 verifications d'interface
```

godot --screenshot --seconds=10        # diagnostic : monde en ASCII puis sortie
godot --loadingshot                    # capture l'ecran de chargement
godot --titletest --seconds=2          # capture les 5 panneaux du titre
godot --fpshot                         # capture la vue subjective (design)
godot --pauseshot                      # capture pause et inventaire (2 PNG)
godot --titletest                      # idem, 5 PNG (voir plus bas)
godot --debugshot                      # capture le menu de debug (F4)
godot --debugrun                       # lance les verifications par le menu
godot --uitest                         # 94 verifications d'interface
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
