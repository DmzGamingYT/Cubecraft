class_name ChunkMesher
extends RefCounted

## Genere la geometrie d'un chunk a partir de ses donnees de blocs.
##
## Le mailleur travaille sur un volume *padding* de 18 x 96 x 18 range en colonnes :
## index = (pz * 18 + px) * 96 + py. Le chunk central occupe px/pz 1..16, sa
## bordure exterieure 0 et 17. Ce layout est choisi pour que la colonne de 96
## octets d'un voisin soit contiguë des deux cotes : le remplissage du padding
## se fait alors par `append_array` (memcpy) au lieu de 300 000 copies unitaires.
## Comme x/z valent 1..16, tous les voisins de bordure sont des index valides :
## aucune comparaison de bornes dans la boucle chaude, seul l'axe Y estpecial.
##
## Chaque face utile produit un quad avec occlusion ambiante calculee a partir
## des trois voisins diagonaux (algorithme classique a 4 niveaux). L'eclairement
## de face et la couleur de biome voyagent dans les attributs de sommet, que le
## materiau multiplie a l'albedo.

const PAD := 18
const PAD_AREA := PAD * PAD
const PAD_SIZE := PAD * PAD * Vox.CHUNK_Y

## Decalage d'index pour +X/-X, +Y/-Y, +Z/-Z dans le volume padding.
const AXIS_STEP := [Vox.CHUNK_Y, 1, PAD * Vox.CHUNK_Y]

## Ordre des faces : +X -X +Y -Y +Z -Z
const FACE_DELTA := [Vox.CHUNK_Y, -Vox.CHUNK_Y, 1, -1, PAD * Vox.CHUNK_Y, -PAD * Vox.CHUNK_Y]

## Marge appliquee aux UV pour eviter que le filtrage ne preleve dans la tuile
## voisine (0.5 texel d'une tuile de 16 px).
const UV_INSET := 0.5 / float(Tiles.TILE_PX)

## Indice de tampon : 0 = opaque, 1 = eau, 2 = alpha (feuillage, torches).
const B_OPAQUE := 0
const B_WATER := 1
const B_CUTOUT := 2

const IDX_BELOW := -1
const IDX_ABOVE := -2


static var FACES: Array = _make_faces()


static func _make_faces() -> Array:
	# Coins dans le sens trigonometrique vu de l'exterieur, et UV associes
	# (v = 0 en haut, comme dans l'espace texture de Godot). L'ordre
	# d'emission des triangles est inverse par Buf.quad pour obtenir des
	# faces avant cote exterieur (sens horaire vu de dehors).
	return [
		{
			"n": Vector3i(1, 0, 0), "axis": 0,
			"c": [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
			"uv": [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)],
		},
		{
			"n": Vector3i(-1, 0, 0), "axis": 0,
			"c": [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
			"uv": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
		},
		{
			"n": Vector3i(0, 1, 0), "axis": 1,
			"c": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
			"uv": [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)],
		},
		{
			"n": Vector3i(0, -1, 0), "axis": 1,
			"c": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
			"uv": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
		},
		{
			"n": Vector3i(0, 0, 1), "axis": 2,
			"c": [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
			"uv": [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)],
		},
		{
			"n": Vector3i(0, 0, -1), "axis": 2,
			"c": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
			"uv": [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)],
		},
	]


## Tampon de sommets accumulant une surface.
class Buf:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	func is_empty() -> bool:
		return idx.is_empty()

	## Ajoute un quad. `p` = 4 positions, `c` = 4 couleurs, `t` = 4 UV (locales).
	## Godot considere comme face avant le cote ou le produit vectoriel pointe
	## en sens oppose : les sommets doivent donc apparaitre dans le sens
	## horaire vu de l'exterieur (produit vectoriel vers l'interieur du bloc).
	## C'est verifie contre BoxMesh et PlaneMesh, et contre les rayons
	## physiques : l'ordre (0,2,1)/(0,3,2) rend le sol visible du dessus et
	## collisionnable par le dessus. L'ordre inverse rend le terrain invisible
	## de dehors et traversable en tombant.
	func quad(p: Array, n: Vector3, c: Array, t: Array) -> void:
		var base := verts.size()
		for i in 4:
			verts.append(p[i])
			norms.append(n)
			colors.append(c[i])
			uvs.append(t[i])
		idx.append(base)
		idx.append(base + 2)
		idx.append(base + 1)
		idx.append(base)
		idx.append(base + 3)
		idx.append(base + 2)


## Construit les trois tampons de sommets d'un chunk.
##
## `padded`  : volume 18 x 96 x 18 (index = px + pz * 18 + py * 324)
## `grass` / `foliage` : teintes de biome, une couleur par colonne du padding
## `min_y` / `max_y` : bornes du volume non vide, pour sauter le ciel
static func build(padded: PackedByteArray, grass: PackedColorArray,
		foliage: PackedColorArray, min_y: int, max_y: int) -> Array:
	var bufs: Array = [Buf.new(), Buf.new(), Buf.new()]
	var size := padded.size()

	var y0: int = maxi(0, min_y)
	var y1: int = mini(Vox.CHUNK_Y - 1, max_y)

	for y in range(y0, y1 + 1):
		for z in Vox.CHUNK_Z:
			var pz := z + 1
			for x in Vox.CHUNK_X:
				var i := (pz * PAD + x + 1) * Vox.CHUNK_Y + y
				var bid := padded[i]
				if bid == Blocks.AIR:
					continue

				var shape := Blocks.shape_of(bid)
				var column := x + 1 + (z + 1) * PAD

				if shape == Blocks.Shape.CROSS:
					_emit_cross(bufs[B_CUTOUT], bid, Vector3(x, y, z))
					continue

				var bucket := B_OPAQUE
				if shape == Blocks.Shape.LIQUID:
					bucket = B_WATER
				elif not Blocks.is_opaque(bid):
					bucket = B_CUTOUT

				var buf: Buf = bufs[bucket]
				var tint := _tint_for(bid, grass, foliage, column)

				for f in 6:
					var d: int = FACE_DELTA[f]
					var ni := i + d
					# Hors monde : sous la bedrock = plein, au-dessus = ciel ouvert.
					var nb: int = Blocks.STONE if ni < 0 else (
						Blocks.AIR if ni >= size else padded[ni])
					if not Blocks.face_visible(bid, nb):
						continue
					_emit_face(buf, bid, f, Vector3(x, y, z), tint, padded, size, ni)

	return bufs


static func _tint_for(bid: int, grass: PackedColorArray, foliage: PackedColorArray,
		column: int) -> Color:
	var kind := Blocks.tint_of(bid)
	if kind == "":
		return Color.WHITE
	var source: PackedColorArray = foliage if kind == "leaves" else grass
	return source[column]


## Echantillonnage d'occlusion avec gestion des bornes verticale du monde.
static func _occludes_at(padded: PackedByteArray, size: int, idx: int) -> bool:
	if idx < 0:
		return true  # sous la bedrock : plein
	if idx >= size:
		return false  # au-dessus du monde : ciel ouvert
	return Blocks.occludes(padded[idx])


static func _emit_face(buf: Buf, bid: int, face: int, base: Vector3, tint: Color,
		padded: PackedByteArray, size: int, ni: int) -> void:
	var spec: Dictionary = FACES[face]
	var corners: Array = spec["c"]
	var local_uv: Array = spec["uv"]
	var normal: Vector3 = spec["n"]
	var axis: int = spec["axis"]
	var t1 := (axis + 1) % 3
	var t2 := (axis + 2) % 3
	var s1_step: int = AXIS_STEP[t1]
	var s2_step: int = AXIS_STEP[t2]

	var tile := Blocks.tile_for_face(bid, face)
	var origin := Tiles.uv_origin(tile)
	var span := Tiles.uv_size()
	var lo_x := UV_INSET * span.x
	var hi_x := span.x - UV_INSET * span.x
	var lo_y := UV_INSET * span.y
	var hi_y := span.y - UV_INSET * span.y
	var shade: float = Vox.FACE_SHADE[face]

	var positions: Array = []
	var colors: Array = []
	var uvs: Array = []

	for k in 4:
		var corner: Vector3 = corners[k]
		# Direction d'occlusion : -1 si le coin est a 0 sur l'axe, +1 s'il vaut 1.
		var d1: int = int(corner[t1]) * 2 - 1
		var d2: int = int(corner[t2]) * 2 - 1
		var i1 := ni + d1 * s1_step
		var i2 := ni + d2 * s2_step
		var ic := i1 + d2 * s2_step

		var o1 := _occludes_at(padded, size, i1)
		var o2 := _occludes_at(padded, size, i2)
		var oc := _occludes_at(padded, size, ic)

		# Deux voisins lateraux pleine masse : angle completement masque.
		var ao := 0
		if not (o1 and o2):
			ao = 3 - (int(o1) + int(o2) + int(oc))

		positions.append(base + corner)
		colors.append(Color(tint.r, tint.g, tint.b, 1.0) * shade * Vox.AO_LEVELS[ao])

		var luv: Vector2 = local_uv[k]
		# Sur les faces laterales, l'axe v est la **hauteur** du bloc, alors
		# que v = 0 est le haut de l'image dans l'espace texture de Godot. Sans
		# inversion, l'image etait posee a l'envers : l'herbe d'une face de cote
		# descendait en bas du bloc au lieu de le couronner. Les faces du
		# dessus et du dessous n'ont pas ce probleme — leur v suit z, pas y.
		if axis != 1:
			luv.y = 1.0 - luv.y
		var uv: Vector2
		if bid == Blocks.WATER:
			# L'eau n'echantillonne pas l'atlas : sa texture est animee, et
			# elle lui est propre. Ses UV sont donc **locales**, et le materiau
			# d'eau les pose telles quelles. Passer par `uv1_scale` et
			# `uv1_offset` aurait marche aussi, mais l'ordre de composition des
			# deux ne se deduit pas du code : le mailler dit ici exactement ce
			# qu'il fait.
			uv = Vector2(lerpf(UV_INSET, 1.0 - UV_INSET, luv.x),
				lerpf(UV_INSET, 1.0 - UV_INSET, luv.y))
		else:
			# L'UV verticale a sa propre taille : l'atlas n'est pas carre.
			uv = origin + Vector2(lerpf(lo_x, hi_x, luv.x), lerpf(lo_y, hi_y, luv.y))
		uvs.append(uv)

	buf.quad(positions, normal, colors, uvs)


static func _emit_cross(buf: Buf, bid: int, base: Vector3) -> void:
	# Deux quads croises, dessines dans les deux sens.
	var def := Blocks.def(bid)
	var inset: float = def.get("cross_inset", 0.0)
	var height: float = def.get("cross_height", 1.0)
	var lo: float = inset
	var hi: float = 1.0 - inset
	var top: float = height

	var tile := Blocks.tile_for_face(bid, 0)
	var origin := Tiles.uv_origin(tile)
	var span := Tiles.uv_size()
	var u0 := origin.x + UV_INSET * span.x
	var u1 := origin.x + span.x - UV_INSET * span.x
	var v0 := origin.y + UV_INSET * span.y
	var v1 := origin.y + span.y - UV_INSET * span.y
	var white := Color(1, 1, 1, 1)
	var positions: Array
	var colors: Array
	var uvs: Array

	# Chaque diagonale est emise deux fois, en sens opposes : la torche reste
	# ainsi visible des deux cotes **sans** desactiver l'elimination des faces
	# arriere, qui vaut aussi pour le feuillage de la meme surface.
	#
	# Diagonale 1 : (lo, 0, lo) -> (hi, 0, hi) -> (hi, top, hi) -> (lo, top, lo)
	positions = [
		base + Vector3(lo, 0.0, lo), base + Vector3(hi, 0.0, hi),
		base + Vector3(hi, top, hi), base + Vector3(lo, top, lo),
	]
	uvs = [Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]
	colors = [white, white, white, white]
	var normal := Vector3(-0.6, 0.0, -0.6).normalized()
	buf.quad(positions, normal, colors, uvs)
	_emit_back(buf, positions, -normal, colors, uvs)

	# Diagonale 2 : (hi, 0, lo) -> (lo, 0, hi) -> (lo, top, hi) -> (hi, top, lo)
	positions = [
		base + Vector3(hi, 0.0, lo), base + Vector3(lo, 0.0, hi),
		base + Vector3(lo, top, hi), base + Vector3(hi, top, lo),
	]
	normal = Vector3(0.6, 0.0, 0.6).normalized()
	buf.quad(positions, normal, colors, uvs)
	_emit_back(buf, positions, -normal, colors, uvs)


## Le meme quad, vu de l'autre cote : coins dans l'ordre inverse et normale
## opposee, ce qui suffit a retourner les triangles.
static func _emit_back(buf: Buf, p: Array, n: Vector3, c: Array, t: Array) -> void:
	buf.quad([p[3], p[2], p[1], p[0]], n, [c[3], c[2], c[1], c[0]],
		[t[3], t[2], t[1], t[0]])


## Assembler un ArrayMesh a partir des tampons. Renvoie le mesh et la liste des
## types de tampon effectivement presents (dans l'ordre des surfaces).
static func to_mesh(bufs: Array) -> Dictionary:
	var mesh := ArrayMesh.new()
	var kinds: Array = []
	for k in 3:
		var buf: Buf = bufs[k]
		if buf.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = buf.verts
		arrays[Mesh.ARRAY_NORMAL] = buf.norms
		arrays[Mesh.ARRAY_COLOR] = buf.colors
		arrays[Mesh.ARRAY_TEX_UV] = buf.uvs
		arrays[Mesh.ARRAY_INDEX] = buf.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		kinds.append(k)
	return {"mesh": mesh, "kinds": kinds}


## Triangle list pour la collision, reprise des memes tampons et du meme ordre de
## ventilation que le rendu : la collision ne peut donc pas diverger du visuel.
## L'eau en est exclue (on la traverse).
static func collision_faces(bufs: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in [B_OPAQUE, B_CUTOUT]:
		var buf: Buf = bufs[k]
		var v := buf.verts
		var idx := buf.idx
		for i in range(0, idx.size(), 3):
			out.append(v[idx[i]])
			out.append(v[idx[i + 1]])
			out.append(v[idx[i + 2]])
	return out
