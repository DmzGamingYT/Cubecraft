class_name ItemEntity
extends Node3D

## Objet largue au sol : petit cube qui tourne, tombe, puis se fait aspirer
## par le joueur quand il passe a portee. Un seul systeme de gravite maison
## suffit : quelques centaines d'entites au maximum dans un rayon raisonnable.

const LIFETIME := 300.0
const PICKUP_RANGE := 1.3
const MAGNET_RANGE := 2.6
const MAGNET_SPEED := 9.0
const HALF_SIZE := 0.14

var item_id := -1
var count := 1
var velocity := Vector3.ZERO

var _age := 0.0
var _mesh: MeshInstance3D
var _sitting := false


static func spawn(parent: Node, pos: Vector3, item: int, amount: int) -> ItemEntity:
	var entity := ItemEntity.new()
	entity.item_id = item
	entity.count = amount
	entity.position = pos
	entity.velocity = Vector3(randf_range(-0.6, 0.6), 1.6, randf_range(-0.6, 0.6))
	parent.add_child(entity)
	return entity


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.3)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = Assets.block_material(
		Items.block_of(item_id) if Items.is_block_item(item_id) else Blocks.COBBLESTONE)
	_mesh.position = Vector3(0, 0.2, 0)
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return

	var world: World = Game.world
	var player: Player = Game.player
	if world == null or player == null:
		return

	# Aspiration magnetique quand le joueur approche.
	var to_player := player.global_position + Vector3(0, 0.9, 0) - (global_position + Vector3(0, 0.2, 0))
	if to_player.length() < MAGNET_RANGE:
		velocity = to_player.normalized() * MAGNET_SPEED
		_sitting = false
	elif _sitting:
		velocity = Vector3.ZERO
	else:
		velocity.y -= 24.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 6.0)

	if not _sitting:
		var motion := velocity * delta
		# Un pas par axe : on peut longer un mur sans rester bloque dedans.
		for axis in 3:
			if is_zero_approx(motion[axis]):
				continue
			var probe := global_position
			probe[axis] += motion[axis]
			if _solid(world, probe):
				if axis == 1:
					velocity.y = 0.0
					_sitting = true
				else:
					velocity[axis] = 0.0
				continue
			global_position[axis] += motion[axis]

	_mesh.rotation.y += delta * 1.6
	_mesh.position.y = 0.2 + sin(_age * 2.4) * 0.05

	if to_player.length() < PICKUP_RANGE:
		_collect(player)


func _solid(world: World, pos: Vector3) -> bool:
	var block := world.get_block(Vector3i(floori(pos.x), floori(pos.y + 0.2), floori(pos.z)))
	return Blocks.is_solid(block)


func _collect(player: Node) -> void:
	var left: int = player.inventory.add(item_id, count)
	if left == count:
		return  # inventaire plein
	Sounds.play_ui("pickup", -8.0)
	if left <= 0:
		queue_free()
	else:
		count = left
