<!-- Page de documentation Cubecraft : Boucle de jeu, minage, blocs dangereux, écran titre et chargement.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
