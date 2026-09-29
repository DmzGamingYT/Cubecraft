class_name WorldGen
extends RefCounted

## Generateur procedural du monde.
##
## Une instance represente un germe (= un monde) et n'est PAS partagee entre
## threads : chaque tache de generation en cree une propre, ce qui evite tout
## acces concurrent aux ressources FastNoiseLite.
##
## Les arbres sont places par cellules de 5x5 derivees d'un hash des
## coordonnees monde. Chaque chunk balaye les cellules de son voisinage et
## n'ecrit que la partie de l'arbre qui tombe dans ses propres limites : deux
## chunks voisins generes independamment produisent toujours le meme arbre,
## sans jamais avoir besoin d'ecrire dans les donnees d'un autre chunk.

const TREE_CELL := 5
const TREE_SCAN := 1  # cellules balayes autour du chunk

const BASE_HEIGHT := 40
## Les deux champs de bruit doivent etre proches de zero simultanement : leurs
## surfaces d'isoszero s'intersectent en tunnels sinueux plutot qu'en poches.
const CAVE_SQUARE_LIMIT := 0.010

var seed_value: int

var _n_height: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_temp: FastNoiseLite
var _n_humid: FastNoiseLite
var _n_cave: FastNoiseLite
var _n_cave2: FastNoiseLite
var _n_ore_coal: FastNoiseLite
var _n_ore_iron: FastNoiseLite
var _n_gravel: FastNoiseLite
var _n_ore_gold: FastNoiseLite
var _n_ore_diamond: FastNoiseLite


func _init(world_seed: int = 0) -> void:
	seed_value = world_seed
	_n_height = _make(0.0040, 4, world_seed + 1)
	_n_detail = _make(0.0210, 3, world_seed + 2, 0.45)
	_n_ridge = _make(0.0016, 3, world_seed + 3)
	_n_temp = _make(0.0045, 2, world_seed + 4)
	_n_humid = _make(0.0040, 2, world_seed + 5)
	_n_cave = _make(0.0210, 2, world_seed + 6)
	_n_cave2 = _make(0.0420, 2, world_seed + 7)
	_n_ore_coal = _make(0.1150, 1, world_seed + 8)
	_n_ore_iron = _make(0.1300, 1, world_seed + 9)
	_n_gravel = _make(0.0900, 1, world_seed + 10)
	# Or et diamant : un bruit **plus rare** que celui du charbon, c'est ce qui
	# rend la descente payante. Les seuils sont plus hauts et la profondeur plus
	# faible, donc il faut creuser vraiment pour les rencontrer.
	_n_ore_gold = _make(0.1500, 1, world_seed + 11)
	_n_ore_diamond = _make(0.1800, 1, world_seed + 12)


static func _make(frequency: float, octaves: int, s: int, gain: float = 0.5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	return n


# ------------------------------------------------------------------ colonnes

## Hauteur du terrain (index y du dernier bloc de surface).
func height_at(x: int, z: int) -> int:
	return _height_from(x, z, _n_height.get_noise_2d(x, z))


func _height_from(x: int, z: int, primary: float) -> int:
	var h := BASE_HEIGHT + primary * 17.0 + _n_detail.get_noise_2d(x, z) * 4.0
	# Relief montagneux : au-dela d'un seuil, la hauteur explose.
	var ridge := _n_ridge.get_noise_2d(x, z)
	if ridge > 0.42:
		h += (ridge - 0.42) * 105.0
	return clampi(int(round(h)), Vox.BEDROCK_HEIGHT + 1, Vox.CHUNK_Y - 12)


func biome_at(x: int, z: int) -> int:
	return biome_for(x, z, height_at(x, z))


func biome_for(x: int, z: int, h: int) -> int:
	if h > 64:
		return Biomes.MOUNTAIN
	var t := _n_temp.get_noise_2d(x, z)
	var w := _n_humid.get_noise_2d(x, z)
	if t < -0.26:
		return Biomes.SNOWY
	if t > 0.28 and w < -0.02:
		return Biomes.DESERT
	if w > 0.16:
		return Biomes.FOREST
	return Biomes.PLAINS


# --------------------------------------------------------------- generation

## Remplit `blocks` (un chunk 16 x 96 x 16) et renvoie [min_y, max_y] occupes.
func generate_chunk(cx: int, cz: int, blocks: PackedByteArray) -> Vector2i:
	var ox := cx * Vox.CHUNK_X
	var oz := cz * Vox.CHUNK_Z
	var top := Vox.BEDROCK_HEIGHT

	for lz in Vox.CHUNK_Z:
		for lx in Vox.CHUNK_X:
			var wx := ox + lx
			var wz := oz + lz
			var h := _height_from(wx, wz, _n_height.get_noise_2d(wx, wz))
			_fill_column(blocks, lx, lz, wx, wz, h, biome_for(wx, wz, h))
			top = maxi(top, h + maxi(0, Vox.SEA_LEVEL - h))

	# Les arbres depassent la cime du terrain : leurs bornes doivent entrer
	# dans `top`, sans quoi le mailleur s'arrete sous les couronnes et les
	# sommets des arbres sont coupes.
	top = maxi(top, _plant_trees(cx, cz, blocks))

	return Vector2i(0, clampi(top + 1, 0, Vox.CHUNK_Y - 1))


func _fill_column(blocks: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		h: int, biome: int) -> void:
	var surface := Blocks.GRASS
	var filler := Blocks.DIRT
	var filler_depth := 3
	match biome:
		Biomes.DESERT:
			surface = Blocks.SAND
			filler = Blocks.SAND
			filler_depth = 4
		Biomes.SNOWY:
			surface = Blocks.SNOW
			filler = Blocks.DIRT
			filler_depth = 3
		Biomes.MOUNTAIN:
			surface = Blocks.STONE
			filler = Blocks.STONE
			filler_depth = 2
		_:
			pass

	# Sol sous l'eau : sable (ou galets en montagne) plutot que de l'herbe.
	if h < Vox.SEA_LEVEL:
		surface = Blocks.GRAVEL if biome == Biomes.MOUNTAIN else Blocks.SAND
		filler = Blocks.SAND
		filler_depth = 2

	for y in range(Vox.BEDROCK_HEIGHT):
		blocks[Vox.index(lx, y, lz)] = Blocks.BEDROCK

	# Roche, terre de surface, puis blocs specialises (minerais, cavernes).
	for y in range(Vox.BEDROCK_HEIGHT, h + 1):
		var bid: int
		if y == h:
			bid = surface
		elif y > h - filler_depth:
			bid = filler
		else:
			bid = _special_block(wx, y, wz, h)
			# On perce la roche mais jamais la couche de surface, sinon le ciel
			# s'effondre dans les grottes.
			if y > Vox.BEDROCK_HEIGHT and y < h - 3 and _is_cave(wx, y, wz):
				bid = Blocks.AIR
		blocks[Vox.index(lx, y, lz)] = bid

	# Nappe d'eau jusqu'au niveau de la mer.
	for y in range(h + 1, Vox.SEA_LEVEL + 1):
		blocks[Vox.index(lx, y, lz)] = Blocks.WATER


## Minerais et galets, uniquement dans la roche profonde.
func _special_block(wx: int, y: int, wz: int, h: int) -> int:
	if y >= h - 1:
		return Blocks.STONE
	if y <= 46 and _n_ore_iron.get_noise_3d(wx, y * 1.6, wz) > 0.78:
		return Blocks.IRON_ORE
	if y <= 62 and _n_ore_coal.get_noise_3d(wx, y * 1.4, wz) > 0.72:
		return Blocks.COAL_ORE
	if y <= 52 and _n_gravel.get_noise_3d(wx, y * 1.3, wz) > 0.84:
		return Blocks.GRAVEL
	# Le diamant est le plus profond des quatre, et de loin le plus rare :
	# il ne se trouve qu'entre la roche mere et le niveau 20, la ou la
	# grotte a eu le temps de s'effondrer autour de lui.
	if y <= 20 and _n_ore_diamond.get_noise_3d(wx, y * 1.7, wz) > 0.88:
		return Blocks.DIAMOND_ORE
	if y <= 34 and _n_ore_gold.get_noise_3d(wx, y * 1.5, wz) > 0.84:
		return Blocks.GOLD_ORE
	return Blocks.STONE


func _is_cave(wx: int, y: int, wz: int) -> bool:
	var c1 := _n_cave.get_noise_3d(wx, y * 2.0, wz)
	var c2 := _n_cave2.get_noise_3d(wx, y * 2.0, wz)
	return c1 * c1 + c2 * c2 < CAVE_SQUARE_LIMIT


# -------------------------------------------------------------------- arbres

## Plante les arbres dont les racines tombent dans ce chunk (y compris ceux
## dont les couronnes debordent depuis un voisin) et renvoie la hauteur
## maximale atteinte, pour etendre les bornes de maillage.
func _plant_trees(cx: int, cz: int, blocks: PackedByteArray) -> int:
	var ox := cx * Vox.CHUNK_X
	var oz := cz * Vox.CHUNK_Z
	var reach := Vox.CHUNK_X + TREE_CELL * TREE_SCAN
	var cell_min := int(floor(float(ox - TREE_CELL * TREE_SCAN) / float(TREE_CELL)))
	var cell_max := int(floor(float(ox + reach) / float(TREE_CELL)))
	var top := 0

	for gz in range(cell_min, cell_max + 1):
		for gx in range(cell_min, cell_max + 1):
			var h := _hash(gx, gz)
			var tx := gx * TREE_CELL + (h % TREE_CELL)
			var tz := gz * TREE_CELL + ((h >> 8) % TREE_CELL)
			var roll := float((h >> 16) % 4096) / 4096.0

			var hgt := height_at(tx, tz)
			if hgt <= Vox.SEA_LEVEL + 1 or hgt > 74:
				continue
			var biome := biome_at(tx, tz)
			if roll > Biomes.tree_density(biome):
				continue
			top = maxi(top, _grow_tree(tx, hgt + 1, tz, biome, ox, oz, blocks))
	return top


## Plante un arbre et renvoie la hauteur du bloc le plus haut qu'il ecrit.
func _grow_tree(tx: int, base_y: int, tz: int, biome: int, ox: int, oz: int,
		blocks: PackedByteArray) -> int:
	var spruce := Biomes.is_spruce(biome)
	var trunk := 4 + (_hash(tx + 17, tz - 31) >> 24) % 3
	if spruce:
		trunk += 2

	for y in range(base_y, base_y + trunk):
		_put(blocks, tx, y, tz, Blocks.LOG, ox, oz)

	if spruce:
		# Epicéa : un cône, large en bas et pointu en haut. Les rayons se
		# comptent **depuis le bas**.
		#
		# La version precedente les comptait depuis le haut (`top - 1 - layer`),
		# si bien que l'etage large se retrouvait au sommet et les trois etages
		# etroits en dessous : un parasol retourne. Comme `face_visible` masque
		# les faces internes du feuillage, il n'y a rien derriere la surface
		# d'une couronne — et de dessous, sous l'assiette large, on voyait donc
		# le ciel *a travers l'arbre*. C'est exactement ce que le joueur
		# signalait : « je vois a travers les feuillages ».
		var tip := base_y + trunk
		for layer in 5:
			var y := tip - 5 + layer
			# Un losange de 13 blocs en bas, puis quatre etages de 3.
			var r := 2 if layer == 0 else 1
			for lx in range(-r, r + 1):
				for lz in range(-r, r + 1):
					if r == 2 and absi(lx) + absi(lz) > 2:
						continue
					_put(blocks, tx + lx, y, tz + lz, Blocks.LEAVES, ox, oz)
		_put(blocks, tx, tip, tz, Blocks.LEAVES, ox, oz)
		return tip

	# Chene : une couronne ronde de quatre etages, du plus large en bas au plus
	# etroit en haut. La version precedente n'en avait que trois, dont le
	# dernier etait un simple plus : une couronne de 5 de large pour 3 de haut,
	# posee au sommet d'un tronc de 4 a 6 blocs. De profil, l'arbre se lisait
	# comme une assiette verte au bout d'un baton. Un etage de plus, et le
	# sommet qui s'arrete au plus, font une vraie boule.
	var head := base_y + trunk
	for layer in 4:
		var ly := head - 1 + layer
		var r := 2 if layer <= 1 else 1
		for lx in range(-r, r + 1):
			for lz in range(-r, r + 1):
				if r == 2:
					# Coins arraches, avec retenue : la couronne basse en perd
					# quelques-uns, celle du dessus presque aucun. Un quart de la
					# couronne en moins suffisait a rendre la silhouette irreguliere
					# sans la trouer, et le feuillage se dessine maintenant a
					# l'interieur : le peu de trous qu'il reste montre des feuilles,
					# pas le ciel.
					if absi(lx) == 2 and absi(lz) == 2:
						var drop := 45 if layer == 0 else 15
						if _hash(tx + lx, tz + lz + layer * 31) % 100 < drop:
							continue
				elif layer == 3 and absi(lx) + absi(lz) > 1:
					continue
				_put(blocks, tx + lx, ly, tz + lz, Blocks.LEAVES, ox, oz)
	return head + 2


## Ecrit un bloc seulement s'il tombe dans les limites du chunk en cours, et
## seulement sur une cellule qu'un arbre a le droit de remplacer.
func _put(blocks: PackedByteArray, wx: int, y: int, wz: int, bid: int, ox: int, oz: int) -> void:
	if y < 0 or y >= Vox.CHUNK_Y:
		return
	var lx := wx - ox
	var lz := wz - oz
	if lx < 0 or lx >= Vox.CHUNK_X or lz < 0 or lz >= Vox.CHUNK_Z:
		return
	var idx := Vox.index(lx, y, lz)
	var existing := blocks[idx]
	if existing != Blocks.AIR and existing != Blocks.WATER and existing != Blocks.LEAVES:
		return
	blocks[idx] = bid


# -------------------------------------------------------------------- hash

static func _hash(a: int, b: int) -> int:
	var h := (a * 374761393 + b * 668265263 + 7919) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	return (h ^ (h >> 16)) & 0x7FFFFFFF
