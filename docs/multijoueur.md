<!-- Page de documentation Cubecraft : Multijoueur ENet à huit joueurs.
     Extraite du README, qui tenait 770 lignes et devenait illisible
     en page d'accueil. Revenir au README : ../README.md -->

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
