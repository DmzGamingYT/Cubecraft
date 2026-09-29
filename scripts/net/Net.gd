extends Node

## Autoload `Net` : multijoueur en reseau local, hote et clients.
##
## Le monde etant entierement procedural, aucune donnee de terrain ne circule :
## l'hote n'envoie que sa graine, et chaque client regenere un terrain
## identique. Ce qui doit voyager, c'est court :
##
##   - la **graine** et la **distance de rendu**, pour que tout le monde marche
##     sur le meme monde ;
##   - la **pose** des joueurs, en flux non fiable, une quinzaine de fois par
##     seconde — une pose perdue est remplacee par la suivante 70 ms plus tard,
##     alors qu'une pose fiable qui s'accumule fait saccader tout le monde ;
##   - les **editions de blocs**, en fiable, parce qu'un bloc casse perdu laisse
##     un trou dans le terrain jusqu'a la fin de la partie.
##
## Les editions sont conservees dans un calque `_overlay` cote client. Un chunk
## regenere apres avoir ete decharge reverrait son etat d'origine, et le
## joueur verrait un mur se dresser devant lui : le calque est donc rejoue a
## chaque `chunk_loaded`.
##
## L'autoload est un noeud de chemin identique (`/root/Net`) sur toutes les
## machines, condition pour que les appels RPC se retrouvent.

enum Mode { OFFLINE, HOST, CLIENT }

## Un client qui ne repond pas est coupe au bout de ce delai. Le serveur ENet
## le fait lui-meme, mais en deux temps, et l'avatar resterait fige entre les
## deux.
const PEER_TIMEOUT := 12.0
## Nombre maximum de clients. Au-dela, l'hote refuse proprement.
const MAX_PLAYERS := 8
## Port par defaut. Un port haut et fixe evite les collisions avec les services
## systeme et permet de le retenir dans un pare-feu local.
const DEFAULT_PORT := 27015
## Frequence d'envoi des poses, en secondes. 15 Hz : assez fluide pour que les
## autres ne voient pas de saccade, assez peu pour que le trafic reste
## indefendable sur un reseau local.
const POSE_INTERVAL := 1.0 / 15.0
## Au-dela, une pose est jugee obsolete et l'avatar s'arrete net plutot que de
## continuer a Deriver vers une position qu'il n'atteindra jamais.
const POSE_STALE := 2.0

signal mode_changed(mode: int)
## Le client recoit ceci quand l'hote lui a transmis la description du monde :
## il peut alors construire un terrain identique.
## Le client est admis, mais **rien n'est encore charge**. Il entre au salon, ou
## il choisit son pseudo et sa tenue et voit les autres joueurs, avant que le
## monde n'existe. C'est ce decalage qui permet a une partie de se decider
## avant de se voir.
signal lobby_entered(world_seed: int, distance: int, spawn: Vector3,
		host_name: String)
## L'hote a lance la partie : le client peut construire son terrain.
signal world_ready(world_seed: int, distance: int, spawn: Vector3)
signal join_failed(reason: String)
## La liste des joueurs a change : presences,Skin, arrivedes, departs.
signal roster_changed
signal chat_received(peer_id: int, author: String, line: String)
## L'hote a refuse une edition et le monde local a ete remis en place. Signale
## pour que l'interface puisse le dire au joueur : un revert muet passe pour un
## bug, alors que c'est l'hote qui a fait son travail.
signal block_reverted(pos: Vector3i)

var mode: int = Mode.OFFLINE
var world_seed := 0
var distance := 5
var spawn := Vector3.ZERO
var local_name := "Joueur"
var local_skin := 0
## true quand tout le monde est admis mais que la partie n'a pas demarre. Le
## salon vit dans cet etat : les avatars y existent, mais aucun terrain n'est
## genere, donc rien ne coute encore.
var in_lobby := false

## Poses connues, pour l'hote qui doit pouvoir inscrire un client qui arrive en
## plein milieu d'une partie. `id` = identifiant de peering ENet.
var _poses: Dictionary = {}
## Fiche du joueur local, en attente d'etre rangee sous le bon identifiant.
## Le client la construit a son admission, quand son identifiant n'est pas
## encore connu, et la reclasse des que la connexion est etablie.
var _self_entry: Dictionary = {}
## Editions connues, clees par position, en attente d'etre rejouees sur un chunk
## qui n'existe pas encore. Cote hote, c'est aussi le journal complet envoye a
## un nouveau client.
var _overlay: Dictionary = {}
## true quand la pose vient de l'hote ou d'un client, false quand c'est la
## notre : sans ce drapeau, une pose recue reboucle et se renvoie a l'infini.
var _applying := false
var _pose_timer := 0.0
var _local_peer_id := 1
var _avatars: Node3D
var _avatars_by_peer: Dictionary = {}
var _world: World = null
## Le joueur local est tenu par sa classe de base, `CharacterBody3D`, et non
## par `Player` : referencer le script du joueur tirerait `Game` — un autoload —
## dans tout ce qui charge `Net`, et le test de fumee, qui n'a pas d'autoload,
## ne compilerait plus. Le lacet est lu par `call()`, le seul point qui n'existe
## que sur `Player`.
var _player: CharacterBody3D = null
var _host_display_name := "Hote"


func _ready() -> void:
	# Les avatars vivent dans le meme monde 3D que le terrain. Comme cet autoload
	# est enfant de la racine, ses positions globales sont deja dans le bon
	# repere : rien d'autre a recadrer.
	_avatars = Node3D.new()
	_avatars.name = "Avatars"
	add_child(_avatars)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if mode == Mode.OFFLINE or _player == null:
		return
	_pose_timer += delta
	if _pose_timer < POSE_INTERVAL:
		return
	_pose_timer = 0.0
	_send_local_pose()


# -------------------------------------------------------------- monde local

## Branche le monde et le joueur du processus. L'hote s'en sert pour capter les
## editions, le client pour rejouer le calque sur chaque nouveau chunk.
func bind_world(world: World, player: CharacterBody3D) -> void:
	_world = world
	_player = player
	if world == null:
		return
	world.block_changed.connect(_on_block_changed)
	world.chunk_loaded.connect(_on_chunk_loaded)
	# Le calque peut deja contenir des editions recues avant que le monde
	# n'existe — cas normal d'un client qui se connecte a une partie en cours.
	for key in _overlay.keys():
		var pos: Vector3i = key
		_apply_at(pos, int(_overlay[pos]))


## Detache le monde courant. Appele au retour a l'ecran titre : les connexions
## tombent avec la partie, mais les avatars doivent disparaitre.
func unbind_world() -> void:
	if _world != null:
		if _world.block_changed.is_connected(_on_block_changed):
			_world.block_changed.disconnect(_on_block_changed)
		if _world.chunk_loaded.is_connected(_on_chunk_loaded):
			_world.chunk_loaded.disconnect(_on_chunk_loaded)
	_world = null
	_player = null
	for id in _avatars_by_peer.keys():
		var node: Node = _avatars_by_peer[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_avatars_by_peer.clear()


# ------------------------------------------------------------- cycle de vie

## Ouvre une partie en reseau. `error` decrit l'echec, vide en cas de succes.
func host_game(seed_value: int, render_distance: int, display_name := "Hote",
		port: int = DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return "Port %d indisponible (code %d)" % [port, err]
	multiplayer.multiplayer_peer = peer
	world_seed = seed_value
	distance = render_distance
	local_name = display_name
	# L'hote est toujours le joueur 1 : c'est lui qui fait autorite sur les
	# editions, et c'est son monde qui fait reference.
	_local_peer_id = 1
	# L'hote s'inscrit des l'ouverture, et pas seulement a l'appel de
	# `announce_local` : un client peut rejoindre avant, et il listerait alors
	# un « Joueur 1 » sans nom. C'est la meme fiche que celle que
	# `_send_local_pose` rafraichira quinze fois par seconde.
	_poses[_local_peer_id] = {
		"name": local_name, "skin": local_skin, "pos": spawn, "yaw": 0.0,
		"stale": 0.0, "speed": 0.0, "grounded": true,
	}
	# L'hote ouvre au salon, pas directement au monde : le joueur doit pouvoir
	# choisir son tenue et inviter d'autres joueurs avant que quoi que ce soit
	# ne soit genere.
	in_lobby = true
	mode = Mode.HOST
	mode_changed.emit(mode)
	return ""


## Se connecte a une partie. Renvoie une chaine vide si la tentative est parties ;
## l'echec reels arrive plus tard, par `join_failed`.
func join_game(address: String, port: int = DEFAULT_PORT) -> String:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Impossible de joindre %s:%d (code %d)" % [address, port, err]
	multiplayer.multiplayer_peer = peer
	_local_peer_id = 0
	in_lobby = true
	mode = Mode.CLIENT
	mode_changed.emit(mode)
	return ""


## Quitte la partie en cours et revient a l'etat hors ligne.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	_poses.clear()
	_overlay.clear()
	_host_display_name = "Hote"
	in_lobby = false
	# L'hote garde son calque tant qu'il joue : le vider ici ferait disparaitre
	# les editions de la partie en cours. Seul le retour au hors ligne complet
	# les oublie, et c'est le client comme l'hote qui calling `leave`.
	if _avatars != null:
		for child in _avatars.get_children():
			child.queue_free()
	_avatars_by_peer.clear()
	mode_changed.emit(mode)


func is_online() -> bool:
	return mode != Mode.OFFLINE


## La partie a-t-elle reellement commence ? Faux pendant tout le salon : le
## monde n'existe pas encore, et le joueur est quelque part dans le noir.
func is_playing() -> bool:
	return is_online() and not in_lobby


func is_host() -> bool:
	return mode == Mode.HOST


## Nombre de joueurs, hote compris.
func player_count() -> int:
	if mode == Mode.HOST:
		return 1 + _avatars_by_peer.size()
	if mode == Mode.CLIENT:
		return _avatars_by_peer.size() + 1
	return 0


## L'identifiant que le reseau a attribue au joueur local. Utilise par le HUD
## pour distinguer notre joueur d'un avatar distant.
func local_id() -> int:
	if _local_peer_id != 0:
		return _local_peer_id
	# Un pair referencé n'est pas forcément actif : après `leave`, ou pendant
	# l'etat hors ligne du menu titre, l'objet existe mais `get_unique_id()`
	# réclame une connexion. Le salon appelle `roster()` dans ces moments-la.
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null \
			or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 1
	return peer.get_unique_id()


# ------------------------------------------------------------------ messages

func _on_connected_ok() -> void:
	# L'identifiant n'existe qu'a partir de maintenant : c'est le moment de
	# ranger la fiche du joueur local sous le bon numero.
	_claim_self_entry()
	# Le client ne peut rien faire tant qu'il ne sait pas quelle graine generer :
	# il demande, et attend la confirmation.
	_request_join.rpc_id(1, local_name, local_skin)


## Range la fiche du joueur local sous son identifiant reel, et retire celle
## qui aurait ete posee trop tot, sous l'identifiant 0.
func _claim_self_entry() -> void:
	if _self_entry.is_empty():
		return
	var id := local_id()
	if id == 0:
		return
	_poses.erase(0)
	_poses[id] = _self_entry
	_self_entry = {}


func _on_connection_failed() -> void:
	join_failed.emit("Le serveur ne repond pas.")


func _on_server_disconnected() -> void:
	join_failed.emit("La connexion a ete coupee.")


func _on_peer_connected(id: int) -> void:
	# Cote client, l'arrivee d'un pair ne se traduit que par la mise a jour du
	# roster : l'hote lui envoie ensuite la description complete.
	if mode == Mode.CLIENT:
		roster_changed.emit()


## Un client demande a entrer, en annoncant au passage son pseudo et sa tenue :
## faire circuler l'identite dans le meme message evite une seconde requete au
## moment precis ou le joueur apparait a l'ecran.
@rpc("any_peer", "call_remote", "reliable")
func _request_join(display_name: String, skin: int) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _avatars_by_peer.size() >= MAX_PLAYERS:
		_join_refused.rpc_id(sender, "Partie complete.")
		return
	# Le client est note avant toute emission : sa tenue et sa pose doivent
	# pouvoir etre relues par la distribution qui suit.
	_poses[sender] = {
		"name": display_name, "skin": skin, "pos": spawn, "yaw": 0.0,
		"stale": 0.0, "speed": 0.0, "grounded": true,
	}
	# Son avatar doit exister **cote hote** sur-le-champ. `_spawn_avatar` est
	# marque `call_remote` : l'appeler ici n'emettrait rien, et sans cet appel
	# l'hote ne verrait ni le joueur qui entre, ni ses deplacements.
	_ensure_avatar(sender, display_name, skin, spawn, 0.0)
	# D'abord le salon : le client recoit la description du monde — qu'il ne
	# generera pas encore — et surtout la liste de ceux qui sont deja la. Il
	# peut choisir son pseudo et sa tenue avant que quoi que ce soit ne soit
	# construit.
	_lobby_opened.rpc_id(sender, world_seed, distance, spawn, local_name)
	# Puis le journal des editions, par lots. Un paquet ENet est plafonne, et
	# envoyer des milliers de positions d'un coup ferait perdre la partie sans
	# le moindre message d'erreur lisible.
	# Ce journal n'a de sens qu'une fois la partie lancee : au salon, personne
	# n'a encore rien casse, et `_overlay` est vide de toute facon.
	var batch: Array = []
	for key in _overlay.keys():
		batch.append(key)
		if batch.size() >= OVERLAY_BATCH:
			_send_overlay_batch.rpc_id(sender, batch, _overlay_ids(batch))
			batch = []
	if not batch.is_empty():
		_send_overlay_batch.rpc_id(sender, batch, _overlay_ids(batch))
	# Puis les joueurs deja presents, pour que le nouveau puisse les voir
	# avant meme de choisir sa propre tenue.
	#
	# Chaque avatar circule dans les **deux** sens, et jamais vers celui qu'il
	# decrit : son personnage est le vrai `Player` de son processus, pas une
	# copie distante. Une diffusion indiscriminee lui afficherait un double de
	# lui-meme, et c'est en oubliant le deuxieme sens qu'il n'aurait vu
	# personne.
	var newcomer: RemotePlayer = _avatars_by_peer.get(sender, null)
	var new_name := local_name
	var new_skin := local_skin
	var new_pos := spawn
	var new_yaw := 0.0
	if newcomer != null and is_instance_valid(newcomer):
		new_name = newcomer.player_name
		new_skin = newcomer.skin_index
		new_pos = newcomer.global_position
		new_yaw = newcomer.yaw
	for raw_id in _avatars_by_peer.keys():
		var id := int(raw_id)
		if id == sender:
			continue
		var avatar: RemotePlayer = _avatars_by_peer[id]
		if avatar == null or not is_instance_valid(avatar):
			continue
		# A celui qui etait deja la : le nouveau venu.
		_spawn_avatar.rpc_id(id, sender, new_name, new_skin, new_pos, new_yaw)
		# Au nouveau venu : celui qui etait deja la.
		_spawn_avatar.rpc_id(sender, id, avatar.player_name, avatar.skin_index,
			avatar.global_position, avatar.yaw)
	# L'hote est, pour le client qui arrive, un joueur comme les autres : sans
	# cette ligne le nouveau venue ne verrait personne, et les poses deposeses
	# ensuite seraient rejetees faute d'entree dans `_poses`.
	_spawn_avatar.rpc_id(sender, _local_peer_id, local_name, local_skin, spawn, 0.0)
	_roster_changed.rpc()
	# **Pas de `_world_confirmed` ici.** C'est toute la difference entre le salon
	# et la partie : le client entre, se presente, choisit sa tenue — et
	# n'attend plus que l'hote dise « c'est parti ».


## Le client vient d'etre admis : il entre au salon, ou il choisit son pseudo
## et sa tenue. Aucun terrain n'est genere pour l'instant.
@rpc("authority", "call_remote", "reliable")
func _lobby_opened(seed_value: int, render_distance: int, spawn_point: Vector3,
		host_name: String) -> void:
	world_seed = seed_value
	distance = render_distance
	spawn = spawn_point
	_host_display_name = host_name
	in_lobby = true
	# Le client s'inscrit aussi : son propre pseudo et sa tenue doivent figurer
	# dans la liste du salon, et l'ecran a besoin de savoir lequel est « moi ».
	# L'hote s'est deja inscrit en ouvrant sa partie.
	#
	# **L'identifiant n'est pas encore attribue ici.** `local_id()` vaut 0 tant
	# que le client n'a pas de pair actif, et inscrire sous 0 creerait une
	# fiche orpheline impossible a relier plus tard : le joueur se verrait
	# deux fois dans le salon, et son vrai identifiant apparaitrait sans nom.
	# La fiche est donc reprise des que le pair est reellement connecte.
	_self_entry = {
		"name": local_name, "skin": local_skin, "pos": spawn_point, "yaw": 0.0,
		"stale": 0.0, "speed": 0.0, "grounded": true,
	}
	_claim_self_entry()
	lobby_entered.emit(world_seed, distance, spawn, host_name)


## L'hote lance la partie. C'est le seul moment ou un terrain est construit :
## tout le monde a deja choisi sa tenue et vu qui serait la.
##
## Le client recoit alors la description du monde et le journal des editions.
func start_session() -> void:
	if mode != Mode.HOST:
		return
	in_lobby = false
	# Le journal des editions precede la confirmation : un client ne doit pas
	# commencer a generer son terrain puis decouvrir un lot en retard.
	_send_overlay.rpc()
	_send_world.rpc(world_seed, distance, spawn, local_name)
	_world_confirmed.rpc()
	roster_changed.emit()


## Le journal des editions, en un seul message. Les lots servent au cas d'un
## monde deja rempli : ici la partie est neuve, le calque est petit, et
## l'hote n'a pas encore eu le temps de casser quoi que ce soit.
@rpc("authority", "call_remote", "reliable")
func _send_overlay() -> void:
	if _overlay.is_empty():
		return
	var positions: Array = _overlay.keys()
	_send_overlay_batch.rpc(positions, _overlay_ids(positions))


## Taille d'un lot d'editions envoyes a un nouveau client. Fixe : un lot trop
## gros ferait perdre la partie, et un lot minuscule la ralentirait pour rien.
const OVERLAY_BATCH := 200


func _overlay_ids(keys: Array) -> Array:
	var ids := []
	for key in keys:
		ids.append(int(_overlay[key]))
	return ids


@rpc("authority", "call_remote", "reliable")
func _join_refused(reason: String) -> void:
	join_failed.emit(reason)
	leave()


@rpc("authority", "call_remote", "reliable")
func _send_world(seed_value: int, render_distance: int, spawn_point: Vector3,
		host_name: String) -> void:
	world_seed = seed_value
	distance = render_distance
	spawn = spawn_point
	_host_display_name = host_name


## Editions deja jouees, en plusieurs messages. Le client n'agit pas encore : il
## attend la confirmation finale, pour ne pas commencer a construire son monde
## puis decouvrir un lot en retard.
@rpc("authority", "call_remote", "reliable")
func _send_overlay_batch(positions: Array, ids: Array) -> void:
	for i in positions.size():
		_overlay[positions[i]] = ids[i]


## L'hote a tout envoye : le monde peut demarrer.
@rpc("authority", "call_remote", "reliable")
func _world_confirmed() -> void:
	# Le salon se ferme ici, cote client. Sans cette ligne, le client resterait
	# « en attente du lancement » alors que le monde existe deja : l'interface
	# afficherait un message devenu faux, et `is_playing()` dirait non.
	in_lobby = false
	world_ready.emit(world_seed, distance, spawn)


## L'hote annonce l'arrivee d'un joueur a tout le monde, nouveau compris.
@rpc("authority", "call_remote", "reliable")
func _spawn_avatar(peer_id: int, display_name: String, skin: int,
		pos: Vector3, yaw: float) -> void:
	_ensure_avatar(peer_id, display_name, skin, pos, yaw)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _roster_changed() -> void:
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _remove_avatar(peer_id: int) -> void:
	var avatar: RemotePlayer = _avatars_by_peer.get(peer_id, null)
	if avatar != null and is_instance_valid(avatar):
		avatar.queue_free()
	_avatars_by_peer.erase(peer_id)
	_poses.erase(peer_id)
	roster_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	if mode == Mode.HOST:
		_poses.erase(id)
		var avatar: RemotePlayer = _avatars_by_peer.get(id, null)
		if avatar != null and is_instance_valid(avatar):
			avatar.queue_free()
		_avatars_by_peer.erase(id)
		# Tout le monde doit effacer l'avatar du joueur parti, pas seulement
		# l'hote : un client ne voit jamais la deconnexion d'un autre client.
		_remove_avatar.rpc(id)
		_roster_changed.rpc()
	else:
		roster_changed.emit()


## Un client change de tenue en cours de partie : l'hote le redistribue.
@rpc("any_peer", "call_remote", "reliable")
func _announce(display_name: String, skin: int) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	var entry: Variant = _poses.get(sender, null)
	var pos := spawn
	var yaw := 0.0
	if entry != null and entry.has("pos"):
		pos = entry["pos"]
		yaw = entry["yaw"]
	_poses[sender] = {
		"name": display_name, "skin": skin, "pos": pos, "yaw": yaw,
		"stale": 0.0, "speed": 0.0, "grounded": true,
	}
	# Comme a l'entree, l'hote applique le changement chez lui : cet appel est
	# marque `call_remote` et ne joue pas en local.
	_ensure_avatar(sender, display_name, skin, pos, yaw)
	# La nouvelle tenue ne se dit qu'aux **autres**. Celui qui vient de la
	# choisir a deja repeint son personnage ; lui renvoyer sa fiche lui
	# dessinerait un second corps, immobile, a cote de lui. La liste vient
	# des pairs reellement connectes, et non de `_poses` : l'hote y figure
	# lui-meme, et un envoi sur soi-meme serait refuse.
	for id in multiplayer.get_peers():
		if int(id) == sender:
			continue
		_spawn_avatar.rpc_id(id, sender, display_name, skin, pos, yaw)
	_roster_changed.rpc()


## Une edition demandee par un client. L'hote est seul autorise a ecrire dans le
## monde : deux clients cassant le meme bloc au meme instant produces alors une
## difference, et le serveur tranche.
@rpc("any_peer", "call_remote", "reliable")
func _submit_block(pos: Vector3i, block_id: int) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _is_sane_block(pos, block_id):
		# Edition refusee : on dit au client ce qu'il doit retrouver. Sans ce
		# message il garderait le bloc dans son monde **et** dans son calque,
		# donc pour toujours : les deux joueurs verraient deux mondes
		# differents, sans qu'aucune erreur ne soit affichee nulle part.
		_revert_block.rpc_id(sender, pos, _authoritative_at(pos))
		return
	_overlay[pos] = block_id
	if _world != null:
		_apply_at(pos, block_id)
	_apply_block.rpc(pos, block_id)


## Ce que l'hote a reellement dans le monde a cette position, ou -1 s'il n'en
## sait rien.
##
## Le -1 compte : `get_block` rend `AIR` pour un chunk non charge, et l'envoyer
## comme verite creuserait un trou la ou le sol est plein. L'hote qui n'a pas
## charge la colonne n'a pas autorité pour la contredire.
func _authoritative_at(pos: Vector3i) -> int:
	if _world == null:
		return -1
	var coords := Vox.chunk_of(pos)
	if _world.chunk_at(coords.x, coords.y) == null:
		return -1
	return _world.get_block(pos)


@rpc("authority", "call_remote", "reliable")
func _revert_block(pos: Vector3i, block_id: int) -> void:
	# L'entree du calque part d'abord : c'est elle qui rejouerait l'edition a
	# chaque chargement de chunk, et qui la ramenerait apres le revert.
	_overlay.erase(pos)
	if block_id >= 0 and _world != null:
		_apply_at(pos, block_id)
	block_reverted.emit(pos)


## Un client envoie sa pose. L'hote la note et la retransmet aux autres : un
## client ne parle jamais directement a un autre client, cela garantirait un
## ordre different selon qui l'a entendue.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_pose(pos: Vector3, yaw: float, speed: float, grounded: bool) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	# La fiche existante est mise a jour champ par champ : la remplacer d'un
	# bloc ferait perdre le pseudo et la tenue, annonces a l'entree et servant
	# a tous les autres joueurs pour habiller cet avatar.
	var entry: Dictionary = _poses.get(sender, {}) as Dictionary
	if entry.is_empty():
		entry = {"name": "Joueur %d" % sender, "skin": 0}
	entry["pos"] = pos
	entry["yaw"] = yaw
	entry["speed"] = speed
	entry["grounded"] = grounded
	entry["stale"] = 0.0
	_poses[sender] = entry
	# L'hote doit voir ses invites bouger aussi. `_relay_pose` est marque
	# `call_remote` : appelee en local elle n'emettrait rien, et l'hote
	# verrait ses joueurs figes a leur point d'arrivee.
	_apply_pose(sender, pos, yaw, speed, grounded)
	_relay_pose.rpc(sender, pos, yaw, speed, grounded)


@rpc("authority", "call_remote", "unreliable_ordered")
func _relay_pose(peer_id: int, pos: Vector3, yaw: float, speed: float,
		grounded: bool) -> void:
	_apply_pose(peer_id, pos, yaw, speed, grounded)


## Note une pose et la pousse vers l'avatar correspondant. Appele des deux
## cotes : par `_relay_pose` quand la pose arrive du reseau, et directement par
## l'hote pour sa propre vue, `_relay_pose` n'ayant aucun effet en local.
func _apply_pose(peer_id: int, pos: Vector3, yaw: float, speed: float,
		grounded: bool) -> void:
	var entry: Variant = _poses.get(peer_id, null)
	if entry == null:
		# Une pose peut preceder l'annonce du joueur : on garde ce qu'on sait.
		entry = {
			"pos": pos, "yaw": yaw, "speed": speed, "grounded": grounded,
			"stale": 0.0, "name": "Joueur %d" % peer_id, "skin": 0,
		}
		_poses[peer_id] = entry
	else:
		entry["pos"] = pos
		entry["yaw"] = yaw
		entry["speed"] = speed
		entry["grounded"] = grounded
		entry["stale"] = 0.0
	var avatar: RemotePlayer = _avatars_by_peer.get(peer_id, null)
	if avatar != null and is_instance_valid(avatar):
		avatar.push_target(pos, yaw, speed, grounded)


@rpc("authority", "call_remote", "reliable")
func _apply_block(pos: Vector3i, block_id: int) -> void:
	_overlay[pos] = block_id
	if _world != null:
		_apply_at(pos, block_id)


## Un message court dans le chat. L'hote le filtre et le retransmet : c'est lui
## qui garde l'ordre chronologique de la conversation.
@rpc("any_peer", "call_remote", "reliable")
func _submit_chat(line: String) -> void:
	if mode != Mode.HOST:
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean := line.strip_edges().left(120)
	if clean.is_empty():
		return
	_relay_chat.rpc(sender, _peer_name(sender), clean)
	chat_received.emit(sender, _peer_name(sender), clean)


@rpc("authority", "call_remote", "reliable")
func _relay_chat(peer_id: int, author: String, line: String) -> void:
	chat_received.emit(peer_id, author, line)


# ----------------------------------------------------------------- mondaine

## Un client envoie sa pose a intervalle fixe, pour que les autres le voient
## bouger meme quand il ne casse aucun bloc.
func _send_local_pose() -> void:
	if _player == null or mode == Mode.OFFLINE:
		return
	var pos := _player.global_position
	var yaw: float = _player.call("get_yaw")
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var grounded := _player.is_on_floor()
	# Une partie hote sans client, ou un client encore en train de se
	# connecter, n'a personne a qui parler : emettre quand meme ferait
	# exhiber une erreur par image, en boucle, pendant toute la partie.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if mode == Mode.HOST:
		_poses[local_id()] = {
			"pos": pos, "yaw": yaw, "speed": speed, "grounded": grounded,
			"stale": 0.0, "name": local_name, "skin": local_skin,
		}
		# L'hote est l'autorite : sa pose part aussi vers les clients. Le `1`
		# est l'identifiant du joueur dont c'est la pose, pas une cible.
		_relay_pose.rpc(1, pos, yaw, speed, grounded)
	else:
		_submit_pose.rpc_id(1, pos, yaw, speed, grounded)


## Envoie un bloc casse ou pose. Le client passe par le serveur, l'hote
## l'emporte directement et le redistribue.
func submit_local_block(pos: Vector3i, block_id: int) -> void:
	if mode == Mode.OFFLINE:
		return
	_overlay[pos] = block_id
	if mode == Mode.HOST:
		_apply_block.rpc(pos, block_id)
	else:
		_submit_block.rpc_id(1, pos, block_id)


func send_chat(line: String) -> void:
	if mode == Mode.OFFLINE:
		return
	if mode == Mode.HOST:
		# Diffuse comme les poses : le `1` est l'auteur, pas une cible.
		_relay_chat.rpc(1, local_name, line)
		chat_received.emit(1, local_name, line)
	else:
		_submit_chat.rpc_id(1, line)


## Annonce le pseudo et la tenue locale. A appeler apres que le monde existe, et
## a chaque changement de skin en cours de partie.
func announce_local(display_name: String, skin: int) -> void:
	local_name = display_name
	local_skin = skin
	if mode == Mode.OFFLINE:
		return
	# La fiche locale est mise a jour dans tous les cas, hote comme client :
	# l'ecran salon se relit lui-meme, et sans cela le joueur y resterait
	# fige sur la tenue qu'il venait de changer, jusqu'au prochain message
	# de l'hote — qui peut ne jamais venir.
	#
	# `local_id()`, et non le champ brut : sur un client, `_local_peer_id`
	# reste a 0 tant que l'hote ne l'a pas renseigne. Inscrire la tenue sous
	# 0 creerait une fiche orpheline — celle-la meme que `_lobby_opened`
	# refuse de creer — et le joueur se verrait deux fois dans le salon,
	# dont une sous le nom d'un inconnu.
	var self_id := local_id()
	var entry: Dictionary = _poses.get(self_id, {}) as Dictionary
	if entry.is_empty():
		entry = {"pos": spawn, "yaw": 0.0, "stale": 0.0, "speed": 0.0,
			"grounded": true}
	entry["name"] = local_name
	entry["skin"] = local_skin
	_poses[self_id] = entry
	if mode == Mode.HOST:
		_roster_changed.rpc()
	else:
		_announce.rpc_id(1, display_name, skin)


# ------------------------------------------------------------------- interne

## Ecrit un bloc en evitant la boucle de reboucle : l'edition venue du reseau
## passe par ici aussi, et sans ce drapeau elle serait renvoyee au serveur.
func _apply_at(pos: Vector3i, block_id: int) -> void:
	if _world == null:
		return
	_applying = true
	_world.set_block(pos, block_id)
	_applying = false


func _on_block_changed(pos: Vector3i, _old_id: int, new_id: int) -> void:
	if _applying or mode == Mode.OFFLINE:
		return
	submit_local_block(pos, new_id)


func _on_chunk_loaded(cx: int, cz: int) -> void:
	if _overlay.is_empty():
		return
	# Un chunk qui vient d'apaitre rejoue le calque : sans cela un mur casse
	# reviendrait tout seul apres un dechargement.
	for key in _overlay.keys():
		var pos: Vector3i = key
		if pos.x / Vox.CHUNK_X != cx or pos.z / Vox.CHUNK_Z != cz:
			continue
		_apply_at(pos, int(_overlay[pos]))


## Un client ne peut pas demander d'ecrire n'importe ou : une position hors du
## monde, ou un identifiant de bloc inconnu, ferait planter le serveur d'un
## joueur qui n'a rien demande de malin.
func _is_sane_block(pos: Vector3i, block_id: int) -> bool:
	if pos.y < 0 or pos.y >= Vox.CHUNK_Y:
		return false
	if block_id < 0 or block_id >= Blocks.COUNT:
		return false
	# Une borne en x et z : au-dela, le joueur ferait charger une colonne que
	# personne n'a demandee, a l'autre bout du monde.
	return absi(pos.x) < Vox.CHUNK_X * 4096 and absi(pos.z) < Vox.CHUNK_Z * 4096


## Nombre d'avatars distants connus. Un client n'a jamais le sien propre : le
## personnage du joueur local est le vrai `Player`.
func avatar_count() -> int:
	return _avatars_by_peer.size()


## Lacet d'un avatar distant, ou une valeur negative si ce joueur est inconnu.
func avatar_yaw(peer_id: int) -> float:
	var avatar: Variant = _avatars_by_peer.get(peer_id, null)
	if avatar == null or not is_instance_valid(avatar):
		return -1.0
	return float(avatar.yaw)


## Bloc retenu au calque d'editions, ou -1 si ce point n'a jamais ete modifie.
## Le calque survit a un chunk decharge, donc cette valeur reste bonne meme
## quand la colonne n'existe plus en memoire.
func overlay_at(pos: Vector3i) -> int:
	return int(_overlay.get(pos, -1))


## Nombre d'editions retenues au calque. C'est la seule donnee de partie qu'un
## client n'a pas regeneree : tout le reste du terrain vient de la graine.
func overlay_size() -> int:
	return _overlay.size()


## Pseudo connu d'un joueur, tel que les autres le voient.
func peer_name(peer_id: int) -> String:
	return _peer_name(peer_id)


## La partie en cours, telle que le salon l'affiche : un tableau de
## dictionnaires `{id, name, skin, host}`. L'interface n'a ainsi aucun besoin
## de connaitre la structure interne de `Net`.
##
## L'hote y figure aussi : au salon il doit se voir dans la liste, exactement
## comme les clients se voient entre eux.
func roster() -> Array:
	var out: Array = []
	if not is_online():
		# Hors ligne il n'y a personne a lister. Renvoyer une liste vide evite
		# surtout de demander un identifiant a un pair qui n'est plus actif.
		return out
	var ids: Array = _poses.keys()
	ids.sort()
	for raw_id in ids:
		var id := int(raw_id)
		out.append({
			"id": id,
			"name": _peer_name(id),
			"skin": _peer_skin(id),
			"host": mode == Mode.HOST and id == _local_peer_id,
			# Le joueur local figure dans sa propre liste : c'est son nom et sa
			# tenue qu'il vient de choisir, il doit se voir choisir. L'ecran
			# salon est le seul endroit ou cela a du sens — en jeu, chacun a
			# son vrai personnage sous les yeux.
			"local": id == local_id(),
		})
	return out


func _peer_name(peer_id: int) -> String:
	var entry: Variant = _poses.get(peer_id, null)
	if entry != null and entry.has("name"):
		return str(entry["name"])
	return "Joueur %d" % peer_id


func _peer_skin(peer_id: int) -> int:
	var entry: Variant = _poses.get(peer_id, null)
	if entry != null and entry.has("skin"):
		return int(entry["skin"])
	return 0


func _ensure_avatar(peer_id: int, display_name: String, skin: int,
		pos: Vector3, yaw: float) -> RemotePlayer:
	# La fiche de pose est inseparable de l'avatar : `_relay_pose` la lit, et
	# sans elle une pose recue serait balee. Elle doit donc naitre avec
	# l'avatar, et pas seulement a la premiere pose envoyee.
	if not _poses.has(peer_id):
		_poses[peer_id] = {
			"name": display_name, "skin": skin, "pos": pos, "yaw": yaw,
			"stale": 0.0, "speed": 0.0, "grounded": true,
		}
	var existing: RemotePlayer = _avatars_by_peer.get(peer_id, null)
	if existing != null and is_instance_valid(existing):
		existing.set_player_info(display_name, skin)
		return existing
	var avatar := RemotePlayer.new()
	avatar.peer_id = peer_id
	avatar.player_name = display_name
	avatar.skin_index = skin
	avatar.yaw = yaw
	# L'avatar entre dans l'arbre **avant** qu'on lui donne sa position : une
	# `global_position` posee sur un noeud qui n'a pas de parent vaut zero et
	# Godot s'y plaint. Les avatars sont enfants directs de `_avatars`, lui-meme
	# a la racine de la scene, donc la position locale est deja globale.
	_avatars.add_child(avatar)
	avatar.global_position = pos
	_avatars_by_peer[peer_id] = avatar
	return avatar
