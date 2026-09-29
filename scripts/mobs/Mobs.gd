class_name Mobs
extends Node3D

## Peuplement du monde : fait apparaitre des animaux le jour et des zombies la
## nuit, autour du joueur, et retire ceux qui s'eloignent trop.
##
## Les apparitions se font sur un disque autour du joueur, jamais dans le
## champ de vision immediate, et seulement sur un bloc solide decouvert.

const PASSIVE_TARGET := 5
const HOSTILE_TARGET := 8
const MIN_SPAWN := 16.0
const MAX_SPAWN := 40.0
const SPAWN_INTERVAL := 3.0
const PIG_CHANCE := 0.65

var world: World
var mobs: Array[Mob] = []

var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Graine fixe, et surtout pas de `randomize()` avant : il serait ecrase
	# immediatement. L'apparition des creatures est donc reproductible, comme
	# le terrain lui-meme.
	_rng.seed = 4242


func _process(delta: float) -> void:
	if world == null or Game.player == null:
		return
	_purge_far()
	_timer -= delta
	if _timer <= 0.0:
		_timer = SPAWN_INTERVAL
		_populate()


## Retire les creatures trop loin (et celles de la veille pour les zombies).
##
## Le parcours se fait par index et a l'envers : une creature tuee se
## `queue_free` toute seule, et `Array.erase` refuse alors une instance deja
## liberee (« invalid (previously freed?) object instance »). `remove_at` se
## contente de la position et ne touche jamais a l'objet.
func _purge_far() -> void:
	var player := Game.player
	for i in range(mobs.size() - 1, -1, -1):
		var mob: Mob = mobs[i]
		if not is_instance_valid(mob):
			mobs.remove_at(i)
			continue
		if player != null and mob.global_position.distance_to(player.global_position) > Mob.DESPAWN_DISTANCE:
			mob.queue_free()
			mobs.remove_at(i)


func _count(kind: int) -> int:
	var total := 0
	for mob in mobs:
		if is_instance_valid(mob) and mob.kind == kind:
			total += 1
	return total


func _populate() -> void:
	var passive_missing := PASSIVE_TARGET - _count(Mob.Kind.PIG)
	if passive_missing > 0:
		_spawn(Mob.Kind.PIG, mini(2, passive_missing))
	if Mob.hostile_spawns(Game.day_time):
		var hostile_missing := HOSTILE_TARGET - _count(Mob.Kind.ZOMBIE)
		if hostile_missing > 0 and _rng.randf() < 0.6:
			_spawn(Mob.Kind.ZOMBIE, 1)


## Cherche une position valide (bloc solide, 2 de haut libre, hors du joueur).
func find_spawn_spot() -> Vector3:
	var player := Game.player
	for attempt in 8:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(MIN_SPAWN, MAX_SPAWN)
		var x := int(round(player.global_position.x + cos(angle) * radius))
		var z := int(round(player.global_position.z + sin(angle) * radius))
		var ground := world.surface_height(x, z)
		if ground <= 0 or ground >= Vox.CHUNK_Y - 3:
			continue
		# Sur un chunk non charge, `get_block` renvoie AIR partout : les deux
		# tests de passage ci-dessous reussiraient donc sans avoir rien vu, et
		# le mob naitrait dans le vide pour y tomber sans arret. On exige un
		# chunk reellement present,collision comprise.
		var coords := Vox.chunk_of(Vector3i(x, 0, z))
		if world.chunk_at(coords.x, coords.y) == null:
			continue
		if Blocks.is_liquid(world.get_block(Vector3i(x, ground, z))):
			continue
		if world.get_block(Vector3i(x, ground + 1, z)) != Blocks.AIR:
			continue
		if world.get_block(Vector3i(x, ground + 2, z)) != Blocks.AIR:
			continue
		return Vector3(x + 0.5, ground + 1.0, z + 0.5)
	return Vector3.ZERO


## Pose une creature a une position precise. Sert au controle visuel
## (`--fpshot`) et aux tests : il faut alors deux animaux a un endroit donne,
## et non le peuplement aleatoire qui les disperse autour du joueur.
func spawn_at(kind: int, at: Vector3, facing: float = 0.0) -> Mob:
	if world == null:
		return null
	var mob := Mob.new()
	mob.setup(kind, world)
	# La position globale ne se regle qu'une fois le mob dans l'arbre : avant
	# `add_child`, Godot renvoie l'identite et signale une erreur.
	add_child(mob)
	mob.global_position = at
	mob.rotation.y = facing
	mobs.append(mob)
	return mob


func _spawn(kind: int, count: int) -> void:
	for i in count:
		var spot := find_spawn_spot()
		if spot == Vector3.ZERO:
			return
		# Les animaux preferent le gazon : une chance sur quatre de passer son
		# chemin. Les zombies, eux, apparaissent des que la nuit tombe.
		if kind == Mob.Kind.PIG and _rng.randf() > PIG_CHANCE:
			continue
		var mob := Mob.new()
		mob.setup(kind, world)
		# La position globale ne se regle qu'une fois le mob dans l'arbre :
		# avant `add_child`, Godot renvoie l'identite et signale une erreur.
		add_child(mob)
		mob.global_position = spot
		mobs.append(mob)


## La creature visee par un rayon depuis la camera du joueur, ou null.
func mob_in_sight(from: Vector3, direction: Vector3, reach: float) -> Mob:
	var best: Mob = null
	var best_distance := reach
	for mob in mobs:
		if not is_instance_valid(mob):
			continue
		var to_mob := mob.global_position + Vector3(0, 0.9, 0) - from
		var distance := to_mob.length()
		if distance > best_distance:
			continue
		# Distance au rayon : on tape la creature visee, pas celle a cote.
		var along := to_mob.dot(direction)
		if along <= 0.0:
			continue
		var lateral := (to_mob - direction * along).length()
		if lateral > 0.75:
			continue
		best = mob
		best_distance = distance
	return best
