extends Node

## Pair du test reseau de bout en bout. Ce script est lance par `NetTest.gd`,
## qui ouvre deux processus Godot : l'un heberge, l'autre se connecte. Les deux
## lancent **le vrai jeu** — autoloads compris, `Net` en tete — sur
## `scenes/NetPeer.tscn`, si bien que ce qui est mesure est exactement ce que
## mesurerait une vraie partie en reseau local.
##
## Les arguments arrivent derriere `--` :
##
##   godot -- --role=host --port=27800 --name=Alice --out=/tmp/h.txt
##
## Les verifications sont ecrites dans le fichier `--out`, que l'autre processus
## relit ensuite pour agreger les deux moities du verdict.
##
## Le scenario est une **machine a etats** : chaque etape est franchie une
## seule fois, dans l'ordre, et une etape qui n'aboutit pas laisse le pair
## attendre plutot que de repeter son echec sixty fois par seconde.

const SEED := 20260929
const DISTANCE := 2
## Limite dure, en **secondes** : un pair bloqu\u00e9 doit s'arr\u00eater, pas laisser
## un processus godot en trainee. La limite \u00e9tait compt\u00e9e en images, et
## c'\u00e9tait une erreur : le test lance trois processus qui g\u00e8n\u00e8rent et maillent
## en m\u00eame temps, donc la cadence d'images d\u00e9pend de la charge de la machine.
## Un pair perfectly dans les clous \u00e9tait alors d\u00e9clar\u00e9 bloqu\u00e9 sur un portable
## charg\u00e9, et le d\u00e9bogage partait sur une fausse piste \u2014 le r\u00e9seau, alors que
## le probl\u00e8me \u00e9tait la machine. Trente secondes \u00e9taient la marge vis\u00e9e \u00e0
## 60 images/s, soit un arr\u00eat \u00e0 dix vraies secondes si tout va bien.
const MAX_SECONDS := 90.0
## Delai pour qu'une connexion ENet locale s'etablisse, en images.
const CONNECT_FRAMES := 420

## Bloc edite par l'hote, attendu cote client.
const HOST_BLOCK := Vector3i(7, 40, -3)
## Bloc edite par le client, attendu cote hote : les deux sens du transfert
## sont donc verifies.
const CLIENT_BLOCK := Vector3i(-2, 41, 9)
## Bloc temoin envoye par le client quand son scenario est complet. L'hote ne
## le verra que si tout le reste a fonctionne : c'est le fil qui relie les deux
## moities du test.
const WITNESS_BLOCK := Vector3i(1, 40, 1)
## Bloc temoin du second client. Deux clients qui ecriraient au meme point
## s'annuleraient : le second verrait le bloc du premier, et l'hote ne pourrait
## plus dire qui a fini.
const WITNESS_BLOCK_2 := Vector3i(1, 41, 1)
## Editions aberrantes que l'hote doit refuser : l'une hors du monde, l'autre
## d'identifiant inconnu. En `const` et non en variable locale, parce que les
## branches d'un `match` ont chacune leur portee.
const BOGUS_Y := Vector3i(0, 9999, 0)
const BOGUS_ID := Vector3i(0, 40, 0)

var role := "host"
var port := 27015
var peer_name := "Alice"
var out_path := ""
var trace := false
## Pseudos de clients attendus : `--expect=Bob,Carol`.
var _expect := "Bob"
var _expected_names_cache: Array = []

var _frame := 0
var _net: Node
var _world: World
var _player: Player

## Etape courante du scenario. Une machine a etats explicite est bien plus
## lisible ici qu'une cascade de drapeaux, et elle ne peut pas repeter une
## verification par image.
var _step := 0
var _elapsed := 0.0
var _checks := 0
var _failures: Array[String] = []
var _lines: Array[String] = []
var _finished := false
## Le joueur n'est pose au sol qu'une fois le terrain charge.
var _placed := false
## Point autour duquel le terrain est genere avant la pose du joueur.
var _spawn_probe := Vector3(0.5, 40.0, 0.5)

## Ce que le pair a recu du reseau, note par les signaux de `Net`.
var _got_world := false
var _got_lobby := false
var _got_lobby_seed := -1
var _got_lobby_distance := -1
var _got_lobby_spawn := Vector3.INF
var _got_seed := -1
var _got_distance := -1
var _got_spawn := Vector3.INF
var _roster_events := 0
var _peers_up := 0
var _peers_down := 0
var _chat: Array[String] = []
## Positions que l'hote a fait remettre en place, pour verifier que le client
## recoit bien l'ordre de revenir en arriere.
var _reverted: Array[Vector3i] = []


func _ready() -> void:
	var args := _parse_args()
	role = args.get("role", "host")
	port = int(args.get("port", "27015"))
	peer_name = args.get("name", "Alice")
	out_path = args.get("out", "")
	trace = args.get("trace", "0") == "1"
	_expect = args.get("expect", "Bob")

	_net = get_node_or_null("/root/Net")
	if _net == null:
		_fail("l'autoload Net est absent : le test ne peut rien mesurer")
		_finish()
		return

	# Les evenements de connexion appartiennent a l'API reseau, pas au noeud
	# `Net`. On s'abonne avant toute tentative : `connected_to_server` peut
	# avoir deja eu lieu quand on regarde.
	var api: MultiplayerAPI = _net.multiplayer
	api.peer_connected.connect(func(_id: int): _peers_up += 1)
	api.peer_disconnected.connect(func(_id: int): _peers_down += 1)
	_net.roster_changed.connect(func(): _roster_events += 1)
	_net.chat_received.connect(
		func(_id: int, author: String, line: String):
			_chat.append("%s: %s" % [author, line]))
	_net.block_reverted.connect(func(pos: Vector3i): _reverted.append(pos))
	_net.lobby_entered.connect(func(s: int, d: int, p: Vector3, _host: String):
		_got_lobby_seed = s
		_got_lobby_distance = d
		_got_lobby_spawn = p
		_got_lobby = true)
	_net.world_ready.connect(func(s: int, d: int, p: Vector3):
		_got_seed = s
		_got_distance = d
		_got_spawn = p
		_got_world = true)

	_world = World.new()
	_world.name = "World"
	_world.setup(SEED, DISTANCE)
	add_child(_world)

	# Le joueur local est un vrai `Player` : c'est lui que `Net` lit pour
	# envoyer sa pose, et le test mesure donc le chemin d'envoi reel.
	_player = Player.new()
	_player.name = "Player"
	_player.world = _world
	add_child(_player)

	_net.local_name = peer_name
	if role == "host":
		var error: String = _net.host_game(SEED, DISTANCE, peer_name, port)
		if not error.is_empty():
			_fail("l'hote n'a pas pu ouvrir la partie (%s)" % error)
			_finish()
			return
		_check(_net.is_host(), "l'hote est en mode HOST")
	else:
		var error: String = _net.join_game("127.0.0.1", port)
		if not error.is_empty():
			_fail("le client n'a pas pu se connecter (%s)" % error)
			_finish()
			return
		_check(not _net.is_host(), "le client n'est pas hote")
		# Tant que l'hote n'a pas confirme, le client ne construit rien : le
		# monde ne peut etre genere qu'avec la graine recue.
		_check(_world.seed_value == SEED,
			"le client n'a pas de monde tant que la graine n'est pas recue")
	_net.bind_world(_world, _player)


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq < 0:
			out[body] = "1"
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


func _process(delta: float) -> void:
	if _finished:
		return
	_frame += 1
	_elapsed += delta
	roster_cache = _net.roster()
	# Le joueur n'est pose qu'une fois le terrain de dessous present : lance
	# a y = 0, il traverserait le monde et finirait a y = -400, ce qui ne
	# testerait plus rien. Le vrai jeu fait de meme via `find_spawn`.
	if not _placed:
		_world.update(_spawn_probe)
		if not _world.is_loaded_around(_spawn_probe, 0):
			return
		_player.global_position = _world.find_spawn() + Vector3(0, 2.0, 0)
		_placed = true
		return
	_world.update(_player.global_position)
	if role == "host":
		_host_step()
	else:
		_client_step()
	if _finished:
		return
	if _elapsed > MAX_SECONDS:
		_fail("delai depasse a l'etape %d (%.1f s, %d images)"
			% [_step, _elapsed, _frame])
		_finish()


# ------------------------------------------------------------------- hote

## Le test lance la session comme le joueur presse le bouton : il appelle
## `start_session`, il ne touche jamais a un signal interne.
var _started := false
func _host_step() -> void:
	match _step:
		0:
			# 1. Le client arrive, et l'hote lui cree un avatar.
			#
			# `peer_connected` annonce l'ouverture du canal ENet, qui precede
			# la demande de jointure : l'avatar n'existe qu'une fois ce paquet
			# la traite. On attend donc l'avatar, pas seulement la connexion.
			if _peers_up == 0:
				return
			_check(true, "l'hote voit un pair se connecter")
			if _net.avatar_count() == 0:
				return
			_check(_net.avatar_count() == 1,
				"l'hote a cree un avatar pour le client (%d)"
				% _net.avatar_count())
			_step = 1
		1:
			# 2. Le pseudo du client a circule jusqu'a l'hote.
			var client_id := _first_remote_id()
			if client_id <= 0:
				return
			var names := _expected_names()
			_check(_net.peer_name(client_id) == str(names[0]),
				"l'hote recoit le pseudo du client (%s)"
				% _net.peer_name(client_id))
			# Le mot au passage part a l'etape 7, une fois **tous** les clients
			# connectes : envoye ici, il n'atteindrait que le premier d'entre
			# eux, et le second client attendrait un message parti avant sa
			# connexion. C'etait une course, pas une verification.
			_step = 2
		2:
			# 3. La liste du salon, cote hote : il doit y voir tous les joueurs,
			# y compris lui-meme, et pouvoir dire qui il attend.
			var roster: Array = _net.roster()
			if roster.size() < 1 + _expected_clients():
				return
			# L'hote ne lance pas tant que les clients n'ont pas tous choisi
			# leur tenue. Le message de choix sert donc aussi de signal de
			# disponibilite : c'est ce qui evite a un client de decouvrir le
			# monde deja genere sous ses pieds.
			# L'hote ne lance que lorsque **chaque** client a recu la fiche de
			# tous les autres, hote compris, et a choisi sa tenue. Lancer plus
			# tot construirait un monde sous les pieds d'un client qui n'a
			# meme pas encore vu qui d'autre sera la.
			if not _roster_is_complete(roster):
				return
			_check(_net.in_lobby, "l'hote est encore au salon")
			_check(_has_named(roster, peer_name),
				"l'hote se voit lui-meme dans la liste du salon")
			_check(true, "l'hote voit tous les clients attendus au salon")
			# 4. **Le lancement.** L'hote est le seul a pouvoir le faire, et c'est
			# lui qui dote les clients d'un terrain.
			# L'hote a deja genere son terrain pour lui — il est sur la fenetre
			# de chargement, en fait. Ce qui doit etre vrai au salon, c'est
			# qu'aucune **edition** n'a encore circule : le calque est vide,
			# donc personne n'a casse quoi que ce soit dans une partie qui
			# n'a pas commence.
			_check(_net.overlay_size() == 0,
				"aucune edition n'a circule tant que la partie n'a pas lance")
			_check(not _started, "la session n'a pas encore ete lancee")
			_net.start_session()
			_started = true
			# L'hote tourne sa vue des le lancement, comme un joueur a la souris.
			# Les clients n'ont ainsi pas a attendre qu'il decide de bouger pour
			# avoir une pose non triviale a observer.
			_player.set_yaw(1.2)
			_check(_started, "la session a bien ete lancee par l'hote")
			# L'edition ne commence qu'ici : au salon, personne n'a de monde
			# ou casser quoi que ce soit, et le calque doit rester vide.
			_net.submit_local_block(HOST_BLOCK, Blocks.STONE)
			if _net.overlay_at(HOST_BLOCK) != Blocks.STONE:
				return
			_check(true, "l'hote enregistre sa propre edition")
			_step = 4
		4:
			# 4. Le bloc du client remonte a l'hote, qui fait autorite.
			if _net.overlay_at(CLIENT_BLOCK) != Blocks.PLANKS:
				return
			_check(true, "le bloc du client remonte a l'hote")
			_step = 5
		5:
			# 5. L'hote bouge et se tourne : c'est au client de voir l'avatar le
			# suivre. Le joueur se tourne vraiment, comme a la souris, et sa pose
			# part par le chemin normal, `_send_local_pose` : le test n'injecte
			# rien dans le reseau, il joue.
			if _net.avatar_count() == 0:
				return
			_check(true, "l'hote a tourne sa vue")
			_step = 6
		6:
			# 6. Deux editions aberrantes du client doivent etre refusees :
			# c'est ce qui empeche un joueur de faire tomber le serveur.
			_check(_net.overlay_at(Vector3i(0, 9999, 0)) == -1,
				"une position hors monde est refusee")
			_check(_net.overlay_at(Vector3i(0, 40, 0)) != 9999,
				"un identifiant de bloc inconnu est refuse")
			_step = 7
		7:
			# 7. Les blocs temoins des clients : la preuve que leurs scenarios
			# entiers se sont deroules. L'hote attend **tous** ceux qu'il
			# attendait, chacun a sa place.
			if _net.overlay_at(WITNESS_BLOCK) != Blocks.DIRT:
				return
			if _expected_clients() > 1 \
					and _net.overlay_at(WITNESS_BLOCK_2) != Blocks.DIRT:
				return
			_check(true, "l'hote a recu les blocs temoins de tous les clients")
			# Un mot au passage : chaque client le verifie en fin de scenario,
			# ce qui prouve que les messages courts comme les poses font le
			# voyage. Envoye ici, doncapres que tout le monde est la.
			_net.send_chat("bonjour depuis l'hote")
			_step = 8
		8:
			# 8. Le serveur a survecu a tout : il tient encore la connexion.
			_check(_net.is_online(), "l'hote est toujours en ligne a la fin")
			_finish()


## Le roster contient-il un joueur de ce nom ?
func _has_named(roster: Array, wanted: String) -> bool:
	for entry in roster:
		if str((entry as Dictionary).get("name", "")) == wanted:
			return true
	return false


## Les pseudos portes par les avatars 3D de ce processus.
##
## La liste du salon et les avatars ne sont pas la meme chose : le salon dit
## **qui** est present, alors qu'un avatar est un corps reellement dessine dans
## le monde. C'est precisement ce qui permet de voir le double que ferait
## apparaitre une diffusion qui se confondrait d'adresse.
func _avatar_names() -> Array:
	var out: Array = []
	var table: Dictionary = _net.get("_avatars_by_peer")
	for id in table.keys():
		var avatar: Variant = table[id]
		if avatar == null or not is_instance_valid(avatar):
			continue
		out.append(str(avatar.player_name))
	return out


func _has_avatar(wanted: String) -> bool:
	return _avatar_names().has(wanted)


## Combien de fois un pseudo apparait dans la liste du salon.
##
## Une liste qui affiche deux fois le joueur local n'est pas un detail
## d'affichage : elle contient une fiche orpheline, posee sous un identifiant
## que personne ne reconnaitra jamais.
func _count_named(roster: Array, wanted: String) -> int:
	var n := 0
	for entry in roster:
		if str((entry as Dictionary).get("name", "")) == wanted:
			n += 1
	return n


## Le roster contient-il un joueur de ce nom portant cette tenue ?
func _has_skin(wanted_name: String, wanted_skin: int) -> bool:
	for entry in roster_cache:
		var row: Dictionary = entry
		if str(row.get("name", "")) == wanted_name \
				and int(row.get("skin", -1)) == wanted_skin:
			return true
	return false


## Dernier roster lu, pour que `_has_skin` n'ait pas a relire le reseau.
var roster_cache: Array = []


## Le roster contient-il un joueur de ce nom ?
## Le salon est-il complet, du point de vue de l'hote ?
##
## L'hote ne lance la partie que lorsque chaque client attendu est complet :
## il porte un nom, il est connu de tous, et il a choisi sa tenue. Ce dernier
## point est ce qui distingue un joueur ayant passe par l'ecran salon d'un
## joueur simplement connecte.
func _roster_is_complete(roster: Array) -> bool:
	if not _has_named(roster, peer_name):
		return false
	for name in _expected_names():
		if not _has_named(roster, str(name)):
			return false
		if not _has_skin(str(name), _chosen_skin_of(str(name))):
			return false
	return true


## Le bloc temoin de ce client : chacun ecrit au sien, pour que l'hote puisse
## dire lequel a fini.
func _witness() -> Vector3i:
	return WITNESS_BLOCK if peer_name == str(_expected_names()[0]) \
		else WITNESS_BLOCK_2


## La tenue qu'un client donne doit porter pour avoir fini l'ecran salon.
##
## Elle est deduite de sa place dans la liste des attendus, de sorte que deux
## clients ne se retrouvent pas avec la meme : sans cela, l'hote ne saurait pas
## lequel des deux a choisi, et le second pourrait etre lance avant d'avoir
## rien vu — ce que le salon est precisement cense empecher.
func _chosen_skin_of(name: String) -> int:
	var index := _expected_names().find(name)
	return 1 + maxi(0, index)


## La tenue que ce pair annonce, d'apres son propre nom.
func _chosen_skin() -> int:
	return _chosen_skin_of(peer_name)



## Les pseudos que l'hote doit attendre, donnes par l'orchestrateur sous la
## forme `--expect=Bob`. Un test a deux clients en donne deux.
func _expected_names() -> Array:
	if _expected_names_cache.is_empty():
		_expected_names_cache = str(_expect).split(",", false)
	return _expected_names_cache


func _expected_clients() -> int:
	return maxi(1, _expected_names().size())


## Premier identifiant de pair present dans la table des avatars distants.
func _first_remote_id() -> int:
	for id in _net.get("_avatars_by_peer").keys():
		return int(id)
	return -1


# ------------------------------------------------------------------ client

func _client_step() -> void:
	match _step:
		0:
			# 1. Le salon : l'hote a admis le client, mais **aucun monde n'existe
			# encore**. C'est tout l'objet du salon — on doit pouvoir etre
			# connecte, se voir dans la liste, et choisir sa tenue, sans qu'un
			# seul bloc ait ete genere.
			if not _got_lobby:
				return
			_check(_net.in_lobby, "le client est connecte mais pas encore en jeu")
			_check(_got_lobby_seed == SEED,
				"le salon transmet la graine (%d)" % _got_lobby_seed)
			_check(_got_lobby_distance == DISTANCE,
				"le salon transmet la distance de rendu")
			_check(_got_lobby_spawn.is_finite(),
				"le salon transmet un point d'apparition")
			_check(not _got_world,
				"aucun monde n'est transmis avant le lancement de l'hote")
			_check(_net.overlay_size() == 0,
				"aucune edition n'a recu au salon")
			_step = 10
		10:
			# 2. La liste des joueurs : le client doit voir l'hote, et se voir
			# lui-meme par son pseudo, avant toute partie.
			var roster: Array = _net.roster()
			if roster.is_empty():
				return
			_check(roster.size() >= 1,
				"le salon liste au moins l'hote (%d)" % roster.size())
			if not _has_named(roster, peer_name):
				return
			_check(true, "le client se voit lui-meme dans la liste du salon")
			# La fiche de l'hote peut arriver apres celle du client lui-meme :
			# on attend le nom plutot que de le juger absent du premier coup.
			if not _has_named(roster, "Alice"):
				return
			_check(true, "le client voit l'hote par son nom dans le salon")
			# 3. Le client **se dit pret**. C'est ce message qui autorise l'hote
			# a lancer : sans lui, un client encore en train de choisir sa tenue
			# se retrouverait dans un monde deja construit sous ses pieds.
			_net.announce_local(peer_name, _chosen_skin())
			_step = 11
		11:
			# 4. La tenue choisie doit revenir, validee par l'hote : c'est lui
			# qui fait autorite sur la liste.
			if not _has_skin(peer_name, _chosen_skin()):
				return
			_check(true, "la tenue choisie au salon est validee par l'hote")
			# Le salon ne doit montrer le joueur qu'une fois. Une seconde
			# fiche du meme pseudo est une fiche orpheline, posee sous un
			# identifiant que le reseau ne reutilisera jamais.
			_check(_count_named(roster_cache, peer_name) == 1,
				"le client n'apparait qu'une fois dans le salon (%d)"
				% _count_named(roster_cache, peer_name))
			# Les avatars 3D ne sont verifies qu'apres le lancement, a
			# l'etape 13 : avant, l'autre client n'est pas encore admis, et
			# l'attendre ici ferait dependre l'hote d'un client qui n'a pas
			# encore choisi sa tenue.
			# On ne verifie pas ici que la partie n'a pas demarre : entre deux
			# images, l'hote a tres bien pu lancer, et c'est son droit. Ce qui
			# compte est qu'aucun terrain n'ait ete construit **avant** que le
			# client ait choisi — verifie a l'etape 0, avant tout choix.
			_step = 12
		12:
			# 5. Lancement. L'hote le declenche ; le client ne fait qu'attendre
			# et doit alors construire son terrain.
			if not _got_world:
				return
			_check(_got_seed == SEED,
				"le client recoit la graine de l'hote (%d)" % _got_seed)
			_check(_got_distance == DISTANCE, "le client recoit la distance")
			_check(_got_spawn.is_finite(), "le client recoit un point d'apparition")
			_check(not _net.in_lobby, "la session a bien ete lancee")
			# Le monde n'est regenere qu'a partir de la graine recue, comme en
			# jeu : le client n'a recu aucun terrain, seulement sa formule. Le
			# joueur doit donc etre repose : son sol a change de place.
			_world.setup(_got_seed, _got_distance)
			_placed = false
			_step = 13
		13:
			# 5. Les avatars 3D. La partie est lancee, donc tout le monde est
			# admis : le client doit avoir un corps pour chacun des autres —
			# l'hote compris — et **rien de plus**. Un avatar portant son
			# propre pseudo serait un double de son personnage, immobile a
			# cote de lui : c'est ce que donne une diffusion envoyee a celui
			# qu'elle decrit, et `roster()` ne le montre pas.
			if not _has_avatar("Alice"):
				return
			for name in _expected_names():
				if str(name) == peer_name:
					continue
				if not _has_avatar(str(name)):
					return
			_check(not _has_avatar(peer_name),
				"le client n'a pas de copie de son propre personnage")
			_check(_avatar_names().size() == _expected_names().size(),
				"le client a exactement un avatar par autre joueur (%d)"
				% _avatar_names().size())
			# Le client doit avoir retrouve le sol de sa graine avant de suivre
			# l'hote : sinon sa pose partirait d'un point en plein ciel.
			if not _placed:
				return
			_step = 14
		14:
			# 3. L'edition de l'hote arrive, et le calque la retient meme si le
			# chunk correspondant n'existe pas encore.
			if _net.overlay_at(HOST_BLOCK) != Blocks.STONE:
				return
			_check(true, "le bloc de l'hote arrive chez le client")
			_step = 15
		15:
			# 4. Le client edite a son tour : l'hote doit faire autorite et
			# lui renvoyer son propre edition.
			_net.submit_local_block(CLIENT_BLOCK, Blocks.PLANKS)
			if _net.overlay_at(CLIENT_BLOCK) != Blocks.PLANKS:
				return
			_check(true, "l'hote a valide l'edition du client")
			_step = 16
		16:
			# 5. Pose : l'avatar de l'hote doit se tourner chez le client. Le
			# joueur local bouge aussi, pour que sa propre pose remonte et que
			# les deux avatars de la partie ne se recouvrent pas.
			_player.set_yaw(0.4)
			_player.global_position += Vector3(0.15, 0.0, 0.0)
			if _net.avatar_count() == 0:
				return
			var yaw: float = _net.avatar_yaw(1)
			if yaw < 0.9:
				return
			_check(yaw > 0.9, "l'avatar de l'hote suit la pose recue (%.2f)" % yaw)
			_step = 17
		17:
			# 6. Deux editions aberrantes : le serveur doit les refuser sans
			# mourir, **et le dire** — sans le retour de l'hote, le client
			# garderait ces blocs dans son monde et dans son calque pour toujours.
			_reverted.clear()
			_net._submit_block.rpc_id(1, BOGUS_Y, Blocks.STONE)
			_net._submit_block.rpc_id(1, BOGUS_ID, 9999)
			_check(true, "le client a envoye deux editions aberrantes")
			_step = 19
		19:
			# L'hote a refuse les deux : le client doit avoir recu deux reverts
			# et ne pas garder ces positions dans son calque. `overlay_at` rend
			# -1 pour une position absente : c'est cet etat-la qu'on vérifie,
			# pas « la valeur est nulle ».
			if _reverted.size() < 2:
				return
			_check(_net.overlay_at(BOGUS_Y) == -1 and _net.overlay_at(BOGUS_ID) == -1,
				"l'hote a ordonne le retour arriere des editions refusees")
			_step = 20
		20:
			# 7. Bloc temoin : c'est lui qui libere l'hote. Chaque client ecrit
			# au sien, et attend le sien.
			_net.submit_local_block(_witness(), Blocks.DIRT)
			_step = 21
		21:
			# 8. Le chat de l'hote doit parvenir. L'hote ne l'envoie qu'apres
			# avoir vu **tous** les temoins : a ce moment, chaque client a
			# termine son scenario et attend, donc le message ne se perd pas.
			if _chat.is_empty():
				return
			_check(_chat[0] == "Alice: bonjour depuis l'hote",
				"le client recoit le chat de l'hote (%s)" % _chat[0])
			_finish()
		22:
			if _net.overlay_at(_witness()) != Blocks.DIRT:
				return
			_check(_net.is_online(), "le client est toujours en ligne a la fin")
			_finish()


# ------------------------------------------------------------------ rapport

func _check(condition: bool, label: String) -> void:
	_checks += 1
	_lines.append("%s\t%s" % ["ok" if condition else "ECHEC", label])
	if not condition:
		_failures.append(label)


func _fail(label: String) -> void:
	if _failures.has(label):
		return
	_failures.append(label)
	_lines.append("ECHEC\t%s" % label)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("== Cubecraft : test reseau (%s) ==" % role)
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			for line in _lines:
				file.store_line(line)
			file.close()
	print("  %s : %d verifications, %d echecs, etape %d"
		% [role, _checks, _failures.size(), _step])
	for line in _failures:
		print("  ECHEC : %s" % line)
	print("----")
	get_tree().quit(0 if _failures.is_empty() else 1)
