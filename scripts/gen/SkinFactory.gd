class_name SkinFactory
extends RefCounted

## Fabrique une skin de personnage au format 64x64 de Minecraft, entierement
## peinte par code : visage, cheveux, col de chemise, ceinture, manches et
## bottes. Aucune image n'est importee, comme le reste du jeu.
##
## La disposition des rectangles est celle du format officiel, ce qui permet
## d'utiliser plus tard une vraie skin importee sans toucher au maillage :
## `PlayerBody` ne connait que les rectangles, pas la peinture.
##
## Repere du layout 64x64, en pixels. Chaque membre occupe un bloc de 16x16 et
## son unfolding tient sur six faces ; le membre gauche est le miroir du droit,
## place plus bas dans l'image :
##
##   Tete    x 0..32   y 0..16
##   Corps   x 16..40  y 16..32
##   Bras D  x 40..56  y 16..32
##   Jambe D x 0..16   y 16..32
##   Bras G  x 32..48  y 48..64
##   Jambe G x 16..32  y 48..64

const SIZE := 64

## Dimensions en pixels d'un membre, dans l'ordre [largeur, hauteur, profondeur].
const HEAD := Vector3i(8, 8, 8)
const BODY := Vector3i(8, 12, 4)
const LIMB := Vector3i(4, 12, 4)

## Hauteur en pixels du haut d'un membre du corps : epauliere et ceinture.
const TORSO_TOP := 12

## Une tenue : les couleurs et la silhouette qui en dependent. La bouche et les
## yeux sont dessines, pas choisis : `variant` change leur forme.
const SKINS := [
	{
		"nom": "Steve",
		"peau": Color(0.80, 0.60, 0.45),
		"haut": Color(0.05, 0.65, 0.65),
		"pantalon": Color(0.20, 0.25, 0.65),
		"cheveux": Color(0.25, 0.18, 0.10),
		"yeux": Color(0.35, 0.45, 0.85),
		"variant": 0,
	},
	{
		"nom": "Alex",
		"peau": Color(0.92, 0.72, 0.55),
		"haut": Color(0.35, 0.65, 0.25),
		"pantalon": Color(0.45, 0.35, 0.25),
		"cheveux": Color(0.75, 0.45, 0.15),
		"yeux": Color(0.30, 0.55, 0.30),
		"variant": 1,
	},
	{
		"nom": "Mineur",
		"peau": Color(0.65, 0.48, 0.35),
		"haut": Color(0.85, 0.70, 0.15),
		"pantalon": Color(0.30, 0.30, 0.32),
		"cheveux": Color(0.12, 0.12, 0.12),
		"yeux": Color(0.50, 0.35, 0.20),
		"variant": 2,
	},
]

## Rectangle de chaque face dans l'image, cle `<membre>.<face>`. Les six faces
## d'un membre sont declarees pour les six membres : c'est ce qui evite les
## recopies miroir, souvent decalees d'un pixel et invisibles a l'oeil mais
## visibles des que le personnage tourne.
##
## `gauche` et `droite` designent les faces laterales, vues depuis l'avant du
## personnage : la face `droite` est toujours celle du bras droit, exterieur.
const UV := {
	"tete.haut": Rect2i(8, 0, 8, 8),
	"tete.bas": Rect2i(16, 0, 8, 8),
	"tete.avant": Rect2i(8, 8, 8, 8),
	"tete.droite": Rect2i(0, 8, 8, 8),
	"tete.gauche": Rect2i(16, 8, 8, 8),
	"tete.arriere": Rect2i(24, 8, 8, 8),

	"corps.haut": Rect2i(20, 16, 8, 4),
	"corps.bas": Rect2i(28, 16, 8, 4),
	"corps.avant": Rect2i(20, 20, 8, 12),
	"corps.droite": Rect2i(16, 20, 4, 12),
	"corps.gauche": Rect2i(28, 20, 4, 12),
	"corps.arriere": Rect2i(32, 20, 8, 12),

	"bras_droite.haut": Rect2i(44, 16, 4, 4),
	"bras_droite.bas": Rect2i(48, 16, 4, 4),
	"bras_droite.avant": Rect2i(44, 20, 4, 12),
	"bras_droite.droite": Rect2i(40, 20, 4, 12),
	"bras_droite.gauche": Rect2i(48, 20, 4, 12),
	"bras_droite.arriere": Rect2i(52, 20, 4, 12),

	"bras_gauche.haut": Rect2i(36, 48, 4, 4),
	"bras_gauche.bas": Rect2i(40, 48, 4, 4),
	"bras_gauche.avant": Rect2i(36, 52, 4, 12),
	"bras_gauche.gauche": Rect2i(32, 52, 4, 12),
	"bras_gauche.droite": Rect2i(40, 52, 4, 12),
	"bras_gauche.arriere": Rect2i(44, 52, 4, 12),

	"jambe_droite.haut": Rect2i(4, 16, 4, 4),
	"jambe_droite.bas": Rect2i(8, 16, 4, 4),
	"jambe_droite.avant": Rect2i(4, 20, 4, 12),
	"jambe_droite.droite": Rect2i(0, 20, 4, 12),
	"jambe_droite.gauche": Rect2i(8, 20, 4, 12),
	"jambe_droite.arriere": Rect2i(12, 20, 4, 12),

	"jambe_gauche.haut": Rect2i(20, 48, 4, 4),
	"jambe_gauche.bas": Rect2i(24, 48, 4, 4),
	"jambe_gauche.avant": Rect2i(20, 52, 4, 12),
	"jambe_gauche.gauche": Rect2i(16, 52, 4, 12),
	"jambe_gauche.droite": Rect2i(24, 52, 4, 12),
	"jambe_gauche.arriere": Rect2i(28, 52, 4, 12),
}

## Les six faces, dans l'ordre ou `PlayerBody` construit ses triangles.
const FACES := ["avant", "arriere", "droite", "gauche", "haut", "bas"]


## Peint la skin d'une tenue et renvoie l'image, en 64x64 pixels.
static func build_skin(index: int) -> Image:
	var skin: Dictionary = SKINS[clampi(index, 0, SKINS.size() - 1)]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# Le fond reste transparent : sans lui, une face non peinte laisserait voir
	# le decor du menu a travers le personnage.
	img.fill(Color(0, 0, 0, 0))

	_paint_head(img, skin)
	_paint_body(img, skin)
	# Les membres sont peints deux a deux par la meme fonction : un bras et une
	# jambe ne different que par la couleur de leur partie haute, et le membre
	# gauche recoit exactement la meme peinture que le droit.
	for member in ["bras_droite", "bras_gauche"]:
		_paint_limb(img, member, skin, skin["haut"], true)
	for member in ["jambe_droite", "jambe_gauche"]:
		_paint_limb(img, member, skin, skin["pantalon"], false)
	return img


## La texture d'une tenue, avec mipmaps : le personnage vu de loin doit rester
## lisible, pas scintiller.
static func skin_texture(index: int) -> ImageTexture:
	var img := build_skin(index)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Materiau du personnage : filtrage au plus proche, comme le pixel-art le
## demande, et une legere emission pour que la face dans l'ombre garde ses
## details de 8 pixels.
static func skin_material(index: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = skin_texture(index)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.95
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


# ------------------------------------------------------------------- peinture

## Rectangle plein, avec un grain leger : une surface unie paraitrait en
## plastique, alors que Minecraft a toujours un bruit de tissu.
static func _fill(img: Image, at: Vector2i, size: Vector2i, color: Color,
		grain: float = 0.0, salt: int = 0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(hash("cubecraft:skin:%d:%d:%d" % [at.x, at.y, salt]))
	for y in size.y:
		for x in size.x:
			var c := color
			if grain > 0.0:
				c = _jitter(color, grain, r)
			img.set_pixel(at.x + x, at.y + y, c)


static func _jitter(base: Color, amount: float, r: RandomNumberGenerator) -> Color:
	var d := r.randf_range(-amount, amount)
	return Color(
		clampf(base.r + d, 0.0, 1.0),
		clampf(base.g + d, 0.0, 1.0),
		clampf(base.b + d, 0.0, 1.0), base.a)


static func _dark(c: Color, amount: float) -> Color:
	return Color(c.r * (1.0 - amount), c.g * (1.0 - amount),
		c.b * (1.0 - amount), c.a)


static func _light(c: Color, amount: float) -> Color:
	return Color(
		clampf(c.r + (1.0 - c.r) * amount, 0.0, 1.0),
		clampf(c.g + (1.0 - c.g) * amount, 0.0, 1.0),
		clampf(c.b + (1.0 - c.b) * amount, 0.0, 1.0), c.a)


## Remplit toutes les faces d'un membre avec une couleur de base.
static func _fill_member(img: Image, member: String, color: Color,
		grain: float = 0.03) -> void:
	for face in FACES:
		var r: Rect2i = UV["%s.%s" % [member, face]]
		_fill(img, r.position, r.size, color, grain, hash(face))


## Un pixel, eventuellement hors du cadre : `set_pixel` echouerait.
static func _dot(img: Image, at: Vector2i, color: Color) -> void:
	if at.x < 0 or at.y < 0 or at.x >= SIZE or at.y >= SIZE:
		return
	img.set_pixel(at.x, at.y, color)


## Tete 8x8 : peau, cheveux sur cinq faces, et un visage sur la face avant.
static func _paint_head(img: Image, skin: Dictionary) -> void:
	var peau: Color = skin["peau"]
	var cheveux: Color = skin["cheveux"]
	var yeux: Color = skin["yeux"]
	var variant: int = skin["variant"]

	_fill_member(img, "tete", peau, 0.02)

	# Dessus et arriere sont coiffes, le dessus un peu plus clair pour
	# qu'il accroche la lumiere.
	var top: Rect2i = UV["tete.haut"]
	_fill(img, top.position, top.size, _light(cheveux, 0.08), 0.05, 7)
	var back: Rect2i = UV["tete.arriere"]
	_fill(img, back.position, back.size, cheveux, 0.05, 8)
	# Les cotes recoivent les cheveux jusqu'a mi-hauteur : sans cela le
	# personnage a une tete chauve de profil.
	for face in ["droite", "gauche"]:
		var side: Rect2i = UV["tete.%s" % face]
		_fill(img, Vector2i(side.position.x, side.position.y),
			Vector2i(side.size.x, 3), cheveux, 0.04, hash(face))

	# Face avant : peau, frange, yeux, sourcils, bouche, nez.
	var f: Rect2i = UV["tete.avant"]
	_fill(img, f.position, f.size, peau, 0.02, 9)

	# Frange : `variant` change l'angle de la coiffure, comme un vrai perso.
	var fringe := 3 if variant == 0 else (2 if variant == 1 else 1)
	for y in fringe:
		var width := f.size.x - (1 if y == fringe - 1 else 0)
		_fill(img, Vector2i(f.position.x, f.position.y + y), Vector2i(width, 1),
			cheveux, 0.04, 10 + y)
	# Mèches sur les temples : c'est ce qui fait lire un visage de 8 pixels.
	for x in [0, f.size.x - 1]:
		_fill(img, Vector2i(f.position.x + x, f.position.y + fringe),
			Vector2i(1, 2), cheveux, 0.0, 20 + x)

	# Yeux : deux pixels de blanc puis deux de couleur, l'iris en bas. Steve et
	# le Mineur regardent droit devant, Alex a l'oeil plus haut.
	var eye_y := 4 if variant == 2 else 3
	for side in [1, 5]:
		var brow := _dark(cheveux, 0.2)
		for dx in 2:
			_dot(img, Vector2i(f.position.x + side + dx, f.position.y + eye_y),
				Color(0.95, 0.95, 0.97))
			_dot(img, Vector2i(f.position.x + side + dx, f.position.y + eye_y + 1),
				yeux)
			_dot(img, Vector2i(f.position.x + side + dx, f.position.y + eye_y - 1),
				brow)

	# Bouche : le Mineur a un sourire marque par les pixels du bord, les autres
	# une ligne droite.
	var mouth := _dark(peau, 0.45)
	_dot(img, Vector2i(f.position.x + 3, f.position.y + 6), mouth)
	_dot(img, Vector2i(f.position.x + 4, f.position.y + 6), mouth)
	if variant == 2:
		_dot(img, Vector2i(f.position.x + 2, f.position.y + 6), mouth)
		_dot(img, Vector2i(f.position.x + 5, f.position.y + 6), mouth)
	# Nez : une ombre d'un pixel, absente sur Alex dont le visage est plus doux.
	if variant != 1:
		_dot(img, Vector2i(f.position.x + 4, f.position.y + 5), _dark(peau, 0.18))

	# Bas de la tete dans l'ombre du menton, pour detacher la tete du buste.
	var under: Rect2i = UV["tete.bas"]
	_fill(img, under.position, under.size, _dark(peau, 0.25), 0.03, 40)


## Corps 8x12 : haut, col en V, ceinture, poche et couture dorsale.
static func _paint_body(img: Image, skin: Dictionary) -> void:
	var haut: Color = skin["haut"]
	var pantalon: Color = skin["pantalon"]
	var peau: Color = skin["peau"]

	_fill_member(img, "corps", haut, 0.03)

	# Ceinture et pantalon sur les derniers pixels du buste, plus sombres.
	for face in FACES:
		var r: Rect2i = UV["corps.%s" % face]
		var rows := r.size.y - 3
		if rows <= 0:
			continue
		_fill(img, Vector2i(r.position.x, r.position.y + rows),
			Vector2i(r.size.x, 3), pantalon, 0.03, 50 + hash(face))

	# Face avant : col en V, bandeau clair, poche poitrine.
	var f: Rect2i = UV["corps.avant"]
	for x in 3:
		_dot(img, Vector2i(f.position.x + 2 + x, f.position.y + x), peau)
		_dot(img, Vector2i(f.position.x + 5 - x, f.position.y + x), peau)
	_fill(img, Vector2i(f.position.x, f.position.y), Vector2i(f.size.x, 1),
		_light(haut, 0.12), 0.0, 60)
	_fill(img, Vector2i(f.position.x + 1, f.position.y + 4), Vector2i(2, 2),
		_dark(haut, 0.12), 0.0, 61)
	# Le dos porte une couture verticale, sinon il est parfaitement plat.
	var b: Rect2i = UV["corps.arriere"]
	_fill(img, Vector2i(b.position.x + 3, b.position.y + 1), Vector2i(2, 8),
		_dark(haut, 0.10), 0.03, 62)


## Un bras ou une jambe : la partie haute prend la couleur du vetement, la
## partie basse est la main nue ou une chaussure. Ce n'est pas un simple
## assombrissement du vetement : une main c'est de la peau, et une chaussure
## une couleur a part, sinon les quatre bras du personnage sont des tuyaux.
static func _paint_limb(img: Image, member: String, skin: Dictionary,
		top: Color, is_arm: bool) -> void:
	var peau: Color = skin["peau"]
	var bas: Color = peau if is_arm else _boots(top)
	var split := 6

	for face in FACES:
		var r: Rect2i = UV["%s.%s" % [member, face]]
		var rows := r.size.y
		# Le dessus et le dessous ne sont pas coupes en deux : une epauliere
		# unie evite la couture horizontale qui traverserait l'epaule.
		if face == "haut" or face == "bas":
			_fill(img, r.position, r.size,
				top if face == "haut" else _dark(top, 0.2), 0.03, 80 + hash(face))
			continue
		# Les faces laterales peuvent etre plus hautes que le devant dans le
		# format officiel : on decoupe sur une proportion, pas sur un compte.
		var cut := maxi(1, int(round(float(rows) * float(split) / 12.0)))
		_fill(img, r.position, Vector2i(r.size.x, cut), top, 0.03, 70 + hash(face))
		_fill(img, Vector2i(r.position.x, r.position.y + cut),
			Vector2i(r.size.x, rows - cut), bas, 0.03, 90 + hash(face))
		# Couture d'epaule ou de hanche : une ligne plus sombre qui separe le
		# vetement de la peau, et donne une epaisseur au membre.
		_fill(img, Vector2i(r.position.x, r.position.y + cut - 1),
			Vector2i(r.size.x, 1), _dark(top, 0.18), 0.0, 100 + hash(face))
		# Bord exterieur dans l'ombre, bord interieur au soleil : c'est ce
		# contraste qui donne du volume a un membre de 4 pixels de large. Le
		# liseré suit les deux sections, sinon la peau de la main heriterait du
		# bleu de la manche. La face exterieure est celle de la droite pour un
		# membre droit, et celle de la gauche pour un membre gauche : la
		# symetrie du personnage veut que les deux bras recoivent la meme lumiere.
		var outer: bool = face == ("droite" if member.ends_with("droite") else "gauche")
		var column := r.size.x - 1 if outer else 0
		_edge(img, Vector2i(r.position.x + column, r.position.y), cut, top, outer)
		_edge(img, Vector2i(r.position.x + column, r.position.y + cut),
			rows - cut, bas, outer)

	# Le dessus du membre est de la couleur du haut, pour que l'epaule soit
	# continue avec le buste quand le bras est le long du corps ; le dessous
	# est la paume, pas la couleur du vetement.
	var top_rect: Rect2i = UV["%s.haut" % member]
	_fill(img, top_rect.position, top_rect.size, top, 0.03, 120)
	var bottom_rect: Rect2i = UV["%s.bas" % member]
	_fill(img, bottom_rect.position, bottom_rect.size, bas, 0.03, 121)


## Une colonne de liseré sur une hauteur donnee : assombrie sur le bord exterieur
## d'un membre, éclaircie sur le bord interieur.
static func _edge(img: Image, at: Vector2i, rows: int, base: Color, dark: bool) -> void:
	var color := _dark(_dark(base, 0.16), 0.10) if dark else _light(base, 0.05)
	_fill(img, at, Vector2i(1, rows), color, 0.0, 130 if dark else 131)


## Couleur d'une chaussure : un brun fonce tire du vetement, assez distant du
## pantalon pour qu'on distingue le bas de la jambe d'un seul coup d'oeil.
static func _boots(pantalon: Color) -> Color:
	return Color(
		clampf(pantalon.r * 0.45 + 0.12, 0.0, 1.0),
		clampf(pantalon.g * 0.45 + 0.10, 0.0, 1.0),
		clampf(pantalon.b * 0.45 + 0.08, 0.0, 1.0), 1.0)


# ------------------------------------------------------------- acces aux UV

## Rectangle UV d'une face de membre, ou `Rect2i()` si le nom est inconnu.
static func uv_rect(member: String, face: String) -> Rect2i:
	return UV.get("%s.%s" % [member, face], Rect2i())


## Rectangle UV normalise, directement exploitable par un `ArrayMesh`.
static func uv_normalized(member: String, face: String) -> Rect2:
	var r := uv_rect(member, face)
	if r.size.x == 0:
		return Rect2()
	return Rect2(
		float(r.position.x) / float(SIZE),
		float(r.position.y) / float(SIZE),
		float(r.size.x) / float(SIZE),
		float(r.size.y) / float(SIZE))


## Dimensions d'un membre en pixels, pour construire la boite 3D.
static func dimensions(member: String) -> Vector3i:
	match member:
		"tete":
			return HEAD
		"corps":
			return BODY
		_:
			return LIMB


## Nombre de tenues disponibles.
static func count() -> int:
	return SKINS.size()


## Nom affiche d'une tenue.
static func skin_name(index: int) -> String:
	return str(SKINS[clampi(index, 0, SKINS.size() - 1)]["nom"])


## Teinte associee a une tenue, pour l'etiquette du menu et le HUD.
static func palette(index: int) -> Dictionary:
	return SKINS[clampi(index, 0, SKINS.size() - 1)]
