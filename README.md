# Cubecraft

Un jeu de type Minecraft en voxel, écrit en GDScript pour **Godot 4.7**, et
**entièrement procédural** : les textures, les sons, le terrain, les arbres et
les grottes sont tous calculés par le code au démarrage.

Le seul dossier d'images du dépôt, `assets/kenney/`, est un pack **CC0** de
Kenney Vleugels qui remplace *quelques* tuiles et icônes par des dessins
prêts à l'emploi. Il est purement optionnel : supprimer le dossier rend le jeu
exactement tel qu'il était, tout simplement un peu moins dessiné
(`scripts/gen/ExternalTiles.gd`, licence dans `assets/kenney/LICENSE-kenney.txt`).

## Lancer le jeu

```bash
godot                                  # jouer
godot --seed=1234                      # choisir son monde
godot --load                           # reprendre la sauvegarde
godot --distance=7                     # portee de rendu initiale
godot --shader=1                       # rendu au lancement (1 chaleureux, 2 vif)
```

```bash
godot --screenshot --seconds=10        # diagnostic : monde en ASCII puis sortie
godot --loadingshot                    # capture l'ecran de chargement
godot --titletest --seconds=2          # capture l'ecran titre
godot --fpshot                         # capture la vue subjective (design)
godot --pauseshot                      # capture pause et inventaire (2 PNG)
godot --debugshot                      # capture le menu de debug (F4)
godot --debugrun                       # lance les verifications par le menu
godot --uitest                         # 86 verifications d'interface
```

Les cinq modes de capture exigent une fenetre : en `--headless`,
`RenderingServer.frame_post_draw` ne se declenche jamais et la capture n'a rien
a lire. Le PNG est ecrit dans `user://cubecraft_capture.png`
(`~/Library/Application Support/Godot/app_userdata/Cubecraft` sur macOS).
`--pauseshot` en ecrit deux, nommes : `cubecraft_pause.png` et
`cubecraft_inventory.png` — c'est la seule facon de verifier a l'œil le design
des icones d'inventaire.

`--fpshot` est la capture de **contrôle du design** et non de diagnostic : elle
place le joueur debout devant la forêt la plus proche, à la même hauteur d'œil
que dans une partie, y pose un cochon et un zombie (gelés : leur IA les
éloignerait et le soleil brûlerait le zombie), et fige les fissures de minage sur
le bloc visé — une cassure ne dure qu'une fraction de seconde, elle ne se
capture pas au hasard.

## Commandes

| Touche | Action |
|---|---|
| `Z Q S D` / `W A S D` / flèches | se déplacer (AZERTY et QWERTY) |
| `Espace` | sauter / monter en vol |
| `Maj` | courir |
| `Ctrl` | s'accroupir / descendre en vol |
| `F` | activer le vol |
| Clic gauche (maintenu) | miner |
| Clic droit | poser un bloc — ouvrir l'établi si on le vise |
| Clic molette | prendre le bloc visé |
| `1`…`9`, molette | changer d'emplacement |
| `E` | inventaire (fabrication 2×2) |
| `G` | jeter l'objet tenu |
| `F3` | informations (FPS, position, biome, chunks) |
| `F4` ou `Ctrl`+`Alt`+`D` | menu de diagnostic (voir plus bas) |
| `F5` | sauvegarder |
| `F6` | rendu : naturel, chaleureux, vif |
| `Échap` | menu pause |

Les touches sont enregistrées par `InputSetup` au démarrage, avec des
`physical_keycode` : sur un clavier AZERTY, `{Z}` et `{W}` déclenchent « avancer ».

## Boucle de jeu

Miner un bloc demande le bon outil : à mains nues on ne obtient rien de la
pierre ni des minerais. Un bloc de bois donne 4 planches, deux planches en
colonne donnent 4 bâtons, et ainsi de suite jusqu'à la pioche en fer.

| Recette | Résultat |
|---|---|
| 1 brique | 4 planches |
| 2 planches (verticales) | 4 bâtons |
| 4 planches | 1 établi |
| bâton + charbon | 4 torches |
| 3 planches + 2 bâtons | pioche en bois (minerai de charbon) |
| 3 pierre taillée + 2 bâtons | pioche en pierre (minerai de fer) |
| fer brut + charbon | lingot de fer |
| 3 lingots + 2 bâtons | pioche en fer |
| 9 lingots | 1 bloc de fer |

Clic droit sur l'établi (posé ou tenu) pour la grille 3×3 complète.

## Écran titre et chargement

Rien n'est dessiné à la main : le ciel, le soleil, les nuages et le sol du menu
sont des `ColorRect` et des textures générées par code — dégradés d'une colonne,
lueur et vignette en 64×64, tuiles de 16×16 pour l'herbe et la terre.

- **Le sol du menu est celui du jeu** : la bande d'herbe et la bande de terre
  affichent les tuiles de l'atlas, l'herbe colorée par le tint de plaine — le
  menu et le monde se répondent au lieu de se ressembler vaguement. L'atlas
  n'existant pas hors du jeu, l'écran retombe sur un bruit local quand il est
  instancié par le test de fumée.
- **Logo détouré** : huit tranches décalées (au lieu de six) donnent l'épaisseur,
  et un contour sombre — `font_outline_color` du thème — détache les lettres du
  ciel, ce qui le fait lire comme un logo gravé et non comme un titre écrit.
- **Une seule colonne large** porte le bandeau du logo, la rangée des deux cartes
  et la ligne d'aide, et c'est elle qui est centrée sur l'écran. Le mot est mesuré
  sur la police du thème ; l'accroche jaune occupe une zone de largeur **fixe** à
  sa droite. Le mot et l'accroche forment donc un bloc centré ensemble, et une
  accroche ne peut jamais passer sur les lettres, même quand elle change toutes
  les 5,5 secondes.
- **Fondu depuis le noir** à l'ouverture, **fondu au noir** quand une partie est
  lancée : le passage au chargement n'est jamais une coupure sèche.
- **Logo empilé** en six tranches décalées, du clair vers le sombre, qui flotte
  doucement ; le texte jaune incliné sautille et se renouvelle sans jamais
  répéter deux fois le même.
- **Soleil carré** avec sa **lueur radiale** générée en 64×64 : l'empilement de
  carrés translucides d'avant laissait voir ses arêtes dans le coin du ciel.
- **Deux couches de nuages** (les lointains plus petits, plus pâles, plus lents).
  La profondeur vient du parallaxe, pas d'un filtre. Les nuages proches restent
  presque opaques : deux blocs translucides qui se chevauchent s'éclaircissent à
  l'intersection, et le nuage se lirait comme une suite de rectangles gris.
  Chaque bloc porte sa **face du dessus plus claire et son ombre de dessous** :
  c'est ce qui en fait un empilement de cubes plutôt qu'un rectangle de papier.
- **Le décor entier se replace au redimensionnement** (`_layout()`) : sol,
  brume, soleil, nuages et bloc de menu sont recalculés à partir de la taille de
  la fenêtre, donc rien ne reste dans son coin.
- **Aperçu du personnage** à droite : il respire, marche sur place, et **pivote à
  la souris** — on clique dessus et on glisse, comme le modèle qu'on retourne
  dans l'inventaire de Minecraft. Il ne tourne plus tout seul : il s'arrête sur
  la face qu'on lui demande, ce qui est la seule façon de comparer un dos ou une
  manche. Une ligne discrète sous l'aperçu (« glisser pour tourner ») le dit.
  Les flèches changent de tenue **sans reconstruire le corps**,
  et la tenue choisie part vers `Main` (`skin_changed`) : c'est celle du joueur,
  celle que le salon affiche et que les autres verront.
- **Boutons en cascade** à l'ouverture, panneau « Nouveau monde » en fondu.
- **Écran de chargement** : barre de progression plate façon Minecraft branchée
  sur le nombre de chunks réellement prêts, compteurs de files, et un conseil de
  jeu qui tourne toutes les 4,5 secondes.

## Architecture

```
scenes/Main.tscn          une seule scène ; tout le reste est construit en code
scripts/
  Main.gd                 assemblage, chargement, boucle, diagnostic
  core/    Vox            constantes et indexation des chunks
           Blocks/Items   catalogues (18 blocs, 7 objets, 1 bloc par bloc)
           Recipes        recettes + moteur d'appariement
           Inventory      36 emplacements, barre rapide
           Game           autoload : pause, écrans, sauvegarde, liaison scène
           InputSetup     autoload : touches
           Checklist      journal de vérifications, partagé test et menu
           Diagnostics    les 86 vérifications, jouables depuis le menu (F4)
           Net            autoload ENet : salon, admissions, diffusion
           SaveSystem     JSON compressé dans user://
           Assets         registre statique des textures et matériaux
  world/   WorldGen       heightmap, biomes, cavernes, minerais, arbres
           ChunkMesher    culling de faces + occlusion ambiante, 3 surfaces
           Chunk          données, maillage et collision d'une colonne 16×16×96
           World          streaming, files de tâches, édition
           VoxelRaycast   parcours DDA pour casser et poser
  player/  Player         déplacement, minage, pose, vie et faim
           ItemEntity/Fx/TorchLights
           PlayerBody     personnage articulé en six boîtes texturées
           BreakOverlay   fissures du bloc miné, dix étapes dans une texture
  mobs/    Mob            cochon et zombie : IA, dégâts, brûlure au soleil
           Mobs           apparition, entretien et nettoyage du groupe
           MobSkin        grain et maillage des créatures, à l'échelle du monde
  net/     Net            autoload ENet : admission, salon, poses, éditions
           RemotePlayer   avatar distant : même corps, animé par le réseau
  ui/      HUD, barre rapide, écrans de conteneur, établi, enchantement,
           menu pause, écran de mort, overlay de debug,
           DebugMenu  panneau de diagnostic (F4), journal et vérifications
           PostFx     post-traitement d'écran cyclable (F6), un seul passage
           Lobby      salon d'attente en réseau
           TitleScreen    menu, ciel procédural, logo et accroche animés
           SkinPreview    aperçu du personnage, dessiné à la main
           UiKit          charte : plaques, boutons, champ, barre de progression
  world/   Weather        pluie, neige, brouillard selon biome et altitude
  gen/     TextureFactory atlas pixel-art   BlockIcons  icones de blocs isometriques
           SoundFactory  bruitages + musique
           SkinFactory  skin 64×64 peinte par code, format Minecraft
           Sounds         autoload : banque de bruitages, voix 3D, musique
tools/SmokeTest.gd        test de bout en bout, sans écran
           NetTest/NetPeer  test réseau à trois processus (hôte + 2 clients)
```

### Décisions à connaître

**Indexation en colonnes.** `Vox.index(x, y, z) = (z * 16 + x) * 96 + y`. Une
colonne verticale est donc contiguë en mémoire, ce qui permet de recopier le
volume de travail du mailleur par `memcpy`. Ce layout est imposé par le volume de
padding (18 × 18 × 96) : c'est le point le plus subtil du projet, et le changer
sans changer le mailleur casse silencieusement tout le rendu.

**Maillage.** Culling de faces + occlusion ambiante à 4 niveaux calculée sur les
trois voisins diagonaux. Trois surfaces par chunk : opaque, eau (alpha) et
alpha-cut (feuillage, torches en croix). La collision reprend exactement
les mêmes triangles, moins l'eau.

**Casser un bloc se voit sur le bloc.** `BreakOverlay` pose un cube d'un
centième de bloc plus grand que la cible, avec les **dix étapes de fissures de
Minecraft dans une seule texture de 16×160** ; changer d'étape ne déplace que
`uv1_offset`, donc rien n'est construit en cours de partie. Ses faces arrière
tombent dans le bloc et échouent au test de profondeur : seule la face qu'on
regarde se fend. Sans lui, le minage ne se lisait qu'à la barre du réticule, et
le bloc visé restait intact jusqu'à disparaître d'un coup.

Le feuillage passe dans la surface alpha-cut, mais sa tuile est **entièrement
peinte** : les creux y sont des taches vert sombre, pas des pixels manquants.
Percer la tuile était sans effet possible — `face_visible` masque les faces
internes du feuillage, donc derrière la surface d'une couronne il n'y a rien, et
le moindre trou donnait directement sur le ciel. Le feuillage « ajouré » se
trouve dans la géométrie des couronnes, pas dans la peinture.

Ces creux sont **petits et nombreux** (des amas de deux pixels), et non plus
quatre taches noires de trois pixels : au premier réglage, la couronne se lisait
comme un arbre malade. La couronne de chêne a gagné un quatrième étage et un
sommet en croix, ce qui la fait ronde au lieu d'être une assiette verte au bout
d'un bâton. Le tronc porte des côtes verticales continues et deux veines, son
dessus un cerne d'écorce : un tronc sans relief ressemble à un assemblage de
rayures.

**Une couronne est un volume, pas une coque.** `face_visible` masquait les faces
internes du feuillage, si bien qu'une couronne de feuilles n'était qu'une
**coque creuse** : comme la face interne de cette coque est éliminée elle aussi,
le moindre bloc manquant — et il en manque, la silhouette est irrégulière par
construction — ouvrait un trou **traversant**, et l'on voyait le ciel au milieu
de l'arbre. Les feuilles se dessinent maintenant entre elles ; le peu de trous
qui reste montre des feuilles, ce qui est ce qu'on attend d'un feuillage.

L'**épicéa** avait un défaut plus franc encore : ses rayons se comptaient depuis
le haut (`top - 1 - layer`), donc l'étage large se retrouvait au sommet et les
étages étroits en dessous — un parasol retourné, avec le ciel visible par
dessous. Un cône large en bas se compte depuis le bas. `TreeDump` imprime la
coupe verticale d'un arbre de chaque espèce, parce qu'aucun test ne voit une
forme.

Les **créatures** ont enfin une matière. `MobSkin` génère un grain de 16×16 —
un bloc du monde — et les boîtes sont des maillages écrits à la main dont les UV
valent la taille de la face **en blocs** : un texel de cochon fait un texel de
terrain. Une `BoxMesh` plaquait le même 0..1 sur les six faces, si bien que le
grain changeait de finesse d'un côté à l'autre. Les pattes pendent désormais
d'une hanche (un pivot en haut, la boîte dessous) comme celles du joueur.

**L'eau est la seule matière animée.** Elle n'a pas de tuile dans l'atlas : elle
a sa propre texture de 16 × 16, repeinte image par image à 12 images/s, ce que
le maillage désigne par des UV locales. C'est 1 ko par image au lieu des 49 ko
qu'aurait coûté de repeindre l'atlas entier. Le motif est une somme de trois
harmoniques à coefficients **entiers**, ce qui le rend périodique sur une
tuile : sans cela, la surface se raccordait mal d'un bloc à l'autre et la boucle
de l'animation claquait en repartant. Les deux sont vérifiées par le test de
fumée, parce qu'une couture dans l'eau ne dit rien à la console.

**Orientation des faces.** Godot n'affiche une face que si ses sommets sont dans
le sens trigonométrique vu de l'extérieur. Inverser cet ordre rend le terrain
entier invisible sans la moindre erreur dans la console : c'est vérifié par le
test de fumée, qui recalcule le produit vectoriel de chaque triangle.

**Multi-threading.** Génération et triangulation tournent sur `WorkerThreadPool`.
Chaque tâche travaille sur une copie du volume de travail et rapporte un numéro
de version : un résultat périmé est jeté, ce qui supprime toute course entre
l'édition d'un bloc par le joueur et le remaillage automatique. Un chunk n'est
maillé que lorsque ses 8 voisins sont générés, faute de quoi ses faces de
bordure seraient dessinées contre de l'air fictif.

**Édition en mémoire.** Un chunk modifié par le joueur est conservé après
déchargement, et dans la sauvegarde : il est zstd + base64 dans le JSON, donc
relativement compact, et la terre procédurale n'occupe aucune place.

## Personnage et tenues

Le joueur n'est pas une boîte : c'est un personnage articulé, fait de six
boîtes texturées, et la même classe sert partout où un corps doit apparaître.

- **`PlayerBody`** construit six membres — tête, buste, deux bras, deux jambes —
  chacun sur un `Node3D` pivotant placé à l'épaule ou à la hanche, la boîte
  étant un enfant décalé vers le bas. Pivoter le membre fait donc tourner
  l'articulation, pas le centre de la boîte : les bras peuvent se balancer sans
  que l'épaule se détache du buste.
- Les proportions sont celles de Minecraft, en blocs : tête de 0,5, membres de
  4 pixels de large, et **1,80 bloc de haut au total** — exactement la hauteur
  de la hitbox du joueur. Le facteur `PX = 1,8 / 32` est le seul endroit où
  l'erreur se vois : il décale la tête à côté du buste au lieu de la poser
  dessus.
- La boîte n'est pas une `BoxMesh`, qui n'accepte pas d'UV : l'`ArrayMesh` est
  écrit à la main, face par face, avec le rectangle de skin correspondant, et
  les triangles dans le sens trigonométrique vu de l'extérieur — la même règle
  que pour le terrain.
- `animate(delta, speed, grounded)` pilote tout : la fréquence du balancement
  suit la vitesse, les membres sont en opposition de phase (c'est ce qui rend
  la marche lisible sur une silhouette de 4 pixels), le buste se penche en
  course, les bras se replient en l'air, et un bras levé (minage, pose) prend le
  dessus sur l'animation de marche. Au repos il ne reste que la respiration.

**`SkinFactory`** peint une skin 64×64 au format officiel de Minecraft, pixel
par pixel : visage, cheveux, col de chemise, ceinture, manches, bottes. Trois
tenues — **Steve**, **Alex**, **Mineur** — chacune définie par ses couleurs et
un `variant` qui change la forme des yeux, du nez et de la bouche. La
disposition des rectangles est celle du format officiel, ce qui permet
d'utiliser plus tard une vraie skin importée sans toucher au maillage :
`PlayerBody` ne connaît que les rectangles, jamais la peinture. Le grain de
tissu n'est pas tiré dans un hasard global mais dérivé de la position du
pixel : une tenue peinte deux fois est identique, sur cette machine comme
sur une autre.

Le personnage est visible dans trois endroits, et nulle part en vue subjective :

| Où | Comment |
|---|---|
| Écran titre | `SkinPreview` : le corps respire et suit la souris au clic-glisser |
| Salon d'attente | avatars 3D réels, disposés en cercle |
| En jeu, chez les autres | `RemotePlayer` : le même corps, animé par le réseau |

En première personne on ne voit pas son propre corps : il n'y a pas de caméra
à la troisième personne.

## Rendu, et le shader de la touche F6

`PostFx` propose trois modes, cyclés par **`F6`** (ou par les flèches du menu
pause), et le mode courant s'affiche une seconde et demie à l'écran :

| Mode | Ce qu'il fait |
|---|---|
| Naturel | rien — c'est l'image du jeu, et le premier du cycle |
| Chaleureux | saturation +16 %, contraste +8 %, teinte chaude, vignette douce |
| Vif | saturation +34 %, contraste +16 %, vignette légère |

Le shader est **un seul passage plein écran, une seule lecture de texture et
une vingtaine d'opérations arithmétiques** : pas de flou, pas de seconde passe,
aucune lecture de voisin. Il lit l'image déjà rendue
(`hint_screen_texture`) et n'écrit qu'une couleur par pixel — saturation autour
de la luminance perçue, contraste, lumière, teinte, puis vignette. Tout est
réglé par uniformes, donc changer de mode ne recompile rien : les presets sont
des jeux de flottants.

La couche est posée **au-dessus de la 3D et au-dessous du HUD** (niveau 5, le
HUD est à 10) : l'interface garde ses couleurs exactes, et la vignette
n'assombrit pas un texte d'inventaire. Elle existe dès l'écran titre, donc la
touche répond partout, et `--shader=N` démarre directement sur un mode.

## Musique

La musique du menu est synthétisée comme le reste du jeu — aucun fichier
audio n'est importé.

- `SoundFactory.menu_music()` écrit **quatre mesures de quatre secondes**, soit
  une boucle de 16 s à 60 pulsations par minute. La durée est divisible par
  quatre pour que chaque mesure tombe exactement sur une seconde d'échantillons.
- Progression **do – la – fa – sol** : les quatre accords les plus stables en
  majeur, et les plus invariants, ce qui fait qu'un auditeur ne s'en lasse pas.
- Trois voix par mesure : une **nappe** de trois notes tenues (attaque longue,
  relâche courte pour ne pas déborder sur la mesure suivante), une **basse** sur
  le premier temps et à la mi-mesure, et un **arpège** de huit notes en
  remontant puis redescendant, la quinte jouée une octave plus haut pour que le
  mouvement reste audible aux aigus. Un bruit de fond très faible désaccorde
  l'aigu : sans lui la nappe est d'une pureté suspecte.
- Les extrémités sont fondues, et le flux est bouclé en avant sur ses 16 s.

La lecture est pilotée par l'autoload `Sounds`, sur un lecteur unique et
**séparé des huit voix 3D** des bruitages : la musique ne doit jamais se
mélanger à un bruit de pas, ni dépendre de la position de la caméra. Elle
démarre à **−9 dB**, **0,6 s après** l'affichage du menu — le fondu d'ouverture
dure 0,55 s, et une musique lancée dessous se ferait couper par l'entrée — et
s'arrête en fondu de 0,3 s au départ vers une partie. Le salon d'attente fait
exprès le silence : c'est là qu'on attend les autres joueurs.

## Multijoueur

Hôte et clients en **ENet**, sur le réseau local, port 27015, huit joueurs au
maximum. Le monde étant entièrement procédural, **aucune donnée de terrain ne
circule** : l'hôte n'envoie que sa graine et sa portée de rendu, et chaque
client régénère un terrain identique. Ce qui doit voyager est court, et son
mode d'envoi est choisi pour ce qu'il protège :

| Ce qui circule | Mode | Pourquoi |
|---|---|---|
| Graine, portée, point d'apparition | fiable | sans eux, les joueurs ne marcheraient pas sur le même monde |
| Poses des joueurs, 15 Hz | non fiable, ordonné | une pose perdue est remplacée 70 ms plus tard ; une pose fiable qui s'accumule fait saccader tout le monde |
| Editions de blocs | fiable | un bloc cassé perdu laisserait un trou jusqu'à la fin de la partie |
| Messages de chat | fiable | l'hôte filtre et retransmet, c'est lui qui tient l'ordre |

Un client ne parle **jamais** directement à un autre client : tout passe par
l'hôte, faute de quoi chacun entendrait les messages dans un ordre différent.
L'hôte est seul autorisé à écrire dans le monde, et il arbitre — deux clients
cassant le même bloc au même instant ne peuvent pas produire deux versions.

Les éditions sont conservées dans un **calque** côté client et rejouées à chaque
chargement de chunk. Sans lui, un chunk régénéré après déchargement reverrait
son état d'origine, et le joueur verrait un mur se dresser devant lui.

**Le salon d'attente** est la phase entre l'admission et le monde : tout le
monde est admis, personne n'a encore de terrain — donc rien ne coûte. On s'y
choisit un pseudo et sa tenue, on voit les vrais avatars des autres en 3D, on
regarde la liste des présents, et l'hôte seul appuie sur « Lancer la partie ».

Le transport du chat existe et fonctionne, mais **aucune fenêtre de chat n'est
encore affichée** : le signal `chat_received` n'est connecté à aucun écran.
Seul l'hôte sauvegarde : écrire sur le disque, chez un client, un monde que
seul l'hôte détient fourrerait des blocs différents de ceux du serveur dans la
prochaine partie solo. Le test `NetTest` vérifie tout cela avec de vrais
processus — un hôte et deux clients, 66 vérifications.

## Menu de diagnostic

`F4` (ou `Ctrl`+`Alt`+`D`) ouvre un panneau de diagnostic **depuis la partie en
cours**, à l'écran titre comme en jeu. Il n'invente rien : il rassemble ce que le
jeu evaluait jusqu'ici dans une console invisible.

- **Informations** : graine, portée, FPS, position, chunks, torches, mémoire,
  draws, durée de session.
- **Vérifications du jeu** : les 86 vérifications d'inventaire, de fabrication,
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
godot --headless --script res://tools/SmokeTest.gd   # 496 verifications
godot --headless --uitest --distance=3       # 86 verifications d'interface
godot --headless --script res://tools/NetTest.gd     # 66 verifications reseau
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
diffusées et le salon d'attente.

## Limites connues

- Le multijoueur fonctionne en hôte/client sur ENet, avec un salon d'attente, mais
  reste minimal : pas de conversation, pas de whitelist, pas de reprise de
  session. Le monde est celui de l'hôte, ses modifications ne sont pas
  sauvegardées pour les clients.
- Le vol reste un mode de déplacement : les ressources sont toujours comptées.
- La torche éclaire grâce à un pool de 8 lumières réassignées en continu :
  au-delà, elle reste visible mais n'éclaire pas.
- La portée de rendu au-delà de 10 chunks devient coûteuse sur les machines
  modestes ; le menu pause permet de l'ajuster à la volée. L'ombre du soleil
  couvre 48 blocs et s'estompe au-delà : c'était 90, ce qui revenait à faire
  rendre au GPU une carte d'ombre bien plus grande que l'écran pour une
  précision invisible — c'est de loin le premier poste de chauffe du jeu.
- Les modes de capture (`--screenshot`, `--titletest`, `--pauseshot`,
  `--loadingshot`) exigent une fenêtre : en `--headless`, Godot ne rend rien et
  la capture attendrait indéfiniment.
- L'aperçu du personnage de l'écran titre **consomme les clics** : il reçoit le
  bouton gauche pour pivoter, donc un futur bouton posé par-dessus ne serait pas
  cliquable. La rotation se fait uniquement au bouton gauche — pas de glisser au
  bouton droit, ni de molette.
- L'inclinaison verticale est bornée à 14° : le pivot est aux pieds, plus fort le
  personnage bascule hors de son ombre et semble tomber.
- L'accroche de l'écran titre est dessinée depuis le bord gauche d'une zone de
  largeur fixe (148 px) : une accroche plus longue que la zone déborde vers la
  droite — jamais sur le logo, mais le couple mot + accroche n'est alors plus
  exactement centré.
