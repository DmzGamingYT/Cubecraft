<p align="center">
  <a href="docs/screenshots/vue.png">
    <img src="docs/screenshots/vue.png" width="880"
         alt="Vue en jeu : une foret de chenes, un cochon et un zombie devant le joueur">
  </a>
</p>

<h1 align="center">Cubecraft</h1>

<p align="center">
  <img alt="Godot 4.7" src="https://img.shields.io/badge/Godot-4.7-478cbf">
  &nbsp;
  <img alt="GDScript" src="https://img.shields.io/badge/GDScript-355570">
  &nbsp;
  <img alt="multijoueur ENet, 8 joueurs" src="https://img.shields.io/badge/multijoueur-ENet%20%C2%B7%208%20joueurs-4c8c4c">
  &nbsp;
  <img alt="Licence MIT" src="https://img.shields.io/badge/licence-MIT-355570">
</p>

Un jeu de type Minecraft en voxel, écrit en GDScript pour **Godot 4.7**, et
**entièrement procédural** : les textures, les sons, le terrain, les arbres et
les grottes sont tous calculés par le code au démarrage.

Le seul dossier d'images du dépôt, `assets/kenney/`, est un pack **CC0** de
Kenney Vleugels qui remplace *quelques* tuiles et icônes par des dessins
prêts à l'emploi. Il est purement optionnel : supprimer le dossier rend le jeu
exactement tel qu'il était, tout simplement un peu moins dessiné
(`scripts/gen/ExternalTiles.gd`, licence dans `assets/kenney/LICENSE-kenney.txt`).

## Captures

Les images viennent du jeu lui-même : chacune est produite par un mode de
capture en ligne de commande, jamais dessinée à la main. Elles se régénèrent
avec `godot --fpshot`, `godot --pauseshot` et `godot --titletest`, et vivent
dans [`docs/screenshots/`](docs/screenshots/).

<table>
  <tr>
    <td align="center" valign="top">
      <a href="docs/screenshots/titre.png">
        <img src="docs/screenshots/titre.png" width="300" alt="Écran titre">
      </a>
      <br><sub><b>Écran titre</b> — ciel, logo et aperçu du personnage</sub>
    </td>
    <td align="center" valign="top">
      <a href="docs/screenshots/inventaire.png">
        <img src="docs/screenshots/inventaire.png" width="300" alt="Inventaire et fabrication">
      </a>
      <br><sub><b>Inventaire</b> — 36 places, fabrication 2×2</sub>
    </td>
    <td align="center" valign="top">
      <a href="docs/screenshots/pause.png">
        <img src="docs/screenshots/pause.png" width="300" alt="Menu pause">
      </a>
      <br><sub><b>Menu pause</b> — sauvegarde, rendu, météo</sub>
    </td>
  </tr>
</table>

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

## Commandes

| Touche | Action |
|---|---|
| `Z Q S D` / `W A S D` / flèches | se déplacer (AZERTY et QWERTY) |
| `Espace` | sauter / monter en vol |
| `Maj` | courir |
| `Ctrl` | s'accroupir / descendre en vol |
| `F` | activer le vol |
| Clic gauche (maintenu) | miner |
| Clic droit | poser un bloc — ouvrir l'établi ou la table d'enchantement si on les vise |
| Clic molette | prendre le bloc visé |
| `1`…`9`, molette | changer d'emplacement |
| `E` | inventaire (fabrication 2×2) |
| `T` ou `/` | chat (ouvre la saisie, la souris est libérée) |
| `G` | jeter l'objet tenu |
| `F3` | informations (FPS, position, biome, chunks) |
| `F4` ou `Ctrl`+`Alt`+`D` | menu de diagnostic (voir plus bas) |
| `F5` | sauvegarder |
| `F6` | rendu : naturel, chaleureux, vif |
| `Échap` | menu pause |

Les touches sont enregistrées par `InputSetup` au démarrage, avec des
`physical_keycode` : sur un clavier AZERTY, `{Z}` et `{W}` déclenchent « avancer ».

### Manette

Le jeu se joue à la manette, sans réglage : la correspondance est dans
`InputSetup`, à côté du clavier.

| Manette | Action |
|---|---|
| Stick gauche | se déplacer |
| Stick droit | regarder (la vitesse suit l'inclinaison) |
| `A` | sauter / monter en vol |
| `B` | jeter l'objet tenu |
| `X` | inventaire |
| `Y` | activer le vol |
| `LB` / `RB` | poser un bloc / miner |
| `LT` / `RT` | prendre le bloc visé / emplacement suivant |
| Croix | parcourir les menus, `Start` ouvre la pause |

Une manette branchée est signalée en bas à droite de l'écran de lancement.
La navigation des menus passe par le focus : la croix déplace le rectangle
jaune, `A` valide, `B` ou `Start` revient en arrière.

Souris et stick se marchent dessus s'ils tournent en même temps. Celui qui
n'a pas bougé depuis le dernier clichage cède la main : **la souris garde
le regard pendant 250 ms après chaque mouvement**, puis le stick droit
reprend. Ce quart de seconde compte : le stick était neutralisé dès
quand la souris était capturée — c'est-à-dire pendant toute la partie — et
la visée à la manette n'existait en pratique que le temps d'une pause.

## Écran de lancement

Cinq panneaux partagent la même carte, pour qu'aucun ne fasse sauter la mise en
page : principal, nouveau monde, mondes, réglages, multijoueur. `Échap` revient
au panneau principal depuis n'importe lequel.

- **Jouer** — partie immédiate, dans le premier emplacement de sauvegarde libre.
- **Mes mondes…** — les six emplacements, avec leur nom, leur graine et la date
  de sauvegarde. On y crée un monde, on en reprend un, ou on en efface un.
  Effacer demande deux fois : le bouton devient rouge et affiche « Confirmer ? ».
- **Réglages…** — musique, bruitages, champ de vision, sensibilité, portée de
  rendu, mode de rendu, inversion de l'axe vertical. Tout est enregistré dans
  `user://cubecraft_settings.json` et reappliqué au lancement suivant ; le son
  s'ajuste pendant qu'on le bouge.

### Sauvegardes

Les parties vivent dans `user://saves/`, une par emplacement, avec un index
d'en-têtes (`index.json`) : lister les mondes ne relit donc pas les fichiers, qui
pèsent plusieurs mégaoctets dès qu'on a joué un peu.

L'ancienne sauvegarde unique (`user://cubecraft_save.json`) est reprise comme
emplacement 1 au premier lancement de cette version, puis déplacée.

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
| 3 diamants + 2 bâtons | pioche en diamant (minerai de diamant) |
| 4 diamants + bâton | épée en diamant |
| 2×2 sable | 1 verre |
| 4 pierres taillées (sans forme) | 4 briques |

Clic droit sur l'établi (posé ou tenu) pour la grille 3×3 complète.

### Les quatre paliers de minage

Chaque minerai porte le palier d'outil qu'il exige, et la pioche le fournit :

| Minerai | Palier | Ce qu'il faut | Profondeur |
|---|---|---|---|
| charbon | 1 | pioche en bois | jusqu'à y = 62 |
| fer | 2 | pioche en pierre | jusqu'à y = 46 |
| or | 3 | pioche en fer | jusqu'à y = 34 |
| diamant | 4 | pioche en diamant | jusqu'à y = 20 |

Le palier 4 est le seul qui se verrouille lui-même : le diamant ne s'obtient
qu'avec la pioche en diamant, et cette pioche ne se fabrique qu'avec du
diamant. Oublier l'un des deux et la progression s'arrête définitivement — c'est
voulu, et c'est aussi ce que vérifie `tools/CheckContent.gd`.

Creuser plus profond est donc la seule progression : à mains nues ou avec la
mauvaise pioche, le bloc se détruit et ne rend **rien**.

### Les blocs dangereux

Depuis peu, certains blocs infligent des dégâts **au contact** : rester contre
de la lave retire 2 cœurs toutes les demi-secondes (la lave est incassable, la
seule façon d'en sortir est de mourir), et se frotter à un cactus en retire un.
Le torse est échantillonné aussi bien que les pieds, pour qu'un bloc situé à
hauteur de poitrine ne soit pas un abri.

## Écran titre et chargement

Rien n'est dessiné à la main : le ciel, le soleil, les nuages et le sol du menu
sont des `ColorRect` et des textures générées par code — dégradés d'une colonne,
lueur et vignette en 64×64, tuiles de 16×16 pour l'herbe et la terre.

- **Le sol du menu est celui du jeu** : la bande d'herbe et la bande de terre
  affichent les tuiles de l'atlas, l'herbe colorée par le tint de plaine — le
  menu et le monde se répondent au lieu de se ressembler vaguement. L'atlas
  n'existant pas hors du jeu, l'écran retombe sur un bruit local quand il est
  instancié par le test de fumée.
- **Relief de voxels sur l'horizon** : deux couches de terrain dessinées au
  carré **depuis les tuiles du jeu** — la face du dessus au sommet de chaque
  colonne, le flanc en dessous, le tout tracé en `_draw()` sans maillage 3D. La
  couche proche (26 px le bloc) porte des arbres faits des mêmes tuiles de
  tronc et de feuilles que ceux du monde ; la couche lointaine (13 px) est plus
  basse, plus petite et **noyée dans la brume du ciel**, ce qui lui donne
  l'écart sans flou. Le profil vient d'un bruit à graine fixe et **périodique** :
  la période (4056 px) est un multiple exact des deux côtés de bloc, donc le
  raccord tombe sur une colonne et l'horizon ne saute pas quand on élargit la
  fenêtre. Comme les autres bandes, les deux couches sont **ancrées en bas** :
  une position absolue calculée sur une largeur capturée au passage dérivait de
  la hauteur de l'herbe dès que la fenêtre changeait de taille.
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
           Blocks/Items   catalogues (27 blocs, 11 objets, 1 bloc par bloc)
           Recipes        recettes + moteur d'appariement
           Inventory      36 emplacements, barre rapide
           Game           autoload : pause, écrans, sauvegarde, liaison scène
           InputSetup     autoload : touches, manette
           Checklist      journal de vérifications, partagé test et menu
           Diagnostics    les 93 vérifications, jouables depuis le menu (F4)
           Net            autoload ENet : salon, admissions, diffusion
           SaveSystem     emplacements compressés dans user://, + index
           Settings       réglages persistants, bornés à la lecture
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
           TitleScreen    menu, ciel procédural, relief de voxels, logo animé
           TitleOptions   panneau des réglages
           TitleWorlds    panneau des emplacements de sauvegarde
           ChatUI         journal et saisie de chat, sans libérer le curseur
           SkinPreview    aperçu du personnage, dessiné à la main
           UiKit          charte : plaques, boutons, champ, barre de progression
  world/   Weather        pluie, neige, brouillard selon biome et altitude
  gen/     Tiles          la grille d'atlas : 8 colonnes × 7 lignes, 50 tuiles
           TextureFactory atlas pixel-art   BlockIcons  icones de blocs isometriques
           ExternalTiles  surcouche CC0 facultative (assets/kenney)
           SoundFactory  bruitages + musique
           SkinFactory  skin 64×64 peinte par code, format Minecraft
           Sounds         autoload : banque de bruitages, voix 3D, musique
tools/SmokeTest.gd        test de bout en bout, sans écran
           NetTest/NetPeer  test réseau à trois processus (hôte + 2 clients)
           CheckContent.gd  le contenu ajouté est-il vraiment atteignable ?
           CheckLights.gd   le pool garde-t-il sa source quand on marche ?
           CheckTitle.gd    le relief du menu boucle-t-il et repose-t-il au sol ?
           TileDump/TreeDump/IconDump/CheckExternal  diagnostics ponctuels
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

**L'interaction passe avant la pose.** Le clic droit teste d'abord le bloc
visé, et seulement ensuite la main : c'est lui qui décide. L'ordre inverse
fermait l'établi dès que la main ne tenait pas un bloc — donc **main vide**, ou
pioche en main. Comme la pioche en bois se fabrique avant l'établi dans la
quasi-totalité des parties, c'était le geste le plus courant du jeu qui ne
marchait pas, sans jamais lever une erreur. Ouvrir un établi est une
*interaction*, pas une pose : c'est donc `_interact` qui le traite, aux côtés
de la table d'enchantement, et la pose ne voit plus que les blocs.

**Orientation des faces.** Godot n'affiche une face que si ses sommets sont dans
le sens trigonométrique vu de l'extérieur. Inverser cet ordre rend le terrain
entier invisible sans la moindre erreur dans la console : c'est vérifié par le
test de fumée, qui recalcule le produit vectoriel de chaque triangle.

**Le calendrier du monde ne tourne pas a chaque image.** `_schedule` balaye le
disque autour du joueur et trie deux fois ses candidats : a la portee 5 c'est
deux cents-accents-vingts cellules et quinze cents lectures de dictionnaire
par image, et la portee 10 le multiplie par trois. Le balayage ne se relance
donc que sur ce qui peut reellement changer la situation — un resultat de
tache applique, une edition de bloc, un changement de portee, un deplacement du
joueur — plus un filet de securite de 0,5 s, pour qu'un evenement oublie ne
laisse pas le disque a moitie charge. Sans lui, le cout du streaming montait
avec la portee de rendu, alors qu'il ne dependait de rien de ce que
le joueur faisait.

**Les torches déchargées quittent la liste des sources.** `World.torches` est
l'index des blocs emissifs que `TorchLights` parcourt cinq fois par seconde.
Elle ne se garnissait qu'a la pose, jamais au déchargement : la liste
grossissait donc sans fin au fur et a mesure que le joueur explore, et une
source oubliee n'etait plus rien — son chunk n'existant plus, `get_block` y
rendait de l'air et la lumiere qu'elle detenait se mettait a eclairer le vide.

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

## Éclairage des torches

La lave et la table d'enchantement émettent aussi, et pas comme des torches :
elles sont dans la même liste que le monde tient à jour, avec leur propre
`light` et leur propre couleur. Avant, toutes recevaient le même couple
couleur/énergie — une table d'enchantement aussi orangée et aussi vive qu'un
feu de camp. La portée et l'énergie sont maintenant lues sur le bloc, et seule
la torche vacille, sur une phase décalée par emplacement : deux torches
posées côte à côte ne doivent pas respirer ensemble.

L'affectation des lumières est **collante**, et c'est le vrai gain. La version
d'avant redistribuait les sources par distance à chaque recalcul, cinq fois par
seconde : dès que le joueur bougeait, la lumière numéro 1 changeait de torche.
Traverser un couloir de torches donnait un clignotement continu, dont la
cause n'était visible nulle part. Une source garde donc sa lumière tant qu'elle
reste dans le ressort ; seuls les emplacements libérés reçoivent les sources
restantes, les plus proches d'abord. Une lumière qui s'éteint ne redevient
disponible qu'une fois **complètement noire** : la reconnecter avant la fin du
fondu la ferait bouger en plein fondu, ce qui se voit plus qu'une extinction un
peu lente.

Le composant ne lit plus `Game.player` mais un champ `follow` que `Main` renseigne.
Un composant d'éclairage n'a rien à faire d'un singleton global, et surtout il
devient testable hors du jeu — ce que `--script` rend possible, puisqu'il n'y a
pas d'autoload dans ce mode.

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

## Limites connues

- La vérification « le bloc visé se fend pendant le minage » est **instable** :
  elle n'échantillonne `BreakOverlay.visible` qu'une fois par image physique,
  et un bloc d'herbe casse à la main nue en quelques images — il arrive que le
  bloc disparaisse avant qu'aucune image n'ait vu les fissures. Le reste de la
  suite est déterministe. Une capture d'état dans `BreakOverlay` (l'étape de
  progression plutôt que sa visibilité par image) la rendrait fiable.

- Le multijoueur fonctionne en hôte/client sur ENet, avec un salon d'attente et
  un **chat** (`T`), mais reste minimal : pas de whitelist, pas de reprise de
  session, aucun historique — le journal du bas de l'écran fait huit lignes et
  chaque message s'efface au bout de douze secondes. Le monde est celui de l'hôte,
  ses modifications ne sont pas sauvegardées pour les clients.
- Le vol reste un mode de déplacement : les ressources sont toujours comptées.
- L'éclairage dynamique repose sur un pool de **16 lumières**, et le projet
  relève pour cela `limits/opengl/max_lights_per_object` de 8 à 16 : le moteur
  ne calcule que les N premières lumières touchant un objet, et un pool plus
  grand que ce plafond gaspille la moitié de son travail sans rien montrer. Au-delà
  de 16 sources dans le ressort, une torche reste visible mais n'éclaire pas.
  Aucune de ces lumières ne projette d'ombre : seize ombres portées de plus de
  six faces ne tiendraient pas soixante images par seconde, et c'est le seul
  endroit du projet où le compromis a été fait en faveur du débit d'images.
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

## Licence

Le code, les scènes, et tout ce que le jeu génère à l'exécution sont sous
[MIT](LICENSE) — réutilisation, modification et redistribution libres, y compris
commerciale.

Une exception, en tête : le dossier `assets/kenney/` est un pack **CC0** de Kenney
Vleugels, redéposé tel quel et également libre de toute contrainte
([`assets/kenney/LICENSE-kenney.txt`](assets/kenney/LICENSE-kenney.txt)). Il est
facultatif : le jeu tourne à l'identique sans lui.
