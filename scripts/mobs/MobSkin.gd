class_name MobSkin
extends RefCounted

## Peaux pixel-art des creatures, peintes par code comme le reste du jeu.
##
## Jusqu'ici un cochon et un zombie etaient des boites `BoxMesh` a `albedo_color`
## plat : de la matiere PVC. Aucune erreur en console, mais une creature sans
## aucun grain se lit comme un meuble, et c'est exactement ce qu'on voyait sur
## une capture.
##
## La texture est un **grain** neutre de 16x16 — donc un bloc du monde a
## l'echelle du jeu — pose sur des UV qui valent la taille de la face en blocs.
## Un texel de creature fait donc exactement un texel de terrain : les deux
## tiennent dans la meme image, et un cochon cesse d'etre plus fin ou plus gros
## que le sol qu'il foule.
##
## Le grain est volontairement proche du blanc (0,74 a 1,0) : il **assombrit**
## legerement la teinte de la creature au lieu de la remplacer. Les couleurs de
## `Mob` restent donc celles que decrivent ses commentaires, et la variation est
## du grain, pas une seconde palette.

const SIZE := 16

## Boites deja construites, indexees par leur taille. Un cochon en aligne une
## douzaine et le jeu en porte une dizaine : sans ce cache, chaque creature
## reecrirait les memes tableaux de sommets.
static var _meshes: Dictionary = {}
static var _texture: ImageTexture = null


## La texture de grain, construite une seule fois.
static func hide_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = int(hash("cubecraft:mobhide"))
	for y in SIZE:
		for x in SIZE:
			# Deux echelles de grain : un bruit fin pixel a pixel, et des
			# taches plus marquees qui donnent le poil. Une seule echelle se
			# lit comme du bruit numerique, et un ecart trop faible — 14 %
			# essayes d'abord — ne se voyait pas du tout sur une creature vue
			# de loin : le grain doit se lire a quatre blocs.
			var value := r.randf_range(0.76, 1.0)
			if r.randf() < 0.22:
				value -= 0.10
			img.set_pixel(x, y, Color(value, value, value, 1.0))
	# Quelques taches de quatre pixels, pour casser la regularite du grain.
	for i in 4:
		var cx := r.randi_range(0, SIZE - 2)
		var cy := r.randi_range(0, SIZE - 2)
		for dy in 2:
			for dx in 2:
				img.set_pixel(cx + dx, cy + dy, Color(0.70, 0.70, 0.70, 1.0))
	_texture = ImageTexture.create_from_image(img)
	return _texture


## Valeur moyenne du grain, utilisee pour compenser l'assombrissement qu'il
## impose a la teinte de la creature.
const GRAIN_MEAN := 0.85


## Une couleur ecrite telle qu'elle doit apparaitre a l'ecran, et non telle
## qu'elle doit etre pour ressortir a 0,9 une fois le grain applique. Sans ce
## rattrapage, toutes les creatures du jeu paraissaient ternes d'un meme cran.
static func tone(color: Color) -> Color:
	return Color(minf(color.r / GRAIN_MEAN, 1.0), minf(color.g / GRAIN_MEAN, 1.0),
		minf(color.b / GRAIN_MEAN, 1.0), color.a)


## Materiau d'une partie de creature : le grain en texture, la teinte en
## `albedo_color`. Chaque boite garde son propre materiau, parce que le coup
## recu s'y marque par une emission rouge et qu'une emission partagee ferait
## clignoter toutes les creatures de l'espece a la fois.
static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = hide_texture()
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Les UV valent la taille de la face **en blocs** (le grain fait un bloc) :
	# au-dela de 1, il faut donc que la texture se repete.
	m.texture_repeat = true
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


## La boite d'une creature : comme `BoxMesh`, mais avec des UV qui suivent la
## taille reelle de chaque face. `BoxMesh` plaque le meme 0..1 sur les six faces,
## si bien qu'une face de 1 bloc et une de 0,25 montraient le meme nombre de
## texels : le grain d'un cochon changeait de finesse d'une face a l'autre.
##
## Les triangles sont ecrits dans le sens trigonometrique vu de l'exterieur,
## comme le maillage du monde : inverse, la creature disparait sans un mot dans
## la console.
static func box_mesh(size: Vector3) -> ArrayMesh:
	var key := "%.4f,%.4f,%.4f" % [size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var faces := [
		{"n": Vector3(0, 0, 1), "c": [Vector3(-x, -y, z), Vector3(x, -y, z),
			Vector3(x, y, z), Vector3(-x, y, z)]},
		{"n": Vector3(0, 0, -1), "c": [Vector3(x, -y, -z), Vector3(-x, -y, -z),
			Vector3(-x, y, -z), Vector3(x, y, -z)]},
		{"n": Vector3(1, 0, 0), "c": [Vector3(x, -y, z), Vector3(x, -y, -z),
			Vector3(x, y, -z), Vector3(x, y, z)]},
		{"n": Vector3(-1, 0, 0), "c": [Vector3(-x, -y, -z), Vector3(-x, -y, z),
			Vector3(-x, y, z), Vector3(-x, y, -z)]},
		{"n": Vector3(0, 1, 0), "c": [Vector3(-x, y, -z), Vector3(x, y, -z),
			Vector3(x, y, z), Vector3(-x, y, z)]},
		{"n": Vector3(0, -1, 0), "c": [Vector3(-x, -y, z), Vector3(x, -y, z),
			Vector3(x, -y, -z), Vector3(-x, -y, -z)]},
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in faces:
		var corners: Array = face["c"]
		var base := vertices.size()
		# Les UV sortent de la geometrie : la largeur de la face sur son premier
		# cote, sa hauteur sur le dernier. En blocs, donc a l'echelle du grain.
		var span_u: float = corners[0].distance_to(corners[1])
		var span_v: float = corners[0].distance_to(corners[3])
		var face_uvs := [Vector2(0, 0), Vector2(span_u, 0),
			Vector2(span_u, span_v), Vector2(0, span_v)]
		for i in 4:
			vertices.push_back(corners[i])
			normals.push_back(face["n"])
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
	_meshes[key] = mesh
	return mesh
