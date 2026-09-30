<!-- Page de documentation Cubecraft : Architecture du code, décisions à connaître, personnage et tenues.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
           Diagnostics    les 105 vérifications, jouables depuis le menu (F4)
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
           DebugMenu  panneau de diagnostic (F4), performances, journal,
                       vérifications
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
           CheckWorld.gd    un monde vide-t-il ses files de taches en mourant ?
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
