class_name VoxelRaycast
extends RefCounted

## Parcours DDA (Amanatides & Woo) dans la grille de voxels.
##
## Indispensable pour casser/poser un bloc : le moteur physique ne connait que
## la surface du terrain, pas les cubes indivisibles. On avance donc cellule par
## cellule le long du rayon, en gardant pour chaque axe la distance jusqu'a la
## prochaine frontiere de cellule.

const EPS := 0.0001


## Resultat : {hit: bool, pos: Vector3i, normal: Vector3i, distance: float, block: int}
static func cast(world: World, origin: Vector3, direction: Vector3, max_distance: float,
		ignore_liquids: bool = true) -> Dictionary:
	var dir := direction.normalized()
	var empty := {"hit": false, "pos": Vector3i.ZERO, "normal": Vector3i.ZERO,
		"distance": 0.0, "block": Blocks.AIR}
	if dir.length_squared() < EPS:
		return empty

	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))

	var step := Vector3i(
		0 if absf(dir.x) < EPS else (1 if dir.x > 0.0 else -1),
		0 if absf(dir.y) < EPS else (1 if dir.y > 0.0 else -1),
		0 if absf(dir.z) < EPS else (1 if dir.z > 0.0 else -1))

	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)

	if step.x != 0:
		t_delta.x = absf(1.0 / dir.x)
		t_max.x = ((float(pos.x) + (1.0 if dir.x > 0.0 else 0.0)) - origin.x) / dir.x
	if step.y != 0:
		t_delta.y = absf(1.0 / dir.y)
		t_max.y = ((float(pos.y) + (1.0 if dir.y > 0.0 else 0.0)) - origin.y) / dir.y
	if step.z != 0:
		t_delta.z = absf(1.0 / dir.z)
		t_max.z = ((float(pos.z) + (1.0 if dir.z > 0.0 else 0.0)) - origin.z) / dir.z

	var normal := Vector3i.ZERO
	var travelled := 0.0
	# Une cellule de plus que la distance maximale ne peut pas etre atteinte.
	for _step in int(max_distance * 3.0) + 3:
		var id := world.get_block(pos)
		var targetable := id != Blocks.AIR
		if targetable and ignore_liquids and Blocks.is_liquid(id):
			targetable = false
		if targetable:
			return {"hit": true, "pos": pos, "normal": normal, "distance": travelled,
				"block": id}

		if t_max.x < t_max.y and t_max.x < t_max.z:
			if t_max.x > max_distance:
				break
			travelled = t_max.x
			t_max.x += t_delta.x
			pos.x += step.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			if t_max.y > max_distance:
				break
			travelled = t_max.y
			t_max.y += t_delta.y
			pos.y += step.y
			normal = Vector3i(0, -step.y, 0)
		else:
			if t_max.z > max_distance:
				break
			travelled = t_max.z
			t_max.z += t_delta.z
			pos.z += step.z
			normal = Vector3i(0, 0, -step.z)

	return empty
