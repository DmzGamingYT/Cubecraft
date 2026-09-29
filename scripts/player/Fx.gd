class_name Fx
extends Node3D

## Gerbe de particules lors d'un bloc casse.
##
## Un pool de petits cubes part du systeme de particules GPU : il n'y a pas
## besoin de plus de finesse ici, et surtout aucun cout quand la pool est vide.

const POOL_SIZE := 64
const GRAVITY := 22.0

var _pool: Array[MeshInstance3D] = []
var _state: Array = []


func _ready() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3(0.16, 0.16, 0.16)
	for i in POOL_SIZE:
		var node := MeshInstance3D.new()
		node.mesh = cube
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.visible = false
		add_child(node)
		_pool.append(node)
		_state.append({"life": 0.0, "vel": Vector3.ZERO, "spin": Vector3.ZERO})


func burst(world_pos: Vector3, block_id: int, amount: int = 12) -> void:
	var material := Assets.block_material(
		Items.block_of(Items.block_item(block_id)) if block_id != Blocks.AIR else Blocks.STONE)
	var spawned := 0
	for i in POOL_SIZE:
		if spawned >= amount:
			break
		var node := _pool[i]
		var s: Dictionary = _state[i]
		if float(s["life"]) > 0.0:
			continue
		s["life"] = randf_range(0.5, 0.9)
		s["vel"] = Vector3(randf_range(-2.4, 2.4), randf_range(1.4, 4.2), randf_range(-2.4, 2.4))
		s["spin"] = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		node.position = world_pos + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35),
				randf_range(-0.35, 0.35))
		node.scale = Vector3.ONE * randf_range(0.6, 1.3)
		node.material_override = material
		node.visible = true
		spawned += 1


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		var s: Dictionary = _state[i]
		var life := float(s["life"])
		if life <= 0.0:
			continue
		life -= delta
		s["life"] = life
		var node := _pool[i]
		if life <= 0.0:
			node.visible = false
			continue
		var vel: Vector3 = s["vel"]
		vel.y -= GRAVITY * delta
		s["vel"] = vel
		node.position += vel * delta
		node.rotation += (s["spin"] as Vector3) * delta
		node.scale = node.scale.lerp(Vector3.ZERO, clampf(delta * 3.0, 0.0, 1.0))
