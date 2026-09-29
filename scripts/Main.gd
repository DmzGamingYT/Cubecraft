extends Node3D

## Point d'entree : assemble la scene 3D, prepare le monde, puis laisse la main
## au joueur une fois le terrain charge.
##
## Tout est construit en code plutot que dans un .tscn : le projet n'a aucun
## asset, la hierarchie est donc entierement deduite de la documentation de ce
## fichier et de ceux qu'il instancie.
##
## Sans option de demarrage auto, un ecran titre (TitleScreen) propose Jouer,
## Nouveau monde, Charger et Quitter : le monde n'est construit qu'au choix du
## joueur. Le retour au titre depuis la pause sauvegarde puis demonte la partie.
##
## Options en ligne de commande :
##   --seed=N          germe du monde (aleatoire sinon) ; demarrage auto
##   --distance=N      portee de rendu en chunks (si != 5 : demarrage auto)
##   --shader=N        mode de post-traitement au demarrage (0 = naturel, F6)
##   --load            demarre sur la sauvegarde existente (sa graine gagne)
##   --screenshot      capture l'ecran en ASCII puis quitte (diagnostic)
##   --fpshot          capture la vue subjective au point d'apparition, avec un
##                     cochon et un zombie poses devant (controle du design)
##   --loadingshot     capture l'ecran de chargement puis quitte (diagnostic)
##   --pauseshot       ouvre pause et inventaire, les capture, puis quitte
##   --titletest       capture l'ecran titre puis quitte (diagnostic)
##   --uitest          joue une serie de verifications d'interface puis quitte
##   --debugshot       ouvre le menu de debug, le capture, puis quitte
##   --debugrun        ouvre le menu, lance les verifications, puis quitte
##   --seconds=N       duree du mode capture / test
##
## Les modes de capture exigent une fenetre : `--headless` ne declenche jamais
## `RenderingServer.frame_post_draw`, la capture n'aurait donc rien a lire.

## Rayon (en chunks) autour du joueur qui doit etre pret avant de le liberer.
## Il vaut 1, pas 2 : un carre de rayon 2 a ses coins a une distance de 2,83
## chunks, et le disque genere s'arrete a `portee + 1` — a petite portee de
## rendu, les coins ne seraient jamais produits et le chargement bloquerait.
const SPAWN_READY_RADIUS := 1

## Duree du fondu qui amene puis efface l'ecran de chargement.
const LOADING_FADE := 0.45

## Secondes entre deux conseils affiches pendant la generation.
const TIP_PERIOD := 4.5

## Conseils affiches pendant la generation : ils expliquent les regles du jeu
## au moment ou le joueur attend, plutot que dans un tutoriel.
const LOADING_TIPS := [
	"les minerais demandent la bonne pioche : a mains nues, la pierre ne donne rien.",
	"clic droit sur un etabli : la grille 3x3 complete s'ouvre.",
	"un baton et un morceau de charbon donnent quatre torches.",
	"les feuilles lachent parfois une pomme ou un baton.",
	"F active le vol, Maj court, Ctrl s'accroupit.",
	"la molette prend le bloc vise et le range dans la barre rapide.",
	"fer brut plus charbon donnent un lingot de fer.",
	"les zombies sortent la nuit et brulent a l'aube.",
	"la table d'enchantement consomme du lapis et de l'experience.",
	"sous l'eau l'air s'epuise : remontez avant de vous noyer.",
	"F5 sauvegarde, Echap ouvre la pause, E l'inventaire, F4 le menu de debug.",
]

var world: World
var player: Player
var fx: Fx
var hud: HUD
var torch_lights: TorchLights
var sun: DirectionalLight3D
var env: Environment
var _sky_material: ProceduralSkyMaterial
var mobs: Mobs
var weather: Weather
## Post-traitement d'ecran : il vit des l'ecran titre, donc hors de `_build_world`.
var postfx: PostFx

var _loading_layer: CanvasLayer
var _loading_root: Control
var _loading_label: Label
var _loading_bar: ProgressBar
var _loading_stats: Label
var _loading_tip: Label
var _loading_wanted := false
var _loading_tween: Tween
var _tip_index := -1
var _tip_timer := 0.0
var _ready_to_play := false
var _leaving_title := false
## Vrai entre la demande de connexion et la reception du monde par l'hote.
## L'ecran titre reste affiche pendant ce temps : c'est lui qui montre
## « Connexion… », et repartir sur une partie solo par defaut ferait croire a
## l'utilisateur que la connexion a echoue sans dire pourquoi.
var _pending_join := false
## La partie en cours vient du reseau. La sauvegarde locale est alors desactivee :
## ecrire sur le disque un monde que seul l'hote detient fourrerait des blocs
## differents de ceux du serveur dans la prochaine partie solo.
var _net_started := false
## Tenue choisie sur l'ecran titre, transmise aux autres joueurs.
var _skin_index := 0
## Rayon de terrain a attendre avant de liberer le joueur. Elargi par le tirage
## de l'ecran de chargement, qui doit rester a l'ecran le temps de la photo.
var _ready_radius := SPAWN_READY_RADIUS
var _elapsed := 0.0
var _screenshot_mode := false
## Capture en vue subjective, au niveau du sol : c'est le cadrage ou l'on juge
## les textures du monde (feuillage, minerais, creatures) telles que le joueur
## les voit, et non une vue de dessus.
var _fpshot := false
var _loading_shot := false
var _capturing := false
var _ui_test := false
var _pause_shot := false
var _title_test := false
var _debug_shot := false
var _debug_run := false
var _centre_failures: Array[String] = []
var _last_report := 0.0
var _shot_delay := 4.0
var _running_limit := 0.0
var title: TitleScreen
## Le salon d'attente en reseau. Nul tant qu'aucune partie en cours n'a ete
## ouverte : il vit entre la connexion et le monde, donc jamais en jeu.
var lobby: Lobby
## Graine et distance retenues par le salon, en attente du lancement. L'hote
## les choisit avant que la partie existe, et le client les recoit de lui.
var _lobby_seed := 0
var _lobby_distance := 5
## Couche du salon. Au-dessus du titre, au-dessous de l'interface de jeu.
var _lobby_layer: CanvasLayer
## L'autoload `Net`, resolu par son nom : comme pour `Sounds`, le passer par
## son identifiant casserait la compilation des scripts testes hors du jeu.
var _net: Node
## Menu de diagnostic (F4). Il vit **hors du HUD**, dans sa propre couche, et
## c'est indispensable : la sequence de verifications demonte la partie et
## relance depuis le titre, donc un menu accroche au HUD disparaitrait au
## moment precis ou l'on veut lire son resultat. Au-dessus du HUD (10) pour
## etre au-dessus des ecrans d'inventaire, en dessous du salon (35).
var debug_menu: DebugMenu
var _debug_layer: CanvasLayer
## Une sequence est-elle en cours ? Le menu desactive son bouton pendant ce
## temps : deux sequences en parallele partageraient le meme joueur et le
## meme monde, et leurs resultats se contrediraient.
var _debug_running := false
## Sequence en cours, pour son rapport final.
var _diag: Diagnostics


func _ready() -> void:
	var args := _parse_args()
	_net = _autoload("Net")
	if _net != null:
		_net.world_ready.connect(_on_net_world_ready)
		_net.lobby_entered.connect(_on_net_lobby_entered)
		_net.roster_changed.connect(_on_net_roster_changed)
		_net.join_failed.connect(_on_net_join_failed)

	Game.world_seed = int(args["seed"])
	Game.render_distance = int(args["distance"])
	if Game.world_seed == 0:
		Game.world_seed = randi()
	_screenshot_mode = bool(args["screenshot"])
	_fpshot = bool(args["fpshot"])
	_loading_shot = bool(args["loadingshot"])
	_ui_test = bool(args["uitest"])
	_pause_shot = bool(args["pauseshot"])
	_title_test = bool(args["titletest"])
	_debug_shot = bool(args["debugshot"])
	_debug_run = bool(args["debugrun"])
	_running_limit = float(args["seconds"])
	_shot_delay = _running_limit if (_screenshot_mode or _fpshot) else 4.0
	if _loading_shot:
		# Le panneau doit rester a l'ecran le temps de la photo : on attend un
		# disque de terrain plus large, et le tirage se fige a 1,5 s par defaut.
		_ready_radius = 3
		_shot_delay = _running_limit if _running_limit > 0.0 else 1.5

	_build_environment()
	_build_postfx()
	if int(args["shader"]) > 0:
		postfx.set_index(int(args["shader"]))
	_build_loading()
	_build_title()
	_build_debug_menu()
	# Demarrage auto seulement sur demande explicite : sinon c'est l'ecran
	# titre qui choisit la graine, et le monde attend ce choix.
	var auto := _screenshot_mode or _fpshot or _loading_shot or _ui_test \
		or _pause_shot or _debug_shot or _debug_run or bool(args["load"]) \
		or int(args["seed"]) != 0 or int(args["distance"]) != 5
	if auto:
		_start_new_game(Game.world_seed, Game.render_distance,
			bool(args["load"]) and Game.has_save())
	else:
		title.show_menu(Game.has_save(), Game.render_distance)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	get_window().title = "Cubecraft"
	# Fermer par la croix doit passer par la meme sortie propre que les menus
	# (arret des sons) : Godot ne quitte donc pas tout seul.
	get_tree().auto_accept_quit = false


## Fermeture demandee par la fenetre (croix, Cmd+Q).
## L'hote a transmis la description du monde : on construit un terrain
## identique au sien et on pose le joueur au point d'apparition de l'hote.
## Sans cette attente, un client demarrerait avec sa propre graine et les deux
## joueurs seraient sur deux mondes differents, sans aucun moyen de le voir.
func _on_net_world_ready(seed_value: int, distance_value: int,
		spawn_point: Vector3) -> void:
	if world != null:
		return
	_pending_join = false
	if world != null:
		return
	await _leave_title()
	# Le salon se referme et le monde commence : c'est le meme chemin que celui
	# suivi par l'hote quand il lance lui-meme sa partie.
	_begin_session(seed_value, distance_value, spawn_point)
	# L'hote a pu ouvrir sa partie ailleurs qu'a son point d'apparition : on
	# rejoint exactement la ou il est.
	if _net != null:
		_net.announce_local(_net.local_name, _skin_index)


## Le client vient d'etre admis par l'hote : on ouvre le salon. C'est le moment
## de se nommer et de choisir sa tenue, et de voir qui d'autre est deja la.
func _on_net_lobby_entered(seed_value: int, distance_value: int,
		_spawn_point: Vector3, host_name: String) -> void:
	_pending_join = false
	if world != null:
		# Le monde existe deja : la session a ete lancee, ce salon est trop tard.
		return
	await _leave_title()
	_show_lobby(seed_value, distance_value, host_name)


## Ouvre le salon. `host_name` est le nom affiche en tete : pour l'hote, son
## propre pseudo ; pour un client, celui de l'hote, qu'il ne connait pas encore.
func _show_lobby(seed_value: int, distance_value: int, host_name: String) -> void:
	if _net == null or lobby != null:
		return
	# Le salon est un ecran a part entiere : la musique du titre s'y arrete,
	# sinon elle couvrirait le silence d'attente que l'ecran cherche a creer.
	if title != null:
		title.stop_music()
	_lobby_seed = seed_value
	_lobby_distance = distance_value
	lobby = Lobby.new()
	lobby.name = "Lobby"
	lobby.set_host(_net.is_host())
	lobby.set_local(_skin_index, _net.local_name)
	lobby.start_requested.connect(_on_lobby_start)
	lobby.skin_changed.connect(_on_lobby_skin)
	lobby.name_changed.connect(_on_lobby_name)
	lobby.quit_requested.connect(_on_lobby_quit)
	if _lobby_layer == null:
		_lobby_layer = CanvasLayer.new()
		_lobby_layer.name = "LobbyLayer"
		# Au-dessus du titre (30), en dessous de l'interface de jeu : le salon
		# ne doit masquer ni le monde ni son interface quand la partie part.
		_lobby_layer.layer = 35
		add_child(_lobby_layer)
	_lobby_layer.add_child(lobby)
	lobby.set_roster(_net.roster())


## La liste des joueurs a change : on la reflette telle quelle dans le salon.
## Sans terrain, un avatar de plus coute trois francs et ne fait rien clignoter.
func _on_net_roster_changed() -> void:
	if lobby != null:
		lobby.set_roster(_net.roster())


## Le joueur change de tenue au salon. L'hote garde la sienne pour l'ecran
## titre ; un client l'annonce, et l'hote la redistribue a tout le monde.
func _on_lobby_skin(skin: int) -> void:
	_skin_index = skin
	if _net != null:
		_net.announce_local(_net.local_name, skin)


func _on_lobby_name(display_name: String) -> void:
	if _net != null:
		_net.announce_local(display_name, _skin_index)


## L'hote lance la partie. C'est le seul passage du salon au monde, des deux
## cotes : le client attendait precisement ce message.
func _on_lobby_start() -> void:
	if _net == null or not _net.is_host():
		return
	_net.start_session()
	# L'hote n'est pas attendu par le signal que recoivent les clients : il
	# demarre son propre monde ici, immediatement.
	_begin_session(_lobby_seed, _lobby_distance, _net.spawn)


## Le salon se referme, et le monde commence. Chemin unique pour l'hote et le
## client : les deux ont recu la meme graine, donc le meme terrain.
func _begin_session(seed_value: int, distance_value: int,
		spawn_point: Vector3) -> void:
	_hide_lobby()
	_start_new_game(seed_value, distance_value, false, true)
	if player != null and spawn_point.length() > 0.0:
		player.global_position = spawn_point


## Sortir du salon : on coupe la partie et on revient au titre. L'hote qui
## quitte emporte la partie avec lui, c'est le sens de l'avertissement.
func _on_lobby_quit() -> void:
	if _net != null and _net.is_host() and _net.player_count() > 1:
		lobby.set_roster(_net.roster())
		return
	if _net != null:
		_net.leave()
	_hide_lobby()
	_on_back_to_title()


func _hide_lobby() -> void:
	if lobby != null:
		lobby.queue_free()
		lobby = null


## Le serveur a refuse la connexion, ou la connexion est tombee. On revient a
## l'ecran titre pour que le joueur puisse reessayer, plutot que de le laisser
## devant un monde a moitie charge qui n'appartient a personne.
func _on_net_join_failed(reason: String) -> void:
	_pending_join = false
	if world != null:
		_on_back_to_title()
	elif title != null:
		title.show_message(reason)


static func _autoload(name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.quit_game()


# -------------------------------------------------------------- construction

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.45, 0.86)
	sky_material.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.ground_bottom_color = Color(0.30, 0.28, 0.27)
	sky_material.ground_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.sun_angle_max = 28.0
	sky_material.sun_curve = 0.15

	var sky := Sky.new()
	sky.sky_material = sky_material
	_sky_material = sky_material

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# L'ambiance vient du ciel : elle seulle les faces tournees vers le bas,
	# que le soleil ne atteint jamais. Assez basse pour que l'eclairement de
	# face et l'occlusion ambiante sculptent le relief au lieu d'etre noyes.
	env.ambient_light_energy = 0.75
	# FILMIC ecrase les demi-teintes vers le noir : on relève le point blanc
	# pour que le terrain garde ses couleurs au lieu de virer au gris sombre.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.80, 0.92)
	# Le lointain fond dans la brume, mais le premier plan reste net.
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun_node := DirectionalLight3D.new()
	sun_node.name = "Sun"
	sun = sun_node
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	# 90 blocs d'ombre etaient demands : a cette taille, la carte d'ombre couvre
	# une surface enormously plus grande que l'ecran, pour une precision que
	# personne ne voit au-dela de quelques dizaines de blocs. C'etait la
	# premiere source de chauffe du jeu. 48 garde des ombres nettes la ou l'on
	# joue, et laisse le GPU respirer.
	sun.directional_shadow_max_distance = 48.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	add_child(sun)


## Le post-traitement est construit avec le decor, et non avec la partie : la
## touche doit repondre a l'ecran titre comme en jeu.
func _build_postfx() -> void:
	postfx = PostFx.new()
	postfx.name = "PostFx"
	add_child(postfx)
	Game.postfx = postfx


func _build_world() -> void:
	world = World.new()
	world.name = "World"
	world.setup(Game.world_seed, Game.render_distance)
	add_child(world)

	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)

	player = Player.new()
	player.name = "Player"
	player.world = world
	add_child(player)
	# L'inventaire de depart est donne avant l'enregistrement : l'interface peut
	# ainsi le lire des son `_ready`.
	player.inventory.add(Items.block_item(Blocks.PLANKS), 8)
	player.inventory.add(Items.STICK, 4)

	torch_lights = TorchLights.new()
	torch_lights.name = "TorchLights"
	torch_lights.world = world
	torch_lights.follow = player
	add_child(torch_lights)

	# Creatures : apparaissent autour du joueur, le jour pour les animaux,
	# la nuit pour les zombies.
	mobs = Mobs.new()
	mobs.name = "Mobs"
	mobs.world = world
	add_child(mobs)

	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)


func _build_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.pause_menu.title_requested.connect(_on_back_to_title)
	hud.death_screen.title_requested.connect(_on_back_to_title)


## Panneau de diagnostic ouvert par F4. Il n'appartient pas au HUD : la sequence
## de verifications qu'il lance termine par un retour au titre suivi d'une
## relance, et un menu enfant du HUD serait detruit au milieu de son propre
## rapport.
func _build_debug_menu() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.name = "DebugLayer"
	_debug_layer.layer = 15
	add_child(_debug_layer)
	debug_menu = DebugMenu.new()
	debug_menu.name = "DebugMenu"
	debug_menu.action_requested.connect(_on_debug_action)
	_debug_layer.add_child(debug_menu)


## F4 et Ctrl+Alt+D ouvrent et ferment le menu. C'est ici plutot que dans le
## HUD parce que le menu doit rester accessible a l'ecran titre, ou il n'y a
## encore aucun HUD. F6 y vit pour la meme raison : le rendu se regle depuis
## le menu de lancement comme depuis la partie.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shader_toggle"):
		if postfx != null:
			postfx.cycle()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("debug_menu"):
		return
	if debug_menu.visible:
		debug_menu.close()
	else:
		debug_menu.open()
	get_viewport().set_input_as_handled()


## Le joueur a clique un bouton du menu. Chaque action est un cas a part :
## certaines ne valent rien hors d'une partie, et il vaut mieux le dire dans le
## journal que d'ignorer silencieusement le clic.
func _on_debug_action(id: String) -> void:
	match id:
		"run_checks":
			_run_diagnostics()
		"probe":
			var report := Diagnostics.probe(Game.world, Game.player)
			print(report)
			debug_menu.add_log(report)
		"teleport_spawn":
			if Game.player == null:
				return
			Game.player.global_position = Game.spawn + Vector3(0, 1, 0)
			Game.player.velocity = Vector3.ZERO
			debug_menu.add_log("Teleporte au point d'apparition %s" % Game.spawn)
		"teleport_up":
			if Game.player == null:
				return
			Game.player.global_position.y += 20.0
			Game.player.velocity = Vector3.ZERO
			debug_menu.add_log("Monte de 20 blocs : %s (le terrain se genere)" \
				% Game.player.global_position)
		"give":
			if Game.player == null:
				return
			var inv := Game.player.inventory
			inv.add(Items.block_item(Blocks.PLANKS), 64)
			inv.add(Items.block_item(Blocks.STONE), 64)
			inv.add(Items.block_item(Blocks.COBBLESTONE), 64)
			inv.add(Items.block_item(Blocks.TORCH), 32)
			inv.add(Items.STICK, 16)
			inv.add(Items.WOOD_PICKAXE, 1)
			inv.add(Items.STONE_PICKAXE, 1)
			inv.add(Items.STONE_SWORD, 1)
			inv.add(Items.APPLE, 8)
			inv.add(Items.COAL, 8)
			debug_menu.add_log("Kit de survie donne : %d epees, %d planches"
				% [inv.count_of(Items.STONE_SWORD),
					inv.count_of(Items.block_item(Blocks.PLANKS))])
		"heal":
			if Game.player == null:
				return
			Game.player.health = Player.MAX_HEALTH
			Game.player.food = Player.MAX_FOOD
			debug_menu.add_log("Vie et faim au maximum.")
		"time":
			_cycle_time()
		"weather":
			if Game.weather == null:
				return
			Game.weather.set_mode(posmod(Game.weather.mode_index() + 1,
				Weather.MODES.size()))
			debug_menu.add_log("Meteo : %s" % Game.weather.mode_name())
		"save":
			debug_menu.add_log("Sauvegarde : %s"
				% ("ecrite" if Game.save_game() else "ECHEC"))
		"quit":
			debug_menu.close()
			await Game.quit_game()


## Le bouton « heure » avance d'un quart de jour : lever, midi, coucher, nuit.
## On ne fait pas un curseur pour une valeur a quatre crans.
func _cycle_time() -> void:
	var current := 0
	for i in DebugMenu.HOURS.size():
		if absf(float(DebugMenu.HOURS[i][0]) - Game.day_time) < 0.03:
			current = i
			break
	current = posmod(current + 1, DebugMenu.HOURS.size())
	Game.day_time = float(DebugMenu.HOURS[current][0])
	debug_menu.add_log("Heure fixee : %s" % str(DebugMenu.HOURS[current][1]))


## Lance la sequence de verifications depuis le menu. C'est exactement le meme
## code que `--uitest` : seul le depart change. Le verdict part sur la console,
## comme avant, et en plus dans le journal du menu.
## Capture de controle du menu de debug (`--debugshot`).
##
## Le menu se verifie dans une fenetre comme `--pauseshot` : on l'ouvre sur une
## partie chargee, on capture, on quitte. La liste de verifications est remplie
## a la main avec les trois etats possibles — passe, echoue, en attente — parce
## que la vraie sequence detruit la partie qu'elle capture ; ici on veut
## juger la mise en page, pas rejouer le test.
func _open_debug_menu_shot() -> void:
	var sample := Checklist.new()
	sample.add("la pile quitte l'emplacement")
	sample.set_result(0, true)
	sample.add("le curseur tient la pile")
	sample.set_result(1, false, "30 au lieu de 0")
	sample.add("deplacement rapide vers la barre")
	debug_menu.set_checklist(sample)
	debug_menu.add_log("Sonde du chunk sous la camera.")
	debug_menu.add_log("Teleporte au point d'apparition (0, 68, 0)")
	debug_menu.add_log("Kit de survie donne : 1 epees, 64 planches")
	debug_menu.add_log("ECHEC : le curseur tient la pile", DebugMenu.FAIL_COLOR)
	debug_menu.open()


## Le chemin **par le menu** de bout en bout (`--debugrun`).
##
## `--uitest` fait la meme sequence, mais en mode fenetre invisible et en
## quittant aussitot : il ne prouve donc rien de ce que voit un joueur. Ici on
## ouvre reellement le menu, on clique le bouton, on attend, et on verifie les
## trois choses qui peuvent ne marcher que par le menu : qu'il survit au
## demontee de la partie, que ses lignes se remplissent, et que le rapport
## s'affiche.
func _debug_run_shot() -> void:
	debug_menu.open()
	_on_debug_action("run_checks")
	var waited := 0
	while _debug_running and waited < 1200:
		await get_tree().process_frame
		waited += 1
	var done := _diag.checklist.done_count()
	print("[debugrun] attente terminee en %d images, sequence %s" % [
		waited, "terminee" if not _debug_running else "TOUJOURS EN COURS"])
	print("[debugrun] %s" % _diag.checklist.report_line())
	print("[debugrun] %d/%d lignes rendues dans le menu" % [
		done, _diag.checklist.count()])
	for name in _diag.checklist.failed_names():
		print("[debugrun] ECHEC : %s" % name)
	print("[debugrun] menu toujours visible : %s" % debug_menu.visible)
	print("[debugrun] partie relancee : monde=%s joueur=%s" % [
		world != null, player != null])
	# Le menu ne se reactualise qu'a son tick (6 fois par seconde) : on lui laisse
	# le temps de replacer son defilement avant de mesurer.
	await get_tree().create_timer(1.0).timeout
	_dump_ui(debug_menu)


func _run_diagnostics() -> void:
	if _debug_running:
		return
	if world == null or player == null or hud == null or not _ready_to_play:
		debug_menu.add_log("Impossible : la partie n'est pas prete.")
		return
	_debug_running = true
	_diag = Diagnostics.new()
	# Les deux derniers arguments sont des `Callable` et non des valeurs : la
	# sequence finit par demonter la partie et la relancer, et ni le retour au
	# titre ni l'etat « pret a jouer » ne peuvent etre captures au depart.
	_diag.setup(get_tree(), world, player, hud, mobs, weather, sun, title,
		_on_back_to_title, func() -> bool: return _ready_to_play)
	_diag.finished = _on_diagnostics_finished
	debug_menu.set_checklist(_diag.checklist)
	debug_menu.add_log("Sequence de verifications lancee…")
	_diag.run()


func _on_diagnostics_finished() -> void:
	_debug_running = false
	var line := _diag.checklist.report_line()
	print("UI %s" % line)
	for name in _diag.checklist.failed_names():
		print("UI ECHEC : %s" % name)
		debug_menu.add_log("ECHEC : %s" % name, DebugMenu.FAIL_COLOR)
	debug_menu.add_log(line,
		DebugMenu.FAIL_COLOR if _diag.checklist.failed_count() > 0
		else DebugMenu.OK_COLOR)


## Panneau de generation : fond noir, titre, barre de progression a la mode
## Minecraft, compteurs reels et un conseil qui tourne. Rien n'est anime au
## hasard : la barre suit le nombre de chunks vraiment prets.
func _build_loading() -> void:
	if _loading_layer != null:
		return
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 20
	add_child(_loading_layer)

	_loading_root = Control.new()
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_screen(_loading_root)
	_loading_layer.add_child(_loading_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.05)
	UiKit.fill_screen(backdrop)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(backdrop)

	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.panel(UiKit.BG_SOLID, 3, Color(0.03, 0.03, 0.04), 4))
	panel.custom_minimum_size = Vector2(470, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var heading := UiKit.label("CUBECRAFT", 28, Color(0.92, 0.92, 0.92))
	heading.add_theme_color_override("font_shadow_color", Color(0.1, 0.1, 0.1))
	heading.add_theme_constant_override("shadow_offset_y", 2)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	_loading_label = UiKit.label("Génération du monde…", 16, UiKit.TEXT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_label)

	_loading_bar = UiKit.progress_bar(430, 18)
	# `ProgressBar` est un `Range` : par defaut il va de 0 a 100 par pas d'un.
	# La progression est calculee en 0..1, on adapte donc la plage.
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.step = 0.001
	box.add_child(_loading_bar)

	_loading_stats = UiKit.label("", 13, UiKit.TEXT_DIM)
	_loading_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_loading_stats)

	# Le conseil change de ligne regulierement : l'attente parait plus courte,
	# et le joueur apprend une regle du jeu au lieu de fixer un texte fige.
	var tip_panel := PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel",
		UiKit.panel(Color(0.08, 0.11, 0.09, 1.0), 2, Color(0.03, 0.03, 0.04), 3))
	box.add_child(tip_panel)
	_loading_tip = UiKit.label("", 14, Color(1.0, 0.95, 0.55))
	_loading_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_tip.custom_minimum_size = Vector2(400, 44)
	tip_panel.add_child(_loading_tip)

	_loading_layer.visible = false


func _build_title() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TitleLayer"
	layer.layer = 30
	add_child(layer)
	title = TitleScreen.new()
	title.name = "Title"
	title.play_requested.connect(_on_title_play)
	title.load_requested.connect(_on_title_load)
	title.quit_requested.connect(func(): Game.quit_game())
	title.host_requested.connect(_on_title_host)
	title.join_requested.connect(_on_title_join)
	title.skin_changed.connect(_on_title_skin)
	layer.add_child(title)
	title.hide_menu()


## La tenue choisie dans l'apercu du menu titre devient celle du joueur : c'est
## elle que les autres verront en multijoueur, celle que le salon affiche, et
## celle du prochain avatar distant. Sans ce branchement, le choix du menu
## n'aurait servi a rien une fois la partie lancee.
func _on_title_skin(skin: int) -> void:
	_skin_index = skin


## Demarre une partie : construit monde, joueur et interface, puis charge le
## terrain autour du point d'apparition. `from_save` relit la graine de la
## sauvegarde pour generer le bon terrain (sans cela, le monde serait tire
## avec une autre graine que celle des chunks edites).
func _start_new_game(seed_value: int, distance: int, from_save := false,
		is_network := false) -> void:
	if from_save and Game.has_save():
		seed_value = _save_seed()
	if seed_value == 0:
		seed_value = randi()
	Game.world_seed = seed_value
	Game.render_distance = distance
	if not from_save:
		Game.day_time = 0.05  # nouveau monde : le matin
	# Un client ne charge jamais la sauvegarde : sa partie vit dans la memoire
	# de l'hote, et relire un fichier local lui montrerait un monde different
	# de celui que voit l'hote.
	_net_started = is_network
	if is_network and _net != null:
		_net.announce_local(_net.local_name, _skin_index)
	_build_world()
	# Les objets sont enregistres au fur et a mesure : l'interface est
	# construite ensuite et lit deja `Game.player` dans son `_ready`.
	# Le reseau doit connaitre monde et joueur avant toute edition : sans cela
	# un bloc casse pendant l'ecran de chargement partirait dans le vide.
	_net.bind_world(world, player)
	Game.world = world
	Game.player = player
	Game.fx = fx
	Game.mobs = mobs
	Game.weather = weather
	weather.bind(env, _sky_material)
	_build_ui()
	Game.hud = hud
	if title != null:
		title.hide_menu()

	Game.spawn = world.find_spawn()
	player.global_position = Game.spawn + Vector3(0, 3, 0)
	player.can_move = false

	_show_loading(true)
	if from_save and Game.has_save():
		Game.load_game()

	if _screenshot_mode:
		# Juste au-dessus du sol et plongeant : c'est le cadrage qui montre le
		# mieux si les textures, les teintes de biome et l'AO sont justes.
		# Midi pile pour une lumiere de reference stable.
		Game.day_time = 0.25
		player.flying = true
		player.global_position = Game.spawn + Vector3(15, 70, -16)
		player.set_yaw(0.0)
		player.set_pitch(deg_to_rad(-89.0))
	elif _fpshot:
		# Le joueur, debout, le regard legerement plongeant : c'est ce que voit
		# reellement le joueur, donc le seul cadrage ou l'on juge une texture de
		# bloc ou une creature.
		Game.day_time = 0.25
		player.flying = false
		player.global_position = Game.spawn + Vector3(0, 0.2, 0)
		player.set_yaw(0.0)
		# Assez plongeant pour que le rayon du reticule tombe sur un bloc dans
		# la portee du joueur (5 blocs) : sinon la capture ne montrerait ni
		# fissures ni bloc vise, seulement de l'herbe au loin.
		player.set_pitch(deg_to_rad(-24.0))
		_face_forest(player)


func _save_seed() -> int:
	var data := SaveSystem.read()
	return int(data.get("seed", 0))


func _on_title_play(seed_value: int, distance: int) -> void:
	await _leave_title()
	_start_new_game(seed_value, distance, false)


## Amene le joueur devant la foret la plus proche et le tourne vers elle.
##
## Une plaine n'a que 5 % de chances de porter un arbre : la capture de design
## tombait donc presque toujours sur de l'herbe, et une texture de feuillage ne
## se juge pas de loin. On se place a six blocs d'une colonne de foret, hors de
## la couronne — se garer dessous mettrait la camera dans les feuilles, ce qui
## ne montrerait rien.
func _face_forest(spotter: Player) -> void:
	var origin := Vector2i(floori(Game.spawn.x), floori(Game.spawn.z))
	var target := Vector2i.ZERO
	var found := false
	for ring in range(6, 96, 3):
		for step in 12:
			var angle := TAU * float(step) / 12.0
			var probe := origin + Vector2i(roundi(cos(angle) * ring), roundi(sin(angle) * ring))
			if world.biome_at(probe.x, probe.y) != Biomes.FOREST:
				continue
			target = probe
			found = true
			break
		if found:
			break
	if not found:
		return
	# On recule de six blocs en s'ecartant de l'origine, puis on regarde la
	# colonne visee : l'arbre est devant, la camera reste dehors.
	var away := Vector2(float(target.x - origin.x), float(target.y - origin.y))
	away = away.normalized() if away.length() > 0.01 else Vector2(0, 1)
	var stand := Vector2(target) - away * 6.0
	var ground := world.surface_height(int(stand.x), int(stand.y))
	if ground <= 0:
		return
	spotter.global_position = Vector3(stand.x, float(ground) + 1.2, stand.y)
	spotter.set_yaw(atan2(-away.x, -away.y))
	spotter.set_pitch(deg_to_rad(-12.0))


## Deux creatures posees devant la camera pour la capture de design : sans
## elles, `--fpshot` ne montrerait presque jamais d'animal, et la teinte d'un
## cochon ne se juge pas dans un menu. Le cochon est a droite, le zombie a
## gauche, tous deux tournes vers le joueur.
func _pose_showcase_mobs(looker: Player) -> void:
	if mobs == null:
		return
	var origin := looker.global_position
	# Le lacet vient de `set_yaw`, pas de `rotation.y` : celle-ci n'est posee
	# qu'a la prochaine image physique.
	var yaw: float = looker.get_yaw()
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	# Le modele d'un mob regarde vers -z : il se tourne vers le joueur avec le
	# meme atan2 que son IA de poursuite.
	for pose in [[Mob.Kind.PIG, ahead * 4.0 + side * 1.6],
			[Mob.Kind.ZOMBIE, ahead * 5.0 - side * 1.8]]:
		var spot: Vector3 = origin + pose[1]
		spot.y = float(world.surface_height(int(floor(spot.x)), int(floor(spot.z)))) + 0.2
		var mob := mobs.spawn_at(pose[0], spot, 0.0)
		if mob != null:
			var to_player := origin - spot
			mob.rotation.y = atan2(-to_player.x, -to_player.z)
			# Gele : l'IA l'eloignerait du cadre et le soleil brulerait le
			# zombie avant la capture.
			mob.set_physics_process(false)
			mob.velocity = Vector3.ZERO


## Fige les fissures de minage sur le bloc vise, a mi-parcours.
##
## Les fissures ne durent qu'une fraction de seconde en jeu : impossible d'en
## juger le dessin sur une capture au hasard. On les pose ici sur le bloc que
## le reticule designe, comme si le joueur etait en train de le casser — c'est
## justement l'etat que la capture doit montrer.
func _freeze_showcase_mining(miner: Player) -> void:
	if miner.camera == null or miner.break_overlay == null:
		return
	var hit := VoxelRaycast.cast(world, miner.camera.global_position,
		miner.look_direction(), Player.REACH)
	if not hit["hit"]:
		return
	miner.break_overlay.set_mining(hit["pos"], 0.62)
	# `Player._process` effacerait les fissures a l'image suivante, puisque le
	# joueur ne mine pas vraiment. Le gel ne touche que le traitement du joueur
	# — la camera, elle, vit dans `_physics_process` et reste en place.
	miner.set_process(false)


## Le joueur ouvre une partie en reseau. L'hote est aussi un joueur : il joue
## dans le monde qu'il ouvre, avec sa propre touche, et son adresse est
## affichee a l'ecran titre pour que les autres le trouvent.
func _on_title_host(seed_value: int, distance: int) -> void:
	if _net == null:
		title.show_message("Le multijoueur est indisponible.")
		return
	if seed_value == 0:
		seed_value = randi()
	var error: String = _net.host_game(seed_value, distance)
	if not error.is_empty():
		title.show_message(error)
		return
	# L'hote passe par le salon lui aussi : c'est lui qui doit pouvoir changer
	# d'avis sur sa tenue, attendre que des clients arrivent, et choisir le
	# moment du lancement. Il n'ouvre donc pas encore le monde.
	await _leave_title()
	_show_lobby(seed_value, distance, _net.local_name)


## Le joueur tente de rejoindre une partie existante. L'ecran titre reste
## affiche : l'echec, ou au contraire la description du monde qui arrive, sont
## tous deux rendus dans ce meme panneau.
func _on_title_join(address: String, port: int) -> void:
	if _net == null:
		title.show_message("Le multijoueur est indisponible.")
		return
	if address.is_empty():
		title.show_message("Il manque l'adresse de l'hote.")
		return
	var error: String = _net.join_game(address, port)
	if not error.is_empty():
		title.show_message(error)
		return
	_pending_join = true
	title.show_message("Connexion a %s:%d…" % [address, port])
	# Le monde n'est construit que lorsque l'hote lance la partie : jusque-la
	# on est connecte mais pas encore dans le jeu, et c'est le salon qui presente
	# la partie. `lobby_entered` fera le reste.


func _on_title_load() -> void:
	await _leave_title()
	_start_new_game(0, Game.render_distance, true)


## Eteint le menu avant de lancer une partie : sans ce fondu, l'ecran titre
## disparait d'un coup et le noir de la generation parait etre un plantage.
func _leave_title() -> void:
	if _leaving_title or world != null:
		return
	_leaving_title = true
	if title != null:
		await title.fade_out()
		title.hide_menu()
	_leaving_title = false


## Retour a l'ecran titre depuis la pause : sauvegarde, puis demonte
## entierement la partie (monde, joueur, interface). Le titre survit.
func _on_back_to_title() -> void:
	if world == null:
		# Aucun monde a demonter : on peut quand meme etre au salon, ou l'on
		# n'arrive que depuis l'ecran titre. Le titre, et sa musique, reviennent.
		_hide_lobby()
		if title != null:
			title.show_menu(Game.has_save(), Game.render_distance)
			title.start_music()
		return
	# Un monde heberge appartient a l'hote : l'ecrire sur le disque mettrait des
	# blocs differents de ceux du serveur dans la prochaine partie solo, sans
	# que rien ne l'indique a l'utilisateur. Seul l'hote sauvegarde.
	if not _net_started:
		Game.save_game()
	get_tree().paused = false
	Game.close_screens()
	Game.running = false
	Game.screen = Game.Screen.NONE
	Game.cursor_stack = {}
	if hud != null:
		hud.queue_free()
		hud = null
	if torch_lights != null:
		torch_lights.queue_free()
		torch_lights = null
	if mobs != null:
		mobs.queue_free()
		mobs = null
	if weather != null:
		weather.queue_free()
		weather = null
	if fx != null:
		fx.queue_free()
		fx = null
	if player != null:
		player.queue_free()
		player = null
	if world != null:
		world.queue_free()
		world = null
	# Le reseau est detache avant que le monde ne meure : ses signaux pointent
	# sur ce monde-la, et les decocher apres sa destruction laisserait des
	# connexions orphelines.
	_net.unbind_world()
	Game.world = null
	Game.player = null
	Game.hud = null
	Game.fx = null
	Game.mobs = null
	Game.weather = null
	Game.weather_dim = 1.0
	_ready_to_play = false
	_show_loading(false)
	if title != null:
		title.show_menu(Game.has_save(), Game.render_distance)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _show_loading(value: bool) -> void:
	if _loading_layer == null or _loading_wanted == value:
		return
	_loading_wanted = value
	# Un fondu en cours n'a plus lieu d'etre : sans ce `kill`, deux tweens se
	# disputerait l'opacite et le panneau resterait bloque a moitie visible.
	if _loading_tween != null and _loading_tween.is_valid():
		_loading_tween.kill()
	if value:
		_tip_index = -1
		_tip_timer = 0.0
		_next_tip()
		_loading_root.modulate.a = 0.0
		_loading_layer.visible = true
		_loading_tween = create_tween()
		_loading_tween.tween_property(_loading_root, "modulate:a", 1.0, LOADING_FADE)
		return
	# La layer reste affichee pendant le fondu : sans cela le monde apparaitrait
	# a mi-chemin, a moitie voile, ce qui parait plus long qu'un vrai fondu.
	_loading_tween = create_tween()
	_loading_tween.tween_property(_loading_root, "modulate:a", 0.0, LOADING_FADE)
	_loading_tween.tween_callback(_hide_loading)


## Range definitivement l'ecran de chargement une fois le fondu termine.
func _hide_loading() -> void:
	_loading_layer.visible = false
	_loading_root.modulate.a = 1.0


## Nourrit le panneau de generation : progression reelle, compteurs, conseil.
func _update_loading(delta: float) -> void:
	var side := 2 * _ready_radius + 1
	var needed := side * side
	var ready := 0
	# Un chunk compte pleinement quand il est maille, mais un chunk deja genere
	# ou en cours de generation represente deja une part du travail : sans ces
	# poids, la barre resterait collee a 0 % puis sauterait d'un coup.
	var weight := 0.0
	for key in world.chunks:
		var state: int = (world.chunks[key] as Chunk).state
		if state == Chunk.State.READY:
			ready += 1
			weight += 1.0
		elif state == Chunk.State.MESHING:
			weight += 0.7
		elif state == Chunk.State.GENERATED:
			weight += 0.45
		elif state == Chunk.State.GENERATING:
			weight += 0.2
	var progress := clampf(weight / float(needed), 0.0, 1.0)
	_loading_bar.value = progress
	_loading_stats.text = "%d%%   •   %d/%d chunks prets   •   %d en file" % [
		int(round(progress * 100.0)), mini(ready, needed), needed,
		world._queued_gen.size() + world._queued_mesh.size()]
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_tip_timer = TIP_PERIOD
		_next_tip()
	if _elapsed - _last_report > 5.0:
		_last_report = _elapsed
		print("[chargement] %5.1f s  %d chunks  %d prets  files %d/%d" % [
			_elapsed, world.chunks.size(), ready,
			world._queued_gen.size(), world._queued_mesh.size()])


## Conseil suivant, en boucle et jamais deux fois le meme d'affile.
func _next_tip() -> void:
	if _loading_tip == null or LOADING_TIPS.is_empty():
		return
	_tip_index = (_tip_index + 1) % LOADING_TIPS.size()
	_loading_tip.text = "Astuce — " + LOADING_TIPS[_tip_index]
	_loading_tip.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_loading_tip, "modulate:a", 1.0, 0.35)


# --------------------------------------------------------------- boucle

## Le soleil tourne autour du monde en 10 minutes : plein a midi, eteint la
## nuit, transitions douces. L'ambiance suit pour garder les interieurs
## lisibles sans ecraser les torches. Le ciel ProceduralSkyMaterial suit seul
## la direction du soleil.
func _update_sky() -> void:
	if sun == null or env == null:
		return
	var elevation := Game.sun_elevation(Game.day_time)
	var dim := Game.weather_dim
	sun.rotation = Vector3(-elevation * deg_to_rad(65.0), deg_to_rad(-38.0), 0.0)
	# Le soleil ne reste pas a sa puissance maximale du matin au soir : avant,
	# il y avait un plateau, puis un basculement franc du plein soleil au noir.
	# `smoothstep` sur l'elevation donne une aube et un crepuscule reels.
	var day := clampf(elevation, 0.0, 1.0)
	sun.light_energy = 1.35 * smoothstep(0.0, 0.32, day) * dim
	# Orange a l'horizon, la ou le soleil rase ; blanc le reste du jour.
	var twilight := clampf(1.0 - absf(elevation) * 5.0, 0.0, 1.0)
	var warm := Color(1.0, 0.62, 0.36)
	var noon := Color(1.0, 0.97, 0.90)
	# Sous l'averse, la lumiere devient grise et douce.
	sun.light_color = noon.lerp(warm, twilight * 0.85).lerp(
		Color(0.74, 0.80, 0.92), 1.0 - dim)
	env.ambient_light_energy = lerpf(0.16, 0.75,
		smoothstep(-0.18, 0.25, elevation)) * dim


func _process(delta: float) -> void:
	_elapsed += delta
	_update_sky()

	if not _ready_to_play and world != null:
		# On ne libere le joueur que quand le disque de terrain est pret :
		# sans cela il tomberait dans le vide au milieu du chargement.
		world.update(player.global_position)
		_update_loading(delta)
		if world.is_loaded_around(Game.spawn, _ready_radius):
			_ready_to_play = true
			_show_loading(false)
			player.can_move = true
			Game.start()
	elif world != null:
		world.update(player.global_position)

	if _capturing:
		return
	if _loading_shot and not _ready_to_play and _elapsed >= _shot_delay:
		# Photo du panneau de generation : sert a verifier barre, compteurs et
		# centrage du panneau (mode fenetre uniquement, la capture a besoin du
		# rendu). Le rayon d'attente est elargi pour rester sur ce panneau.
		_capturing = true
		_loading_shot = false
		await get_tree().process_frame
		await get_tree().process_frame
		_check_centring("chargement", _loading_root)
		await _capture_ascii()
		await Game.quit_game()
	elif _pause_shot and _ready_to_play:
		_capturing = true
		_pause_shot = false
		# Le menu doit etre mesure AVANT la capture : on verifie ainsi que le
		# panneau est reellement centre, et pas seulement a l'ecran.
		Game.toggle_pause()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_centring("menu pause", hud.pause_menu)
		# Puis capture **menus ouverts** : mesurer un panneau est une chose, en
		# montrer le dessin en est une autre, et c'est ce que la capture doit
		# servir. Fermer les ecrans avant de photographier ne laissait qu'une
		# image du monde, et `--pauseshot` ne rendait donc jamais ce qu'il
		# annoncait.
		await _capture_ascii("cubecraft_pause.png")
		Game.close_screens()
		get_tree().paused = false
		Game.toggle_inventory()
		await get_tree().process_frame
		await get_tree().process_frame
		_check_centring("inventaire", hud.inventory_screen)
		await _capture_ascii("cubecraft_inventory.png")
		Game.close_screens()
		await get_tree().process_frame
		await Game.quit_game()
	elif _ui_test and _ready_to_play:
		_capturing = true
		await _run_ui_test()
		await Game.quit_game()
	elif _debug_run and _ready_to_play:
		_capturing = true
		_debug_run = false
		await _debug_run_shot()
		await Game.quit_game()
	elif _debug_shot and _ready_to_play:
		_capturing = true
		_debug_shot = false
		_open_debug_menu_shot()
		# Deux images avant de mesurer : les ancres ne donnent leurs rectangles
		# reels qu'apres la mise en page, et un panneau mesure trop tot serait
		# declare mal place a tort.
		await get_tree().process_frame
		await get_tree().process_frame
		_check_centring("menu debug", debug_menu)
		_dump_ui(debug_menu)
		await _capture_ascii()
		await Game.quit_game()
	elif (_screenshot_mode or _fpshot) and _ready_to_play and _elapsed >= _shot_delay:
		_capturing = true
		if _fpshot:
			# Les creatures de controle se posent juste avant la photo, sur un
			# terrain deja genere, et sont gelees : un cochon qui erre et un
			# zombie qui brule au soleil auraient quitte le cadre.
			_pose_showcase_mobs(player)
			_freeze_showcase_mining(player)
			await get_tree().process_frame
		# On attend la capture AVANT de quitter : quitter dans la meme image
		# interromprait le `await` et l'image ne serait jamais lue.
		await _capture_ascii()
		await Game.quit_game()
	elif _title_test and title != null and title.visible \
			and _running_limit > 0.0 and _elapsed >= _running_limit:
		_capturing = true
		await _capture_ascii()
		await Game.quit_game()
	elif _running_limit > 0.0 and _elapsed >= _running_limit:
		# `Game.quit_game` laisse passer un cycle audio : on gele la boucle
		# pour ne pas relancer la sortie a chaque image.
		_capturing = true
		await Game.quit_game()


# --------------------------------------------------- mode diagnostic

## Le panneau d'un ecran doit etre centre dans la fenetre : c'est le symptome
## que donne un `Control` ancre a 0.5 dont les offsets n'ont pas ete reinitialises.
## Il vit sous le `CenterContainer`, on le cherche donc en profondeur.
func _find_panel(node: Node) -> Control:
	if node is PanelContainer:
		return node
	for child in node.get_children():
		var found := _find_panel(child)
		if found != null:
			return found
	return null


func _check_centring(label: String, screen: Control) -> void:
	var panel := _find_panel(screen)
	if panel == null:
		print("[centre] %s : aucun panneau trouve" % label)
		return
	# On remonte la chaine jusqu'a la racine : chaque maillon mal dimensionne
	# decale le panneau, et le faut pouvoir nommer precisement.
	var node: Node = panel
	while node != null:
		if node is Control:
			var c := node as Control
			print("[centre]   %s '%s' rect=%s ancres=(%.2f,%.2f,%.2f,%.2f) offsets=(%d,%d,%d,%d)" % [
				c.get_class(), c.name, c.get_global_rect(),
				c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
				c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
		node = node.get_parent()
	var view := get_viewport().get_visible_rect().size
	var rect := panel.get_global_rect()
	var centre := rect.get_center()
	var dx := absf(centre.x - view.x * 0.5)
	var inside := rect.position.x >= -1.0 and rect.end.x <= view.x + 1.0
	var ok := dx < 2.0 and inside
	print("[centre] %-12s fenetre=%s panneau=%s centre=(%.0f,%.0f) ecart_x=%.0f  %s" % [
		label, view, rect.size, centre.x, centre.y, dx, "OK" if ok else "MAL PLACE"])
	if not ok:
		_centre_failures.append(label)


## Vidage d'un ecran : type, nom, rectangle et texte de chaque `Control`.
##
## Une capture ASCII ne dit pas *ou* sont les controles, seulement qu'il y a
## de l'encre. Pour juger une mise en page — un bouton hors cadre, un panneau
## mal centre, un champ ecrase — la liste des rectangles vaut mieux que
## l'image : elle est exacte, et elle se lit dans le terminal.
func _dump_ui(node: Node, depth: int = 0) -> void:
	var pad := "  ".repeat(depth)
	if node is Control:
		var c := node as Control
		var text := ""
		if c is Label:
			text = " «%s»" % str((c as Label).text).left(40)
		elif c is Button:
			text = " «%s»" % (c as Button).text
		elif c is RichTextLabel:
			text = " «%s»" % (c as RichTextLabel).get_parsed_text().left(40)
		print("%s%s %s rect=%s%s" % [pad, c.get_class(), c.name,
			c.get_global_rect(), text])
		if c is ScrollContainer:
			var bar := (c as ScrollContainer).get_v_scroll_bar()
			if bar.max_value > 0.0:
				print("%s  (defilement : position %d px, contenu %d px, visible %d px)" % [
					pad, int((c as ScrollContainer).scroll_vertical),
					int(bar.max_value), int(c.size.y)])
	for child in node.get_children():
		_dump_ui(child, depth + 1)


## Capture l'image et la rejoue en caracteres dans le terminal : on peut
## verifier d'un coup d'oeil l'orientation des faces, l'eclairage et les
## couleurs, sans ouvrir d'image.
func _capture_ascii(name := "cubecraft_capture.png") -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("[diag] capture impossible")
		return
	image.save_png("user://" + name)

	var width := 108
	var height := 40
	var chars := " .:-=+*#%@"
	print("---- capture ASCII (%dx%d) ----" % [image.get_width(), image.get_height()])
	for row in height:
		var line := ""
		for col in width:
			var u := float(col) / float(width - 1)
			var v := float(row) / float(height - 1)
			var pixel := image.get_pixel(
				int(u * (image.get_width() - 1)), int(v * (image.get_height() - 1)))
			var luma := pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			line += chars[clampi(int(luma * (chars.length() - 1)), 0, chars.length() - 1)]
		print(line)

	# Grille de couleurs : on peut ainsi verifier que l'herbe est verte, la
	# terre marron, l'eau bleue, sans avoir a ouvrir l'image.
	print("---- couleurs dominantes ----")
	for row in 14:
		var line := ""
		for col in 40:
			var pixel := image.get_pixel(
				int((float(col) + 0.5) / 40.0 * (image.get_width() - 1)),
				int((float(row) + 0.5) / 14.0 * (image.get_height() - 1)))
			line += pixel.to_html(false)
		print(line)

	# Histogramme : les teintes les plus presentes, avec leur part de l'image.
	var histogram: Dictionary = {}
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var key := image.get_pixel(x, y).to_html(false)
			histogram[key] = int(histogram.get(key, 0)) + 1
	var ranked: Array = histogram.keys()
	ranked.sort_custom(func(a, b): return histogram[a] > histogram[b])
	var sampled := float(image.get_width() * image.get_height()) / 9.0
	var top := "teintes principales : "
	for i in mini(10, ranked.size()):
		top += "%s %.0f%%  " % [ranked[i], 100.0 * histogram[ranked[i]] / sampled]
	print(top)
	if world != null:
		_probe_mesh()
	if world != null and player != null:
		print("cam=%s  bloc sous la camera=%s  biome=%s" % [
			player.global_position.round(),
			Blocks.name_of(world.get_block(Vector3i(floori(player.global_position.x),
				floori(player.global_position.y) - 2, floori(player.global_position.z)))),
			Biomes.name_of(world.biome_at(floori(player.global_position.x),
				floori(player.global_position.z)))])
	var chunk_count := world.chunks.size() if world != null else 0
	var torch_count := world.torches.size() if world != null else 0
	print("---- fin capture (%d chunks, %.0f ms, %d torches, %d teintes) ----" % [
		chunk_count, Time.get_ticks_msec(), torch_count, histogram.size()])


## Test de l'interface d'inventaire et de fabrication, joue dans le vrai jeu :
## c'est le seul endroit ou les autoloads (Game, Atlas) existent, donc le seul
## ou la logique des ecrans de conteneur est verifiable.
##
## La sequence elle-meme vit dans `Diagnostics`, partage avec le menu de debug :
## c'est le meme code, lance soit au demarrage par `--uitest`, soit a la
## demande depuis le menu. Ici on ne fait que fournir l'etat de jeu, et
## reporter le verdict — sur la console pour le test, a l'ecran pour le menu.
func _run_ui_test() -> void:
	var diag := Diagnostics.new()
	diag.setup(get_tree(), world, player, hud, mobs, weather, sun, title,
		_on_back_to_title, func() -> bool: return _ready_to_play)
	await diag.run()
	print("UI %s" % diag.checklist.report_line())
	for name in diag.checklist.failed_names():
		print("UI ECHEC : %s" % name)


## Lecture directe des donnees de sommet du chunk sous la camera : c'est le
## seul moyen de distinguer un probleme de texture d'un probleme de teinte.
## La sonde elle-meme vit dans `Diagnostics`, partage avec le menu de debug,
## qui affiche le meme rapport a l'ecran.
func _probe_mesh() -> void:
	print(Diagnostics.probe(world, player))


# ------------------------------------------------------- arguments

func _parse_args() -> Dictionary:
	var args := {
		"seed": 0, "distance": 5, "load": false, "screenshot": false, "seconds": 0.0,
		"uitest": false, "pauseshot": false, "titletest": false, "loadingshot": false,
		"debugshot": false, "debugrun": false, "fpshot": false, "shader": 0,
	}
	for raw in OS.get_cmdline_args():
		if raw == "--load":
			args["load"] = true
		elif raw == "--screenshot":
			args["screenshot"] = true
		elif raw == "--fpshot":
			args["fpshot"] = true
		elif raw == "--titletest":
			args["titletest"] = true
		elif raw == "--uitest":
			args["uitest"] = true
		elif raw == "--pauseshot":
			args["pauseshot"] = true
		elif raw == "--loadingshot":
			args["loadingshot"] = true
		elif raw == "--debugshot":
			args["debugshot"] = true
		elif raw == "--debugrun":
			args["debugrun"] = true
		elif raw.begins_with("--seed="):
			args["seed"] = int(raw.split("=")[1])
		elif raw.begins_with("--distance="):
			args["distance"] = int(raw.split("=")[1])
		elif raw.begins_with("--shader="):
			args["shader"] = int(raw.split("=")[1])
		elif raw.begins_with("--seconds="):
			args["seconds"] = float(raw.split("=")[1])
	return args
