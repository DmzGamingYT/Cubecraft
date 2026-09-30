<!-- Page de documentation Cubecraft : Rendu, touche F6, musique et éclairage des torches.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
