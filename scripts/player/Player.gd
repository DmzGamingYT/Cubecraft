class_name Player
extends CharacterBody3D

## Joueur en vue subjective : deplacement, minage, pose de blocs.
##
## La camera est un enfant d'une tete qui suit le corps : le bobbing de marche
## ne secoue donc pas le regard quand le corps est ajuste. Le regard est aussi
## volontairement plus ample que la hitbox, comme dans Minecraft.

const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.2
const SNEAK_SPEED := 1.9
const SWIM_SPEED := 3.1
const FLY_SPEED := 14.0
const JUMP_VELOCITY := 8.6
const GRAVITY := 28.0
const WATER_GRAVITY := 6.0
const REACH := 5.0

const BODY_HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const BODY_RADIUS := 0.3

## Montee automatique d'un demi-bloc (marche sur soi-meme comme sur Minecraft).
const STEP_HEIGHT := 0.6

const FOV_BASE := 75.0
const FOV_SPRINT := 85.0
const FOV_FLY := 95.0

const BOB_FREQUENCY := 9.0
const BOB_AMOUNT := 0.055

signal target_changed(block_id: int)
signal mining_progress(ratio: float)

var world: World
var inventory := Inventory.new()

var head: Node3D
var camera: Camera3D
var highlight: MeshInstance3D
## Fissures du bloc mine : c'est ce qui rend la cassure lisible autrement que
## par la barre du reticule.
var break_overlay: BreakOverlay

var mouse_sensitive := 0.0022
## Champ de vision de repos. La constante `FOV_BASE` en est la valeur d'origine ;
## celle-ci bouge avec le reglage du joueur, et la course comme le vol s'y
## ajoutent par-dessus.
var base_fov := FOV_BASE
## Vitesse de rotation du stick droit, en radians par seconde a pleine poussee.
## Un stick analogique n'a pas de pas : sa vitesse doit suivre la poussee, sinon
## la visee a la manette paraitrait collee a l'ecran ou inexistante.
var stick_look_speed := 2.6
## Inverser l'axe vertical. Reglage, pas dur : la plupart des gens n'en voulez
## pas, et ceux qui le veulent l'attendent.
var invert_y := false
var flying := false
var can_move := true

var _yaw := 0.0
var _pitch := 0.0
var _bob_time := 0.0
var _step_distance := 0.0
var _mining_target := Vector3i.ZERO
var _mining_progress := 0.0
var _fov := FOV_BASE
var _head_in_water := false
var _feet_in_water := false
var _was_on_floor := true
var _highlight_mat: StandardMaterial3D

## Etat expose au HUD.
var target_id := Blocks.AIR
var target_pos := Vector3i.ZERO
var mining_ratio := 0.0

## Survie facon Minecraft : 20 points = 10 icones.
const MAX_HEALTH := 20.0
const MAX_FOOD := 20.0
const MAX_AIR := 10.0
## Vitesse verticale d'impact a partir de laquelle la chute blesse : une
## chute de 4 blocs donne ~15 (2 degats = 1 coeur), 23 blocs tuent (~23).
const FALL_THRESHOLD := 12.0

var health := MAX_HEALTH
var food := MAX_FOOD
var air := MAX_AIR
var dead := false
var death_cause := ""
var _regen_timer := 0.0
var _starve_timer := 0.0
var _drown_timer := 0.0
## Degats par seconde qu'inflige le bloc dans lequel le corps est entre
## ( lave, cactus ). 0 quand on n'est dans aucun bloc dangereux.
var _contact_hazard := 0.0
## Cadence d'application : on ne blit pas a chaque image physique, ce qui viderait
## la vie en une seconde et demi sans jamais laisser au joueur le temps de
## s'en echapper.
var _contact_timer := 0.0
var _hunger_acc := 0.0
var _attack_cd := 0.0
var _swing := 0.0

## Experience : `xp` est la barre courante, `xp_level` le niveau entier.
## Le niveau suivant demande 7 + 2 * niveau experience, comme Minecraft.
var xp := 0.0
var xp_level := 0


## Cout du prochain niveau (fonction pure, testee).
static func xp_to_next(level: int) -> int:
	return 7 + 2 * maxi(0, level)


## Degats d'un impact vertical (fonction pure, testee en fumee).
static func fall_damage(impact_vy: float) -> int:
	return maxi(0, int(-impact_vy - FALL_THRESHOLD))


func _ready() -> void:
	collision_layer = Mob.LAYER_PLAYER
	# Le monde et les creatures. Sans la couche des mobs, on traversait les
	# zombies comme un fantome, et ils nous traversaient en retour.
	collision_mask = Mob.LAYER_WORLD | Mob.LAYER_MOB

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	add_child(shape)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, EYE_HEIGHT, 0)
	add_child(head)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = base_fov
	camera.near = 0.05
	camera.far = 320.0
	head.add_child(camera)

	_build_highlight()
	break_overlay = BreakOverlay.new()
	break_overlay.name = "BreakOverlay"
	add_child(break_overlay)


## Contour du bloc vise, en lignes fines, qui vire de l'ambre a l'orange
## pendant le minage.
func _build_highlight() -> void:
	highlight = MeshInstance3D.new()
	highlight.name = "Highlight"
	highlight.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _highlight_material())
	var corners := [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	# Leger surplus pour que le trait ne scintille pas dans la face du bloc.
	var margin := 0.002
	for edge in edges:
		var a: Vector3 = corners[edge[0]]
		var b: Vector3 = corners[edge[1]]
		a = a.lerp(Vector3(0.5, 0.5, 0.5), -margin)
		b = b.lerp(Vector3(0.5, 0.5, 0.5), -margin)
		mesh.surface_set_color(Color(1, 1, 1, 0.9))
		mesh.surface_add_vertex(a)
		mesh.surface_set_color(Color(1, 1, 1, 0.9))
		mesh.surface_add_vertex(b)
	mesh.surface_end()
	highlight.mesh = mesh
	highlight.visible = false
	# Le joueur tourne sur lui-meme a chaque deplacement ; sans cette ligne, le
	# contour heriterait de son lacet, et la boite dessinee pivotait autour du
	# coin du bloc vise. Elle paraissait alors decalee par rapport au bloc
	# sous le viseur — jusqu'a disparaitre du terrain a 45 degres.
	highlight.top_level = true
	add_child(highlight)


func _highlight_material() -> StandardMaterial3D:
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_mat.vertex_color_use_as_albedo = true
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_mat.no_depth_test = false
	_highlight_mat.albedo_color = Color(1, 1, 1, 1)
	return _highlight_mat


# ---------------------------------------------------------------- entrees

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitive
		# `_pitch` est en radians — c'est ce qu'attend `head.rotation.x`. Le
		# borner en degres le laissait tourner de 5 000 degres : on pouvait
		# regarder a l'envers, et le viseur ne designait plus rien de cliquable.
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitive
			* (-1.0 if invert_y else 1.0),
			-PI * 0.499, PI * 0.499)
		return

	if world == null or not is_instance_valid(camera):
		return

	if event.is_action_pressed("fly"):
		flying = not flying
		if flying:
			velocity.y = 0.0
	elif event.is_action_pressed("attack"):
		_attack()
	elif event.is_action_pressed("place"):
		# Clic droit : manger si comestible, sinon interagir (table
		# d'enchantement), sinon poser le bloc tenu.
		if not _try_eat():
			var hit := VoxelRaycast.cast(world, camera.global_position, look_direction(), REACH)
			if not _interact(hit):
				_process_place(hit)
	elif event.is_action_pressed("pick"):
		_pick_block()
	elif event.is_action_pressed("drop"):
		Game.drop_from_hand(1)
	elif event.is_action_pressed("inventory"):
		Game.toggle_inventory()


## Clic molette : recupere le bloc vise dans la barre rapide.
func _pick_block() -> void:
	var hit := VoxelRaycast.cast(world, camera.global_position, look_direction(), REACH)
	if not hit["hit"]:
		return
	var item_id := Blocks.item_id(hit["block"])
	if item_id < 0:
		return
	for i in Inventory.HOTBAR_SIZE:
		if inventory.slots[i].get("id", -1) == item_id:
			inventory.selected = i
			return
	if inventory.add(item_id, 1) > 0:
		inventory.selected = Inventory.HOTBAR_SIZE - 1


## Experience gagnee : remplit la barre, puisMonte d'un niveau.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += float(amount)
	while xp >= Player.xp_to_next(xp_level):
		xp -= Player.xp_to_next(xp_level)
		xp_level += 1
		Sounds.play_ui("levelup")


## Experience necessaire au niveau suivant, pour l'overlay.
func xp_progress() -> float:
	return clampf(xp / float(Player.xp_to_next(xp_level)), 0.0, 1.0)


## Coup de portée : la creature visee est blitee, reculee, peut mourir.
func _attack() -> void:
	if dead or not can_move or Game.mobs == null or _attack_cd > 0.0:
		return
	_attack_cd = 0.35
	_swing = 0.25
	var from := camera.global_position
	var direction := look_direction()
	var mob := Game.mobs.mob_in_sight(from, direction, REACH)
	if mob == null:
		return
	var held := inventory.held_id()
	var enchants := Inventory.enchants_of(inventory.held())
	var damage := Items.damage_of(held) + Items.enchant_damage(enchants)
	# Un coup au dos fait plus mal, comme dans Minecraft.
	if mob.global_position.distance_to(global_position) < 2.0:
		damage += 1
	mob.take_damage(damage, direction * 6.0)
	Sounds.play_at("hit", mob.global_position, -4.0)


## Secoue la camera au moment du coup.
func _animate_swing(delta: float) -> void:
	if _swing <= 0.0:
		return
	_swing = maxf(0.0, _swing - delta)
	var amount := 0.06 * (_swing / 0.25)
	camera.rotation.z = -amount
	if _swing <= 0.0:
		camera.rotation.z = 0.0


func look_direction() -> Vector3:
	return -camera.global_transform.basis.z


## Inflige des degats (cause affichee a l'ecran de mort).
func take_damage(amount: int, cause: String) -> void:
	if dead or amount <= 0:
		return
	health = maxf(0.0, health - float(amount))
	Sounds.play_ui("hurt")
	if health <= 0.0:
		_die(cause)


func _die(cause: String) -> void:
	dead = true
	death_cause = cause
	can_move = false
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Retour au point d'apparition, jauges pleines.
func respawn() -> void:
	health = MAX_HEALTH
	food = MAX_FOOD
	air = MAX_AIR
	dead = false
	death_cause = ""
	_regen_timer = 0.0
	_starve_timer = 0.0
	_drown_timer = 0.0
	_contact_timer = 0.0
	_contact_hazard = 0.0
	_hunger_acc = 0.0
	flying = false
	Game.place_player(Game.spawn)
	can_move = true
	Game.close_screens()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mange l'objet tenu s'il est comestible. Renvoie true si mange.
func _try_eat() -> bool:
	if dead:
		return true
	var held := inventory.held_id()
	var restore := Items.food_of(held)
	if restore <= 0 or food >= MAX_FOOD:
		return false
	if inventory.take_from_selected(1) <= 0:
		return false
	food = minf(MAX_FOOD, food + float(restore))
	Sounds.play_ui("eat")
	return true


## Faim, noyade et regeneration, une fois par image physique.
func _survival(delta: float) -> void:
	# Noyade : 10 s d'air, puis 2 degats toutes les 2 s.
	if _head_in_water and not flying:
		air = maxf(0.0, air - delta)
		if air <= 0.0:
			_drown_timer += delta
			if _drown_timer >= 2.0:
				_drown_timer = 0.0
				take_damage(2, "noyade")
	else:
		air = MAX_AIR
		_drown_timer = 0.0
	if dead:
		return
	# Bloc dangereux (lave, cactus). On applique par paliers de 0,5 s plutot
	# que par image : c'est ce qui laisse au joueur le temps de s'ecarter.
	if _contact_hazard > 0.0:
		_contact_timer += delta
		if _contact_timer >= 0.5:
			_contact_timer = 0.0
			take_damage(int(maxf(1.0, _contact_hazard * 0.5)), "brulure")
	else:
		_contact_timer = 0.0
	# La faim fond avec l'effort : ~30 s de marche ou ~8 s de sprint par point.
	var effort := 0.2
	if not is_on_floor() and not _feet_in_water:
		effort = 0.2
	elif Input.is_action_pressed("sprint"):
		effort = 4.0
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		effort = 1.0
	_hunger_acc += delta * effort
	if _hunger_acc >= 30.0:
		_hunger_acc = 0.0
		food = maxf(0.0, food - 1.0)
	# Affame : 1 degat toutes les 4 s. Rassasie : +1 vie toutes les 3 s.
	if food <= 0.0:
		_starve_timer += delta
		if _starve_timer >= 4.0:
			_starve_timer = 0.0
			take_damage(1, "faim")
	else:
		_starve_timer = 0.0
	if food >= 18.0 and health < MAX_HEALTH:
		_regen_timer += delta
		if _regen_timer >= 3.0:
			_regen_timer = 0.0
			health = minf(MAX_HEALTH, health + 1.0)
	else:
		_regen_timer = 0.0


func set_yaw(value: float) -> void:
	_yaw = value


func get_yaw() -> float:
	return _yaw


func set_pitch(value: float) -> void:
	_pitch = value
	if head != null:
		head.rotation.x = _pitch


# ------------------------------------------------------------- deplacement

func _physics_process(delta: float) -> void:
	_update_look(delta)
	rotation.y = _yaw
	head.rotation.x = _pitch
	_update_water_state()
	_update_speed(delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if can_move:
		_move(delta)
	_update_bob(delta)
	_animate_swing(delta)


func _update_water_state() -> void:
	var feet := world.get_block(Vector3i(floori(global_position.x),
			floori(global_position.y + 0.4), floori(global_position.z)))
	var eyes := world.get_block(Vector3i(floori(global_position.x),
			floori(global_position.y + EYE_HEIGHT), floori(global_position.z)))
	_feet_in_water = Blocks.is_liquid(feet)
	_head_in_water = Blocks.is_liquid(eyes)
	_contact_hazard = _hazard_at(feet)
	# Le torse aussi : un cactus plante a cote doit mordre meme si le joueur
	# marche juste a cote, pieds sur un bloc sain.
	var torso := world.get_block(Vector3i(
		floori(global_position.x), floori(global_position.y + 0.9),
		floori(global_position.z)))
	_contact_hazard = maxf(_contact_hazard, _hazard_at(torso))
	if is_instance_valid(camera):
		camera.fov = _fov
		camera.far = 320.0 if not _head_in_water else 6.0


## Degats par seconde infliges par un bloc, ou 0. Le contrat est porte par le
## registre lui-meme (cle `hurt`) : ajouter un bloc dangereux ne demande donc
## qu'une entree de plus dans `Blocks`.
func _hazard_at(block_id: int) -> float:
	return float(Blocks.def(block_id).get("hurt", 0.0))


func _update_speed(delta: float) -> void:
	var sprinting := Input.is_action_pressed("sprint") and not flying
	var target := base_fov
	if flying:
		target = base_fov + (FOV_FLY - FOV_BASE)
	elif sprinting:
		target = base_fov + (FOV_SPRINT - FOV_BASE)
	_fov = lerpf(_fov, target, clampf(delta * 8.0, 0.0, 1.0))


## Rotation de la camera au stick droit, a la manette.
##
## Le stick est lu par `Input.get_axis` plutot que par la somme des touches :
## `is_action_pressed` ne rend qu'un booleen, et la camera tournerait alors par
## crans, d'un coup, comme un jeu d'arcade. Le stick demande une vitesse
## graduelle, et `get_axis` la donne.
func _update_look(delta: float) -> void:
	if not can_move or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# La souris et le stick se marchent dessus si les deux tournent : celui
		# qui n'a pas bouge depuis le dernier clichage cede la main. La souris
		# gagne a chaque fois qu'on en voit un mouvement, parce que c'est elle
		# qui donne le deplacement de tete fin.
		return
	var turn := Input.get_axis("look_left", "look_right")
	var tilt := Input.get_axis("look_up", "look_down")
	if absf(turn) < 0.01 and absf(tilt) < 0.01:
		return
	_yaw -= turn * stick_look_speed * delta
	var step := tilt * stick_look_speed * delta * (-1.0 if invert_y else 1.0)
	_pitch = clampf(_pitch + step, -PI * 0.499, PI * 0.499)


func _move(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input.y -= 1.0
	if Input.is_action_pressed("move_back"):
		input.y += 1.0
	if Input.is_action_pressed("move_left"):
		input.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input.x += 1.0
	input = input.limit_length(1.0)

	# Direction voulue dans le repere du regard (verticale exclue).
	var basis_yaw := Basis(Vector3.UP, _yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var speed := _current_speed()

	if flying:
		var vertical := 0.0
		if Input.is_action_pressed("jump"):
			vertical += 1.0
		if Input.is_action_pressed("crouch"):
			vertical -= 1.0
		velocity = velocity.lerp(wish * speed + Vector3.UP * vertical * speed,
			clampf(delta * 12.0, 0.0, 1.0))
	else:
		var horizontal := wish * speed
		velocity.x = horizontal.x
		velocity.z = horizontal.z

		if _feet_in_water:
			velocity.y = maxf(velocity.y - WATER_GRAVITY * delta, -3.0)
			if Input.is_action_pressed("jump"):
				velocity.y = 4.0
		else:
			if is_on_floor():
				if Input.is_action_pressed("jump"):
					velocity.y = JUMP_VELOCITY
				else:
					velocity.y = 0.0
			else:
				velocity.y -= GRAVITY * delta
				# Un rattrapage si le joueur traverse la surface au passage.
				if _was_on_floor and velocity.y < 0.0:
					velocity.y = 0.0

	var before := Vector2(velocity.x, velocity.z)
	var impact_vy := velocity.y
	var was_airborne := not is_on_floor()
	move_and_slide()
	if is_on_wall() and is_on_floor() and not flying:
		_try_step_up(before)
	# Atterrissage : la vitesse d'avant l'impact decide des degats.
	if is_on_floor() and was_airborne and not flying and not _feet_in_water:
		var dmg := Player.fall_damage(impact_vy)
		if dmg > 0:
			take_damage(dmg, "chute")
	_was_on_floor = is_on_floor()
	_footsteps(before.length() * delta)
	if not dead:
		_survival(delta)


func _current_speed() -> float:
	if flying:
		return FLY_SPEED
	if _feet_in_water:
		return SWIM_SPEED
	if Input.is_action_pressed("crouch"):
		return SNEAK_SPEED
	if Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward"):
		return SPRINT_SPEED
	return WALK_SPEED


## Monte d'un demi-bloc si de la place existe au-dessus du decalage.
func _try_step_up(motion: Vector2) -> void:
	if motion.length_squared() < 0.0001:
		return
	var lifted := global_transform
	lifted.origin += Vector3.UP * STEP_HEIGHT
	var probe := Vector3(motion.x, 0.0, motion.y).normalized() * 0.08
	if test_move(lifted, probe):
		return
	global_position = lifted.origin
	velocity.y = maxf(velocity.y, 0.0)


func _footsteps(distance: float) -> void:
	if not is_on_floor() and not flying:
		return
	if _feet_in_water:
		return
	_step_distance += distance
	if _step_distance < 1.9:
		return
	_step_distance = 0.0
	var under := world.get_block(Vector3i(floori(global_position.x),
			floori(global_position.y - 0.2), floori(global_position.z)))
	if under == Blocks.AIR:
		return
	var name := "step_" + Sounds.material_of(under)
	Sounds.play_at(name, global_position, -16.0, 0.18)


func _update_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.5 and not flying:
		_bob_time += delta * BOB_FREQUENCY * clampf(horizontal_speed / WALK_SPEED, 0.0, 1.6)
		head.position.y = EYE_HEIGHT + sin(_bob_time) * BOB_AMOUNT
		head.position.x = cos(_bob_time * 0.5) * BOB_AMOUNT * 0.5
	else:
		_bob_time = 0.0
		head.position.y = lerpf(head.position.y, EYE_HEIGHT, clampf(delta * 10.0, 0.0, 1.0))
		head.position.x = lerpf(head.position.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))


# ------------------------------------------------------- minage et pose

func _process(delta: float) -> void:
	if world == null or not is_instance_valid(camera):
		return
	var hit := VoxelRaycast.cast(world, camera.global_position, look_direction(), REACH)

	if hit["hit"]:
		var pos: Vector3i = hit["pos"]
		highlight.visible = true
		highlight.global_position = Vector3(pos)
		# Le contour se resserre legerement pour rester lisible au contact.
		var id: int = hit["block"]
		target_id = id
		target_pos = pos
		target_changed.emit(id)
	else:
		highlight.visible = false
		target_id = Blocks.AIR
		target_changed.emit(Blocks.AIR)
		break_overlay.clear()

	if Game.mobs != null and Game.mobs.mob_in_sight(
			camera.global_position, look_direction(), REACH) != null:
		# Un clic tape la creature visee : pas de minage en meme temps.
		_reset_mining()
		highlight.visible = false
		return
	if not Input.is_action_pressed("break") or not can_move:
		_reset_mining()
		return
	if not hit["hit"]:
		_reset_mining()
		return

	var target: Vector3i = hit["pos"]
	if target != _mining_target:
		_mining_target = target
		_mining_progress = 0.0

	var block_id: int = hit["block"]
	var held := inventory.held_id()
	var correct_tool := Items.is_tool_for(held, block_id)
	var enchants := Inventory.enchants_of(inventory.held())
	var duration := Blocks.break_time(block_id, correct_tool) \
		/ (Items.speed_of(held) * Items.enchant_speed(held, enchants))
	_mining_progress += delta / maxf(duration, 0.01)
	mining_ratio = clampf(_mining_progress, 0.0, 1.0)
	mining_progress.emit(mining_ratio)
	# Le contour chauffe a mesure que le bloc cede.
	var t := clampf(_mining_progress, 0.0, 1.0)
	_highlight_mat.albedo_color = Color(1.0, lerpf(0.92, 0.45, t), lerpf(0.75, 0.12, t), 1.0)

	# Le bloc se fend a l'endroit vise, au rythme de la progression.
	break_overlay.set_mining(target, mining_ratio)

	if _mining_progress >= 1.0:
		_mine(target, block_id)
		_reset_mining()


func _reset_mining() -> void:
	# Les fissures s'effacent toujours : elles pourraient sinon rester posees
	# sur un bloc qu'on vient de lacher du regard.
	if break_overlay != null:
		break_overlay.clear()
	if _mining_progress > 0.0:
		_mining_progress = 0.0
		mining_ratio = 0.0
		_highlight_mat.albedo_color = Color(1, 1, 1, 1)
		mining_progress.emit(0.0)


func _mine(pos: Vector3i, block_id: int) -> void:
	if Blocks.break_time(block_id, true) == INF:
		return
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	Sounds.play_at("break_" + Sounds.material_of(block_id), center, -4.0)
	Game.on_block_broken(pos, block_id)
	world.set_block(pos, Blocks.AIR)


## Clic droit sur un bloc special (table d'enchantement). Renvoie true si
## l'ecran correspondant s'est ouvert.
func _interact(hit: Dictionary) -> bool:
	if not hit["hit"]:
		return false
	var block_id: int = hit["block"]
	if Blocks.interact_of(block_id) != "enchant":
		return false
	Game.open_enchanting(Vector3(hit["pos"]))
	return true


## Casse le bloc vise et fait tomber son objet.
func _process_place(hit: Dictionary) -> void:
	if not hit["hit"]:
		return
	var held := inventory.held_id()
	if held < 0:
		return
	var block_id := Items.block_of(held)
	if block_id < 0:
		return

	# Clic droit sur un etabli : on ouvre l'interface de fabrication.
	if hit["block"] == Blocks.CRAFTING_TABLE and hit["normal"] != Vector3i.ZERO:
		Game.open_crafting_table(Vector3(hit["pos"]) + Vector3(0.5, 0.5, 0.5))
		return

	var target: Vector3i = hit["pos"] + hit["normal"]
	if world.get_block(target) != Blocks.AIR:
		return
	if Blocks.is_solid(block_id) and _intersects_player(target):
		return

	var place_pos := target
	# Les blocs en croix (torche) se posent sur un support, pas en l'air.
	if Blocks.is_cross(block_id):
		var below := world.get_block(Vector3i(target.x, target.y - 1, target.z))
		if below == Blocks.AIR or Blocks.is_cross(below):
			return
		place_pos = Vector3i(target.x, target.y, target.z)

	world.set_block(place_pos, block_id)
	inventory.take_from_selected(1)
	Sounds.play_at("place_" + Sounds.material_of(block_id),
		Vector3(place_pos) + Vector3(0.5, 0.5, 0.5), -6.0)
	# Le bloc pose peut devenir le support d'une torche voisine.
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1)]:
		var neighbour: Vector3i = place_pos + offset
		if world.get_block(neighbour) == Blocks.TORCH:
			if world.get_block(Vector3i(place_pos.x, place_pos.y - 1, place_pos.z)) == Blocks.AIR:
				world.set_block(neighbour, Blocks.AIR)


func _intersects_player(block_pos: Vector3i) -> bool:
	# Le joueur occupe une boite alignee sur la grille : on teste l'intersection
	# avec le cube unite du bloc.
	var min_corner := global_position - Vector3(BODY_RADIUS, 0.0, BODY_RADIUS)
	var max_corner := global_position + Vector3(BODY_RADIUS, BODY_HEIGHT, BODY_RADIUS)
	return (min_corner.x < float(block_pos.x) + 1.0 and max_corner.x > float(block_pos.x)
		and min_corner.y < float(block_pos.y) + 1.0 and max_corner.y > float(block_pos.y)
		and min_corner.z < float(block_pos.z) + 1.0 and max_corner.z > float(block_pos.z))
