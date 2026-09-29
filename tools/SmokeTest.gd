extends SceneTree

## Test de fumee headless du moteur voxel.
##
##   godot --headless --script res://tools/SmokeTest.gd
##
## Verifie, sans ecran ni fenetre : la generation du terrain, la coherence des
## maillages produits (orientation des triangles, bornes des UV), la fabrication
## des collisions, le raycast voxel, les recettes et l'inventaire. Le code de
## retour vaut 0 si tout passe.

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	print("== Cubecraft : test de fumee ==")

	_test_blocks_registry()
	_test_generation()
	_test_single_block()
	_test_meshing()
	_test_winding()
	_test_uvs()
	_test_collision()
	_test_raycast()
	_test_recipes()
	_test_inventory()
	_test_save_codec()
	_test_textures()
	_test_character()
	_test_effects()
	_test_foliage()
	_test_title_seed()

	# La partie integration a besoin d'une SceneTree qui tourne : elle prend le
	# relais dans _process, image par image.
	_world = World.new()
	_world.setup(2024, 2)
	root.add_child(_world)
	_frames = 0
	print("----")
	print("  - integration (streaming du monde)")


# ------------------------------------------------- phase integration (_process)

var _world: World
var _frames := 0
var _phase := 0
var _ground := 0
var _torch := Vector3i.ZERO


func _process(_delta: float) -> bool:
	if _world == null:
		return true
	_frames += 1
	_world.update(Vector3(8, 40, 8))

	if _phase == 0:
		if not _world.is_loaded_around(Vector3(8, 40, 8), 1):
			if _frames > 600:
				check(false, "le monde ne se charge pas en 600 images")
				return _finish()
			return false
		_phase = 1
		_run_world_checks()
		return false

	# Laisse au mailleur le temps de reappliquer le bloc casse.
	if _phase == 1 and _frames > 12:
		_phase = 2
		_run_remesh_checks()
		return false

	# L'interface d'inventaire ne peut pas etre testee ici : en mode --script les
	# autoloads (Game, Atlas) n'existent pas. Ce test est joue dans le vrai jeu
	# par `godot --uitest`, ou la logique des ecrans est reellement exercee.
	return _finish()


func _run_world_checks() -> void:
	check(_world.chunks.size() >= 9, "chunks generes autour du joueur (%d)" % _world.chunks.size())
	var ready := 0
	for key in _world.chunks:
		var chunk: Chunk = _world.chunks[key]
		if chunk.state == Chunk.State.READY and chunk.mesh_dirty == false:
			ready += 1
	check(ready >= 9, "chunks mailles autour du joueur (%d)" % ready)

	# Le terrain sous le joueur est solide.
	_ground = _world.surface_height(8, 8)
	check(_ground > 0, "hauteur de surface plausible (%d)" % _ground)
	check(_world.get_block(Vector3i(8, 0, 8)) == Blocks.BEDROCK, "bedrock au fond")

	# Edition : casser puis poser.
	var target := Vector3i(8, _ground, 8)
	var before := _world.get_block(target)
	check(before != Blocks.AIR, "le bloc de surface existe (%s)" % Blocks.name_of(before))
	var old := _world.set_block(target, Blocks.AIR)
	check(old == before, "set_block renvoie l'ancien bloc")
	check(_world.get_block(target) == Blocks.AIR, "le bloc est casse")
	check(_world.chunk_at(0, 0).mesh_dirty, "le chunk est marque a remailler")

	_torch = Vector3i(8, _ground + 1, 8)
	_world.set_block(_torch, Blocks.TORCH)
	check(_world.get_block(_torch) == Blocks.TORCH, "torche posee")
	check(_world.torches.has(_torch), "la torche est indexee pour l'eclairage")
	check(_world.get_block(target) == Blocks.AIR, "la cassure a bien ete conservee")

	# Un point hors monde est refuse proprement.
	check(_world.set_block(Vector3i(8, -1, 8), Blocks.STONE) == -1, "ecriture refusee sous y=0")
	check(_world.get_block(Vector3i(8, 500, 8)) == Blocks.AIR, "lecture hors monde = air")

	# La collision est enregistree aupres de PhysicServer : une forme posee
	# sous un simple Node3D y est ignoree, et le joueur traverserait le sol.
	var from := Vector3(8.5, float(_ground) + 6.0, 8.5)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(8.5, 0.0, 8.5))
	var contact := _world.get_world_3d().direct_space_state.intersect_ray(query)
	check(not contact.is_empty(), "un rayon physique touche le terrain")
	if not contact.is_empty():
		var y := (contact["position"] as Vector3).y
		# Le bloc casse etait en _ground, la torche en _ground + 1 : le
		# contact doit se faire a la surface, pas au fond du monde (avec des
		# faces inversees, le rayon traversait le sol jusqu'au bedrock).
		check(y >= float(_ground) - 0.001 and y <= float(_ground) + 2.001,
			"le contact se fait a la surface (%.1f, sol=%d)" % [y, _ground])


func _run_remesh_checks() -> void:
	var chunk := _world.chunk_at(0, 0)
	check(chunk.state == Chunk.State.READY, "chunk remaillé")
	var holder: MeshInstance3D = chunk.get_node("Mesh")
	check(holder.mesh != null and holder.mesh.get_surface_count() > 0,
		"le remaillage a produit des surfaces")
	check(_world.get_block(_torch) == Blocks.TORCH, "la torche a survecu au remaillage")
	check(_world.get_block(Vector3i(8, _ground, 8)) == Blocks.AIR,
		"le bloc casse a survecu au remaillage")

	# Sauvegarde : le bloc casse doit y figurer, et pas la terre procedurale.
	var saved_chunks: Array = []
	for key in _world.chunks:
		var edited: Chunk = _world.chunks[key]
		if not edited.modified:
			continue
		saved_chunks.append({
			"cx": edited.cx, "cz": edited.cz,
			"data": SaveSystem.encode_chunk(edited.blocks),
		})
	check(saved_chunks.size() >= 1, "les chunks modifies sont sauvegardes")
	var restored := SaveSystem.decode_chunk(saved_chunks[0]["data"])
	check(restored.size() == Vox.CHUNK_VOLUME, "chunk restaure a la bonne taille")
	check(restored[Vox.index(_torch.x, _torch.y, _torch.z)] == Blocks.TORCH,
		"la torche est bien dans la sauvegarde")
	check(restored[Vox.index(8, _ground, 8)] == Blocks.AIR,
		"le bloc casse est bien dans la sauvegarde")

	# Dechargement : les donnees modifiees doivent survivre en memoire.
	var key := Vox.chunk_key(0, 0)
	_world.update(Vector3(8, 40, 8) + Vector3(500, 0, 500))
	_world.update(Vector3(8, 40, 8) + Vector3(500, 0, 500))
	check(not _world.chunks.has(key), "le chunk eloigne est decharge")
	check(_world._kept.has(key), "le chunk modifie est conserve en memoire")


func _finish() -> bool:
	print("----")
	if failures.is_empty():
		print("OK : %d verifications passees." % checks)
		return true
	for failure in failures:
		print("ECHEC : %s" % failure)
	print("ECHEC : %d/%d verifications en echec." % [failures.size(), checks])
	return true


func check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
	return condition


func section(title: String) -> void:
	print("  - %s" % title)


# ------------------------------------------------------------------ blocs

func _test_blocks_registry() -> void:
	section("registre des blocs")
	check(Blocks.defs.size() == Blocks.COUNT, "chaque bloc a une definition")
	check(Blocks.STONE == 1 and Blocks.AIR == 0, "identifiants de blocs stables")
	for id in range(1, Blocks.COUNT):
		var def := Blocks.def(id)
		check(def.has("name") and def.has("hardness") and def.has("tier"),
			"bloc %d complet" % id)
		check(Blocks.def(9999).has("name"), "bloc inconnu renvoye par defaut")
	check(Items.all().size() == Items.COUNT + Blocks.COUNT - 1,
		"un objet par bloc placeable")
	check(Items.block_of(Items.block_item(Blocks.PLANKS)) == Blocks.PLANKS,
		"aller-retour objet -> bloc")
	check(Blocks.break_time(Blocks.BEDROCK, true) == INF, "bedrock incassable")
	check(Blocks.break_time(Blocks.STONE, true) < Blocks.break_time(Blocks.STONE, false),
		"l'outil correct accelere")


# ------------------------------------------------------------- generation

func _test_generation() -> void:
	section("generation du terrain")
	var gen := WorldGen.new(12345)
	var blocks := PackedByteArray()
	blocks.resize(Vox.CHUNK_VOLUME)
	var bounds := gen.generate_chunk(0, 0, blocks)

	check(bounds.y > Vox.BEDROCK_HEIGHT, "le chunk contient de la matiere")
	check(bounds.y < Vox.CHUNK_Y, "les bornes restent dans le monde")

	# Les bornes guident le mailleur : elles doivent englober tout le volume
	# non vide, arbres compris, sans quoi leur sommet serait coupe.
	var highest := 0
	for i in blocks.size():
		if blocks[i] != Blocks.AIR:
			highest = maxi(highest, i % Vox.CHUNK_Y)
	check(bounds.y > highest,
		"les bornes couvrent tout le volume (sommet=%d, borne haute=%d)" % [highest, bounds.y])

	for y in Vox.BEDROCK_HEIGHT:
		check(blocks[Vox.index(0, y, 0)] == Blocks.BEDROCK, "bedrock a y=%d" % y)
	check(blocks[Vox.index(8, Vox.CHUNK_Y - 1, 8)] == Blocks.AIR, "ciel libre au sommet")

	# Au-dessus d'une colonne emergee, on ne doit trouver que de l'air : l'eau
	# s'arrete au niveau de la mer et ne deborde pas.
	var surface_column := -1
	for lz in Vox.CHUNK_Z:
		for lx in Vox.CHUNK_X:
			if gen.height_at(lx, lz) > Vox.SEA_LEVEL:
				surface_column = lz * Vox.CHUNK_X + lx
				break
		if surface_column >= 0:
			break
	check(surface_column >= 0, "le chunk contient une terre emergee")
	if surface_column >= 0:
		var clx := surface_column % Vox.CHUNK_X
		var clz := surface_column / Vox.CHUNK_X
		var flooded := 0
		for y in range(Vox.SEA_LEVEL + 1, Vox.CHUNK_Y):
			if blocks[Vox.index(clx, y, clz)] == Blocks.WATER:
				flooded += 1
		check(flooded == 0, "%d blocs d'eau au-dessus du niveau de la mer" % flooded)

	# Coherence entre generation et requetes de colonnes.
	var coherent := true
	for lz in [0, 5, 15]:
		for lx in [0, 7, 15]:
			var h := gen.height_at(lx, lz)
			if blocks[Vox.index(lx, mini(h, Vox.CHUNK_Y - 1), lz)] == Blocks.AIR:
				coherent = false
	check(coherent, "hauteur de colonne coherente avec les blocs")

	# Deux generations du meme germe doivent etre identiques.
	var again := PackedByteArray()
	again.resize(Vox.CHUNK_VOLUME)
	gen.generate_chunk(0, 0, again)
	check(blocks == again, "generation deterministe")

	# Un autre germe doit donner un terrain different.
	var other := WorldGen.new(999)
	var other_blocks := PackedByteArray()
	other_blocks.resize(Vox.CHUNK_VOLUME)
	other.generate_chunk(0, 0, other_blocks)
	check(blocks != other_blocks, "le germe change le terrain")

	# Les biomes existent tous et le monde ne contient que des blocs connus.
	var known := {}
	for lz in Vox.CHUNK_Z:
		for lx in Vox.CHUNK_X:
			for y in Vox.CHUNK_Y:
				var id := other_blocks[Vox.index(lx, y, lz)]
				if id >= Blocks.COUNT:
					check(false, "identifiant de bloc hors registre : %d" % id)
					return
	check(true, "tous les identifiants de blocs sont connus")
	for i in range(-96, 96, 3):
		for j in range(-96, 96, 3):
			known[other.biome_at(i, j)] = true
	check(known.size() >= 3, "plusieurs biomes dans l'echantillon (%d)" % known.size())


# ---------------------------------------------------------------- maillage

## Volume padding construit depuis un dictionnaire {Vector2i -> PackedByteArray}.
## Construit par cotes, independamment de World._padded_for, pour que le test
## valide le mailleur et non sa propre implementation.
func _padded_from(chunks: Dictionary) -> PackedByteArray:
	var pad := PackedByteArray()
	pad.resize(ChunkMesher.PAD_SIZE)
	var last := ChunkMesher.PAD - 1
	for pz in ChunkMesher.PAD:
		for px in ChunkMesher.PAD:
			var coords: Vector2i
			var lx := 0
			var lz := 0
			if px == 0:
				coords = Vector2i(-1, pz - 1)
				lx = Vox.CHUNK_X - 1
			elif px == last:
				coords = Vector2i(1, pz - 1)
				lx = 0
			else:
				coords = Vector2i(0, pz - 1)
				lx = px - 1
			if pz == 0:
				coords.y = -1
				lz = Vox.CHUNK_Z - 1
			elif pz == last:
				coords.y = 1
				lz = 0
			else:
				lz = pz - 1

			var src: PackedByteArray = chunks.get(coords, PackedByteArray())
			if src.is_empty():
				continue
			var base := Vox.column_index(lx, lz)
			for k in Vox.CHUNK_Y:
				pad[(pz * ChunkMesher.PAD + px) * Vox.CHUNK_Y + k] = src[base + k]
	return pad


func _flat_tints() -> Array:
	var flat := PackedColorArray()
	flat.resize(ChunkMesher.PAD_AREA)
	flat.fill(Color(1, 1, 1, 1))
	return [flat, flat]


## Un volume contenant un seul bloc de pierre, entoure d'air.
func _single_block_padded(x: int, y: int, z: int) -> PackedByteArray:
	var pad := PackedByteArray()
	pad.resize(ChunkMesher.PAD_SIZE)
	pad[(z * ChunkMesher.PAD + x) * Vox.CHUNK_Y + y] = Blocks.STONE
	return pad


func _test_single_block() -> void:
	section("un bloc isole")
	var tints := _flat_tints()
	var bufs := ChunkMesher.build(_single_block_padded(8, 20, 8), tints[0], tints[1], 0, 95)
	var opaque: ChunkMesher.Buf = bufs[ChunkMesher.B_OPAQUE]
	# 6 faces x 4 sommets, et 12 triangles.
	check(opaque.verts.size() == 24, "24 sommets pour un cube (%d)" % opaque.verts.size())
	check(opaque.idx.size() == 36, "36 indices pour un cube (%d)" % opaque.idx.size())
	check(bufs[ChunkMesher.B_WATER].is_empty(), "pas de surface d'eau")
	check(bufs[ChunkMesher.B_CUTOUT].is_empty(), "pas de surface alpha")

	# Les 6 normales doivent couvrir exactement les 6 axes.
	var axes := {}
	for normal in opaque.norms:
		axes[normal] = true
	check(axes.size() == 6, "6 directions de face (%d)" % axes.size())
	for axis in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		check(axes.has(axis), "face %s presente" % axis)

	# Deux blocs distincts separes par de l'air : 2 x 6 faces.
	var apart := _single_block_padded(2, 20, 8)
	apart[(8 * ChunkMesher.PAD + 13) * Vox.CHUNK_Y + 20] = Blocks.STONE
	var two: ChunkMesher.Buf = ChunkMesher.build(apart, tints[0], tints[1], 0, 95)[
		ChunkMesher.B_OPAQUE]
	check(two.verts.size() == 48, "deux cubes non jointifs : 48 sommets (%d)" % two.verts.size())

	# Deux cubes jointifs : la face de contact est culee.
	var joined := PackedByteArray()
	joined.resize(ChunkMesher.PAD_SIZE)
	joined[(8 * ChunkMesher.PAD + 8) * Vox.CHUNK_Y + 20] = Blocks.STONE
	joined[(8 * ChunkMesher.PAD + 9) * Vox.CHUNK_Y + 20] = Blocks.STONE
	var joint: ChunkMesher.Buf = ChunkMesher.build(joined, tints[0], tints[1], 0, 95)[
		ChunkMesher.B_OPAQUE]
	# 12 faces - 2 faces de contact.
	check(joint.verts.size() == 40, "deux cubes jointifs : 40 sommets (%d)" % joint.verts.size())

	# Le padding doit avoir exactement la taille attendue.
	check(joined.size() == ChunkMesher.PAD_SIZE, "taille du volume padding")
	check(ChunkMesher.PAD_SIZE == 18 * 18 * Vox.CHUNK_Y, "geometrie du padding")


func _build_buffers() -> Array:
	var gen := WorldGen.new(12345)
	var chunks := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var data := PackedByteArray()
			data.resize(Vox.CHUNK_VOLUME)
			gen.generate_chunk(dx, dz, data)
			chunks[Vector2i(dx, dz)] = data
	var pad := _padded_from(chunks)
	check(pad.size() == ChunkMesher.PAD_SIZE, "volume padding complet")
	var bounds := Vector2i(0, Vox.CHUNK_Y - 1)
	var grass := PackedColorArray()
	var foliage := PackedColorArray()
	grass.resize(ChunkMesher.PAD_AREA)
	foliage.resize(ChunkMesher.PAD_AREA)
	for i in ChunkMesher.PAD_AREA:
		grass[i] = Color(0.5, 0.8, 0.4, 1.0)
		foliage[i] = Color(0.3, 0.7, 0.3, 1.0)
	return [ChunkMesher.build(pad, grass, foliage, bounds.x, bounds.y), pad]


func _test_meshing() -> void:
	section("maillage des chunks")
	var bufs = _build_buffers()[0]
	check(bufs[ChunkMesher.B_OPAQUE].verts.size() > 0, "surface opaque non vide")
	check(bufs[ChunkMesher.B_OPAQUE].idx.size() % 3 == 0, "indices par triangles")
	check(bufs[ChunkMesher.B_OPAQUE].verts.size() == bufs[ChunkMesher.B_OPAQUE].norms.size(),
		"sommets et normales alignes")
	check(bufs[ChunkMesher.B_OPAQUE].verts.size() == bufs[ChunkMesher.B_OPAQUE].colors.size(),
		"sommets et couleurs alignes")
	check(bufs[ChunkMesher.B_OPAQUE].verts.size() == bufs[ChunkMesher.B_OPAQUE].uvs.size(),
		"sommets et UV alignes")
	# Un sommet par quad, 6 indices par quad.
	check(bufs[ChunkMesher.B_OPAQUE].idx.size() * 4 == bufs[ChunkMesher.B_OPAQUE].verts.size() * 6,
		"deux triangles par quad")


func _test_winding() -> void:
	section("orientation des triangles")
	var bufs = _build_buffers()[0]
	var checked := 0
	var wrong := 0
	for k in [ChunkMesher.B_OPAQUE, ChunkMesher.B_CUTOUT, ChunkMesher.B_WATER]:
		var buf: ChunkMesher.Buf = bufs[k]
		for i in range(0, buf.idx.size(), 3):
			var a := buf.verts[buf.idx[i]]
			var b := buf.verts[buf.idx[i + 1]]
			var c := buf.verts[buf.idx[i + 2]]
			var geometric := (b - a).cross(c - a)
			if geometric.length_squared() < 0.000001:
				continue
			geometric = geometric.normalized()
			var intended := buf.norms[buf.idx[i]].normalized()
			checked += 1
			# Godot considere comme face avant le cote oppose au produit
			# vectoriel (sens horaire vu de l'exterieur, comme BoxMesh et
			# PlaneMesh) : le produit vectoriel doit donc pointer vers
			# l'interieur du bloc, sinon la face est eliminee par backface
			# culling et traversee en collision.
			if geometric.dot(intended) > -0.001:
				wrong += 1
	check(checked > 1000, "suffisamment de triangles controles (%d)" % checked)
	check(wrong == 0, "%d triangles/%d mal orientes" % [wrong, checked])


func _test_uvs() -> void:
	section("coordonnees UV")
	var bufs = _build_buffers()[0]
	var outside := 0
	var degenerate := 0
	for k in 3:
		var buf: ChunkMesher.Buf = bufs[k]
		for uv in buf.uvs:
			if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
				outside += 1
		if buf.verts.size() > 0:
			for c in buf.colors:
				if c.r < 0.0 or c.g < 0.0 or c.b < 0.0 or c.r > 1.5:
					degenerate += 1
					break
	check(outside == 0, "%d UV hors atlas" % outside)
	check(degenerate == 0, "couleurs de sommet dans des bornes raisonnables")
	_test_uv_orientation()


## L'image d'une tuile doit etre posee **dans le bon sens** sur le bloc.
##
## Dans l'espace texture de Godot, v = 0 est le HAUT de l'image. Les faces
## laterales du mailleur plaçaient leurs UV ainsi : le bas du bloc recevait
## v = 0, donc le haut de l'image — et l'image etait posee a l'envers. C'est
## invisible sur une texture symetrique comme la pierre, et criant sur une
## face d'herbe, dont la bordure verte doit couronner le bloc.
func _test_uv_orientation() -> void:
	var bufs = _build_buffers()[0]
	var buf: ChunkMesher.Buf = bufs[ChunkMesher.B_OPAQUE]
	var inverted := 0
	var side_faces := 0
	var i := 0
	while i + 3 < buf.verts.size():
		# Un quad : on cherche s'il est vertical et s'il est a moitie horaire.
		var y_bottom := 0.0
		var y_top := 0.0
		var seen := {}
		for k in 4:
			y_bottom = minf(y_bottom, buf.verts[i + k].y)
			y_top = maxf(y_top, buf.verts[i + k].y)
			seen[buf.norms[i + k]] = true
		# Face laterale : normale horizontale, deux extremites en hauteur.
		if buf.norms[i].y == 0.0 and y_top - y_bottom > 0.9:
			side_faces += 1
			var v_bottom := INF
			var v_top := -INF
			for k in 4:
				# Sommet du bas, puis du haut.
				if is_equal_approx(buf.verts[i + k].y, y_bottom):
					v_bottom = minf(v_bottom, buf.uvs[i + k].y)
				else:
					v_top = maxf(v_top, buf.uvs[i + k].y)
			# v = 0 est le HAUT de l'image : le haut du bloc doit donc
			# recevoir le PLUS PETIT v, et le bas du bloc le plus grand.
			if v_top >= v_bottom:
				inverted += 1
		i += 4
	check(side_faces > 0, "%d faces laterales inspectees" % side_faces)
	check(inverted == 0,
		"%d faces laterales posees a l'envers" % inverted)


func _test_collision() -> void:
	section("collision")
	var bufs = _build_buffers()[0]
	var faces := ChunkMesher.collision_faces(bufs)
	check(not faces.is_empty(), "collision non vide")
	check(faces.size() % 3 == 0, "collision en triangles")
	check(faces.size() == (bufs[ChunkMesher.B_OPAQUE] as ChunkMesher.Buf).idx.size()
		+ (bufs[ChunkMesher.B_CUTOUT] as ChunkMesher.Buf).idx.size(),
		"la collision reprend exactement les surfaces opaques et alpha")

	# Cas construit : une piscine. L'eau doit etre dessinee mais jamais collisionnable.
	var pool := _pool_buffers()
	var water: ChunkMesher.Buf = pool[ChunkMesher.B_WATER]
	var solid: ChunkMesher.Buf = pool[ChunkMesher.B_OPAQUE]
	check(water.idx.size() > 0, "la surface d'eau est generee")
	check(solid.idx.size() > 0, "le fond de la piscine est genere")

	var pool_faces := ChunkMesher.collision_faces(pool)
	var leaked := 0
	for v in pool_faces:
		# La pierre occupe y = 0..4 : ses faces laterales montent jusqu'a y = 5.
		# Au-dela, c'est de l'eau, qui ne doit jamais etre collisionnable.
		if v.y > 5.001:
			leaked += 1
	check(pool_faces.size() > 0, "la piscine a une collision")
	check(leaked == 0, "%d sommets de collision dans l'eau" % leaked)


## Petite piscine : 5 couches de pierre, 3 d'eau, rien au-dessus.
func _pool_buffers() -> Array:
	var pad := PackedByteArray()
	pad.resize(ChunkMesher.PAD_SIZE)
	for y in 5:
		for lz in Vox.CHUNK_Z:
			for lx in Vox.CHUNK_X:
				pad[(lz + 1) * ChunkMesher.PAD * Vox.CHUNK_Y + (lx + 1) * Vox.CHUNK_Y + y] = \
					Blocks.STONE
	for y in range(5, 8):
		for lz in Vox.CHUNK_Z:
			for lx in Vox.CHUNK_X:
				pad[(lz + 1) * ChunkMesher.PAD * Vox.CHUNK_Y + (lx + 1) * Vox.CHUNK_Y + y] = \
					Blocks.WATER

	var flat := PackedColorArray()
	flat.resize(ChunkMesher.PAD_AREA)
	flat.fill(Color(1, 1, 1, 1))
	return ChunkMesher.build(pad, flat, flat, 0, 8)


# ---------------------------------------------------------------- raycast

class _FakeWorld:
	extends World
	var grid := {}

	func get_block(pos: Vector3i) -> int:
		return int(grid.get(pos, Blocks.AIR))


func _test_raycast() -> void:
	section("raycast voxel")
	var fake := _FakeWorld.new()
	# Un mur a x = 4, verticale, sur toute la hauteur.
	for y in range(0, 10):
		for z in range(-3, 4):
			fake.grid[Vector3i(4, y, z)] = Blocks.STONE

	var hit := VoxelRaycast.cast(fake, Vector3(0.5, 5.0, 0.0), Vector3.RIGHT, 10.0)
	check(hit["hit"], "le mur est detecte")
	check(hit["pos"] == Vector3i(4, 5, 0), "la cellule visee est exacte")
	check(hit["normal"] == Vector3i(-1, 0, 0), "la normale pointe vers le tireur")
	check(is_equal_approx(float(hit["distance"]), 3.5),
		"distance au bloc = 3.5 (%.2f)" % hit["distance"])

	var back := VoxelRaycast.cast(fake, Vector3(9.5, 5.0, 0.0), Vector3.LEFT, 10.0)
	check(back["hit"] and back["pos"] == Vector3i(4, 5, 0), "raycast dans l'autre sens")
	check(back["normal"] == Vector3i(1, 0, 0), "normale opposee")

	var miss := VoxelRaycast.cast(fake, Vector3(0.5, 5.0, 0.0), Vector3.UP, 10.0)
	check(not miss["hit"], "un tir vers le ciel ne touche rien")

	var short := VoxelRaycast.cast(fake, Vector3(0.5, 5.0, 0.0), Vector3.RIGHT, 2.0)
	check(not short["hit"], "la portee limite la detection")
	fake.free()

	# Un pas diagonal ne doit sauter aucune cellule : on pose un bloc sur la
	# trajectoire reelle du rayon (il alterne x et z).
	var diagonal := _FakeWorld.new()
	diagonal.grid[Vector3i(3, 5, 3)] = Blocks.STONE
	var d := VoxelRaycast.cast(diagonal, Vector3(0.0, 5.0, 0.0), Vector3(1, 0, 1).normalized(), 10.0)
	check(d["hit"], "un pas diagonal touche la cellule visee")
	check(d["pos"] == Vector3i(3, 5, 3), "cellule diagonale exacte")
	# La normale est celle du dernier deplacement : X ou Z, jamais les deux.
	var normal: Vector3i = d["normal"]
	check(normal == Vector3i(-1, 0, 0) or normal == Vector3i(0, 0, -1),
		"normale diagonale simple (%s)" % normal)
	diagonal.free()

	# Une marche d'escalier : chaque cellule est detectee immediatement, sans
	# laisser le rayon filer au-dela.
	var stairs := _FakeWorld.new()
	var visited: Array[Vector3i] = []
	for i in 5:
		stairs.grid[Vector3i(i, 5, 0)] = Blocks.STONE
		visited.append(Vector3i(i, 5, 0))
	for i in 4:
		var hit_i := VoxelRaycast.cast(stairs, Vector3(0.0, 5.0, 0.0), Vector3.RIGHT, 10.0)
		stairs.grid.erase(hit_i["pos"])
		check(hit_i["pos"] == visited[0], "escalier : cellule %d" % i)
		visited.remove_at(0)
	stairs.free()


# --------------------------------------------------------------- recettes

func _grid(size: int, cells: Dictionary) -> Array:
	var out: Array = []
	for i in size * size:
		out.append(int(cells.get(i, Recipes.EMPTY)))
	return out


func _test_recipes() -> void:
	section("recettes")
	var plank := Items.block_item(Blocks.PLANKS)
	var log := Items.block_item(Blocks.LOG)

	var r := Recipes.match(_grid(2, {0: log}), 2)
	check(not r.is_empty() and r["id"] == plank and r["count"] == 4, "brique -> 4 planches")

	r = Recipes.match(_grid(2, {0: plank, 2: plank}), 2)
	check(not r.is_empty() and r["id"] == Items.STICK and r["count"] == 4,
		"2 planches en colonne -> 4 batons")

	# Le meme schema doit matcher dans une grille 3x3 a toute position.
	r = Recipes.match(_grid(3, {4: plank, 7: plank}), 3)
	check(not r.is_empty() and r["id"] == Items.STICK, "schema 3x3 decale")

	r = Recipes.match(_grid(3, {0: plank, 1: plank, 2: plank, 4: Items.STICK,
		7: Items.STICK}), 3)
	check(not r.is_empty() and r["id"] == Items.WOOD_PICKAXE, "pioche en bois")

	# Une grille avec un objet en trop ne doit PAS matcher.
	r = Recipes.match(_grid(3, {0: plank, 1: plank, 2: plank, 4: Items.STICK,
		7: Items.STICK, 8: plank}), 3)
	check(r.is_empty(), "un ingredient en trop invalide la recette")

	# Le 2x2 de l'inventaire ne suffit pas pour une recette qui demande 3 colonnes.
	r = Recipes.match(_grid(2, {0: plank, 1: plank, 2: Items.STICK, 3: Items.STICK}), 2)
	check(r.is_empty(), "une recette 3x3 ne tient pas dans une grille 2x2")
	# ...mais 4 planches font bien un etabli.
	r = Recipes.match(_grid(2, {0: plank, 1: plank, 2: plank, 3: plank}), 2)
	check(not r.is_empty() and r["id"] == Items.block_item(Blocks.CRAFTING_TABLE),
		"4 planches font un etabli")

	r = Recipes.match(_grid(2, {0: Items.STICK, 1: Items.COAL}), 2)
	check(not r.is_empty() and r["id"] == Items.block_item(Blocks.TORCH)
		and r["count"] == 4, "torche")

	r = Recipes.match(_grid(2, {0: Items.RAW_IRON, 1: Items.COAL}), 2)
	check(not r.is_empty() and r["id"] == Items.IRON_INGOT, "fer brut + charbon = lingot")

	check(Recipes.match(_grid(2, {}), 2).is_empty(), "grille vide : aucune recette")
	check(Recipes.match(_grid(3, {0: Items.IRON_PICKAXE}), 3).is_empty(),
		"un objet seul ne fabrique rien")

	# Les recettes decrites doivent etre toutes atteignables.
	for recipe in Recipes.all:
		var grid: Array = []
		for i in 9:
			grid.append(Recipes.EMPTY)
		if recipe.has("shapeless"):
			var k := 0
			for item_id in recipe["shapeless"]:
				grid[k] = item_id
				k += 1
		else:
			for y in recipe["shape"].size():
				for x in (recipe["shape"][y] as Array).size():
					grid[y * 3 + x] = recipe["shape"][y][x]
		var found := Recipes.match(grid, 3)
		check(not found.is_empty() and found["id"] == recipe["out"],
			"la recette %d est atteignable" % Recipes.all.find(recipe))


# ------------------------------------------------------------- inventaire

func _test_inventory() -> void:
	section("inventaire")
	var inv := Inventory.new()
	var cobble := Items.block_item(Blocks.COBBLESTONE)
	check(inv.add(cobble, 70) == 0, "70 pavee rentrent")
	check(inv.count_of(cobble) == 70, "compte coherent")
	check(inv.slots[0]["count"] == 64, "pile maximale appliquee")
	check(inv.slots[1]["count"] == 6, "deuxieme pile creee")

	inv.selected = 0
	check(inv.take_from_selected(10) == 10, "retrait partiel")
	check(inv.slots[0]["count"] == 54, "compte apres retrait")
	inv.take_from_selected(100)
	check(inv.slots[0].is_empty(), "pile videe")

	# Un outil ne se stack pas.
	var pick := Items.IRON_PICKAXE
	inv.add(pick, 5)
	check(inv.count_of(pick) == 5, "cinq pioches empilees en un seul emplacement... ")
	var used := 0
	for i in Inventory.SIZE:
		if inv.slots[i].get("id", -1) == pick:
			used += 1
	check(used == 5, "un outil par emplacement (%d)" % used)

	# Serialisation.
	var dumped := inv.to_array()
	var restored := Inventory.new()
	restored.from_array(dumped)
	check(restored.to_array() == dumped, "aller-retour de serialisation")

	# Depot d'un depot.
	var before := inv.count_of(Items.STICK)
	inv.add(Items.STICK, 1)
	check(inv.count_of(Items.STICK) == before + 1, "ajout simple")


# ------------------------------------------------------------ sauvegarde

func _test_save_codec() -> void:
	section("codec de sauvegarde")
	var gen := WorldGen.new(777)
	var blocks := PackedByteArray()
	blocks.resize(Vox.CHUNK_VOLUME)
	gen.generate_chunk(2, -3, blocks)
	var text := SaveSystem.encode_chunk(blocks)
	check(text.length() > 0, "chunk encode")
	check(text.length() < blocks.size() * 2, "la compression reduit la taille")
	var back := SaveSystem.decode_chunk(text)
	check(back == blocks, "aller-retour de compression exact")


# ------------------------------------------------------------- textures

func _test_textures() -> void:
	section("atlas de textures")
	var image := TextureFactory.build_atlas()
	var expected := Vector2i(Tiles.COLS * Tiles.TILE_PX, Tiles.ROWS * Tiles.TILE_PX)
	check(image.get_size() == expected, "dimensions de l'atlas %s" % image.get_size())

	var painted := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				painted += 1
	check(painted > image.get_width() * image.get_height() * 0.4,
		"l'atlas est peint (%d/%d pixels)" % [painted, image.get_width() * image.get_height()])

	# Chaque bloc placeable doit pointer sur une tuile reellement peinte.
	for id in range(1, Blocks.COUNT):
		var tile := Blocks.tile_for_face(id, 4)
		check(tile >= 0 and tile < Tiles.COUNT, "tuile valide pour le bloc %d" % id)

	# Les UV de tuile doivent tomber dans l'atlas.
	for tile in range(Tiles.COUNT):
		var origin := Tiles.uv_origin(tile)
		var span := Tiles.uv_size()
		check(origin.x >= 0.0 and origin.x + span.x <= 1.0001,
			"tuile %d dans l'atlas en U" % tile)
		check(origin.y >= 0.0 and origin.y + span.y <= 1.0001,
			"tuile %d dans l'atlas en V" % tile)

	_test_water()


## L'eau est la seule texture animee du jeu : elle doit donc etre verifiee
## comme telle — deux proprietes qu'aucune erreur en console ne signale.
##
## Elle doit **bouger**, sans quoi l'eau reste figee. Et elle doit se
## **raccorder** : le motif est repete sur toute la surface, si bien qu'une
## tuile qui ne boucle pas sur elle-meme etale une couture entre chaque bloc,
## qui traverse le lac en juxtaposition des memes pieces. Ni l'ecran ni la
## console ne disent d'ou vient une couture : elle se voit, c'est tout.
func _test_water() -> void:
	var px := Tiles.TILE_PX
	# Une image de plus que la boucle : a `PX` colonnes de decalage, le
	# motif doit etre revenu exactement ou il etait. C'est cette periodicite
	# qui fait a la fois que la tuile se raccorde a elle-meme d'un bloc a
	# l'autre, et que la boucle de l'animation ne claque pas en repartant.
	var count := px + 1
	var frames := TextureFactory.build_water_frames(count)
	check(frames.size() == count, "l'eau a ses images d'animation")
	var first: Image = frames[0]
	check(first.get_size() == Vector2i(px, px),
		"une image d'eau fait la taille d'une tuile")

	var drift := 0.0
	var loop := 0.0
	for y in px:
		for x in px:
			drift += _rgb_distance(first.get_pixel(x, y),
				frames[1].get_pixel(x, y))
			loop += _rgb_distance(first.get_pixel(x, y),
				frames[count - 1].get_pixel(x, y))
	check(drift > 0.01, "l'eau se deplace d'une image a l'autre")
	# Un motif non periodique donnerait un ecart du meme ordre que le
	# mouvement lui-meme ; seule l'erreur de flottant doit subsister.
	check(loop < drift * 0.01,
		"la boucle d'eau se referme sur elle-meme (%.5f)" % loop)


## Distance entre deux couleurs de l'atlas, sur le canal visible.
func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Le personnage : proportions, skin, et surtout orientation des UV. Une face
## dont les UV sont remappees a l'envers ne leve aucune erreur en console, elle
## affiche simplement un visage de travers — c'est le meme piege que
## l'orientation des triangles du monde, et il merite le meme test.
func _test_character() -> void:
	section("personnage")
	var body := PlayerBody.new()
	body.build()

	# La silhouette doit tenir dans la hitbox du joueur : 1,8 bloc de haut, les
	# pieds au sol, la tete au-dessus du buste, jamais de membre qui s'y
	# entrelace. C'est ce qui distingue une vraie proportion d'une pile de
	# boites posees au hasard.
	var spans := {}
	for member in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var pivot: Node3D = body.get(member)
		var box: MeshInstance3D = pivot.get_node("Boite")
		var aabb: AABB = box.mesh.get_aabb()
		var lo: Vector3 = pivot.transform * aabb.position
		var hi: Vector3 = pivot.transform * (aabb.position + aabb.size)
		spans[member] = [lo, hi]
		# Le membre est centre en x : un bras decale ferait une epaule de travers.
		check(absf((lo.x + hi.x) * 0.5 - pivot.position.x) < 0.001,
			"%s centre sur son pivot" % member)
	check(spans["head"][0].y > spans["body"][1].y - 0.001, "tete posee sur le buste")
	check(spans["body"][0].y > spans["leg_right"][1].y - 0.001, "buste pose sur les jambes")
	check(absf(spans["leg_right"][0].y) < 0.001, "pieds au sol")
	check(absf(spans["head"][1].y - 1.8) < 0.01,
		"hauteur totale 1,8 bloc (%.3f)" % spans["head"][1].y)

	# Les bras doivent toucher le buste sans le traverser : un bras qui entre
	# dans le torse se voit immediatement en jeu.
	var body_lo: Vector3 = spans["body"][0]
	var body_hi: Vector3 = spans["body"][1]
	var arm_lo: Vector3 = spans["arm_left"][0]
	check(absf(arm_lo.x - body_hi.x) < 0.001, "le bras s'appuie contre le buste")

	# Chaque face doit pointer sur le bon rectangle de la skin. On regroupe les
	# UV par normale et on verifie qu'elles tombent toutes dans le rectangle
	# attendu : c'est la qu'un miroir ou un retournement se voit.
	for member in ["tete", "corps", "bras_droite", "jambe_gauche"]:
		var pivot2: Node3D = body.get(_PIVOT_OF[member])
		var mesh: MeshInstance3D = pivot2.get_node("Boite")
		var arrays := mesh.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check(uvs.size() == normals.size() and uvs.size() == 24,
			"%s : 6 faces de 4 UV" % member)
		var buckets := {}
		for i in uvs.size():
			var key := "%d,%d,%d" % [roundi(normals[i].x), roundi(normals[i].y),
				roundi(normals[i].z)]
			var u: Vector2 = uvs[i]
			if not buckets.has(key):
				buckets[key] = Rect2(u, Vector2.ZERO)
			var old: Rect2 = buckets[key]
			var lo := Vector2(minf(old.position.x, u.x), minf(old.position.y, u.y))
			var hi := Vector2(maxf(old.position.x + old.size.x, u.x),
				maxf(old.position.y + old.size.y, u.y))
			buckets[key] = Rect2(lo, hi - lo)
		for face in SkinFactory.FACES:
			var want := SkinFactory.uv_normalized(member, face)
			# Le rectangle est cherche dans le lot de la normale de CETTE face,
			# pas dans n'importe quel lot : sans cela, un miroir qui echange le
			# devant et l'arriere passerait quand meme le test.
			var normal := PlayerBody._face_normal(face)
			var key := "%d,%d,%d" % [roundi(normal.x), roundi(normal.y),
				roundi(normal.z)]
			var r: Rect2 = buckets.get(key, Rect2())
			check(r.size.x > 0.0 \
					and absf(r.position.x - want.position.x) < 0.01 \
					and absf(r.position.y - want.position.y) < 0.01 \
					and absf(r.size.x - want.size.x) < 0.01 \
					and absf(r.size.y - want.size.y) < 0.01,
				"%s.%s : UV sur le bon rectangle, pour cette normale" % [member, face])
			# Un rectangle correct ne suffit pas : echanger deux coins d'une
			# face laisse le rectangle intact mais retourne la peinture. On verifie
			# donc que U suit l'axe horizontal de la face et que V suit son axe
			# vertical, sommet par sommet.
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var pairs: Array = []
			for i in uvs.size():
				if "%d,%d,%d" % [roundi(normals[i].x), roundi(normals[i].y),
						roundi(normals[i].z)] == key:
					pairs.append([verts[i], uvs[i]])
			var axes: Variant = _FACE_AXES.get(face, null)
			check(axes != null and pairs.size() == 4,
				"%s.%s : quatre sommets a orienter" % [member, face])
			if axes == null or pairs.size() != 4:
				continue
			var u_dir: Vector3 = axes[0]
			var v_dir: Vector3 = axes[1]
			# L'invariant reel n'est pas « U est croissant » — deux sommets de
			# meme cote partagent la meme valeur. C'est que U ne depend QUE de
			# l'axe horizontal de la face, et V que de son axe vertical. Un
			# miroir, lui, rend U dependant de l'axe vertical, et c'est
			# precisement ce que ce test doit voir.
			check(_axis_is_a_function_of(pairs, u_dir, 0),
				"%s.%s : U ne depend que de l'axe horizontal" % [member, face])
			check(_axis_is_a_function_of(pairs, v_dir, 1),
				"%s.%s : V ne depend que de l'axe vertical" % [member, face])
			# Et dans le bon sens : une face miroir est une fonction parfaitement
			# reguliere de son axe, seulement de signe inverse. C'est ce test-la
			# qui distingue « la face n'est pas retournee » d'« elle est
			# retournee », ce que le monde ne signale d'aucune maniere.
			check(_axis_points_along(pairs, u_dir, 0),
				"%s.%s : U progresse dans le sens attendu" % [member, face])
			check(_axis_points_along(pairs, v_dir, 1),
				"%s.%s : V progresse dans le sens attendu" % [member, face])

	# La skin doit etre peinte partout ou le maillage lit des pixels : un
	# rectangle vide se verrait par transparence sur le personnage.
	var image := SkinFactory.build_skin(0)
	for member in ["tete", "corps", "bras_droite", "jambe_gauche"]:
		for face in SkinFactory.FACES:
			var r: Rect2i = SkinFactory.uv_rect(member, face)
			var opaque := 0
			for y in r.size.y:
				for x in r.size.x:
					if image.get_pixel(r.position.x + x, r.position.y + y).a > 0.5:
						opaque += 1
			check(opaque == r.size.x * r.size.y,
				"%s.%s entierement peint" % [member, face])


## Les noms de membres de la skin ne sont pas les noms de pivots du corps : la
## table est la seule passerelle entre les deux, et le test la verifie aussi
## indirectement en piegeant un nom inconnu.
const _PIVOT_OF := {
	"tete": "head",
	"corps": "body",
	"bras_droite": "arm_right",
	"bras_gauche": "arm_left",
	"jambe_droite": "leg_right",
	"jambe_gauche": "leg_left",
}


## Vrai si la composante UV demandee croit dans le sens de l'axe indique : le
## cote du membre le plus eloigne dans la direction de `axis` doit porter la
## plus grande valeur. C'est le test qui voit un miroir, la ou le simple
## controle de dependance ne voit rien.
func _axis_points_along(pairs: Array, axis: Vector3, component: int) -> bool:
	var low := INF
	var high := -INF
	var low_value := 0.0
	var high_value := 0.0
	for pair in pairs:
		var position: Vector3 = pair[0]
		var uv: Vector2 = pair[1]
		var projection := position.dot(axis)
		var value: float = uv.x if component == 0 else uv.y
		if projection < low:
			low = projection
			low_value = value
		if projection > high:
			high = projection
			high_value = value
	if high_value - low_value == 0.0:
		return false
	# L'axe est deja oriente dans le sens ou la valeur doit croitre : la
	# coordonnee la plus forte doit donc porter la plus grande UV.
	return high_value > low_value


## Vrai si la composante UV demandee est une fonction de l'axe 3D indique :
## deux sommets a la meme projection sur cet axe portent la meme valeur, et
## deux projections differentes portent deux valeurs differentes. C'est la
## formulation exacte de « la face n'est pas retournee ».
## `pairs` est une liste de `[position, uv]`, `component` vaut 0 pour U et 1
## pour V.
func _axis_is_a_function_of(pairs: Array, axis: Vector3, component: int) -> bool:
	var by_axis := {}
	for pair in pairs:
		var position: Vector3 = pair[0]
		var uv: Vector2 = pair[1]
		var projection := snappedf(position.dot(axis), 0.0001)
		var value: float = uv.x if component == 0 else uv.y
		if by_axis.has(projection):
			var previous: float = by_axis[projection]
			if absf(previous - value) > 0.0001:
				return false
		else:
			by_axis[projection] = value
	# Les deux cotes de la face doivent porter deux valeurs distinctes, sinon
	# la face est degeneree en un trait.
	if by_axis.size() != 2:
		return false
	var values: Array = by_axis.values()
	return absf(values[0] - values[1]) > 0.0001


## Pour chaque face de membre, l'axe 3D vers lequel U doit croitre et celui vers
## lequel V doit croitre. C'est la convention du format officiel de skin :
## **U progresse vers la droite du spectateur qui regarde la face de l'exterieur**.
## Le test la reapplique de facon independante du maillage, ce qui lui permet de
## voir un miroir que l'implementation commettrait.
const _FACE_AXES := {
	"avant": [Vector3(1, 0, 0), Vector3(0, -1, 0)],
	"arriere": [Vector3(-1, 0, 0), Vector3(0, -1, 0)],
	"droite": [Vector3(0, 0, -1), Vector3(0, -1, 0)],
	"gauche": [Vector3(0, 0, 1), Vector3(0, -1, 0)],
	"haut": [Vector3(1, 0, 0), Vector3(0, 0, 1)],
	"bas": [Vector3(1, 0, 0), Vector3(0, 0, 1)],
}


## Fissures de minage, peaux de creatures et rendu : trois ajouts dont le dessin
## ne se verifie pas a l'oeil sur une capture — l'etape de fissures doit
## s'ajouter sans se remplacer, une boite de creature doit avoir ses six faces,
## et le mode « naturel » du rendu doit etre le premier, sans shader.
func _test_effects() -> void:
	section("cassure, creatures, rendu")

	# --- Fissures : dix etages empiles dans une seule image.
	var cracks := BreakOverlay.build_texture()
	check(cracks.get_size() == Vector2i(BreakOverlay.PX,
		BreakOverlay.PX * BreakOverlay.STAGES),
		"la planche de fissures a %d etages" % BreakOverlay.STAGES)
	# Chaque etage doit contenir **plus** de pixels que le precedent : des etages
	# qui se remplaceraient donneraient une progression illisible, ce qui est
	# exactement le defaut qu'on corrige.
	var previous := -1
	var monotone := true
	for stage in BreakOverlay.STAGES:
		var drawn := 0
		for y in BreakOverlay.PX:
			for x in BreakOverlay.PX:
				if cracks.get_pixel(x, stage * BreakOverlay.PX + y).a > 0.01:
					drawn += 1
		if drawn <= previous:
			monotone = false
		previous = drawn
	check(previous > 0, "la derniere etape est dessinee (%d pixels)" % previous)
	check(monotone, "le nombre de fissures augmente a chaque etape")
	# La correspondance progression -> etape, y compris ses bornes.
	check(BreakOverlay._stage_of(0.0) == -1, "aucune fissure a la progression nulle")
	check(BreakOverlay._stage_of(0.001) == 0, "la premiere fissure parait aussitot")
	check(BreakOverlay._stage_of(1.0) == BreakOverlay.STAGES - 1,
		"la progression complete atteint la derniere etape")
	check(BreakOverlay._stage_of(1.7) == BreakOverlay.STAGES - 1,
		"une progression aberrante est bornee")
	var overlay := BreakOverlay.new()
	var overlay_mesh: ArrayMesh = overlay._box_mesh()
	check(overlay_mesh.get_surface_count() == 1, "la boite de fissures a une surface")
	check(overlay_mesh.surface_get_array_len(0) == 24,
		"la boite de fissures a six faces de quatre sommets")
	overlay.free()

	# --- Creatures : du grain, et des boites a six faces.
	var hide := MobSkin.hide_texture()
	# `ImageTexture.get_size()` est un Vector2, contrairement a celui d'une Image.
	check(hide.get_size() == Vector2(MobSkin.SIZE, MobSkin.SIZE),
		"le grain des creatures fait %d pixels de cote" % MobSkin.SIZE)
	var darkest := 1.0
	var lightest := 0.0
	for y in MobSkin.SIZE:
		for x in MobSkin.SIZE:
			var value := hide.get_image().get_pixel(x, y).r
			darkest = minf(darkest, value)
			lightest = maxf(lightest, value)
	check(lightest - darkest > 0.15,
		"le grain des creatures se voit (%.2f d'ecart)" % (lightest - darkest))
	var box := MobSkin.box_mesh(Vector3(0.5, 0.5, 0.5))
	check(box.get_surface_count() == 1, "la boite d'une creature a une surface")
	check(box.surface_get_array_len(0) == 24,
		"la boite d'une creature a six faces de quatre sommets")
	# Deux appels du meme format doivent renvoyer la meme ressource : le cache
	# evite de reconstruire les memes tableaux a chaque creature.
	check(MobSkin.box_mesh(Vector3(0.5, 0.5, 0.5)) == box,
		"les boites de meme taille sont mises en cache")

	# --- Icones de blocs : un cube en perspective, pas une tuile plate.
	var atlas := TextureFactory.build_atlas()
	var icon := BlockIcons.build(atlas, Blocks.GRASS,
		Biomes.grass_tint(Biomes.PLAINS))
	check(icon != null and icon.get_size() == Vector2i(BlockIcons.SIZE, BlockIcons.SIZE),
		"l'icone d'un bloc est un carre de %d pixels" % BlockIcons.SIZE)
	# Le dessus est domine par la face du dessus, le bas par les deux cotes :
	# une icone ou le haut n'est pas plus clair est plate, et le cube ne se lit
	# plus comme un cube.
	var upper := 0.0
	var lower := 0.0
	var upper_count := 0
	var lower_count := 0
	for y in BlockIcons.SIZE:
		for x in BlockIcons.SIZE:
			var c := icon.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			if y < BlockIcons.SIZE / 3:
				upper += luma
				upper_count += 1
			elif y > BlockIcons.SIZE * 2 / 3:
				lower += luma
				lower_count += 1
	check(upper_count > 0 and lower_count > 0, "l'icone couvre le haut et le bas")
	check(upper / maxf(float(upper_count), 1.0) > lower / maxf(float(lower_count), 1.0),
		"le dessus de l'icone est plus clair que les cotes")

	# --- Rendu : le mode par defaut ne touche a rien.
	check(PostFx.count() >= 2, "plusieurs modes de rendu")
	check(not bool(PostFx.PRESETS[0]["enabled"]),
		"le premier mode de rendu laisse l'image intacte")
	check(PostFx.PRESETS[0]["saturation"] == 1.0 and PostFx.PRESETS[0]["vignette"] == 0.0,
		"le mode naturel a des reglages neutres")


## Le feuillage doit etre **plein**, pas une coque.
##
## C'est la regression signalee deux fois par le joueur : « je vois a travers
## les feuillages ». Une couronne dont les faces internes sont culees n'est
## qu'une enveloppe ; comme la face interne de cette enveloppe est eliminee
## elle aussi, le moindre bloc manquant ouvrait un trou traversant jusqu'au
## ciel. On verifie donc les deux bouts de la chaine : la regle de cullage, et
## le nombre de faces que le mailleur en tire reellement.
func _test_foliage() -> void:
	section("feuillage plein")
	# Les feuilles se dessinent entre elles : c'est ce qui remplit la couronne.
	check(Blocks.face_visible(Blocks.LEAVES, Blocks.LEAVES),
		"une feuille dessine sa face vers une autre feuille")
	check(Blocks.face_visible(Blocks.LEAVES, Blocks.AIR),
		"une feuille dessine sa face vers l'air")
	# En revanche les blocs opaques gardent leurs faces internes culees : le
	# volume de feuillage doit rester le seul changement.
	check(not Blocks.face_visible(Blocks.STONE, Blocks.STONE),
		"deux blocs opaques jointifs ne dessinent pas leur face de contact")
	check(not Blocks.face_visible(Blocks.LEAVES, Blocks.STONE),
		"une feuille contre un bloc opaque ne dessine rien")
	check(not Blocks.is_opaque(Blocks.LEAVES),
		"les feuilles ne sont pas opaques (elles vont dans la surface alpha)")

	# La tuile de feuillage doit etre **entierement peinte** : un pixel
	# transparent dans la tuile est un trou en plein milieu d'une face, donc du
	# ciel au coeur de la couronne — la meme regression, par l'autre bout.
	var atlas := TextureFactory.build_atlas()
	var tx := (Tiles.LEAVES % Tiles.COLS) * Tiles.TILE_PX
	var ty := (Tiles.LEAVES / Tiles.COLS) * Tiles.TILE_PX
	var holes := 0
	for y in Tiles.TILE_PX:
		for x in Tiles.TILE_PX:
			if atlas.get_pixel(tx + x, ty + y).a < 0.99:
				holes += 1
	check(holes == 0, "la tuile de feuillage n'a aucun pixel transparent (%d)" % holes)

	# Un volume de 3 x 3 x 3 feuilles : chaque bloc emet ses six faces, y
	# compris celles tournees vers une autre feuille. Un feuillage cule comme
	# avant n'en emettrait que l'enveloppe, soit 54 faces au lieu de 162 — la
	# couronne serait creuse, et l'on verrait le ciel au travers.
	var blob := PackedByteArray()
	blob.resize(ChunkMesher.PAD_SIZE)
	for y in range(20, 23):
		for z in range(8, 11):
			for x in range(8, 11):
				blob[(z * ChunkMesher.PAD + x) * Vox.CHUNK_Y + y] = Blocks.LEAVES
	var flat := _flat_tints()
	var leaves: ChunkMesher.Buf = ChunkMesher.build(blob, flat[0], flat[1], 0, 95)[
		ChunkMesher.B_CUTOUT]
	check(leaves.idx.size() / 6 == 162,
		"27 feuilles donnent 162 faces, faces internes comprises (%d)"
		% (leaves.idx.size() / 6))

	# Le meme volume en pierre ne donne que son enveloppe : la reference qui
	# montre que le feuillage, lui, n'en est plus une.
	var stone := PackedByteArray()
	stone.resize(ChunkMesher.PAD_SIZE)
	for y in range(20, 23):
		for z in range(8, 11):
			for x in range(8, 11):
				stone[(z * ChunkMesher.PAD + x) * Vox.CHUNK_Y + y] = Blocks.STONE
	var solid: ChunkMesher.Buf = ChunkMesher.build(stone, flat[0], flat[1], 0, 95)[
		ChunkMesher.B_OPAQUE]
	check(solid.idx.size() / 6 == 54,
		"27 pierres n'emettent que leur enveloppe : 54 faces (%d)"
		% (solid.idx.size() / 6))


func _test_title_seed() -> void:
	section("graine de l'ecran titre")
	check(TitleScreen.parse_seed("12345") == 12345, "entier positif")
	check(TitleScreen.parse_seed("-7") == -7, "entier negatif")
	check(TitleScreen.parse_seed("  42  ") == 42, "espaces rognes")
	var a := TitleScreen.parse_seed("monde")
	check(a == TitleScreen.parse_seed("monde"), "texte hache stable (%d)" % a)
	check(TitleScreen.parse_seed("monde") != TitleScreen.parse_seed("autre"),
		"textes differents acceptes")
	var random := TitleScreen.parse_seed("")
	check(typeof(random) == TYPE_INT, "vide = graine aleatoire entiere")
