class_name BlockIcons
extends RefCounted

## Icones isometriques des blocs, pour l'inventaire et la barre rapide.
##
## Jusqu'ici un bloc range dans l'inventaire affichait sa **tuile plate** : un
## carre de 16 pixels, ou l'herbe et la pierre se ressemblaient, et ou la face
## du dessus d'un bloc de terre n'existait pas. Minecraft montre un cube en
## perspective : trois faces visibles, la face du dessus la plus claire, les
## deux cotes plus sombres. C'est ce que ce fichier construit, sans le moindre
## fichier image — comme le reste du jeu.
##
## L'icone est un carre de `SIZE` pixels. Chaque face visible est un
## parallelogramme decrit par une origine et deux vecteurs d'arete ; on le
## remplit par **projection inverse** : pour chaque pixel de l'icone, on resout
## (u, v) dans la base des deux aretes, et on echantillonne la tuile. Une
## projection directe laisserait des trous la ou deux pixels voisins tombent sur
## le meme texel.

## Cote de l'icone. Un emplacement de `Slot` fait 42 pixels, moins 5 de marge de
## chaque cote : l'icone tombe donc exactement a l'echelle, sans etirement.
const SIZE := 32

## Cote d'une tuile de l'atlas.
const TILE := 16

## Vecteurs de projection, en pixels d'icone. La face du dessus se parcourt par
## (+X, +Z), les deux cotes par (X ou Z, -Y) et +Y.
const AXIS_X := Vector2(14.0, 7.0)
const AXIS_Z := Vector2(-14.0, 7.0)
const AXIS_Y := Vector2(0.0, 14.0)

## Luminosite de chaque face. Le dessus recoit le plus de ciel, la face +X est
## de profil, la face +Z tourne le dos a la lumiere : sans cet ecart, les trois
## faces se lisent comme un aplat et le cube parait plat.
const SHADE_TOP := 1.0
const SHADE_X := 0.78
const SHADE_Z := 0.62


## L'icone d'un bloc, ou null si le bloc n'a pas de tuile exploitable.
##
## `atlas` est l'image complete des tuiles ; `tint` la teinte de biome a
## appliquer (l'herbe et le feuillage sont gris-vert dans l'atlas et prennent
## leur couleur aux sommets du maillage — une icone sans teinte montrerait une
## herbe grise, introuvable dans le jeu).
static func build(atlas: Image, block_id: int, tint: Color) -> Image:
	if atlas == null or block_id <= 0:
		return null
	var top_tile := Blocks.tile_for_face(block_id, 2)
	var x_tile := Blocks.tile_for_face(block_id, 0)
	var z_tile := Blocks.tile_for_face(block_id, 4)
	if top_tile < 0 or x_tile < 0 or z_tile < 0:
		return null

	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# La face du dessus : son coin superieur est le sommet du cube, sur l'axe
	# vertical du milieu ; elle s'etend par +X vers la droite et +Z vers la
	# gauche, donc vers le bas des deux cotes.
	var apex := Vector2(float(SIZE) * 0.5, 2.0)
	_face(img, atlas, top_tile, apex, AXIS_X, AXIS_Z, SHADE_TOP, tint)
	# Les deux cotes pendent sous le coin bas du dessus, a la verticale.
	#
	# Leurs aretes horizontales sont l'**oppose** d'un des deux axes du dessus,
	# pas l'axe lui-meme : depuis le coin commun `seam`, la face +X repart vers
	# -Z et la face +Z vers -X. Prendre l'axe dans le mauvais sens ne se voit pas
	# sur l'icone — elle reste un cube — mais les deux cotes partent de travers
	# et le fond du cube se decale d'une rangee de pixels.
	var seam := apex + AXIS_X + AXIS_Z
	_face(img, atlas, x_tile, seam, -AXIS_Z, AXIS_Y, SHADE_X, tint)
	_face(img, atlas, z_tile, seam, -AXIS_X, AXIS_Y, SHADE_Z, tint)
	# Un liseret sombre sur le contour : l'icone se detache du creux gris de
	# l'emplacement, ou un carre vert pale se perdait.
	_outline(img)
	return img


## Remplit un parallelogramme : `origin + u * edge_u + v * edge_v`, pour u et v
## dans [0, 1[. `shade` assombrit la face, `tint` colore l'echantillon.
static func _face(img: Image, atlas: Image, tile: int, origin: Vector2,
		edge_u: Vector2, edge_v: Vector2, shade: float, tint: Color) -> void:
	var det := edge_u.x * edge_v.y - edge_u.y * edge_v.x
	if absf(det) < 0.00001:
		return
	var ox := (tile % Tiles.COLS) * TILE
	var oy := (tile / Tiles.COLS) * TILE
	# Bornes du parallelogramme : inutile de balayer toute l'icone trois fois.
	var min_x := maxi(0, int(floor(minf(minf(origin.x, origin.x + edge_u.x),
		minf(origin.x + edge_v.x, origin.x + edge_u.x + edge_v.x)))))
	var max_x := mini(SIZE - 1, int(ceil(maxf(maxf(origin.x, origin.x + edge_u.x),
		maxf(origin.x + edge_v.x, origin.x + edge_u.x + edge_v.x)))))
	var min_y := maxi(0, int(floor(minf(minf(origin.y, origin.y + edge_u.y),
		minf(origin.y + edge_v.y, origin.y + edge_u.y + edge_v.y)))))
	var max_y := mini(SIZE - 1, int(ceil(maxf(maxf(origin.y, origin.y + edge_u.y),
		maxf(origin.y + edge_v.y, origin.y + edge_u.y + edge_v.y)))))
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var d := Vector2(float(px) + 0.5, float(py) + 0.5) - origin
			var u := (d.x * edge_v.y - d.y * edge_v.x) / det
			var v := (edge_u.x * d.y - edge_u.y * d.x) / det
			if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
				continue
			var source := atlas.get_pixel(
				ox + clampi(int(u * float(TILE)), 0, TILE - 1),
				oy + clampi(int(v * float(TILE)), 0, TILE - 1))
			img.set_pixel(px, py, Color(
				clampf(source.r * tint.r * shade, 0.0, 1.0),
				clampf(source.g * tint.g * shade, 0.0, 1.0),
				clampf(source.b * tint.b * shade, 0.0, 1.0),
				1.0))


## Assombrit d'un cran les pixels qui touchent le vide : c'est le contour de
## l'icone. Il se fait apres coup, sur les pixels deja peints, pour ne pas
## dependre de l'ordre des faces.
static func _outline(img: Image) -> void:
	var marked: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if img.get_pixel(x, y).a < 0.5:
				continue
			if not _is_filled(img, x - 1, y) or not _is_filled(img, x + 1, y) \
					or not _is_filled(img, x, y - 1) or not _is_filled(img, x, y + 1):
				marked.append(Vector2i(x, y))
	for at in marked:
		var c := img.get_pixel(at.x, at.y)
		img.set_pixel(at.x, at.y, Color(c.r * 0.62, c.g * 0.62, c.b * 0.62, 1.0))


static func _is_filled(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return false
	return img.get_pixel(x, y).a >= 0.5
