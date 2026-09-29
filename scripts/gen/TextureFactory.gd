class_name TextureFactory
extends RefCounted

##Fabrique l'atlas de textures pixel-art du jeu, sans aucun fichier image.
##
## L'atlas fait COLS x ROWS tuiles de PX x PX pixels. Chaque tuile est peinte
## par une fonction dediee avec un generateur pseudo-aleatoire a graine fixe :
## le resultat est parfaitement reproductible d'une session a l'autre.

const PX := 16

# Palette de base, en gris-vert pour tout ce qui recoit un tint de biome.
const C_DIRT := Color(0.49, 0.35, 0.23)
const C_STONE := Color(0.52, 0.52, 0.53)
const C_SAND := Color(0.87, 0.80, 0.57)
const C_WOOD := Color(0.45, 0.32, 0.19)
const C_PLANKS := Color(0.71, 0.55, 0.34)
const C_LEAF := Color(0.55, 0.60, 0.48)
const C_SNOW := Color(0.94, 0.96, 0.99)


static func build_atlas() -> Image:
	var img := Image.create(Tiles.COLS * PX, Tiles.ROWS * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for tile in range(Tiles.COUNT):
		_paint_tile(img, tile)
	# Habillage optionnel par des images tierces (CC0) : ne recouvre que les
	# tuiles pour lesquelles un fichier est present, et ne touche pas a la
	# grille. Sans le dossier `assets/kenney/`, cette ligne ne change rien.
	ExternalTiles.apply_to_atlas(img)
	return img


# ---------------------------------------------------------------- utilitaires

static func _origin(tile: int) -> Vector2i:
	return Vector2i((tile % Tiles.COLS) * PX, (tile / Tiles.COLS) * PX)


static func _px(img: Image, o: Vector2i, x: int, y: int, c: Color) -> void:
	if x < 0 or x >= PX or y < 0 or y >= PX:
		return
	img.set_pixel(o.x + x, o.y + y, c)


static func _rng(tile: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(hash("cubecraft:%d:%d" % [tile, salt]))
	return r


static func _jitter(base: Color, amount: float, r: RandomNumberGenerator) -> Color:
	var d := r.randf_range(-amount, amount)
	return Color(
		clampf(base.r + d, 0.0, 1.0),
		clampf(base.g + d, 0.0, 1.0),
		clampf(base.b + d, 0.0, 1.0),
		base.a)


## Bruit dense : chaque pixel decale autour de la couleur de base.
static func _noise_fill(img: Image, o: Vector2i, base: Color, amount: float,
		r: RandomNumberGenerator) -> void:
	for y in PX:
		for x in PX:
			_px(img, o, x, y, _jitter(base, amount, r))


## Semee de pixels plus sombres, pour casser la regularite du bruit.
static func _speckle(img: Image, o: Vector2i, base: Color, count: int, amount: float,
		r: RandomNumberGenerator) -> void:
	for i in count:
		var x := r.randi_range(0, PX - 1)
		var y := r.randi_range(0, PX - 1)
		_px(img, o, x, y, _jitter(base, -amount, r))


# ------------------------------------------------------------- tuiles de blocs

static func _paint_dirt(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, C_DIRT, 0.055, r)
	_speckle(img, o, C_DIRT, 26, 0.09, r)
	_speckle(img, o, C_DIRT.lerp(Color(0.3, 0.21, 0.14), 0.5), 8, 0.05, r)


static func _paint_grass_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Gris-vert : la couleur reelle vient du tint de biome applique aux sommets.
	#
	# Le bruit est volontairement faible et **groupe** : un ecart tire a chaque
	# pixel donnait, sur une grande plaine, une image qui fourmille comme de la
	# neige, et le gazon se lisait comme une nappe de bruit plutot que comme de
	# l'herbe. Minecraft fait l'inverse — un aplat presque uni, releve de
	# quelques touffes.
	_noise_fill(img, o, C_LEAF, 0.03, r)
	# Touffes : des amas de deux pixels, plus sombres, qui cassent l'uniformite
	# sans la remplacer par du bruit.
	for i in 7:
		var cx := r.randi_range(0, PX - 2)
		var cy := r.randi_range(0, PX - 2)
		for dy in 2:
			for dx in 2:
				if r.randf() < 0.3:
					continue
				_px(img, o, cx + dx, cy + dy,
					_jitter(C_LEAF.darkened(0.11), 0.03, r))
	_speckle(img, o, C_LEAF.lightened(0.12), 10, 0.05, r)


static func _paint_grass_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_dirt(img, o, r)
	var grass := C_LEAF
	for y in 4:
		for x in PX:
			# Bord irregulier entre l'herbe et la terre.
			var jag := 0
			if r.randf() < 0.32:
				jag = 1
			elif r.randf() < 0.10:
				jag = -1
			if y + jag < 4:
				_px(img, o, x, y, _jitter(grass, 0.07, r))


static func _paint_stone(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, C_STONE, 0.045, r)
	_speckle(img, o, C_STONE, 18, 0.08, r)
	# Quelques fissures plus marquees.
	for i in 3:
		var x := r.randi_range(1, PX - 2)
		var y := r.randi_range(1, PX - 2)
		_px(img, o, x, y, Color(0.38, 0.38, 0.40))
		_px(img, o, x + 1, y, Color(0.40, 0.40, 0.42))


static func _paint_cobble(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Mortier sombre entre des pierres carrees legerement decalees.
	_noise_fill(img, o, Color(0.31, 0.31, 0.33), 0.03, r)
	for cy in 4:
		for cx in 4:
			var sx := cx * 4 + (1 if r.randf() < 0.5 else 0)
			var sy := cy * 4 + (1 if r.randf() < 0.5 else 0)
			var tone := Color(0.52, 0.52, 0.54).lerp(Color(0.64, 0.64, 0.66), r.randf())
			for y in 3:
				for x in 3:
					# Coins arrondis aleatoires -> aspect de moellon.
					var corner := (x == 0 or x == 2) and (y == 0 or y == 2)
					if corner and r.randf() < 0.55:
						continue
					_px(img, o, sx + x, sy + y, _jitter(tone, 0.05, r))
			# Lumiere en haut a gauche, ombre en bas a droite.
			_px(img, o, sx, sy, tone.lightened(0.16))
			_px(img, o, sx + 2, sy + 2, tone.darkened(0.20))


static func _paint_sand(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, C_SAND, 0.045, r)
	_speckle(img, o, C_SAND, 20, 0.09, r)


static func _paint_gravel(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.45, 0.43, 0.42), 0.05, r)
	# Petits cailloux de 2x2 dans des tons varies.
	var tones := [
		Color(0.58, 0.56, 0.53), Color(0.36, 0.35, 0.34),
		Color(0.48, 0.43, 0.38), Color(0.66, 0.64, 0.61),
	]
	for cy in 5:
		for cx in 5:
			if r.randf() < 0.45:
				continue
			var t: Color = tones[r.randi_range(0, tones.size() - 1)]
			_px(img, o, cx * 3 + r.randi_range(0, 1), cy * 3 + r.randi_range(0, 1), t)
			_px(img, o, cx * 3 + 1 + r.randi_range(0, 1), cy * 3, t.lightened(0.08))


static func _paint_bedrock(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Motif caillouteux tres contrastant, insoluble.
	for cy in 4:
		for cx in 4:
			var tone := Color(0.18, 0.18, 0.20).lerp(Color(0.46, 0.46, 0.48), r.randf())
			var sx := cx * 4 + r.randi_range(0, 1)
			var sy := cy * 4 + r.randi_range(0, 1)
			for y in 3:
				for x in 3:
					_px(img, o, sx + x, sy + y, _jitter(tone, 0.05, r))


static func _paint_log_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Ecorce : des cotes verticales qui courent sur toute la hauteur. Un ton
	# par colonne, puis un grain fin : ecorces et veines restent continues, ce
	# qui est justement ce qui distingue une ecorce d'un bruit de bois.
	for x in PX:
		var tone := C_WOOD.lerp(Color(0.62, 0.46, 0.27), r.randf() * 0.9)
		# Une cote sur quatre est nettement plus sombre : c'est ce contraste
		# qui donne l'echelle de l'ecorce, sans quoi le tronc est un aplat.
		if r.randf() < 0.22:
			tone = tone.darkened(0.26)
		for y in PX:
			var d := -0.05 if r.randf() < 0.10 else 0.0
			_px(img, o, x, y, _jitter(tone, 0.022 + d, r))
	# Deux veines creusees, tracees d'un bout a l'autre de la tuile : un tronc
	# sans elles est un assemblage de rayures verticales sans relief.
	for vein in [r.randi_range(2, 5), r.randi_range(10, 13)]:
		var wobble := 0
		for y in PX:
			if r.randf() < 0.22:
				wobble = clampi(wobble + (1 if r.randf() < 0.5 else -1), -1, 1)
			_px(img, o, vein + wobble, y, C_WOOD.darkened(0.34))
			_px(img, o, vein + wobble + 1, y, C_WOOD.darkened(0.12))


static func _paint_log_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	var center := Vector2(7.5, 7.5)
	# Ecorce tout autour : sans elle, le dessus d'un tronc se raccorde au cote
	# sans transition, et la souche parait posee sur elle-meme.
	for y in PX:
		for x in PX:
			if x == 0 or y == 0 or x == PX - 1 or y == PX - 1:
				_px(img, o, x, y, _jitter(C_WOOD.darkened(0.18), 0.04, r))
	for y in range(1, PX - 1):
		for x in range(1, PX - 1):
			var dist := Vector2(x, y).distance_to(center)
			# Cernes concentriques, un peu irreguliers : des anneaux parfaits se
			# lisent comme une cible imprimee plutot que comme du bois.
			var ring := fmod(dist + sin(float(x) * 1.7) * 0.35, 2.6) / 2.6
			var tone := C_WOOD.lerp(C_PLANKS, 0.42) if ring < 0.5 else Color(0.40, 0.28, 0.16)
			_px(img, o, x, y, _jitter(tone, 0.035, r))
	# Coeur du tronc.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if absi(dx) + absi(dy) <= 1:
				_px(img, o, 7 + dx, 7 + dy, Color(0.34, 0.23, 0.13))


static func _paint_leaves(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Gris-vert + tint de biome. La tuile est **entièrement peinte**.
	#
	# La version précédente tirait 8 % de pixels au hasard et les laissait
	# transparents. Cela se lisait très mal, pour trois raisons qui se
	# cumulent : un trou au milieu d'une face est un carré de ciel — un point
	# bleu, la seule couleur qui n'existe pas dans un feuillage — ; ces points
	# disparaissaient dès que le bloc s'éloignait, le mipmap estompant le
	# percement sous le seuil du scissor, donc le feuillage scintillait en
	# marchant ; et surtout le trou était le ciel *directement*, car
	# `face_visible` masque les faces internes du feuillage : derrière la
	# surface d'une couronne il n'y a rien. Percer la tuile revient à percer
	# l'arbre entier.
	#
	# Le relief vient donc de la peinture, mais il doit rester **fin** : c'est un
	# feuillage, pas une caverne. Deux reglages successifs se sont rates ici.
	# D'abord des trous transparents, qui donnaient sur le ciel. Ensuite des
	# creux noirs de trois pixels, qu'on lisait comme de la moisissure : la
	# couronne devenait un amas vert tachete, un arbre malade vu de loin.
	#
	# Ce qui marche est ce que fait Minecraft : une variation pixel a pixel
	# faible, puis des amas sombres **petits et nombreux**, de deux pixels, qui
	# dessinent la silhouette des feuilles sans jamais creuser la couronne.
	for y in PX:
		for x in PX:
			_px(img, o, x, y, _jitter(C_LEAF, 0.05, r))
	var shade := C_LEAF.lerp(Color(0.30, 0.40, 0.22), 0.72)
	for i in 14:
		var cx := r.randi_range(0, PX - 2)
		var cy := r.randi_range(0, PX - 2)
		# Un pixel d'amas sur quatre manque : quatre carres identiques se
		# liraient comme un tampon.
		for dy in 2:
			for dx in 2:
				if r.randf() < 0.25:
					continue
				_px(img, o, cx + dx, cy + dy, _jitter(shade, 0.03, r))
	# Pointes prises de lumiere, pour que le feuillage ait un dessus.
	_speckle(img, o, C_LEAF.lerp(Color(0.92, 1.0, 0.80), 0.40), 16, 0.06, r)


static func _paint_planks(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# 4 lattes horizontales, chacune avec son propre ton et sa couture verticale.
	# Le trait sombre en haut de chaque latte est ce qui fait lire « quatre
	# planches » d'un coup d'oeil : sans lui, la tuile ressemble a un carre de
	# bois bruit\u00e9 plutot qu'a un assemblage.
	for row in 4:
		var tone := C_PLANKS.lerp(C_WOOD, r.randf() * 0.35)
		var seam := r.randi_range(3, 12)
		for y in range(row * 4, row * 4 + 4):
			for x in PX:
				_px(img, o, x, y, _jitter(tone, 0.045, r))
			# Jointures de la latte.
			_px(img, o, seam, row * 4, tone.darkened(0.35))
			_px(img, o, seam, row * 4 + 1, tone.darkened(0.28))
			# Grain du bois.
			_px(img, o, (seam + 5) % PX, row * 4 + 1, tone.darkened(0.12))
			_px(img, o, (seam + 9) % PX, row * 4 + 3, tone.darkened(0.10))
		# Ombre portee entre deux lattes, sur toute la largeur.
		for x in PX:
			_px(img, o, x, row * 4, tone.darkened(0.42))
			_px(img, o, x, row * 4 + 1, tone.darkened(0.18))


static func _paint_water(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	var base := Color(0.20, 0.42, 0.78, 0.74)
	_noise_fill(img, o, base, 0.035, r)
	# Petites vaguelettes plus claires.
	for i in 7:
		var y := r.randi_range(0, PX - 1)
		var x := r.randi_range(0, PX - 3)
		_px(img, o, x, y, base.lightened(0.20))
		_px(img, o, x + 1, y, base.lightened(0.14))


## Les images successives de la surface de l'eau.
##
## L'eau est la seule matiere du jeu qui bouge. Plutot qu'un materiau anime ou
## qu'un decalque, ce sont **les pixels** qui changent : une image par image,
## `update()` ne represente que 1 ko — contre 49 ko si l'on repintait
## l'atlas entier. Le mouvement reste celui d'un motif peint, ce que le reste
## du jeu fait partout ailleurs.
##
## L'ecoulement est purement horizontal, d'une colonne par image. C'est ce qui
## referme la boucle : au bout de `PX` images, le motif est revenu exactement
## a sa place, puisque chaque harmonique fait un nombre entier de tours par
## tuile. Une derive oblique, meme plus agreable, decoincait la boucle de
## plusieurs lignes, et le decalage se voyait au raccord.
static func build_water_frames(count: int) -> Array[Image]:
	var frames: Array[Image] = []
	for k in count:
		var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
		_paint_water_frame(img, k)
		img.generate_mipmaps()
		frames.append(img)
	return frames


## Une image de la surface de l'eau, decalee de `phase` pixels. Voir
## `build_water_frames`.
static func _paint_water_frame(img: Image, phase: int) -> void:
	var base := Color(0.20, 0.42, 0.78, 0.74)
	for y in PX:
		for x in PX:
			var u := float(x + phase) / float(PX)
			var v := float(y) / float(PX)
			# Trois harmoniques. Les coefficients sont des entiers : c'est ce
			# qui rend la tuile **periodique**, donc raccordable a elle-meme.
			# Un motif tire au hasard
			# serait coupe en deux par son propre rebord, et le raccord
			#appearaitrait en traversant toute la surface.
			var wave := sin(TAU * (2.0 * u + 3.0 * v)) * 0.50 \
				+ sin(TAU * (3.0 * u - 2.0 * v)) * 0.35 \
				+ sin(TAU * (5.0 * u + v)) * 0.15
			img.set_pixel(x, y, base.lightened(clampf(wave * 0.13 + 0.15, 0.0, 0.32)))


static func _paint_snow_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, C_SNOW, 0.022, r)
	_speckle(img, o, C_SNOW, 10, 0.04, r)


static func _paint_snow_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_dirt(img, o, r)
	for y in 4:
		for x in PX:
			if y == 3 and r.randf() < 0.35:
				continue
			_px(img, o, x, y, _jitter(C_SNOW, 0.03, r))


static func _paint_coal_ore(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_stone(img, o, r)
	for blob in 5:
		var bx := r.randi_range(1, PX - 4)
		var by := r.randi_range(1, PX - 4)
		var size := r.randi_range(2, 3)
		for y in size:
			for x in size:
				if x + y > size and r.randf() < 0.5:
					continue
				_px(img, o, bx + x, by + y, _jitter(Color(0.10, 0.10, 0.11), 0.03, r))
		_px(img, o, bx, by, Color(0.30, 0.30, 0.32))


static func _paint_iron_ore(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_stone(img, o, r)
	for blob in 4:
		var bx := r.randi_range(1, PX - 4)
		var by := r.randi_range(1, PX - 4)
		var size := r.randi_range(2, 3)
		var tone := Color(0.85, 0.71, 0.55)
		for y in size:
			for x in size:
				if x + y > size and r.randf() < 0.5:
					continue
				_px(img, o, bx + x, by + y, _jitter(tone, 0.06, r))
		_px(img, o, bx, by, tone.lightened(0.30))
		_px(img, o, bx + size - 1, by + size - 1, tone.darkened(0.28))


static func _paint_lapis_ore(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_stone(img, o, r)
	# Amas bleu-lapis sur la pierre.
	for blob in 4:
		var bx := r.randi_range(1, PX - 4)
		var by := r.randi_range(1, PX - 4)
		var size := r.randi_range(2, 3)
		var tone := Color(0.24, 0.34, 0.78)
		for y in size:
			for x in size:
				if x + y > size and r.randf() < 0.5:
					continue
				_px(img, o, bx + x, by + y, _jitter(tone, 0.07, r))
		_px(img, o, bx, by, tone.lightened(0.35))
		_px(img, o, bx + size - 1, by + size - 1, tone.darkened(0.30))


static func _paint_enchant_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_planks(img, o, r)
	# Plateau de pierre encadre, avec un rune violette au centre.
	_noise_fill(img, o, Color(0.34, 0.31, 0.42), 0.02, r)
	for i in PX:
		_px(img, o, i, 1, Color(0.20, 0.18, 0.26))
		_px(img, o, 1, i, Color(0.20, 0.18, 0.26))
		_px(img, o, i, PX - 2, Color(0.20, 0.18, 0.26))
		_px(img, o, PX - 2, i, Color(0.20, 0.18, 0.26))
	for i in 5:
		var d := absi(i - 2)
		_px(img, o, 5 + d, 5 + i, Color(0.62, 0.40, 0.92))
		_px(img, o, 10 - d, 5 + i, Color(0.62, 0.40, 0.92))
	_px(img, o, 8, 4, Color(0.80, 0.66, 0.98))
	_px(img, o, 7, 5, Color(0.55, 0.35, 0.85))
	_px(img, o, 8, 5, Color(0.55, 0.35, 0.85))
	_px(img, o, 9, 5, Color(0.55, 0.35, 0.85))


static func _paint_enchant_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_dirt(img, o, r)
	# Tissu violet noue sur les trois faces.
	var cloth := Color(0.42, 0.20, 0.58)
	for y in range(2, 8):
		for x in range(3, 13):
			_px(img, o, x, y, _jitter(cloth, 0.05, r))
	for i in PX:
		_px(img, o, i, 2, cloth.lightened(0.25))
		_px(img, o, i, 7, cloth.darkened(0.30))


static func _paint_enchant_front(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_enchant_side(img, o, r)
	# Pavet runique : deux bras levés en violet lumineux.
	var rune := Color(0.72, 0.55, 0.98)
	for y in 3:
		_px(img, o, 8, 3 + y, rune)
		_px(img, o, 8 - y, 3, rune)
		_px(img, o, 8 + y, 3, rune)
	_px(img, o, 8, 2, rune.lightened(0.30))
	_px(img, o, 8, 6, rune.darkened(0.20))


static func _paint_lapis_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Petit cristal bleu facon bloc de lapis.
	var base := Color(0.26, 0.36, 0.80)
	for y in range(5, 12):
		for x in range(5, 12):
			var d := absi(x - 8) + absi(y - 8)
			if d > 3 or (d == 3 and r.randf() < 0.5):
				continue
			_px(img, o, x, y, _jitter(base, 0.06, r))
	_px(img, o, 6, 6, base.lightened(0.40))
	_px(img, o, 6, 7, base.lightened(0.20))


static func _paint_porkchop_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Côtelette : un morceau de viande rose, avec son os qui depasse vers le bas
	# a gauche. Deux aplats empiles ne se lisaient pas comme un aliment mais
	# comme deux rectangles — c'est la forme qui fait l'objet.
	var meat := Color(0.90, 0.52, 0.50)
	var fat := Color(0.97, 0.80, 0.76)
	var bone := Color(0.95, 0.92, 0.84)
	for y in range(3, 12):
		for x in range(4, 14):
			var dx := float(x - 9) / 4.6
			var dy := float(y - 7) / 4.2
			if dx * dx + dy * dy > 1.0:
				continue
			_px(img, o, x, y, _jitter(meat, 0.05, r))
	# Os : un manche clair qui sort en bas a gauche.
	for i in 5:
		_px(img, o, 6 - i, 11 - i, bone)
		_px(img, o, 6 - i, 12 - i, bone.darkened(0.18))
	# Loupe de gras sur le dessus, et une arête plus claire.
	for i in 4:
		_px(img, o, 7 + i, 4, fat)
	_px(img, o, 8, 5, fat)
	_px(img, o, 9, 5, fat.lightened(0.15))
	_px(img, o, 5, 9, meat.darkened(0.22))


static func _paint_sword(img: Image, o: Vector2i, r: RandomNumberGenerator, blade: Color) -> void:
	# Epee en diagonale, pointe en haut a droite — l'orientation de Minecraft.
	#
	# La version precedente dressait une lame verticale de quatre pixels de
	# large, terminee par un garde de huit pixels : le tout se lisait comme un
	# marteau, et une epee qu'on ne reconnait pas est une epee ratee. Une lame
	# de deux pixels sur une diagonale, un garde perpendiculaire court, une
	# poignee dans l'axe : c'est ce qui fait la silhouette.
	var light := blade.lightened(0.42)
	var dark := blade.darkened(0.34)
	for k in 10:
		var x := 4 + k
		var y := 11 - k
		# Arete claire sur le dessus, corps plus sombre dessous : deux pixels
		# d'epaisseur, ce qui est la largeur d'une lame de Minecraft.
		_px(img, o, x, y - 1, _jitter(light, 0.03, r))
		_px(img, o, x, y, dark)
	# Pointe effilee, d'un seul pixel.
	_px(img, o, 14, 0, light)
	_px(img, o, 14, 1, dark)
	# Garde : perpendiculaire a la lame, de part et d'autre de sa base.
	var guard := Color(0.62, 0.50, 0.24)
	for d in 2:
		_px(img, o, 3 - d, 10 - d, guard)
		_px(img, o, 5 + d, 12 + d, guard.darkened(0.25))
	# Poignee : dans l'axe de la lame, vers le coin bas-gauche.
	var grip := Color(0.40, 0.28, 0.15)
	for d in 3:
		_px(img, o, 3 - d, 12 + d, grip)
		_px(img, o, 4 - d, 12 + d, grip.darkened(0.28))


static func _paint_iron_block(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	var metal := Color(0.85, 0.85, 0.87)
	_noise_fill(img, o, metal, 0.025, r)
	# Bordureombree + rivets, pour un aspect de lingot.
	for i in PX:
		_px(img, o, i, 0, metal.darkened(0.30))
		_px(img, o, i, PX - 1, metal.darkened(0.30))
		_px(img, o, 0, i, metal.darkened(0.22))
		_px(img, o, PX - 1, i, metal.darkened(0.22))
	for cx in [2, 13]:
		for cy in [2, 13]:
			_px(img, o, cx, cy, metal.darkened(0.35))
			_px(img, o, cx + 1, cy, metal.lightened(0.10))


static func _paint_table_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_planks(img, o, r)
	# Quadrillage de l'etabli.
	for i in 4:
		var p := 2 + i * 4
		for x in range(2, 14):
			_px(img, o, x, p, C_WOOD.darkened(0.45))
		for y in range(2, 14):
			_px(img, o, p, y, C_WOOD.darkened(0.45))
	# Un coin d'outil_trace.
	_px(img, o, 5, 5, Color(0.55, 0.55, 0.57))
	_px(img, o, 6, 5, Color(0.62, 0.62, 0.64))
	_px(img, o, 5, 6, Color(0.48, 0.48, 0.50))


static func _paint_table_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_planks(img, o, r)
	# Coffre de rangement vu de profil.
	for y in range(5, 13):
		for x in range(2, 14):
			_px(img, o, x, y, C_WOOD.darkened(0.30))
	for x in range(2, 14):
		_px(img, o, x, 5, Color(0.30, 0.21, 0.12))
		_px(img, o, x, 12, Color(0.30, 0.21, 0.12))
	_px(img, o, 7, 8, Color(0.72, 0.58, 0.30))
	_px(img, o, 8, 8, Color(0.72, 0.58, 0.30))


static func _paint_table_front(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_paint_table_side(img, o, r)
	# Grille de fabrication 3x3 au centre.
	for gy in 3:
		for gx in 3:
			var bx := 3 + gx * 4
			var by := 5 + gy * 3
			for y in 2:
				for x in 2:
					_px(img, o, bx + x, by + y, Color(0.72, 0.56, 0.34))
			_px(img, o, bx, by, Color(0.34, 0.24, 0.14))
			_px(img, o, bx + 1, by + 1, Color(0.62, 0.48, 0.29))


static func _paint_torch(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Manche de bois au centre, flamme au sommet. Rendu en croix billboard.
	var wood := Color(0.44, 0.31, 0.18)
	for y in range(5, 15):
		_px(img, o, 7, y, wood)
		_px(img, o, 8, y, wood.darkened(0.18))
	# Flamme.
	_px(img, o, 7, 4, Color(0.99, 0.80, 0.28))
	_px(img, o, 8, 4, Color(0.99, 0.66, 0.18))
	_px(img, o, 7, 3, Color(1.00, 0.91, 0.55))
	_px(img, o, 6, 5, Color(0.96, 0.55, 0.15))
	_px(img, o, 9, 5, Color(0.96, 0.55, 0.15))
	_px(img, o, 7, 5, Color(1.00, 0.85, 0.40))
	_px(img, o, 8, 5, Color(0.98, 0.72, 0.22))


# ------------------------------------------------------ icones d'objets purs

static func _paint_stick_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Le baton de Minecraft est un morceau de bois epais, pose en diagonale du
	# coin bas-gauche au coin haut-droit, avec une arete eclairee dessus et un
	# flanc sombre dessous. Trace sur un seul pixel de large, il se lisait comme
	# une rayure ; c'est l'epaisseur et le contraste des aretes qui en font un
	# objet.
	var wood := Color(0.60, 0.43, 0.24)
	var light := wood.lightened(0.34)
	var dark := wood.darkened(0.38)
	# Une extrémité carree et un peu plus large que le corps : sans elle, un
	# baton est un trait, avec elle c'est une branche coupee.
	for i in 12:
		var t := float(i) / 11.0
		var x := 2 + int(round(t * 10.0))
		var y := 13 - int(round(t * 10.0))
		_px(img, o, x, y, _jitter(wood, 0.035, r))
		_px(img, o, x, y - 1, light)
		_px(img, o, x + 1, y, dark)
	# Bout : deux pixels de plus en travers, a chaque extremite.
	_px(img, o, 2, 14, wood.darkened(0.18))
	_px(img, o, 3, 14, dark)
	_px(img, o, 12, 3, light)
	_px(img, o, 13, 3, dark)


static func _paint_apple_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Pomme ronde rouge, reflet clair et petite feuille.
	var base := Color(0.78, 0.12, 0.12)
	for y in range(4, 13):
		for x in range(4, 13):
			var d := absi(x - 8) + absi(y - 9)
			if d > 5 or (d == 5 and r.randf() < 0.5):
				continue
			_px(img, o, x, y, _jitter(base, 0.05, r))
	for i in 4:
		_px(img, o, r.randi_range(5, 7), r.randi_range(5, 7), Color(1.0, 0.55, 0.55))
	_px(img, o, 8, 3, Color(0.35, 0.22, 0.10))
	_px(img, o, 10, 2, Color(0.25, 0.55, 0.20))
	_px(img, o, 11, 2, Color(0.25, 0.55, 0.20))


static func _paint_coal_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	# Moreau de charbon : une masse anguleuse, une face prise de lumiere en haut
	# a gauche, un coeur plus noir. Un simple rond sombre se perdait sur le fond
	# gris fonce de la barre rapide — l'objet le plus courant du jeu etait celui
	# qu'on voyait le moins.
	var base := Color(0.13, 0.13, 0.15)
	var facet := Color(0.26, 0.26, 0.30)
	for y in range(4, 13):
		for x in range(4, 13):
			var d := absi(x - 8) + absi(y - 8)
			if d > 4:
				continue
			var tone := base
			if d <= 1:
				tone = base.darkened(0.45)
			elif x + y <= 13:
				tone = facet
			_px(img, o, x, y, _jitter(tone, 0.03, r))
	# Reflet en haut a gauche : c'est lui qui fait lire le volume.
	_px(img, o, 7, 5, Color(0.40, 0.40, 0.45))
	_px(img, o, 6, 6, Color(0.44, 0.44, 0.49))
	_px(img, o, 5, 7, facet)


static func _paint_raw_iron_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	var base := Color(0.79, 0.70, 0.63)
	for y in range(5, 12):
		for x in range(4, 13):
			if absi(x - 8) + absi(y - 8) > 4 + r.randf() * 1.5:
				continue
			_px(img, o, x, y, _jitter(base, 0.07, r))
	_px(img, o, 6, 6, base.lightened(0.28))
	_px(img, o, 9, 10, base.darkened(0.30))


static func _paint_iron_ingot_icon(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	var metal := Color(0.88, 0.88, 0.90)
	for y in range(6, 12):
		var inset := (y - 6) / 2
		for x in range(3 + inset, 13 - inset):
			_px(img, o, x, y, _jitter(metal, 0.03, r))
	for x in range(5, 11):
		_px(img, o, x, 6, Color(0.99, 0.99, 1.0))
	for x in range(4, 12):
		_px(img, o, x, 11, metal.darkened(0.35))


static func _paint_pickaxe(img: Image, o: Vector2i, r: RandomNumberGenerator, head: Color) -> void:
	# Manche : une diagonale de deux pixels, du coin bas-gauche au centre de la
	# tete. Il s'arrete sous l'arc, il ne le traverse pas.
	var handle := Color(0.52, 0.37, 0.20)
	for i in 10:
		var t := float(i) / 9.0
		var x := 3 + int(round(t * 4.0))
		var y := 14 - int(round(t * 9.0))
		_px(img, o, x, y, handle)
		_px(img, o, x + 1, y, handle.lightened(0.22))
	# Tete : un arc large de neuf pixels dont les deux pointes retombent. Une
	# barre droite se lirait comme une hache ; c'est la retombee des extremites
	# qui fait la pioche.
	for i in 9:
		var x := 3 + i
		var droop := int(round(absf(float(i) - 4.0) * 0.7))
		var y := 3 + droop
		_px(img, o, x, y, _jitter(head, 0.03, r))
		_px(img, o, x, y + 1, head.darkened(0.32))
	# Lumiere sur le dessus de l'arc, ombre sous les pointes.
	_px(img, o, 5, 3, head.lightened(0.30))
	_px(img, o, 6, 3, head.lightened(0.42))
	_px(img, o, 7, 3, head.lightened(0.36))
	_px(img, o, 8, 3, head.lightened(0.22))
	_px(img, o, 3, 6, head.darkened(0.20))
	_px(img, o, 11, 6, head.darkened(0.20))


# ------------------------------------- tuiles ajoutees (repli sans assets CC0)
#
# Ces tuiles ne servent que si le dossier `assets/kenney/` est absent. Avec les
# images tierces, `ExternalTiles` les recouvre et ces fonctions ne sont jamais
# appelees — mais elles restent le filet de securite du projet : la peinture par
# le code doit toujours suffire a faire tourner le jeu.

## Verre : un cadre clair et un centre laisse vide. Le centre est **transparent**,
## pas blanc : le bloc est marque non opaque, donc il part dans la surface
## alpha-cut, et c'est ce trou qui laisse voir ce qu'il y a derriere.
static func _paint_glass(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	for y in PX:
		for x in PX:
			# Le cadre fait 2 pixels de large : c'est lui qui porte l'epi de
			# verre, le centre ne garde qu'un voile tres leger.
			var edge := x < 2 or y < 2 or x >= PX - 2 or y >= PX - 2
			var c := Color(0.82, 0.90, 0.94, 0.92) if edge else Color(0.78, 0.88, 0.94, 0.16)
			_px(img, o, x, y, _jitter(c, 0.02, r))
	# Un reflet oblique : deux lignes claires, le seul détail qui distingue le
	# verre d'un carre bleu pale.
	for i in 5:
		_px(img, o, 3 + i, 11 - i, Color(1, 1, 1, 0.55))
		_px(img, o, 4 + i, 11 - i, Color(1, 1, 1, 0.30))


static func _paint_brick(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.36, 0.20, 0.16), 0.03, r)
	for row in 4:
		# Decalage d'une rangee sur deux : c'est ce qui fait lire le mur comme
		# un appareil regulier plutot que comme des bandes.
		var shift := 0 if row % 2 == 0 else 4
		for col in 2:
			var bx := col * 8 + shift
			var by := row * 4
			var tone := Color(0.68, 0.32, 0.26).lerp(Color(0.78, 0.40, 0.32), r.randf())
			for y in 3:
				for x in 7:
					_px(img, o, bx + x, by + y, _jitter(tone, 0.045, r))
			_px(img, o, bx, by, tone.lightened(0.18))
			_px(img, o, bx + 6, by + 2, tone.darkened(0.18))


static func _paint_ice(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.66, 0.80, 0.95), 0.05, r)
	# Les fentes : deux diagonales croisees, comme dans la glace cassee.
	for i in 9:
		var c := Color(0.86, 0.94, 1.0, 0.9)
		_px(img, o, 3 + i, 3 + i, c)
		_px(img, o, 11 - i, 3 + i, c)
	for i in 4:
		_px(img, o, 6 + i, 9 - i, Color(0.92, 0.97, 1.0, 0.75))


## Lave : les memes harmoniques entieres que l'eau, pour que la tuile se
## raccorde a elle-meme. La couleur, elle, est fixe — c'est la lumiere du bloc
## qui fait le reste.
static func _paint_lava(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	for y in PX:
		for x in PX:
			var v := sin(TAU * (x * 2 + y) / PX) + sin(TAU * (x - 2 * y) / PX)
			var t := (v + 2.0) * 0.25
			_px(img, o, x, y, Color(0.85, 0.28, 0.05).lerp(Color(1.0, 0.82, 0.18), t))


static func _paint_cactus_side(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.20, 0.48, 0.22), 0.04, r)
	# Les aretes du corps : deux colonnes plus sombres de part et d'autre.
	for y in PX:
		_px(img, o, 0, y, Color(0.14, 0.34, 0.16))
		_px(img, o, PX - 1, y, Color(0.14, 0.34, 0.16))
		for i in 3:
			_px(img, o, 4 + i, y, Color(0.13, 0.33, 0.14))
	# Quelques epines.
	for i in 5:
		_px(img, o, 2 + (i * 5) % 11, 2 + (i * 7) % 12, Color(0.85, 0.88, 0.70))


static func _paint_cactus_top(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.24, 0.54, 0.25), 0.04, r)
	# Cerne exterieur et coeur plus clair : vu de dessus, un cactus est un
	# disque, pas un carre.
	for i in PX:
		_px(img, o, i, 0, Color(0.15, 0.36, 0.17))
		_px(img, o, i, PX - 1, Color(0.15, 0.36, 0.17))
		_px(img, o, 0, i, Color(0.15, 0.36, 0.17))
		_px(img, o, PX - 1, i, Color(0.15, 0.36, 0.17))
	for y in range(4, 12):
		for x in range(4, 12):
			_px(img, o, x, y, _jitter(Color(0.30, 0.62, 0.30), 0.04, r))


static func _paint_planks_red(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.56, 0.26, 0.18), 0.04, r)
	for row in 4:
		var by := row * 4
		var tone := Color(0.66, 0.32, 0.22).lerp(Color(0.74, 0.38, 0.26), r.randf())
		for x in PX:
			_px(img, o, x, by, tone.darkened(0.30))
		for y in range(1, 4):
			for x in PX:
				_px(img, o, x, by + y, _jitter(tone, 0.035, r))
		# Joint vertical decale d'une planche a l'autre.
		var seam := 3 + (row * 5) % 10
		for y in range(by + 1, by + 4):
			_px(img, o, seam, y, tone.darkened(0.32))


static func _paint_red_sand(img: Image, o: Vector2i, r: RandomNumberGenerator) -> void:
	_noise_fill(img, o, Color(0.80, 0.47, 0.29), 0.05, r)
	_speckle(img, o, Color(0.80, 0.47, 0.29), 22, 0.10, r)
	_speckle(img, o, Color(0.62, 0.33, 0.19), 6, 0.05, r)


## Minerai a la facon de `_paint_coal_ore` : des taches de la couleur du metal
## sur la roche, plus quelques pixels pales qui font briller.
static func _paint_ore(img: Image, o: Vector2i, r: RandomNumberGenerator,
		color: Color, count: int) -> void:
	_noise_fill(img, o, Color(0.42, 0.42, 0.44), 0.05, r)
	for i in count:
		var cx := r.randi_range(1, PX - 3)
		var cy := r.randi_range(1, PX - 3)
		var w := r.randi_range(2, 3)
		for y in w:
			for x in w:
				_px(img, o, cx + x, cy + y, _jitter(color, 0.05, r))
		_px(img, o, cx, cy, color.lightened(0.30))


## Repli des gemmes : un losange facette sur fond vide. Recolore par l'appelant
## a travers le parametre `gem`.
static func _paint_gem_icon(img: Image, o: Vector2i, r: RandomNumberGenerator,
		gem: Color) -> void:
	_img_clear(img, o)
	for row in 7:
		var half := 3 if row < 4 else 6 - row
		for x in range(7 - half, 8 + half):
			_px(img, o, x, row + 5, _jitter(gem, 0.05, r))
	# Deux facettes claires : sans elles le losange est plat.
	for y in range(5, 8):
		_px(img, o, 5, y, gem.lightened(0.45))
	_px(img, o, 6, 6, gem.lightened(0.30))
	for y in range(9, 12):
		_px(img, o, 10 - y, y, gem.darkened(0.28))


static func _img_clear(img: Image, o: Vector2i) -> void:
	for y in PX:
		for x in PX:
			_px(img, o, x, y, Color(0, 0, 0, 0))


# -------------------------------------------------------------- dispatch

static func _paint_tile(img: Image, tile: int) -> void:
	var o := _origin(tile)
	var r := _rng(tile)
	match tile:
		Tiles.GRASS_TOP: _paint_grass_top(img, o, r)
		Tiles.GRASS_SIDE: _paint_grass_side(img, o, r)
		Tiles.DIRT: _paint_dirt(img, o, r)
		Tiles.STONE: _paint_stone(img, o, r)
		Tiles.COBBLE: _paint_cobble(img, o, r)
		Tiles.SAND: _paint_sand(img, o, r)
		Tiles.GRAVEL: _paint_gravel(img, o, r)
		Tiles.BEDROCK: _paint_bedrock(img, o, r)
		Tiles.LOG_SIDE: _paint_log_side(img, o, r)
		Tiles.LOG_TOP: _paint_log_top(img, o, r)
		Tiles.LEAVES: _paint_leaves(img, o, r)
		Tiles.PLANKS: _paint_planks(img, o, r)
		Tiles.WATER: _paint_water(img, o, r)
		Tiles.SNOW_TOP: _paint_snow_top(img, o, r)
		Tiles.SNOW_SIDE: _paint_snow_side(img, o, r)
		Tiles.COAL_ORE: _paint_coal_ore(img, o, r)
		Tiles.IRON_ORE: _paint_iron_ore(img, o, r)
		Tiles.TABLE_TOP: _paint_table_top(img, o, r)
		Tiles.TABLE_SIDE: _paint_table_side(img, o, r)
		Tiles.TABLE_FRONT: _paint_table_front(img, o, r)
		Tiles.TORCH: _paint_torch(img, o, r)
		Tiles.IRON_BLOCK: _paint_iron_block(img, o, r)
		Tiles.TOOL_STICK: _paint_stick_icon(img, o, r)
		Tiles.TOOL_COAL: _paint_coal_icon(img, o, r)
		Tiles.TOOL_RAW_IRON: _paint_raw_iron_icon(img, o, r)
		Tiles.TOOL_IRON_INGOT: _paint_iron_ingot_icon(img, o, r)
		Tiles.TOOL_WOOD_PICKAXE: _paint_pickaxe(img, o, r, C_PLANKS)
		Tiles.TOOL_STONE_PICKAXE: _paint_pickaxe(img, o, r, Color(0.52, 0.52, 0.54))
		Tiles.TOOL_IRON_PICKAXE: _paint_pickaxe(img, o, r, Color(0.90, 0.90, 0.92))
		Tiles.APPLE: _paint_apple_icon(img, o, r)
		Tiles.LAPI_ORE: _paint_lapis_ore(img, o, r)
		Tiles.ENCHANT_TOP: _paint_enchant_top(img, o, r)
		Tiles.ENCHANT_SIDE: _paint_enchant_side(img, o, r)
		Tiles.ENCHANT_FRONT: _paint_enchant_front(img, o, r)
		Tiles.LAPIS: _paint_lapis_icon(img, o, r)
		Tiles.PORKCHOP: _paint_porkchop_icon(img, o, r)
		Tiles.TOOL_WOOD_SWORD: _paint_sword(img, o, r, C_PLANKS)
		Tiles.TOOL_STONE_SWORD: _paint_sword(img, o, r, Color(0.60, 0.60, 0.62))
		Tiles.TOOL_IRON_SWORD: _paint_sword(img, o, r, Color(0.92, 0.92, 0.94))
		Tiles.GLASS: _paint_glass(img, o, r)
		Tiles.BRICK: _paint_brick(img, o, r)
		Tiles.ICE: _paint_ice(img, o, r)
		Tiles.LAVA: _paint_lava(img, o, r)
		Tiles.CACTUS_SIDE: _paint_cactus_side(img, o, r)
		Tiles.CACTUS_TOP: _paint_cactus_top(img, o, r)
		Tiles.PLANKS_RED: _paint_planks_red(img, o, r)
		Tiles.GOLD_ORE: _paint_ore(img, o, r, Color(0.95, 0.80, 0.25), 5)
		Tiles.DIAMOND_ORE: _paint_ore(img, o, r, Color(0.35, 0.85, 0.85), 5)
		Tiles.RED_SAND: _paint_red_sand(img, o, r)
		Tiles.TOOL_GEM: _paint_gem_icon(img, o, r, Color(0.45, 0.90, 0.90))
		_: pass
