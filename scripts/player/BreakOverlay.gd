class_name BreakOverlay
extends MeshInstance3D

## Fissures du bloc en cours de minage.
##
## Sans elles, casser un bloc ne se voyait qu'au contour qui change de teinte et
## a la barre du reticule : le bloc vise restait intact jusqu'a disparaitre d'un
## coup. C'est exactement ce que fait Minecraft autrement, en affichant le bloc
## qui se fend par etapes.
##
## Le dessin est une **unique** texture de `STAGES` etages de 16x16, et changer
## d'etape ne fait que deplacer `uv1_offset` : aucune image n'est construite en
## cours de partie, aucun noeud n'est recree. Un cube legerement plus grand que
## le bloc porte cette texture, faces avant tournees vers l'exterieur ; ses faces
## arriere sont dans le bloc et echouent au test de profondeur, donc seule la
## face que le joueur regarde se fissure — le meme tour que le contour de visee.
##
## La texture est batie une fois pour toutes et mise en cache : deux mines
## simultanees, ou deux joueurs en reseau, ne la recalculent pas.

## Nombre d'etapes de fissuration. Dix, comme Minecraft : assez pour que la
## progression se lise, assez peu pour que la texture tienne en 16x160 pixels.
const STAGES := 10
const PX := 16

## Demi-epaisseur du surplus de la boite, en blocs. Sans elle, les faces du
## cube de fissures seraient exactement coplanaire avec celles du bloc et
## clignoteraient au test de profondeur (z-fighting).
const LIFT := 0.002

const CRACK_COLOR := Color(0.05, 0.05, 0.06)

static var _shared_texture: ImageTexture = null

var _material: StandardMaterial3D
var _stage := -1


## Construit la boite et son materiau. Appele par `_ready`, et directement par
## les scripts de diagnostic qui instancient ce noeud hors d'un arbre monte.
func build() -> void:
	if _material != null:
		return
	mesh = _box_mesh()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_texture = texture()
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_material.uv1_scale = Vector3(1.0, 1.0 / float(STAGES), 1.0)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# La boite de fissures ne doit jamais heriter du lacet du joueur : sans
	# cela elle pivoterait autour du coin du bloc au lieu de rester posee dessus.
	top_level = true
	visible = false


func _ready() -> void:
	build()


## Les fissures sont-elles affichees ?
func is_active() -> bool:
	return visible


## Pose les fissures sur le bloc `pos` (coin inferieur du bloc, comme le
## contour de visee) et sur l'etape deduite de `ratio`, de 0 a 1.
func set_mining(pos: Vector3i, ratio: float) -> void:
	global_position = Vector3(pos)
	visible = true
	set_stage(_stage_of(ratio))


func clear() -> void:
	visible = false
	_stage = -1
	# L'etage doit repartir de zero, et pas seulement le drapeau : sans cela,
	# `set_mining` sur une progression nulle — que `set_stage` refuse comme un
	# doublon — laisserait les fissures de la cassure precedente a l'ecran.
	if _material != null:
		_material.uv1_offset = Vector3.ZERO


## Etape de fissuration d'une progression donnee. Fonction pure : c'est elle
## que verifie le test de fumee, l'affichage lui-meme ne se testant pas.
static func _stage_of(ratio: float) -> int:
	if ratio <= 0.0:
		return -1
	return clampi(int(floor(ratio * float(STAGES))), 0, STAGES - 1)


func set_stage(stage: int) -> void:
	if stage == _stage or _material == null:
		return
	_stage = stage
	_material.uv1_offset = Vector3(0.0, float(stage) / float(STAGES), 0.0)


# ---------------------------------------------------------------- texture

## La texture des fissures, construite et mise en cache au premier usage.
static func texture() -> ImageTexture:
	if _shared_texture == null:
		_shared_texture = ImageTexture.create_from_image(build_texture())
	return _shared_texture


## Les `STAGES` etages de fissures, empiles verticalement dans une seule image.
##
## Chaque etage contient les fissures des etages precedents, plus une : elles
## s'ajoutent sans jamais se remplacer, ce qui est la seule facon de lire une
## progression. Elles partent toutes du centre et s'en ecartent en zigzaguant,
## comme les etoiles de fissures de Minecraft, plutot que d'etre semees au
## hasard — un semis uniforme se lit comme du bruit, pas comme une cassure.
static func build_texture() -> Image:
	var img := Image.create(PX, PX * STAGES, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	# Graine fixe : les fissures sont identiques d'une partie a l'autre, comme
	# le reste des textures du jeu.
	r.seed = 0x5EED0F
	var cracks: Array[PackedVector2Array] = []
	var center := Vector2(float(PX) * 0.5 - 0.5, float(PX) * 0.5 - 0.5)
	for i in STAGES:
		var points := PackedVector2Array()
		# Chaque fissure part d'un point voisin du centre, et non du centre
		# exactement : dix traits partant tous du meme pixel se superposaient en
		# une tache sombre au milieu du bloc, qu'on lisait comme une salissure.
		var angle := r.randf() * TAU
		var at := center + Vector2(cos(angle), sin(angle)) * r.randf_range(0.6, 2.2)
		var steps := 5 + i
		for _step in steps:
			points.append(at)
			angle += r.randf_range(-0.6, 0.6)
			at += Vector2(cos(angle), sin(angle)) * r.randf_range(1.4, 2.4)
			at.x = clampf(at.x, 0.0, float(PX - 1))
			at.y = clampf(at.y, 0.0, float(PX - 1))
		cracks.append(points)

	var row := PackedVector2Array()
	for stage in STAGES:
		row.clear()
		# L'opacite monte avec l'etape : une derniere fissure doit etre plus
		# franche que la premiere, sinon une progression avancee se lit comme
		# une progression naissante.
		var alpha := clampf(0.34 + 0.052 * float(stage), 0.0, 0.92)
		for index in stage + 1:
			row.append_array(cracks[index])
		for i in row.size() - 1:
			_stroke(img, stage, row[i], row[i + 1], alpha)
	return img


## Trace un segment dans un etage de l'image, en marchant par demi-pixels :
## sans ce pas, une diagonale 1:1 saute un pixel sur deux a l'ecran.
static func _stroke(img: Image, stage: int, from: Vector2, to: Vector2,
		alpha: float) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(ceil(length * 2.0)))
	for i in steps + 1:
		var p := from.lerp(to, float(i) / float(steps))
		var x := clampi(int(round(p.x)), 0, PX - 1)
		var y := clampi(int(round(p.y)), 0, PX - 1)
		img.set_pixel(x, stage * PX + y, Color(CRACK_COLOR.r, CRACK_COLOR.g,
			CRACK_COLOR.b, alpha))


# ------------------------------------------------------------------- maillage

## La boite des fissures : six faces de 1 bloc, gonflees de `LIFT` vers
## l'exterieur pour passer devant le bloc sans clignoter.
##
## Les triangles sont ecrits dans le sens trigonometrique vu de l'exterieur,
## comme tout le reste du projet : inverse, la boite disparait sans le moindre
## message dans la console.
func _box_mesh() -> ArrayMesh:
	var lo := -LIFT
	var hi := 1.0 + LIFT
	# Coin bas-gauche et etendue de chaque face, avec l'axe de sa normale.
	var faces := [
		{"normal": Vector3(0, 0, 1), "a": Vector3(lo, lo, hi), "b": Vector3(hi, lo, hi),
			"c": Vector3(hi, hi, hi), "d": Vector3(lo, hi, hi)},
		{"normal": Vector3(0, 0, -1), "a": Vector3(hi, lo, lo), "b": Vector3(lo, lo, lo),
			"c": Vector3(lo, hi, lo), "d": Vector3(hi, hi, lo)},
		{"normal": Vector3(1, 0, 0), "a": Vector3(hi, lo, hi), "b": Vector3(hi, lo, lo),
			"c": Vector3(hi, hi, lo), "d": Vector3(hi, hi, hi)},
		{"normal": Vector3(-1, 0, 0), "a": Vector3(lo, lo, lo), "b": Vector3(lo, lo, hi),
			"c": Vector3(lo, hi, hi), "d": Vector3(lo, hi, lo)},
		{"normal": Vector3(0, 1, 0), "a": Vector3(lo, hi, lo), "b": Vector3(hi, hi, lo),
			"c": Vector3(hi, hi, hi), "d": Vector3(lo, hi, hi)},
		{"normal": Vector3(0, -1, 0), "a": Vector3(lo, lo, hi), "b": Vector3(hi, lo, hi),
			"c": Vector3(hi, lo, lo), "d": Vector3(lo, lo, lo)},
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in faces:
		var base := vertices.size()
		var corners := [face["a"], face["b"], face["c"], face["d"]]
		var face_uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in 4:
			vertices.push_back(corners[i])
			normals.push_back(face["normal"])
			uvs.push_back(face_uvs[i])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
