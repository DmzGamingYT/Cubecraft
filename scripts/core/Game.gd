extends Node

## Autoload `Game`.
##
## Point de rencontre entre la scene 3D et l'interface : il tient les references
## du monde, du joueur et du HUD, gere la pause, les ecrans (inventaire,
## etabli), les objets laches et la sauvegarde. Il tourne meme en pause pour
## pouvoir la lever.

enum Screen { NONE, INVENTORY, CRAFTING, ENCHANTING }

const AUTOSAVE_SECONDS := 45.0

## Duree d'un jour complet en secondes, comme Minecraft (10 minutes).
const DAY_LENGTH := 600.0

## Heure du jour 0..1 : 0 = lever, 0.25 = midi, 0.5 = coucher, 0.75 = minuit.
var day_time := 0.05

## Facteur de lumiere publie par la meteo (1 = degage, 0.3 = pleine averse).
var weather_dim := 1.0

var world: World
var player: Player
var hud: CanvasLayer
var fx: Fx
var mobs: Mobs
var weather: Weather
## Post-traitement d'ecran (voir `PostFx`). Il existe des l'ecran titre, donc
## il n'est pas range parmi les noeuds de partie.
var postfx: PostFx

var screen: int = Screen.NONE
var running := false
var world_seed := 0
var render_distance := 5
var spawn := Vector3.ZERO
## Emplacement de sauvegarde que la partie ecrase, et nom que le joueur lui a
## donne. Un emplacement vide est un nom vide : le menu des mondes s'en sert pour
## distinguer « cree puis revenu » de « jamais joue ».
var save_slot := 1
var world_name := ""

## Pile d'objets tenue par le curseur dans les ecrans de conteneur.
var cursor_stack: Dictionary = {}

var _autosave := 0.0
var _crafter: Node = null
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not running or world == null or player == null:
		return
	_autosave += delta
	if _autosave >= AUTOSAVE_SECONDS:
		_autosave = 0.0
		save_game()
	# L'horloge tourne meme en pause ? Non : figee avec le monde.
	if not get_tree().paused:
		day_time = fmod(day_time + delta / DAY_LENGTH, 1.0)


## Hauteur du soleil (-1 = minuit, +1 = midi) pour une heure donnee.
static func sun_elevation(time: float) -> float:
	return sin(TAU * time)


## Heure lisible pour l'overlay (jour de 6h a 18h).
func clock_text() -> String:
	var total := int(fmod(6.0 + day_time * 24.0, 24.0)) * 60 \
		+ int(fmod(day_time * 24.0 * 60.0, 60.0))
	return "%02d:%02d" % [total / 60, total % 60]


# ------------------------------------------------------------ cycle de vie

func register(actor: Node) -> void:
	if actor is World:
		world = actor
	elif actor is Player:
		player = actor
	elif actor is CanvasLayer:
		hud = actor
	elif actor is Fx:
		fx = actor
	elif actor is Mobs:
		mobs = actor
	elif actor is Weather:
		weather = actor


func start() -> void:
	running = true
	_apply_mouse_captured()


## Sortie propre : coupe les sons en cours, laisse au serveur audio le temps de
## relacher ses playbacks, puis quitte. Sans cette attente, fermer le jeu
## pendant l'averse fait signaler deux objets fuis (le flux de pluie et sa
## lecture) ; une voix de bruitage en train de jouer fuit de meme.
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	if weather != null:
		weather.stop_audio()
	Sounds.stop_all()
	if is_inside_tree():
		# Un cycle de melangeage suffit ; 0,35 s couvre les tampons audio.
		await get_tree().create_timer(0.35).timeout
	get_tree().quit()


# ----------------------------------------------------------------- ecrans

func _apply_mouse_captured() -> void:
	var dead := player != null and player.dead
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if screen == Screen.NONE \
			and not get_tree().paused and not dead else Input.MOUSE_MODE_VISIBLE


func toggle_pause() -> void:
	if screen != Screen.NONE:
		close_screens()
		return
	if not running:
		return
	if player != null and player.dead:
		return  # pas de pause sur l'ecran de mort
	get_tree().paused = not get_tree().paused
	if get_tree().paused:
		player.can_move = false
		save_game()
	else:
		player.can_move = true
	_apply_mouse_captured()


func toggle_inventory() -> void:
	if screen == Screen.INVENTORY:
		close_screens()
	else:
		open_screen(Screen.INVENTORY)


func open_crafting_table(_pos: Vector3) -> void:
	open_screen(Screen.CRAFTING)


## Clic droit sur une table d'enchantement.
func open_enchanting(_pos: Vector3) -> void:
	open_screen(Screen.ENCHANTING)


func open_screen(which: int) -> void:
	if screen == which:
		close_screens()
		return
	if player != null and player.dead:
		return  # mort : seule la réapparition compte
	# Le chat n'est pas un ecran, donc `open_screen` ne le ferme pas tout seul :
	# sans ces trois lignes, un inventaire ouverts par le joueur alors qu'il
	# ecrivait laisserait la ligne de saisie par-dessus la grille.
	if hud != null and hud.chat != null and hud.chat.is_open():
		hud.chat.close()
	screen = which
	player.can_move = false
	_apply_mouse_captured()
	if hud != null:
		hud.show_screen(which)


func close_screens() -> void:
	if screen == Screen.NONE:
		return
	screen = Screen.NONE
	if player != null:
		player.can_move = true
	_apply_mouse_captured()
	if hud != null:
		hud.show_screen(Screen.NONE)


func is_screen_open() -> bool:
	return screen != Screen.NONE


# ------------------------------------------------------------- monde vivant

func on_block_broken(pos: Vector3i, block_id: int) -> void:
	if fx != null:
		fx.burst(Vector3(pos) + Vector3(0.5, 0.5, 0.5), block_id)

	var def := Blocks.def(block_id)
	var needed: int = def["tier"]
	if needed > 90:
		return  # bedrock : rien a recuperer
	if needed > Items.tier_of(player.inventory.held_id()):
		return  # outil trop faible, le bloc se detruit sans rien donner

	var drop: int = def["drop"]
	if drop == Blocks.SELF:
		drop = Blocks.item_id(block_id)
	elif drop == Blocks.NOTHING and block_id == Blocks.LEAVES:
		# Les feuilles lachent parfois une pomme ou un baton.
		if randf() < 0.06:
			drop = Items.APPLE
		elif randf() < 0.14:
			drop = Items.STICK
		else:
			return

	if drop > 0:
		ItemEntity.spawn(world, Vector3(pos) + Vector3(0.5, 0.6, 0.5), drop, 1)
		# Fortune : un drop supplementaire, comme dans Minecraft.
		var fortune := Items.fortune_extra(_held_enchants())
		for extra in fortune:
			if randf() < 0.35 + 0.15 * float(extra):
				ItemEntity.spawn(world, Vector3(pos) + Vector3(0.5, 0.6, 0.5), drop, 1)
	if needed <= Items.tier_of(player.inventory.held_id()):
		player.add_xp(Blocks.xp_of(block_id))


## Enchantements de l'objet tenu.
func _held_enchants() -> Dictionary:
	if player == null:
		return {}
	return Inventory.enchants_of(player.inventory.held())


## Une creature est morte : drops et experience.
func on_mob_killed(mob: Node) -> void:
	if mob == null or player == null:
		return
	var pos: Vector3 = mob.global_position
	var kind: int = mob.kind
	if kind == Mob.Kind.PIG:
		ItemEntity.spawn(world, pos + Vector3(0, 0.5, 0), Items.PORKCHOP, 1)
		if randf() < 0.35:
			ItemEntity.spawn(world, pos + Vector3(0, 0.5, 0), Items.PORKCHOP, 1)
		player.add_xp(5)
	else:
		# Un zombie laisse parfois un lingot, comme une armure rouillee.
		if randf() < 0.5:
			ItemEntity.spawn(world, pos + Vector3(0, 0.5, 0), Items.IRON_INGOT, 1)
		player.add_xp(8)


## Jette au sol le contenu de l'emplacement selectionne.
func drop_from_hand(amount: int) -> void:
	if player == null:
		return
	var taken: int = player.inventory.take_from_selected(amount)
	if taken <= 0:
		return
	var id: int = player.inventory.slots[player.inventory.selected].get("id", -1)
	if id > 0:
		var forward := -player.camera.global_transform.basis.z
		var entity := ItemEntity.spawn(world,
			player.global_position + Vector3(0, 1.2, 0) + forward * 0.6, id, taken)
		entity.velocity = forward * 5.0 + Vector3.UP * 2.0


## Replace le joueur sur un point solide (utilise apres un chargement).
func place_player(pos: Vector3) -> void:
	if player == null:
		return
	var ground := world.surface_height(floori(pos.x), floori(pos.z))
	var y := maxf(pos.y, float(ground + 1))
	player.global_position = Vector3(pos.x, y + 0.2, pos.z)
	player.velocity = Vector3.ZERO
	player.flying = false


# ------------------------------------------------------------- sauvegarde

func has_save() -> bool:
	return SaveSystem.exists_any()


## L'emplacement demande existe-t-il ? Le menu des mondes s'en sert pour
## n'ouvrir « Charger » que sur une ligne reellement occupee.
func has_slot(slot: int) -> bool:
	return SaveSystem.exists(slot)


func save_game() -> bool:
	if world == null or player == null:
		return false
	var chunks: Array = []
	for key in world.chunks:
		var chunk: Chunk = world.chunks[key]
		if not chunk.modified:
			continue
		chunks.append({
			"cx": chunk.cx, "cz": chunk.cz,
			"min_y": chunk.min_y, "max_y": chunk.max_y,
			"data": SaveSystem.encode_chunk(chunk.blocks),
		})
	# Les chunks modifies mais deja decharges vivent dans le cache du monde.
	for key in world._kept:
		var kept: Dictionary = world._kept[key]
		chunks.append({
			"cx": Vox.key_to_cx(key), "cz": Vox.key_to_cz(key),
			"min_y": kept["min_y"], "max_y": kept["max_y"],
			"data": SaveSystem.encode_chunk(kept["blocks"]),
		})

	var data := {
		"version": SaveSystem.FORMAT_VERSION,
		"seed": world.seed_value,
		"time": day_time,
		"name": world_name,
		# Horodatage en temps Unix : l'index des emplacements s'en sert pour
		# nommer un monde et le classer, et une date gregorienne lisible par
		# tout le monde n'a pas sa place dans un fichier de sauvegarde.
		"saved_at": int(Time.get_unix_time_from_system()),
		"spawn": [spawn.x, spawn.y, spawn.z],
		"player": {
			"pos": [player.global_position.x, player.global_position.y, player.global_position.z],
			"yaw": player.get_yaw(),
			"flying": player.flying,
			"health": player.health,
			"food": player.food,
			"xp": player.xp,
			"level": player.xp_level,
		},
		"inventory": player.inventory.to_array(),
		"selected": player.inventory.selected,
		"chunks": chunks,
	}
	return SaveSystem.write(data, save_slot)


## Recharge la sauvegarde de l'emplacement courant. Renvoie false s'il n'y en a pas.
func load_game() -> bool:
	return load_slot(save_slot)


## Recharge un emplacement donne et en fait l'emplacement courant : la partie
## qui suit ecrase celui-la, et non celui d'ou l'on venait.
func load_slot(slot: int) -> bool:
	var data := SaveSystem.read(slot)
	if data.is_empty():
		return false
	save_slot = slot
	world_name = str(data.get("name", ""))

	world_seed = int(data.get("seed", 0))
	day_time = fmod(float(data.get("time", 0.05)), 1.0)
	var spawn_data: Array = data.get("spawn", [0, 40, 0])
	spawn = Vector3(spawn_data[0], spawn_data[1], spawn_data[2])

	for entry in data.get("chunks", []):
		var key := Vox.chunk_key(int(entry["cx"]), int(entry["cz"]))
		world._kept[key] = {
			"blocks": SaveSystem.decode_chunk(entry["data"]),
			"min_y": int(entry.get("min_y", 0)),
			"max_y": int(entry.get("max_y", Vox.CHUNK_Y - 1)),
		}

	var player_data: Dictionary = data.get("player", {})
	var pos: Array = player_data.get("pos", [spawn.x, spawn.y, spawn.z])
	player.global_position = Vector3(pos[0], pos[1], pos[2])
	player.set_yaw(float(player_data.get("yaw", 0.0)))
	player.flying = bool(player_data.get("flying", false))
	player.velocity = Vector3.ZERO
	# Un mort ne se recharge pas : on le reveille avec 1 PV.
	player.health = maxf(1.0, float(player_data.get("health", Player.MAX_HEALTH)))
	player.food = clampf(float(player_data.get("food", Player.MAX_FOOD)),
		0.0, Player.MAX_FOOD)
	player.dead = false
	player.xp = maxf(0.0, float(player_data.get("xp", 0.0)))
	player.xp_level = maxi(0, int(player_data.get("level", 0)))

	player.inventory.from_array(data.get("inventory", []))
	player.inventory.selected = clampi(int(data.get("selected", 0)), 0,
		Inventory.HOTBAR_SIZE - 1)
	return true
