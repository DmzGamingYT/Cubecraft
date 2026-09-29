extends Node

## Autoload `Atlas`.
##
## Fabrique au demarrage l'unique texture du jeu (l'atlas pixel-art genere par
## TextureFactory), les trois materiaux de chunk, et les icones d'objets
## recoupees dans cet atlas, puis les publie dans `Assets` pour que le reste du
## code y accede sans dependre de l'autoload.
##
## L'eau est la seule matiere animee : elle a sa propre texture, decalee
## image par image, plutot que de partager l'atlas.

## Nombre d'images de la surface de l'eau. Seize, comme le nombre de pixels
## d'une tuile : une image par pixel de decalage, donc une boucle dont le
## raccord est exact.
const WATER_FRAMES := 16
## Images par seconde. Douze suffit : l'eau doit lente, et chaque changement
## ne represente que 256 pixels.
const WATER_FPS := 12.0

var _water_frames: Array[Image] = []
var _water_texture: ImageTexture = null
var _water_clock := 0.0
var _water_frame := 0

func _ready() -> void:
	var image := TextureFactory.build_atlas()
	image.generate_mipmaps()
	Assets.atlas = ImageTexture.create_from_image(image)

	for tile in range(Tiles.COUNT):
		var region := Rect2i(
			(tile % Tiles.COLS) * Tiles.TILE_PX,
			(tile / Tiles.COLS) * Tiles.TILE_PX,
			Tiles.TILE_PX, Tiles.TILE_PX)
		Assets.tile_images[tile] = ImageTexture.create_from_image(image.get_region(region))

	Assets.materials[ChunkMesher.B_OPAQUE] = _make_opaque()
	# L'eau a sa propre texture, plutot qu'une tuile de l'atlas : c'est la
	# seule qui bouge, et la repinter ne coute qu'un kilo-octet par image.
	_water_frames = TextureFactory.build_water_frames(WATER_FRAMES)
	_water_texture = ImageTexture.create_from_image(_water_frames[0])
	Assets.materials[ChunkMesher.B_WATER] = _make_water()
	Assets.materials[ChunkMesher.B_CUTOUT] = _make_cutout()

	# Un materiau par bloc, pour les objets au sol et les particules.
	for block_id in range(1, Blocks.COUNT):
		Assets.block_materials[block_id] = _make_block_material(block_id)

	# Les icones isometriques des blocs, a partir de la meme image d'atlas : les
	# emplacements de l'inventaire montrent donc exactement la matiere du monde.
	# Les blocs en croix (la torche) sont laisses de cote : un cube de torche
	# serait un mensonge, sa tuile plate dit mieux ce qu'on tient.
	for block_id in range(1, Blocks.COUNT):
		if Blocks.shape_of(block_id) != Blocks.Shape.CUBE:
			continue
		if Blocks.is_liquid(block_id):
			continue
		var tint := _icon_tint(block_id)
		var icon := BlockIcons.build(image, block_id, tint)
		if icon != null:
			Assets.block_icons[block_id] = ImageTexture.create_from_image(icon)

	for item_id in Items.all():
		# L'icone du pack CC0 passe en premier : elle est dessinee en 64 px, donc
		# plus nette que la tuile 16 px etoiliee dans un emplacement de 42. Un
		# objet sans icone dans le pack garde celle de l'atlas.
		var external := ExternalTiles.item_icon(item_id)
		Assets.item_icons[item_id] = external if external != null \
			else Assets.tile_images[Items.icon_tile(item_id)]

	Assets.is_ready = true


## Teinte d'une icone de bloc. L'herbe et le feuillage de l'atlas sont gris-vert
## et prennent leur couleur aux sommets du maillage : sans cette teinte, l'icone
## montrerait un gazon gris qui n'existe nulle part dans le jeu. On prend celle
## du biome de plaine, le plus courant.
func _icon_tint(block_id: int) -> Color:
	match Blocks.tint_of(block_id):
		"grass":
			return Biomes.grass_tint(Biomes.PLAINS)
		"leaves":
			return Biomes.foliage_tint(Biomes.PLAINS)
		_:
			return Color(1, 1, 1)


## L'eau coule : une image par `1 / WATER_FPS` seconde. Le rendu n'a pas a
## savoir que la surface bouge — seule la texture change, et les faces deja
## maillées echantillonnent la nouvelle sans etre rejetees.
func _process(delta: float) -> void:
	if _water_texture == null or _water_frames.size() < 2:
		return
	_water_clock += delta
	var step := 1.0 / WATER_FPS
	if _water_clock < step:
		return
	_water_clock -= step
	_water_frame = (_water_frame + 1) % _water_frames.size()
	_water_texture.update(_water_frames[_water_frame])


func _make_opaque() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.atlas
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _make_water() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _water_texture
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Pas de `uv1_scale` ici : le maillage donne deja a l'eau des UV locales,
	# parce que sa texture n'est pas celle de l'atlas. Le materiau se contente
	# de la poser.
	# On traverse l'eau de face comme de dos, mais les blocs derriere restent
	# visibles : c'est le role du canal alpha, pas du tri de transparence.
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.roughness = 0.08
	m.rim = 0.25
	m.rim_tint = 0.1
	return m


func _make_cutout() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.atlas
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Alpha scissor plutot que blend : pas de tri de transparence, et les
	# trous du feuillage restent nets au lieu d'être baves.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	# Faces arriere eliminees. Les blocs en croix (torches) restent visibles
	# des deux cotes parce que le maillage leur dessine une face dans chaque
	# sens — et non pas en desactivant l'elimination, comme avant : cela
	# empilait aussi les faces **internes** du feuillage, et une couronne
	# d'arbres se lisait alors comme un empilement de grands quads verts
	# troues, vus de l'interieur.
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.roughness = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## Petit materiau d'un bloc seul : l'atlas n'est alors echantillonne que sur la
## tuile de ce bloc.
func _make_block_material(block_id: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.atlas
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var origin := Tiles.uv_origin(Blocks.tile_for_face(block_id, 4))
	var span := Tiles.uv_size()
	m.uv1_offset = Vector3(origin.x, origin.y, 0.0)
	m.uv1_scale = Vector3(span.x, span.y, 1.0)
	return m
