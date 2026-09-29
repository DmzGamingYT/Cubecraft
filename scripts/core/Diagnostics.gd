class_name Diagnostics
extends RefCounted

## Verifications du jeu, jouables **dans la partie en cours**.
##
## Ce code vivait dans `Main._run_ui_test`, appele uniquement par `--uitest` :
## il demarrait le jeu, enchainait une longue sequence, puis quittait. Impossible
## a relancer en cours de partie, et son resultat n'etait lisible que dans une
## console — donc inexistant pour quiconque joue au jeu.
##
## Ici, les verifications sont regroupees derriere une `Checklist` partagee, et
## peuvent etre declenchees depuis le menu de debug. L'etat de jeu est fourni
## par l'appelant : ce module ne presume pas d'ou il vient.
##
## **La sequence est brutale** : elle vide l'inventaire, repositionne le
## joueur, le tue et le fait reapparaitre, lache des mobs du haut du monde, et
## finit par demonter la partie pour la relancer depuis le titre. C'est
## acceptable pour un outil de diagnostic, et c'est exactement ce que le menu
## doit annoncer — sinon on feroit confiance a l'utilisateur sur une partie abimee.

## Journal des verifications, partage avec le menu de debug.
var checklist := Checklist.new()
## Etat de jeu fourni par l'appelant. Le module n'a pas d'acces a la scene
## de `Main`, donc les objets necessaires sont passes explicitement.
var world: World
var player: Player
var hud: HUD
var mobs: Mobs
var weather: Weather
var sun: DirectionalLight3D
var title: TitleScreen
## Retour au titre de l'appelant. La sequence se termine par une relance complete
## depuis l'ecran titre ; `Diagnostics` n'a pas d'acces a `Main`, donc la
## methode lui est passee.
var back_to_title: Callable = Callable()
## La partie rechargee est-elle prete ? **Evalue au moment de l'appel** : une
## copie de l'etat resterait false pour toujours, et l'attente de la fin du
## chargement ne finirait jamais.
var is_ready: Callable = Callable()
## Rappelee quand la sequence est finie, pour que le menu puisse se reactualiser.
var finished: Callable = Callable()
## Arbre de scene de l'appelant. Le module en a besoin pour avancer image par
## image : plusieurs verifications attendent que le jeu ait reagi (une epee qui
## blesse, un ecran qui s'ouvre, une pluie qui s'installe). Un `RefCounted`
## n'etant pas dans l'arbre, il ne peut pas faire `get_tree()` lui-meme.
var tree: SceneTree = null

# Cadre de travail partage par les sections. La sequence est une seule histoire
# qui se sert du meme inventaire et des memes ecrans d'un bout a l'autre : ces
# objets sont donc des membres, sinon chaque section devrait les redeclarer et
# les references ne survivraient pas au changement de partie.

## Inventaire du joueur, reinitialise puis filled par les sections.
var inv: Inventory
## Ecran d'inventaire (2x2 et fabrication 2x2).
var inv_screen: ContainerUI
## Ecran d'etabli (3x3).
var table: ContainerUI
## Ecran d'enchantement.
var ench: EnchantScreen
## Objet sur lequel portent les enchantements.
var sword: int = Items.STONE_SWORD


## Une image d'attente. Raccourci : ces attentes sont partout dans la sequence,
## et passer par `tree` a chaque fois rendrait le code illisible.
func _frame() -> void:
	await tree.process_frame


func _physics() -> void:
	await tree.physics_frame


func setup(game_tree: SceneTree, game_world: World, game_player: Player,
		game_hud: HUD, game_mobs: Mobs, game_weather: Weather,
		game_sun: DirectionalLight3D, game_title: TitleScreen,
		title_request: Callable, ready_check: Callable) -> void:
	tree = game_tree
	world = game_world
	player = game_player
	hud = game_hud
	mobs = game_mobs
	weather = game_weather
	sun = game_sun
	title = game_title
	back_to_title = title_request
	is_ready = ready_check


## Relecture des references de jeu.
##
## Indispensable apres le retour au titre : la partie d'origine est liberee, et
## les references conservees pointersaient alors vers des objets detruits — lire
## une propriete dessus fait tomber le jeu. `Game` est l'autoload qui tient
## exactement ces cinq references a jour, `sun` et `title` survivant au
## demontee.
func refresh() -> void:
	world = Game.world
	player = Game.player
	hud = Game.hud as HUD
	mobs = Game.mobs
	weather = Game.weather
	inv = player.inventory if player != null else null
	inv_screen = hud.inventory_screen if hud != null else null
	table = hud.crafting_screen if hud != null else null
	ench = hud.enchant_screen if hud != null else null


## Enregistre une verification et son resultat. `label` apparait tel quel dans
## le menu : il doit dire ce qui est verifie, pas comment c'est fait.
func _check(label: String, condition: bool, detail := "") -> void:
	checklist.set_result(checklist.add(label), condition, detail)


## Lance la sequence complete. Le temps passe sert au rapport final.
func run() -> void:
	if checklist.is_running():
		return  # deux sequences en parallele se marcheraient dessus
	var started := Time.get_ticks_msec()
	refresh()
	checklist.begin()
	# Une sequence lancee sur une partie encore en chargement testerait des
	# ecrans qui n'existent pas et tuerait un joueur tombe dans le vide : elle
	# ne commence donc que sur une partie liberee.
	_check("la partie est prete", is_ready.is_valid() and bool(is_ready.call()))
	_inventory_and_crafting()
	await _survival()
	await _mining()
	await _mobs_and_xp()
	await _enchantments()
	await _weather()
	await _teardown_and_restart()
	checklist.end((Time.get_ticks_msec() - started) / 1000.0)
	if finished.is_valid():
		finished.call()


func _inventory_and_crafting() -> void:
	inv = player.inventory
	inv_screen = hud.inventory_screen
	var plank := Items.block_item(Blocks.PLANKS)
	inv.reset()

	inv.slots[0] = {"id": plank, "count": 30}
	inv_screen._refresh()
	inv_screen._on_inventory_pressed(0, MOUSE_BUTTON_LEFT, false)
	_check("la pile quitte l'emplacement", inv.slots[0].is_empty())
	_check("le curseur tient la pile", int(Game.cursor_stack.get("count", 0)) == 30)
	inv_screen._on_inventory_pressed(5, MOUSE_BUTTON_LEFT, false)
	_check("la pile est deposee", int(inv.slots[5]["count"]) == 30)
	_check("le curseur se vide", Game.cursor_stack.is_empty())

	inv_screen._on_inventory_pressed(5, MOUSE_BUTTON_RIGHT, false)
	_check("la moitie est prise", int(Game.cursor_stack.get("count", 0)) == 15)
	_check("l'autre moitie reste", int(inv.slots[5]["count"]) == 15)
	inv_screen._on_inventory_pressed(0, MOUSE_BUTTON_RIGHT, false)
	_check("clic droit depose une unite", int(inv.slots[0]["count"]) == 1)
	_check("le curseur a perdu une unite", int(Game.cursor_stack.get("count", 0)) == 14)
	Game.cursor_stack = {}
	inv.reset()

	inv.slots[20] = {"id": plank, "count": 5}
	inv_screen._on_inventory_pressed(20, MOUSE_BUTTON_LEFT, true)
	_check("l'emplacement d'origine est vide", inv.slots[20].is_empty())
	_check("deplacement rapide vers la barre", int(inv.slots[0]["count"]) == 5)
	inv_screen._on_inventory_pressed(0, MOUSE_BUTTON_LEFT, true)
	_check("aller-retour barre rapide vers le rangement", inv.slots[0].is_empty() and inv.count_of(plank) == 5)

	inv.reset()
	inv.add(plank, 8)
	inv_screen.grid[0] = {"id": plank, "count": 1}
	inv_screen.grid[2] = {"id": plank, "count": 1}
	inv_screen._recompute()
	inv_screen._refresh()
	_check("la grille propose des batons", not inv_screen._result.is_empty() and inv_screen._result["id"] == Items.STICK)
	inv_screen._on_result_pressed(-1, MOUSE_BUTTON_LEFT, false)
	_check("la fabrication verse 4 batons", inv.count_of(Items.STICK) == 4)
	_check("les ingredients sont consommes", inv_screen.grid[0].is_empty() and inv_screen.grid[2].is_empty())

	inv_screen.grid[0] = {"id": plank, "count": 1}
	inv_screen._recompute()
	_check("grille incomplete : pas de resultat", inv_screen._result.is_empty())
	inv_screen.give_back()
	_check("la grille videe rend ses objets", inv.count_of(plank) >= 1)

	inv.reset()
	inv_screen.grid[0] = {"id": plank, "count": 8}
	inv_screen.grid[2] = {"id": plank, "count": 8}
	inv_screen._recompute()
	inv_screen._on_result_pressed(-1, MOUSE_BUTTON_RIGHT, false)
	_check("fabrication en serie (%d batons)" % inv.count_of(Items.STICK), inv.count_of(Items.STICK) == 32)
	inv_screen.give_back()
	Game.cursor_stack = {}

	# L'etabli (3x3) doit savoir fabriquer une pioche.
	table = hud.crafting_screen
	table.grid[0] = {"id": plank, "count": 1}
	table.grid[1] = {"id": plank, "count": 1}
	table.grid[2] = {"id": plank, "count": 1}
	table.grid[4] = {"id": Items.STICK, "count": 1}
	table.grid[7] = {"id": Items.STICK, "count": 1}
	table._recompute()
	_check("l'etabli 3x3 fabrique une pioche", not table._result.is_empty() and table._result["id"] == Items.WOOD_PICKAXE)
	table.give_back()

	# Ouvrir et refermer chaque ecran ne doit rien perdre.
	Game.toggle_inventory()
	_check("inventaire ouvert", Game.is_screen_open() and not player.can_move)
	Game.open_crafting_table(player.global_position)
	_check("ecran etabli ouvert", Game.screen == Game.Screen.CRAFTING)
	Game.close_screens()
	_check("ecrans refermes", not Game.is_screen_open() and player.can_move)
	Game.toggle_pause()
	_check("pause activee", tree.paused)
	Game.toggle_pause()
	_check("pause levee", not tree.paused)

	# La barre rapide doit se trouver dans la fenetre : ancrée en bas avec des
	# offsets nuls, elle passerait sous l'ecran et resterait invisible.
	var view := tree.root.get_visible_rect().size
	var bar := hud.hotbar.get_global_rect()
	_check("la barre rapide est dans la fenetre (%s)" % bar, bar.size.y > 0.0 and bar.position.y >= -1.0 and bar.end.y <= view.y + 1.0)


## Le joueur se blesse, mange, meurt et reapparait : la boucle de survie doit
## laisser le joueur exactement comme avant, moins le temps ecoule.
func _survival() -> void:
	# Survie : table des degats de chute, blessures, pomme, mort, torches de nuit.
	_check("petite chute sans degats", Player.fall_damage(-5.0) == 0)
	_check("chute de 4 blocs = 3 degats", Player.fall_damage(-15.0) == 3)
	_check("chute mortelle", Player.fall_damage(-36.0) == 24)
	player.take_damage(5, "chute")
	_check("blessure : 15 PV", player.health == 15.0)
	player.take_damage(0, "chute")
	player.take_damage(-3, "chute")
	_check("degats nuls ignores", player.health == 15.0)
	player.food = 10.0
	inv.reset()
	inv.add(Items.APPLE, 2)
	inv.selected = 0
	_check("la pomme se mange", player._try_eat())
	_check("pomme : +4 faim, une consommee", player.food == 14.0 and inv.count_of(Items.APPLE) == 1)
	Game.day_time = 0.75
	await _frame()
	await _frame()
	_check("nuit noire (energie %.3f)" % sun.light_energy, sun.light_energy <= 0.001)
	Game.day_time = 0.25
	await _frame()
	await _frame()
	_check("midi ensoleille", absf(sun.light_energy - 1.35) < 0.001)
	player.take_damage(999, "chute")
	_check("mort : bloque", player.dead and not player.can_move)
	await _frame()
	await _frame()
	_check("ecran de mort affiche", hud.death_screen.visible)
	player.respawn()
	_check("reapparition : 20 PV, mobile", not player.dead and player.health == 20.0 and player.can_move)


## Le minage tel qu'un joueur le pratique : on vise un bloc, on **maintient** le
## clic gauche, et on attend que le bloc disparaisse.
##
## Toutes les autres verifications cassent des blocs en appelant l'API. Celle-ci
## entraine la chaine complete — raycast depuis la position reelle de l'oeil,
## progression image par image, duree calculee sur l'outil tenu, declenchement a
## l'echeance — et c'est la seule qui rejoue ce que fait la souris. Une action
## d'input synthetisee suffit : `Input.action_press` rend
## `Input.is_action_pressed("break")` vrai exactement comme un bouton enfonce.
func _mining() -> void:
	# Le joueur vient de reapparaitre et peut encore etre en chute : on le laisse
	# se poser, sinon la hauteur de l'oeil est fausse et la visee rate.
	var settled := 0
	while not player.is_on_floor() and settled < 240:
		await _physics()
		settled += 1

	# Le bloc a miner est **choisi par le test**, et le terrain autour est degage
	# si besoin : viser le sol reel rendait la verification dependante de la
	# forme du biome, et une falaise entre le joueur et la cible echouait sans
	# rien prouver.
	#
	# La diagonale n'est pas un detail : c'est elle qui donne au joueur un lacet
	# non nul. Vise droit devant, il tourne de zero degree, le contour
	# n'herite d'aucune rotation, et la verification passerait meme avec le bug.
	player.set_yaw(deg_to_rad(-45.0))
	player.set_pitch(deg_to_rad(-22.0))
	# La camera est posee en `_physics_process` : il faut une image physique
	# avant que le viseur ne corresponde a la nouvelle orientation.
	await _physics()
	var eye := player.camera.global_position
	var hit := VoxelRaycast.cast(world, eye, player.look_direction(), Player.REACH)
	# Sans rencontre, la cellule visee est celle atteinte au bout du bras tendu.
	var target: Vector3i = hit["pos"]
	if not hit["hit"]:
		var far: Vector3 = eye + player.look_direction() * Player.REACH
		target = Vector3i(floori(far.x), floori(far.y), floori(far.z))
	var previous := world.get_block(target)
	# De l'air, de l'eau ou de la bedrock : on pose son bloc, on ne mine que ce
	# que l'on sait cassable.
	if previous == Blocks.AIR or previous == Blocks.WATER \
			or Blocks.break_time(previous, true) == INF:
		world.set_block(target, Blocks.GRASS)
	_check("un bloc est vise devant le joueur",
		VoxelRaycast.cast(world, eye, player.look_direction(), Player.REACH)["pos"]
			== target)

	# Le contour doit encadrer exactement le bloc vise. Il est enfant du joueur,
	# qui tourne sur lui-meme : sans `top_level`, la boite herite de son lacet
	# et pivote autour du coin du bloc, et parait decalee — jusqu'a disparaitre
	# du terrain des que le joueur regardait de trois quarts.
	#
	# Le contour, lui, est pose en `_process`, donc **apres** l'image physique
	# qui applique le lacet : juge immediatement apres l'attente ci-dessus, on
	# lisait un contour calcule avec l'orientation precedente — voire jamais
	# pose du tout, le joueur sortant de sa reapparition. Le nombre d'images
	# idle qui s'ecoulent la n'est pas fixe (deux images physiques peuvent tenir
	# dans une seule image de rendu), et la verification etait partiale : elle
	# passait sur un monde, echouait sur un autre, sans que le jeu change rien.
	# On laisse donc a `Player` le temps de poser son contour sur le bloc vise,
	# avec une borne courte : la geometrie est jugee apres, rotation comprise,
	# donc un contour qui heriterait du lacet echoue toujours ici.
	var settling := 0
	while settling < 12 and (not player.highlight.visible
			or player.target_pos != target):
		await _frame()
		settling += 1
	var corner: Vector3 = player.highlight.global_transform * Vector3(1, 1, 1)
	var want := Vector3(target) + Vector3(1, 1, 1)
	_check("le contour encadre le bloc vise (lacet %.0f degres)"
		% rad_to_deg(player.get_yaw()),
		player.highlight.visible and corner.distance_to(want) < 0.001,
		"coin %s attendu %s, visible %s, bloc vise %s, apres %d images"
			% [corner, want, player.highlight.visible,
				player.target_pos, settling])

	# On vide la main pour que la duree ne depende pas de l'equipement du joueur.
	player.inventory.reset()
	player.inventory.add(Items.block_item(Blocks.PLANKS), 1)
	player.inventory.selected = 0
	var correct := Items.is_tool_for(player.inventory.held_id(), Blocks.GRASS)
	var expected := Blocks.break_time(Blocks.GRASS, correct) \
		/ maxf(Items.speed_of(player.inventory.held_id()), 0.01)
	_check("la duree de minage a la main est bornee (%.1f s)" % expected,
		expected < 20.0)

	var waited := 0
	# Les fissures du bloc mine : on les echantillonne a chaque image physique,
	# parce qu'elles paraissent et disparaissent en moins d'une seconde. Une
	# seule lecture ratee ne prouverait rien — c'est la meme prudence que pour
	# le contour de visee, qui se pose en `_process` et non en physique.
	var cracked := false
	var crack_pos := Vector3.ZERO
	Input.action_press("break")
	while world.get_block(target) == Blocks.GRASS and waited < 1800:
		await _physics()
		waited += 1
		if player.break_overlay != null and player.break_overlay.visible:
			cracked = true
			crack_pos = player.break_overlay.global_position
	# On relache **avant** de juger : le viseur passe aussitot sur le bloc
	# suivant et repartirait a le casser, et la progression repartirait avec.
	Input.action_release("break")
	await _physics()
	await _physics()
	_check("tenir le clic casse le bloc (%.1f s, prevu %.1f s)"
		% [float(waited) / 60.0, expected],
		world.get_block(target) == Blocks.AIR)
	_check("la progression retombe a zero apres la cassure", player.mining_ratio == 0.0)
	_check("le bloc vise se fend pendant le minage",
		cracked and crack_pos.distance_to(Vector3(target)) < 0.001,
		"visible %s a %s, bloc vise %s" % [cracked, crack_pos, target])
	_check("les fissures s'effacent une fois le bloc casse",
		player.break_overlay != null and not player.break_overlay.visible)

	# On remet le terrain comme on l'a trouve : la suite raisonne sur un monde
	# continu, et le joueur ne doit pas tomber dans le trou qu'on a creuse.
	world.set_block(target, previous)
	await _physics()


## Apparition des mobs selon l'heure, brulure au soleil, degats, mort, xp.
func _mobs_and_xp() -> void:
	# Mobs : regles d'apparition, spawning reel, degats, mort, xp.
	_check("pas de zombie en plein jour", not Mob.hostile_spawns(0.25))
	_check("zombies la nuit", Mob.hostile_spawns(0.75))
	_check("seuls les zombies brulent a l'aube", Mob.burns_in_sunlight(Mob.Kind.ZOMBIE, 0.01)
		and not Mob.burns_in_sunlight(Mob.Kind.PIG, 0.01)
		and not Mob.burns_in_sunlight(Mob.Kind.ZOMBIE, 0.5))
	_check("le zombie est plus resistant", Mob.max_health_of(Mob.Kind.ZOMBIE) > Mob.max_health_of(Mob.Kind.PIG))
	# Mobs : le soleil doit BRULER reellement, et rien ne doit naitre pour
	# bruler aussitot. Ces deux verifications verrouillent une regression
	# constatee : les regles testaient chacune une plage horaire differente
	# (apparition apres 0.5, brulure apres 0.92), et la seconde condition
	# d'eclairage du code de jeu rendait leur intersection vide : aucun
	# zombie n'a jamais brule, de jour comme de nuit.
	var burn_slots := 0
	var contradiction := 0
	for i in 1001:
		var hour := float(i) / 1000.0
		if Mob.burns_in_sunlight(Mob.Kind.ZOMBIE, hour):
			burn_slots += 1
		if Mob.hostile_spawns(hour) and Mob.burns_in_sunlight(Mob.Kind.ZOMBIE, hour):
			contradiction += 1
	_check("le zombie brule une bonne moitie de la journee (%d/1001)"
		% burn_slots, burn_slots > 300)
	_check("aucun hostile n'apparait en plein soleil", contradiction == 0)
	_check("le zombie brule a midi", Mob.burns_in_sunlight(Mob.Kind.ZOMBIE, 0.25))
	_check("le cochon ne brule pas", not Mob.burns_in_sunlight(Mob.Kind.PIG, 0.25))

	# Degats de chute : la hauteur tombee se lisait apres la remise a zero du
	# suivi de chute, donc la difference etait negative et la regle ne se
	# declenchait jamais. On lache un cochon du haut du monde et on verifie
	# qu'il arrive blesse.
	var faller := Mob.new()
	faller.setup(Mob.Kind.PIG, world)
	mobs.add_child(faller)
	faller.global_position = Vector3(floori(player.global_position.x),
		Vox.CHUNK_Y - 3, floori(player.global_position.z))
	for i in 300:
		await _physics()
		if not is_instance_valid(faller):
			break
		if faller.is_on_floor() and i > 3:
			break
	_check("un mob lache de haut se blesse a l'atterrissage", not is_instance_valid(faller) or faller.health < faller.max_health)
	if is_instance_valid(faller):
		faller.queue_free()
	_check("une position d'apparition est trouvee", mobs != null and mobs.find_spawn_spot() != Vector3.ZERO)
	_check("cout de niveau progressif", Player.xp_to_next(0) == 7 and Player.xp_to_next(1) == 9)
	player.xp = 0.0
	player.xp_level = 0
	player.add_xp(7)
	_check("7 xp = niveau 1", player.xp_level == 1)
	player.xp_level = 5
	var pig := Mob.new()
	pig.setup(Mob.Kind.PIG, world)
	mobs.add_child(pig)
	# Comme pour l'apparition en jeu, la position globale demande que le
	# mob soit deja dans l'arbre.
	pig.global_position = player.global_position + Vector3(1, 0, 0)
	mobs.mobs.append(pig)
	var hp_before := pig.health
	player._attack_cd = 0.0
	player.camera.look_at(pig.global_position + Vector3(0, 0.9, 0))
	player._attack()
	_check("le coup blit la creature", pig.health < hp_before)
	pig.take_damage(99, Vector3.ZERO)
	_check("la creature meurt a 0 PV", pig.health <= 0)
	_check("la creature liberee", pig.is_queued_for_deletion())
	await _frame()
	_check("la creature detruite", not is_instance_valid(pig))
	player.xp_level = 0
	player.add_xp(20)
	_check("le xp de mise a mort est gagne", player.xp_level >= 1)


## Les enchantements coutent du lapis et des niveaux, et s'appliquent a l'objet.
func _enchantments() -> void:
	# Enchantements : l'objet gagne l'enchant, coute lapis et niveau.
	sword = Items.STONE_SWORD
	inv.reset()
	inv.add(sword, 1)
	inv.add(Items.LAPIS, 4)
	inv.selected = 0
	player.xp_level = 3
	Game.open_enchanting(player.global_position)
	await _frame()
	_check("l'ecran d'enchantement s'ouvre", hud.enchant_screen.visible)
	ench = hud.enchant_screen
	_check("Tranchant achete", ench._apply("tranchant"))
	var held_ench := Inventory.enchants_of(inv.held())
	_check("Tranchant I applique", int(held_ench.get("tranchant", 0)) == 1)
	_check("le lapis est depense (2 restants)", inv.count_of(Items.LAPIS) == 2)
	_check("2 niveaux sont depenses", player.xp_level == 1)
	_check("Efficacite II multiplie la vitesse par 1.6", Items.enchant_speed(sword, {"efficacite": 2}) == 1.6)
	_check("Tranchant +2 degats", Items.enchant_damage(held_ench) == 2)
	_check("Fortune (niveau 2) refuse avec 1 seul niveau", not ench._apply("fortune"))
	Game.close_screens()
	player.inventory.reset()


## Modes de meteo forces : la pluie doit s'installer, assombrir le ciel, puis
## disparaitre sans laisser de particule en suspens.
func _weather() -> void:
	# Meteo : modes forces, ciel qui s'assombrit, puis retour au degage.
	# Le noeud de particules est cree a la volee : il ne doit exister que le
	# temps qu'il precipite, sinon son shader fuit a la fermeture du jeu.
	_check("aucune particule par temps clair", weather._rain == null)
	weather.set_mode(Weather.Mode.RAIN)
	_check("mode pluie", weather.mode_name() == "Pluie")
	for i in 120:
		weather._process(0.05)
	_check("la pluie s'installe (%.2f)" % weather.strength, weather.strength > 0.9)
	_check("le ciel s'assombrit (%.2f)" % Game.weather_dim, Game.weather_dim < 0.75)
	_check("les gouttes apparaissent sous la pluie", weather._rain != null)
	_check("les gouttes tombent", weather._rain.emitting)
	weather.set_mode(Weather.Mode.SNOW)
	_check("mode neige", weather.current == Weather.Mode.SNOW)
	weather.set_mode(Weather.Mode.CLEAR)
	for i in 120:
		weather._process(0.05)
	_check("le ciel se degage", weather.strength < 0.05)
	_check("les particules sont detruites apres l'arret de la pluie", weather._rain == null)
	weather.set_mode(Weather.Mode.AUTO)


## Retour au titre puis relance : c'est la seule facon de verifier que la
## partie se demonte proprement — et que le joueur peut rejouer derriere.
func _teardown_and_restart() -> void:
	# Retour au titre en dernier : la partie se demonte proprement et le
	# titre revient, comme depuis le bouton du menu pause.
	back_to_title.call()
	_check("retour au titre nettoie la partie", Game.world == null and Game.player == null)
	_check("les mobs et la meteo sont liberes", Game.mobs == null and Game.weather == null)
	_check("l'ecran titre est de retour", title != null and title.visible)
	_check("l'apercu du personnage est present", title != null and title.has_preview())

	# Rejouer depuis le titre : graine tapee puis bouton Creer, comme un
	# joueur. On attend le chargement comme au demarrage.
	title._seed_field.text = "1234"
	title._show_new_panel()
	title._on_create()
	# Le depart passe par un fondu au noir : on laisse l'animation finir avant
	# de verifier que le menu est range (une image = ~16 ms, 60 suffisent).
	var handoff := 0
	while title.visible and handoff < 60:
		await _frame()
		handoff += 1
	_check("le titre se cache au demarrage", not title.visible)
	# La partie vient d'etre reconstruite : les references de depart sont
	# mortes, il faut relire les nouvelles avant de verifier quoi que ce soit.
	refresh()
	var deadline := Time.get_ticks_msec() + 120000
	while not bool(is_ready.call()) and Time.get_ticks_msec() < deadline:
		await _frame()
	refresh()
	_check("la partie redemarre depuis le titre", bool(is_ready.call()))
	_check("la graine tapee est utilisee (%d)" % Game.world_seed, Game.world_seed == 1234)
	_check("le joueur rejoue", player != null and player.can_move)


## Lecture directe des donnees de sommet du chunk sous la camera.
##
## C'est le seul moyen de distinguer un probleme de texture d'un probleme de
## teinte : la couleur du sommet vient du biome et de l'AO, ses coordonnees de
## texture de l'atlas. Afficher l'image ne dit pas lequel des deux est faux.
## Ici, la sonde retourne son rapport **en texte** : la capture d'ecran
## l'imprime, le menu de debug l'affiche dans son journal, et les deux
## executes exactement le meme code.
static func probe(game_world: World, game_player: Player) -> String:
	if game_world == null or game_player == null:
		return "sonde : aucune partie en cours."
	var out := PackedStringArray()
	var states := {}
	var with_mesh := 0
	var empty_mesh := 0
	for key in game_world.chunks:
		var chunk: Chunk = game_world.chunks[key]
		states[chunk.state] = int(states.get(chunk.state, 0)) + 1
		var holder: MeshInstance3D = chunk.get_node_or_null("Mesh")
		if holder != null and holder.mesh != null:
			with_mesh += 1
			if holder.mesh.get_surface_count() == 0:
				empty_mesh += 1
	out.append("sonde : %d chunks, etats=%s, avec mesh=%d dont vides=%d" % [
		game_world.chunks.size(), states, with_mesh, empty_mesh])

	var below := Vector3i(floori(game_player.global_position.x),
		floori(game_player.global_position.y) - 2, floori(game_player.global_position.z))
	var coords := Vox.chunk_of(below)
	var target := game_world.chunk_at(coords.x, coords.y)
	if target == null:
		out.append("sonde : aucun chunk sous la camera (%d,%d)" % [coords.x, coords.y])
		return "\n".join(out)
	var holder2: MeshInstance3D = target.get_node_or_null("Mesh")
	var mesh: ArrayMesh = holder2.mesh if holder2 != null else null
	if mesh == null or mesh.get_surface_count() == 0:
		var non_air := 0
		for value in target.blocks:
			if value != Blocks.AIR:
				non_air += 1
		out.append("sonde : chunk (%d,%d) etat=%d min_y=%d max_y=%d taille=%d non_air=%d surfaces=%s" % [
			coords.x, coords.y, target.state, target.min_y, target.max_y,
			target.blocks.size(), non_air,
			mesh.get_surface_count() if mesh != null else "mesh nul"])
		return "\n".join(out)
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	out.append("sonde : %d surfaces, %d sommets, texture=%s" % [
		mesh.get_surface_count(), verts.size(), Assets.atlas])
	for i in [0, 1, 2, verts.size() / 2, verts.size() - 1]:
		if i < 0 or i >= verts.size():
			continue
		out.append("  v%-6d pos=%s uv=(%.4f, %.4f) couleur=%s" % [
			i, verts[i], uvs[i].x, uvs[i].y, colors[i].to_html(false)])
	return "\n".join(out)
