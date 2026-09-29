class_name Chunk
extends Node3D

## Un chunk : ses donnees de blocs, son maillage et sa collision.
##
## Le maillage tient en un seul MeshInstance3D : l'ArrayMesh porte jusqu'a trois
## surfaces (opaque, eau, alpha) avec chacune son materiau. La collision est un
## unique ConcavePolygonShape3D construit a partir des memes triangles que la
## surface opaque et la surface alpha, ce qui garantit qu'elles correspondent
## exactement au rendu.

enum State { EMPTY, GENERATING, GENERATED, MESHING, READY }

var cx: int
var cz: int
var blocks := PackedByteArray()
var state: int = State.EMPTY

## Bornes du volume non vide, pour ne pas mailler le ciel.
var min_y := 0
var max_y := 0

## Version des donnees ; le maillage n'est reapplique que s'il la depasse.
var version := 0
var mesh_version := -1

## A remailler : donnees modifiees, ou bordure exposee par le mouvement d'un
## voisin.
var mesh_dirty := true
var dirty_border := true

## Chunk modifie par le joueur : conserve en memoire meme apreschargement.
var modified := false

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D


func setup(chunk_x: int, chunk_z: int) -> void:
	cx = chunk_x
	cz = chunk_z
	name = "Chunk_%d_%d" % [chunk_x, chunk_z]
	position = Vector3(chunk_x * Vox.CHUNK_X, 0, chunk_z * Vox.CHUNK_Z)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	# Le maillage est deja en coordonnees monde a l'echelle du chunk.
	_mesh_instance.transform = Transform3D.IDENTITY
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mesh_instance)

	# Une CollisionShape3D n'est prise en compte par PhysicServer que si elle
	# est l'enfant d'un CollisionObject3D : sous ce simple Node3D, elle reste
	# orpheline, le monde est sans collision et le joueur tombe dans le vide.
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	body.add_child(_collision)


func block(x: int, y: int, z: int) -> int:
	if y < 0 or y >= Vox.CHUNK_Y:
		return Blocks.AIR
	return blocks[Vox.index(x, y, z)]


func set_local_block(x: int, y: int, z: int, id: int) -> void:
	if y < 0 or y >= Vox.CHUNK_Y:
		return
	var idx := Vox.index(x, y, z)
	if blocks[idx] == id:
		return
	blocks[idx] = id
	version += 1
	modified = true
	if id != Blocks.AIR:
		min_y = mini(min_y, y)
	max_y = maxi(max_y, y)


## Hauteur du premier bloc sur lequel on peut se tenir dans cette colonne.
## Les blocs en croix (torches) et l'eau ne comptent pas.
func height_above(x: int, z: int) -> int:
	for y in range(Vox.CHUNK_Y - 1, -1, -1):
		if Blocks.is_solid(blocks[Vox.index(x, y, z)]):
			return y
	return 0


func world_block(wx: int, y: int, wz: int) -> int:
	return block(wx - cx * Vox.CHUNK_X, y, wz - cz * Vox.CHUNK_Z)


## Applique un maillage produit par un worker.
func apply_mesh(result: Dictionary) -> void:
	var mesh: ArrayMesh = result["mesh"]
	_mesh_instance.mesh = mesh

	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, Assets.material_for(result["kinds"][i]))

	var faces: PackedVector3Array = result["faces"]
	if faces.is_empty():
		_collision.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		_collision.shape = shape

	mesh_version = version
	mesh_dirty = false
	dirty_border = false
	state = State.READY
