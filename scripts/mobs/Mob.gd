class_name Mob
extends CharacterBody3D

## Creature cubique, facon Minecraft : corps en boites, gravite, marche qui
## franchit un bloc, et deux comportements.
##
## Passif (cochon) : errance tranquille, se fleuit quand on l'approche.
## Hostile (zombie) : poursuit le joueur, le frappe au contact et brule au
## soleil. Un clic gauche de la pioche tape ; une epee inflige plus.

enum Kind { PIG, ZOMBIE }

const GRAVITY := 26.0
const JUMP_VELOCITY := 8.0
## Delai avant de retenter de franchir une marche : sans lui, un mob bloque
## recoit une impulsion vers le haut a chaque atterrissage et sautille sans
## arret contre le mur.
const STEP_COOLDOWN := 0.5
## Hauteur de chute au-dela de laquelle un mob se blesse (il est epargne
## quatre blocs).
const SAFE_FALL := 5.0
const MAX_HEALTH := {"pig": 10, "zombie": 16}

## Couches de collision. Le monde est en 1, le joueur en 2, les creatures en 4.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MOB := 4

## Seuil d'elevation solaire au-dessus duquel le soleil brule les hostiles.
## On ne peut pas prendre zero : `sin(TAU * 0.5)` vaut 1.2e-16 et non 0, donc
## un seuil a zero ferait bruler un zombie a la tombee exacte du jour.
const SUN_UP := 0.05

## Regles d'apparition, en fonctions pures pour etre testees hors jeu.
const DESPAWN_DISTANCE := 56.0
const SIGHT_RANGE := 18.0
const ATTACK_RANGE := 1.4

var world: World
var kind: int = Kind.PIG
var health := 10
var max_health := 10
var _wander := 0.0
var _yaw := 0.0
var _attack_cd := 0.0
var _burn_cd := 0.0
var _step_cd := 0.0
var _hurt_flash := 0.0
var _fall_from := 0.0
var _legs := []
var _boxes: Array[MeshInstance3D] = []


## Un hostil peut-il apparaitre a cette heure ? (fonction pure)
## C'est exactement la negation de `burns_in_sunlight` pour un zombie : avant,
## les deux regles se recouvraient, si bien qu'un zombie pouvait naitre la nuit
## et bruler au meme moment, et qu'en plein jour (soleil a son zenith) aucune
## des deux ne s'appliquait.
static func hostile_spawns(time: float) -> bool:
	return not sun_is_up(time)


## Le soleil est-il assez haut pour bruler ? (fonction pure)
## `sun_elevation` vaut 0 au lever (time ~0), 1 a midi (0.25) et 0 au coucher
## (0.5) : le soleil est donc au-dessus de l'horizon de l'aube au crepuscule.
static func sun_is_up(time: float) -> bool:
	return Game.sun_elevation(time) > Mob.SUN_UP


## Le soleil brule-t-il cet hostile la ? (fonction pure)
## Un cochon resiste au soleil, un zombie brule de l'aube au crepuscule.
static func burns_in_sunlight(kind_value: int, time: float) -> bool:
	return kind_value == Kind.ZOMBIE and sun_is_up(time)


static func max_health_of(kind_value: int) -> int:
	return int(MAX_HEALTH["pig" if kind_value == Kind.PIG else "zombie"])


func setup(mob_kind: int, mob_world: World) -> void:
	kind = mob_kind
	world = mob_world
	max_health = Mob.max_health_of(kind)
	health = max_health
	_wander = randf() * 2.0
	_yaw = randf() * TAU


func _ready() -> void:
	collision_layer = Mob.LAYER_MOB
	# Le monde, le joueur et les autres creatures. Sans le joueur et les
	# congeners, un mob traversait les deux : on traversait les zombies comme
	# du brouillard, et ils nous traversaient en retour.
	collision_mask = Mob.LAYER_WORLD | Mob.LAYER_PLAYER | Mob.LAYER_MOB
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# La boite de collision doit suivre le modele, sinon la creature frappe et
	# recule a vide, ou se cogne dans le sol. Un cochon de Minecraft fait 0,9
	# de haut, un zombie 1,8.
	if kind == Kind.PIG:
		box.size = Vector3(0.7, 0.9, 1.1)
		shape.position = Vector3(0, 0.45, 0)
	else:
		box.size = Vector3(0.6, 1.8, 0.6)
		shape.position = Vector3(0, 0.9, 0)
	shape.shape = box
	add_child(shape)
	_build_body()


## Corps en boites, aux proportions de Minecraft, teinte par espece.
##
## Les deux creatures partageaient jusqu'ici la meme caisse de 0,7 x 0,7 x 1,0 :
## le zombie etait aussi large que long, et la tete du cochon — posee a 0,72
## devant le centre du corps, sur 0,5 de profondeur — etait engloutie aux deux
## tiers dans le buste. Il ne restait qu'un bloc rose et quatre pieds.
func _build_body() -> void:
	_legs.clear()
	if kind == Kind.PIG:
		_build_pig()
	else:
		_build_zombie()


## Cochon : corps bas et allonge, tete en avant, musee, quatre pattes courtes.
func _build_pig() -> void:
	var hide := Color(0.94, 0.58, 0.58)
	var head := Color(0.97, 0.71, 0.71)
	# Un cochon de Minecraft est rose des pattes à la tête : des pattes
	# presque aussi foncées que le musee dessinaient quatre bottines sombres,
	# et c'est ce qui le faisait lire comme une caisse sur des pieds plutôt
	# que comme un cochon.
	var legs_color := Color(0.82, 0.49, 0.49)
	var eye := Color(0.08, 0.08, 0.10)
	# 10 x 8 x 16 pixels de Minecraft, donc 0,625 x 0,5 x 1,0 bloc. Le corps
	# commence au dessus des pattes et va de z = -0,5 a z = +0,5.
	_add_box(Vector3(0.625, 0.5, 1.0), Vector3(0, 0.625, 0), hide)
	# Tete 8 x 8 x 8 posee contre l'avant du corps : elle depasse franchement,
	# c'est ce qui donne au cochon sa silhouette reconnaissable.
	_add_box(Vector3(0.5, 0.5, 0.5), Vector3(0, 0.66, -0.75), head)
	# Musee, plus etroite et plus basse que la tete.
	_add_box(Vector3(0.25, 0.1875, 0.125), Vector3(0, 0.6, -1.0625),
		Color(0.87, 0.56, 0.60))
	_add_box(Vector3(0.05, 0.05, 0.05), Vector3(-0.06, 0.6, -1.13), eye)
	_add_box(Vector3(0.05, 0.05, 0.05), Vector3(0.06, 0.6, -1.13), eye)
	# Yeux, de part et d'autre de la tete.
	_add_box(Vector3(0.06, 0.06, 0.05), Vector3(-0.26, 0.78, -0.92), eye)
	_add_box(Vector3(0.06, 0.06, 0.05), Vector3(0.26, 0.78, -0.92), eye)
	# Oreilles, deux petits pavillons sur le dessus de la tete.
	_add_box(Vector3(0.125, 0.125, 0.06), Vector3(-0.16, 0.9, -0.72),
		Color(0.88, 0.52, 0.52))
	_add_box(Vector3(0.125, 0.125, 0.06), Vector3(0.16, 0.9, -0.72),
		Color(0.88, 0.52, 0.52))
	# Pattes 4 x 6 x 4 pixels, aux quatre coins du corps.
	for dx in [-0.19, 0.19]:
		for dz in [-0.32, 0.32]:
			_legs.append(_add_leg(Vector3(0.25, 0.375, 0.25),
				Vector3(dx, 0.375, dz), legs_color))
	# Queue : un petit carré plat au-dessus de l'arrière-train. Minuscule, mais
	# c'est elle qui donne le sens de lecture à la silhouette vue de dos — et le
	# dos, c'est ce qu'on voit le plus souvent d'un animal qui erre.
	_add_box(Vector3(0.12, 0.12, 0.06), Vector3(0, 0.7, 0.53),
		Color(0.88, 0.52, 0.52))


## Zombie : humanoide debout, deux bras qui depassent le buste, deux jambes.
func _build_zombie() -> void:
	var flesh := Color(0.36, 0.58, 0.34)
	var shirt := Color(0.32, 0.45, 0.62)
	var pants := Color(0.26, 0.30, 0.48)
	var eye := Color(0.10, 0.16, 0.10)
	# Jambes de 12 pixels, buste de 12, tete de 8 : 1,8 bloc au total.
	for dx in [-0.125, 0.125]:
		_legs.append(_add_leg(Vector3(0.25, 0.75, 0.25), Vector3(dx, 0.75, 0), pants))
	_add_box(Vector3(0.5, 0.75, 0.25), Vector3(0, 1.125, 0), shirt)
	# Bras, poses le long du buste et depassant un peu devant.
	for dx in [-0.375, 0.375]:
		_add_box(Vector3(0.25, 0.75, 0.25), Vector3(dx, 1.125, 0), flesh)
	_add_box(Vector3(0.5, 0.5, 0.5), Vector3(0, 1.75, 0), flesh)
	_add_box(Vector3(0.08, 0.08, 0.05), Vector3(-0.12, 1.8, -0.26), eye)
	_add_box(Vector3(0.08, 0.08, 0.05), Vector3(0.12, 1.8, -0.26), eye)


## Boite statique : corps, tete, museau, oreilles, queue. La matiere vient de
## `MobSkin` (un grain pixel-art a l'echelle du terrain), et non d'un aplat.
func _add_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = MobSkin.box_mesh(size)
	node.material_override = MobSkin.material(MobSkin.tone(color))
	node.position = pos
	add_child(node)
	_boxes.append(node)
	return node


## Patte ou jambe : le pivot est a la hanche, la boite pend dessous. Tourner la
## boite autour de son centre faisait basculer la patte dans le vide, la hanche
## restant accrochee a rien — c'est la meme regle que pour le joueur.
func _add_leg(size: Vector3, hip: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	var node := MeshInstance3D.new()
	node.mesh = MobSkin.box_mesh(size)
	node.material_override = MobSkin.material(MobSkin.tone(color))
	node.position = Vector3(0, -size.y * 0.5, 0)
	pivot.add_child(node)
	add_child(pivot)
	_boxes.append(node)
	return pivot


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_step_cd = maxf(0.0, _step_cd - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)

	var player := Game.player
	var hostile := kind == Kind.ZOMBIE
	var to_player := Vector3.ZERO
	var distance := 999.0
	if player != null and not player.dead:
		to_player = player.global_position - global_position
		distance = to_player.length()

	# Le zombie brule au soleil : il perd un point toutes les 0.5 s.
	# `burns_in_sunlight` teste deja l'elevation du soleil : c'etait en ajoutant
	# ici un second filtre `> 0.15` que l'ensemble devenait vide, et qu'aucun
	# zombie n'a jamais brule.
	if hostile and Mob.burns_in_sunlight(kind, Game.day_time):
		_burn(delta)

	# Direction voulue : poursuite pour l'hostile, errance sinon.
	var wish := Vector3.ZERO
	if hostile and distance < SIGHT_RANGE:
		wish = to_player
		wish.y = 0.0
		_yaw = atan2(-wish.x, -wish.z)
	elif distance < 3.0:
		# Un animal s'ecarte du joueur.
		wish = -to_player
		wish.y = 0.0
		if wish.length() > 0.01:
			wish = wish.normalized()
		_yaw = atan2(-wish.x, -wish.z)
	else:
		_wander -= delta
		if _wander <= 0.0:
			_wander = randf_range(1.5, 4.0)
			_yaw = randf() * TAU
		# Le modèle regarde vers **-z** : c'est pourquoi les deux branches
		# ci-dessus en déduisent le lacet avec `atan2(-x, -z)`. Avancer, ici,
		# c'est donc `(sin, cos)` **négatif** — l'autre signe faisait avancer
		# l'animal à reculons, tête derrière lui, dès qu'il errait.
		wish = Vector3(-sin(_yaw), 0.0, -cos(_yaw))

	var speed := 1.4 if kind == Kind.PIG else (2.6 if hostile else 1.4)
	if wish.length() > 0.01:
		velocity.x = wish.normalized().x * speed
		velocity.z = wish.normalized().z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	rotation.y = lerp_angle(rotation.y, _yaw, clampf(delta * 8.0, 0.0, 1.0))

	# Gravite et franchissement d'une marche.
	if is_on_floor():
		velocity.y = 0.0
		# Un mob ne doit pas rester bloque contre une marche. Avant, le saut
		# partait des que le mob touchait un mur, a chaque image : il
		# sautilait sur place. On ne tente le franchissement que s'il pousse
		# vraiment vers le mur, et au plus une fois tous les STEP_COOLDOWN.
		if is_on_wall() and _step_cd <= 0.0 and wish.length() > 0.01:
			velocity.y = Mob.JUMP_VELOCITY
			_step_cd = Mob.STEP_COOLDOWN
	else:
		velocity.y -= Mob.GRAVITY * delta
		_fall_from = maxf(_fall_from, global_position.y)
	move_and_slide()

	# Degats de chute. La hauteur tombee se lit AVANT de remettre `_fall_from`
	# a zero : sinon la difference porte toujours sur 0 moins la position
	# courante, elle est negative, et le test `> SAFE_FALL` n'est jamais vrai.
	# Les degats de chute n'existaient donc pas.
	if is_on_floor():
		var drop := _fall_from - global_position.y
		_fall_from = 0.0
		if drop > Mob.SAFE_FALL:
			take_damage(int(drop - (Mob.SAFE_FALL - 1.0)), Vector3.ZERO)

	# Attaque au contact.
	if hostile and distance < Mob.ATTACK_RANGE and _attack_cd <= 0.0 \
			and player != null and not player.dead:
		_attack_cd = 1.1
		var dmg := 5 if not Mob.sun_is_up(Game.day_time) else 3  # plus fort la nuit
		player.take_damage(dmg, "monstre")
		player.velocity += to_player.normalized() * 5.0

	_animate(delta)


func _animate(_delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.2
	var phase := float(Time.get_ticks_msec()) * 0.008
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		leg.rotation.x = sin(phase + float(i) * PI) * 0.5 if moving else 0.0
	# Un `Node3D` n'a pas de `modulate` : le coup recus se voit par une
	# lueur rouge sur les boites, remise a zero juste apres.
	for box in _boxes:
		var mat := box.material_override as StandardMaterial3D
		mat.emission_enabled = _hurt_flash > 0.0
		mat.emission = Color(0.9, 0.15, 0.12)
		mat.emission_energy_multiplier = 0.8


func _burn(delta: float) -> void:
	_burn_cd -= delta
	if _burn_cd <= 0.0:
		_burn_cd = 0.5
		take_damage(2, Vector3.ZERO)


## Degats recus. `knock` impulsion de recul (zero pour un feu ou une chute).
func take_damage(amount: int, knock: Vector3) -> void:
	if health <= 0:
		return
	health -= amount
	_hurt_flash = 0.25
	velocity += knock
	if knock != Vector3.ZERO:
		velocity.y = maxf(velocity.y, 5.0)
	if health <= 0:
		_die()


func _die() -> void:
	Sounds.play_at("hurt", global_position, -6.0)
	Game.on_mob_killed(self)
	queue_free()
