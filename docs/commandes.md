<!-- Page de documentation Cubecraft : Commandes, manette, écran de lancement et sauvegardes.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
