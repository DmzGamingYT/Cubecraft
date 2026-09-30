<!-- Page de documentation Cubecraft : Limites connues et compromis assumés.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
