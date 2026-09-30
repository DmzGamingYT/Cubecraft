class_name World
extends Node3D

## Monde infini en streaming, genere et maille sur des threads de fond.
##
## Deux etapes par chunk : GENERATION, puis MAILLAGE. Un chunk n'est maille que
## lorsque ses 8 voisins sont generes, faute de quoi ses faces de bordure
## seraient calculees contre de l'air fictif (un mur traverserait le monde).
##
## Chaque tache travaille sur une COPIE des donnees (volume padding compris) et
## rapporte le numero de version de son chunk : un resultat perime est jete, ce
## qui supprime toute course entre l'edition d'un bloc et le remaillage.
## L'application se fait sur le thread principal, avec un budget par image pour
## etaler la creation des maillages et des collisions.

signal block_changed(pos: Vector3i, old_id: int, new_id: int)
## Emis quand une colonne entre en memoire, generative ou restauree depuis les
## donnees conservees. Le multijoueur s'en sert pour reappliquer les editions
## recusées avant que la colonne n'existe.
signal chunk_loaded(cx: int, cz: int)

## Chunks modifies : on les garde en memoire apres dechargement de la scene.
const KEEP_MARGIN := 2
const MESHES_PER_FRAME := 2
const GENERATIONS_PER_FRAME := 8

## Filet de securite du reelancement de `_schedule` (voir `_schedule`), en
## millisecondes. Le drapeau suffit en temps normal ; ce delai garantit qu'un
## evenement qu'on aurait oublie de signaler ne laisse pas le disque a moitie
## charge. On mesure le temps ecoule plutot que d'additionner un delta : les
## tests appellent `update` depuis leurs propres boucles, ou le delta du monde
## n'est pas celui de leur image.
const RESCHEDULE_BACKSTOP_MS := 500

var seed_value := 0
var render_distance := 5

## key -> Chunk resident.
var chunks: Dictionary = {}
## key -> {blocks, min_y, max_y} pour les chunks modifies hors de portee.
var _kept: Dictionary = {}

var _gen: WorldGen
var _center := Vector2i(1 << 30, 1 << 30)
var _queued_gen: Dictionary = {}
var _queued_mesh: Dictionary = {}
## `_schedule` coute un balayage du disque et deux tris : le refaire a chaque
## image, c'est payer la fouille du monde 60 fois par seconde pour trouver le
## plus souvent rien de neuf. Le drapeau est pose par ce qui peut reellement
## changer la situation — un resultat de tache applique, une edition, un
## changement de portee — et `update` ne reveille le calendrier que sur ce
## drapeau, le deplacement du joueur, ou le filet de securite.
var _schedule_dirty := true
var _last_schedule_at := 0

## Positions des blocs qui emettent de la lumiere (torches), pour TorchLights.
var torches: Dictionary = {}

var _lock := Mutex.new()
var _gen_results: Dictionary = {}
var _mesh_results: Dictionary = {}


func setup(world_seed: int, distance: int) -> void:
	seed_value = world_seed
	render_distance = maxi(2, distance)
	_gen = WorldGen.new(seed_value)


func _ready() -> void:
	if _gen == null:
		setup(seed_value, render_distance)


func _exit_tree() -> void:
	# Les taches en vol referencent cet objet : on les laisse finir avant de
	# mourir, sinon un worker thread toucherait un objet deja detruit.
	var deadline := Time.get_ticks_msec() + 2000
	while (_queued_gen.size() > 0 or _queued_mesh.size() > 0) \
			and Time.get_ticks_msec() < deadline:
		_collect()
		OS.delay_msec(5)


## Change la portee de rendu a chaud. Le prochain appel a `update` recharge le
## disque autour du joueur et decharge ce qui sort du nouveau rayon.
func set_render_distance(value: int) -> void:
	var clamped := clampi(value, 2, 14)
	if clamped == render_distance:
		return
	render_distance = clamped
	_center = Vector2i(1 << 30, 1 << 30)  # force la revision du centre
	_schedule_dirty = true


# ------------------------------------------------------------------ requetes

func chunk_at(cx: int, cz: int) -> Chunk:
	return chunks.get(Vox.chunk_key(cx, cz))


func _blocks_at(cx: int, cz: int) -> PackedByteArray:
	var key := Vox.chunk_key(cx, cz)
	var chunk: Chunk = chunks.get(key)
	if chunk != null and not chunk.blocks.is_empty():
		return chunk.blocks
	var kept: Variant = _kept.get(key)
	return kept["blocks"] if kept != null else PackedByteArray()


## Bloc du monde ; AIR si le chunk n'est pas charge ou hors limites.
func get_block(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= Vox.CHUNK_Y:
		return Blocks.AIR
	var coords := Vox.chunk_of(pos)
	var chunk := chunk_at(coords.x, coords.y)
	if chunk == null:
		return Blocks.AIR
	return chunk.world_block(pos.x, pos.y, pos.z)


## Ecrit un bloc et reclasse le maillage du voisinage immediat.
## Renvoie l'ancien identifiant, ou -1 si la zone n'est pas chargee.
func set_block(pos: Vector3i, id: int) -> int:
	if pos.y < 0 or pos.y >= Vox.CHUNK_Y:
		return -1
	var coords := Vox.chunk_of(pos)
	var chunk := chunk_at(coords.x, coords.y)
	if chunk == null:
		return -1
	var lx := pos.x - coords.x * Vox.CHUNK_X
	var lz := pos.z - coords.y * Vox.CHUNK_Z
	var old := chunk.block(lx, pos.y, lz)
	if old == id:
		return old
	chunk.set_local_block(lx, pos.y, lz, id)
	# Seules les torches sont eclairantes : on tient la liste a jour plutot que
	# de balayer la grille a chaque image.
	if Blocks.light_of(old) > 0:
		torches.erase(pos)
	if Blocks.light_of(id) > 0:
		torches[pos] = true

	_mark_dirty(coords.x, coords.y)
	_schedule_dirty = true
	block_changed.emit(pos, old, id)
	return old


func _mark_dirty(cx: int, cz: int) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk: Chunk = chunks.get(Vox.chunk_key(cx + dx, cz + dz))
			if chunk != null:
				chunk.mesh_dirty = true
				# Un voisin a bouge : sa bordure doit etre remailee meme si ses
				# propres donnees n'ont pas change.
				if dx != 0 or dz != 0:
					chunk.dirty_border = true
	_schedule_dirty = true


## Position d'apparition : premiere terre emergee autour de l'origine.
func find_spawn() -> Vector3:
	for r in range(0, 40):
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				if absi(x) != r and absi(z) != r:
					continue
				var h := _gen.height_at(x, z)
				if h > Vox.SEA_LEVEL + 1:
					return Vector3(x + 0.5, h + 1.2, z + 0.5)
	return Vector3(0.5, Vox.SEA_LEVEL + 4, 0.5)


func biome_at(wx: int, wz: int) -> int:
	return _gen.biome_at(wx, wz)


## Hauteur du bloc solide le plus haut a une position donnee.
func surface_height(wx: int, wz: int) -> int:
	var coords := Vox.chunk_of(Vector3i(wx, 0, wz))
	var chunk := chunk_at(coords.x, coords.y)
	if chunk == null:
		return _gen.height_at(wx, wz)
	var top := chunk.height_above(wx - coords.x * Vox.CHUNK_X, wz - coords.y * Vox.CHUNK_Z)
	return Vox.SEA_LEVEL if top == 0 and chunk.blocks.is_empty() else top


# --------------------------------------------------------------- streaming

func update(player_pos: Vector3) -> void:
	_collect()
	var center := Vox.chunk_of(Vector3i(floori(player_pos.x), 0, floori(player_pos.z)))
	if center != _center:
		_center = center
		_unload_far(center)
		_schedule_dirty = true
	var now := Time.get_ticks_msec()
	if now - _last_schedule_at >= RESCHEDULE_BACKSTOP_MS:
		_schedule_dirty = true
	if _schedule_dirty:
		_schedule_dirty = false
		_last_schedule_at = now
		_schedule()


## Le disque de terrain autour du joueur est-il complet ?
func is_loaded_around(pos: Vector3, radius: int) -> bool:
	var center := Vox.chunk_of(Vector3i(floori(pos.x), 0, floori(pos.z)))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var chunk: Chunk = chunks.get(Vox.chunk_key(center.x + dx, center.y + dz))
			if chunk == null or chunk.state != Chunk.State.READY:
				return false
	return true


func _collect() -> void:
	if _gen_results.is_empty() and _mesh_results.is_empty():
		return
	_lock.lock()
	var gen := _gen_results
	var mesh := _mesh_results
	_gen_results = {}
	_mesh_results = {}
	_lock.unlock()

	for key in gen:
		var entry: Dictionary = gen[key]
		_queued_gen.erase(key)
		var cx := Vox.key_to_cx(key)
		var cz := Vox.key_to_cz(key)
		var chunk := _ensure_chunk(cx, cz)
		if chunk.blocks.is_empty():
			chunk.blocks = entry["blocks"]
			chunk.min_y = entry["bounds"].x
			chunk.max_y = entry["bounds"].y
			chunk.version += 1
			chunk.state = Chunk.State.GENERATED
		chunk.mesh_dirty = true
		# Ces voisins viennent d'obtenir une bordure qui leur manquait.
		_mark_dirty(cx, cz)
	_schedule_dirty = true

	# Le maillage est le poste le plus cher : on l'etalit sur plusieurs images.
	var budget := MESHES_PER_FRAME
	for key in mesh:
		if budget <= 0:
			_lock.lock()
			_mesh_results[key] = mesh[key]
			_lock.unlock()
			continue
		budget -= 1
		_queued_mesh.erase(key)
		var entry: Dictionary = mesh[key]
		var chunk: Chunk = chunks.get(key)
		if chunk == null or chunk.version != entry["version"]:
			continue  # le monde a bouge depuis : resultat obsolete
		var built := ChunkMesher.to_mesh(entry["bufs"])
		built["faces"] = entry["faces"]
		chunk.apply_mesh(built)
		chunk.mesh_dirty = false
		chunk.dirty_border = false


func _ensure_chunk(cx: int, cz: int) -> Chunk:
	var key := Vox.chunk_key(cx, cz)
	var chunk: Chunk = chunks.get(key)
	if chunk != null:
		return chunk

	chunk = Chunk.new()
	chunk.setup(cx, cz)
	var kept: Variant = _kept.get(key)
	if kept != null:
		# Chunk modifie par le joueur : on restaure ses donnees plutot que de
		# regenenerer, sans quoi les editions seraient perdues.
		chunk.blocks = kept["blocks"]
		chunk.min_y = kept["min_y"]
		chunk.max_y = kept["max_y"]
		chunk.version = 1
		chunk.state = Chunk.State.GENERATED
		_kept.erase(key)
	add_child(chunk)
	chunks[key] = chunk
	# Le monde est procedural et se construit paresseusement : en multijoueur,
	# une edition recue du reseau peut arriver avant que le chunk existe, et il
	# faut savoir quand le rejouer. Le signal est emis ici, une fois le chunk
	# pret a recevoir des blocs.
	chunk_loaded.emit(cx, cz)
	return chunk


## Decharge les chunks hors portee, en gardant leurs donnees s'ils ont ete
## modifies par le joueur.
func _unload_far(center: Vector2i) -> void:
	var limit := render_distance + KEEP_MARGIN
	var doomed: Array = []
	for key in chunks:
		var dx := absi(Vox.key_to_cx(key) - center.x)
		var dz := absi(Vox.key_to_cz(key) - center.y)
		if dx > limit or dz > limit:
			doomed.append(key)
	for key in doomed:
		var chunk: Chunk = chunks[key]
		chunk.queue_free()
		chunks.erase(key)
		if chunk.modified:
			_kept[key] = {
				"blocks": chunk.blocks, "min_y": chunk.min_y, "max_y": chunk.max_y,
			}
	# Les sources des positions dechargees quittent la liste des torches.
	# `TorchLights` la parcourt cinq fois par seconde, et une source oubliee
	# n'est plus rien : son chunk n'existe plus, `get_block` y rend de l'air,
	# et la lumiere qu'elle detenait se met a eclairer le vide. La liste
	# grossissait aussi sans fin au fur et a mesure que le joueur explore.
	var dropped: Array = []
	for pos: Vector3i in torches:
		var coords := Vox.chunk_of(pos)
		if doomed.has(Vox.chunk_key(coords.x, coords.y)):
			dropped.append(pos)
	for pos in dropped:
		torches.erase(pos)


func _schedule() -> void:
	var center := _center
	var max_tasks := maxi(2, OS.get_processor_count())
	var span := render_distance + 1

	# 1. Generer, du plus proche du joueur au plus eloigne.
	var wanted: Array = []
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			if dx * dx + dz * dz > span * span:
				continue
			var cx := center.x + dx
			var cz := center.y + dz
			var key := Vox.chunk_key(cx, cz)
			if not _blocks_at(cx, cz).is_empty() or _queued_gen.has(key):
				continue
			wanted.append([dx * dx + dz * dz, cx, cz, key])
	wanted.sort_custom(func(a, b): return a[0] < b[0])

	var submitted := 0
	for entry in wanted:
		if submitted >= GENERATIONS_PER_FRAME or _inflight() >= max_tasks:
			break
		_queued_gen[entry[3]] = true
		WorkerThreadPool.add_task(_task_generate.bind(entry[1], entry[2]))
		submitted += 1

	# 2. Mailler tout ce qui est Resident, sale, et entoure de voisins generes.
	var candidates: Array = []
	for key in chunks:
		var chunk: Chunk = chunks[key]
		if not (chunk.mesh_dirty or chunk.dirty_border):
			continue
		if _queued_mesh.has(key):
			continue
		if not _neighbours_ready(Vox.key_to_cx(key), Vox.key_to_cz(key)):
			continue
		var dx := absi(Vox.key_to_cx(key) - center.x)
		var dz := absi(Vox.key_to_cz(key) - center.y)
		if dx > span or dz > span:
			continue
		candidates.append([dx * dx + dz * dz, Vox.key_to_cx(key), Vox.key_to_cz(key), key])
	candidates.sort_custom(func(a, b): return a[0] < b[0])

	for entry in candidates:
		if _inflight() >= max_tasks:
			break
		_queued_mesh[entry[3]] = true
		_submit_mesh(entry[1], entry[2])


func _inflight() -> int:
	return _queued_gen.size() + _queued_mesh.size()


func _neighbours_ready(cx: int, cz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if _blocks_at(cx + dx, cz + dz).is_empty():
				return false
	return true


# ------------------------------------------------------------------- taches

func _task_generate(cx: int, cz: int) -> void:
	var gen := WorldGen.new(seed_value)
	var data := PackedByteArray()
	data.resize(Vox.CHUNK_VOLUME)
	var bounds := gen.generate_chunk(cx, cz, data)
	if _lock == null:
		return
	_lock.lock()
	_gen_results[Vox.chunk_key(cx, cz)] = {"blocks": data, "bounds": bounds}
	_lock.unlock()


## Copie de travail du volume padding.
##
## Le volume fait 18 x 18 colonnes : le chunk central occupe px/pz 1..16, et il ne
## faut donc tirer de chaque voisin que SA bordure — une colonne, pas un chunk
## entier. Le remplissage se fait dans l'ordre exact de la memoire (pz puis px),
## une colonne de 96 octets par append_array, soit 18 x 18 x 96 = 31 104 octets.
func _padded_for(cx: int, cz: int) -> PackedByteArray:
	var blank := PackedByteArray()
	blank.resize(Vox.CHUNK_Y)
	var last := ChunkMesher.PAD - 1
	var sources := [
		_blocks_at(cx - 1, cz - 1), _blocks_at(cx, cz - 1), _blocks_at(cx + 1, cz - 1),
		_blocks_at(cx - 1, cz), _blocks_at(cx, cz), _blocks_at(cx + 1, cz),
		_blocks_at(cx - 1, cz + 1), _blocks_at(cx, cz + 1), _blocks_at(cx + 1, cz + 1),
	]
	var pad := PackedByteArray()
	for pz in ChunkMesher.PAD:
		var inside_row := pz >= 1 and pz <= last - 1
		for px in ChunkMesher.PAD:
			var inside := inside_row and px >= 1 and px <= last - 1
			var index := 0
			var lx := 0
			var lz := 0
			if inside:
				index = 4
				lx = px - 1
				lz = pz - 1
			elif inside_row:
				# Bords gauche et droit : une colonne du voisin lateral.
				lx = Vox.CHUNK_X - 1 if px == 0 else 0
				lz = pz - 1
				index = 3 if px == 0 else 5
			elif px >= 1 and px <= last - 1:
				# Bords arriere et avant.
				lx = px - 1
				lz = Vox.CHUNK_Z - 1 if pz == 0 else 0
				index = 1 if pz == 0 else 7
			else:
				# Coins.
				var left := px == 0
				var back := pz == 0
				lx = Vox.CHUNK_X - 1 if left else 0
				lz = Vox.CHUNK_Z - 1 if back else 0
				index = (0 if back else 6) + (0 if left else 2)

			var src: PackedByteArray = sources[index]
			if src.is_empty():
				pad.append_array(blank)
			else:
				var base := Vox.column_index(lx, lz)
				pad.append_array(src.slice(base, base + Vox.CHUNK_Y))
	return pad


## Teintes de biome des 18 x 18 colonnes du padding.
func _tints_for(cx: int, cz: int) -> Array:
	var grass := PackedColorArray()
	var foliage := PackedColorArray()
	grass.resize(ChunkMesher.PAD_AREA)
	foliage.resize(ChunkMesher.PAD_AREA)
	var ox := (cx - 1) * Vox.CHUNK_X
	var oz := (cz - 1) * Vox.CHUNK_Z
	for pz in ChunkMesher.PAD:
		for px in ChunkMesher.PAD:
			var biome := _gen.biome_at(ox + px, oz + pz)
			var column := px + pz * ChunkMesher.PAD
			grass[column] = Biomes.grass_tint(biome)
			foliage[column] = Biomes.foliage_tint(biome)
	return [grass, foliage]


## La lecture du monde vituel se fait ici, sur le thread principal ; seule la
## triangulation part sur un thread de fond.
func _submit_mesh(cx: int, cz: int) -> void:
	var chunk := chunk_at(cx, cz)
	if chunk == null:
		_queued_mesh.erase(Vox.chunk_key(cx, cz))
		return
	var pad := _padded_for(cx, cz)
	var tints := _tints_for(cx, cz)
	WorkerThreadPool.add_task(_task_mesh.bind(cx, cz, pad, tints[0], tints[1],
			chunk.min_y, chunk.max_y, chunk.version))


func _task_mesh(cx: int, cz: int, pad: PackedByteArray, grass: PackedColorArray,
		foliage: PackedColorArray, min_y: int, max_y: int, version: int) -> void:
	var bufs := ChunkMesher.build(pad, grass, foliage, min_y, max_y)
	var faces := ChunkMesher.collision_faces(bufs)
	if _lock == null:
		return
	_lock.lock()
	_mesh_results[Vox.chunk_key(cx, cz)] = {
		"bufs": bufs, "faces": faces, "version": version,
	}
	_lock.unlock()
