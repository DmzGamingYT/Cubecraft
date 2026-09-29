class_name Recipes
extends RefCounted

## Recettes de fabrication.
##
## Deux formes :
##   {"shapeless": [id, ...], "out": id, "count": n}  -- ordre indifferent
##   {"shape": [[id, ...], ...], "out": id, "count": n} -- schema impose
##
## L'appariement se fait dans une grille carree `size` x `size` (2 ou 3). Un
## schema plus petit que la grille est essaye a toutes les positions, a
## condition que rien d'autre n'occupe la grille.

const EMPTY := -1

static var all: Array = _build()


static func _build() -> Array:
	var plank := Items.block_item(Blocks.PLANKS)
	var cobble := Items.block_item(Blocks.COBBLESTONE)
	var ingot := Items.IRON_INGOT

	return [
		# --- Conversions
		{"shapeless": [Items.block_item(Blocks.LOG)], "out": plank, "count": 4},
		{"shape": [[plank], [plank]], "out": Items.STICK, "count": 4},
		{"shapeless": [Items.RAW_IRON, Items.COAL], "out": ingot, "count": 1},

		# --- Mobilier
		{"shape": [[plank, plank], [plank, plank]],
			"out": Items.block_item(Blocks.CRAFTING_TABLE), "count": 1},
		{"shapeless": [Items.STICK, Items.COAL], "out": Items.block_item(Blocks.TORCH), "count": 4},

		# --- Outils : une pioche par palier de minage
		{"shape": [[plank, plank, plank], [EMPTY, Items.STICK, EMPTY], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.WOOD_PICKAXE, "count": 1},
		{"shape": [[cobble, cobble, cobble], [EMPTY, Items.STICK, EMPTY], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.STONE_PICKAXE, "count": 1},
		{"shape": [[ingot, ingot, ingot], [EMPTY, Items.STICK, EMPTY], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.IRON_PICKAXE, "count": 1},

		# --- Epees : combat contre les monstres
		{"shape": [[plank, plank], [plank, plank], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.WOOD_SWORD, "count": 1},
		{"shape": [[cobble, cobble], [cobble, cobble], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.STONE_SWORD, "count": 1},
		{"shape": [[ingot, ingot], [ingot, ingot], [EMPTY, Items.STICK, EMPTY]],
			"out": Items.IRON_SWORD, "count": 1},

		# --- Compression
		{"shape": [
			[ingot, ingot, ingot],
			[ingot, ingot, ingot],
			[ingot, ingot, ingot]],
			"out": Items.block_item(Blocks.IRON_BLOCK), "count": 1},
		{"shape": [
			[Items.LAPIS, Items.LAPIS, Items.LAPIS],
			[Items.LAPIS, Items.LAPIS, Items.LAPIS],
			[Items.LAPIS, Items.LAPIS, Items.LAPIS]],
			"out": Items.block_item(Blocks.LAPI_ORE), "count": 1},

		# --- Table d'enchantement : planches + lapis, comme l'original
		{"shape": [
			[EMPTY, Items.LAPIS, EMPTY],
			[Items.LAPIS, Items.block_item(Blocks.IRON_BLOCK), Items.LAPIS],
			[EMPTY, Items.LAPIS, EMPTY]],
			"out": Items.block_item(Blocks.ENCHANTING_TABLE), "count": 1},

		# --- Materiaux et blocs ajoutes apres coup.
		# Outils en diamant : ils n'ouvrent rien sans le minerai de diamant,
		# et le minerai de diamant ne s'ouvre qu'avec eux. C'est le seul acces
		# au palier 4, et il se ferme entierement si on oublie l'un des deux.
		{"shape": [
			[Items.DIAMOND, Items.DIAMOND, Items.DIAMOND],
			[EMPTY, Items.STICK, EMPTY],
			[EMPTY, Items.STICK, EMPTY]],
			"out": Items.DIAMOND_PICKAXE, "count": 1},
		{"shape": [
			[Items.DIAMOND, Items.DIAMOND],
			[Items.DIAMOND, Items.DIAMOND],
			[EMPTY, Items.STICK, EMPTY]],
			"out": Items.DIAMOND_SWORD, "count": 1},
		# Verre : du sable fondu, donc une recette d'etabli qui ne demande
		# aucune ressource nouvelle a miner.
		{"shape": [[Items.block_item(Blocks.SAND), Items.block_item(Blocks.SAND)],
			[Items.block_item(Blocks.SAND), Items.block_item(Blocks.SAND)]],
			"out": Items.block_item(Blocks.GLASS), "count": 1},
		# Briques : quatre moellons. L'argile n'est pas un bloc du registre, on
		# part donc du materiau qu'on a deja sous la main plutot que d'ajouter
		# un maillon de plus a la chaine de survival.
		{"shapeless": [cobble, cobble, cobble, cobble],
			"out": Items.block_item(Blocks.BRICK), "count": 1},
	]


## Recette correspondant a une grille, ou {} si rien ne correspond.
## `grid` : Array de size*size, EMPTY pour un emplacement vide.
static func match(grid: Array, size: int) -> Dictionary:
	for recipe in all:
		var ok := false
		if recipe.has("shapeless"):
			ok = _shapeless_ok(grid, recipe["shapeless"])
		else:
			ok = _shaped_ok(grid, size, recipe["shape"])
		if ok:
			return {"id": int(recipe["out"]), "count": int(recipe["count"])}
	return {}


static func _shapeless_ok(grid: Array, ingredients: Array) -> bool:
	var need: Dictionary = {}
	for item_id in ingredients:
		need[item_id] = int(need.get(item_id, 0)) + 1
	var have: Dictionary = {}
	for item_id in grid:
		if item_id == EMPTY:
			continue
		have[item_id] = int(have.get(item_id, 0)) + 1
	return have == need


## Essaie le schema a toutes les positions possibles dans la grille.
static func _shaped_ok(grid: Array, size: int, shape: Array) -> bool:
	var pattern := _trim(shape)
	if pattern.is_empty():
		return false
	var ph: int = pattern.size()
	var pw: int = (pattern[0] as Array).size()
	if pw > size or ph > size:
		return false

	for oy in range(size - ph + 1):
		for ox in range(size - pw + 1):
			if _place_ok(grid, size, pattern, ox, oy):
				return true
	return false


static func _place_ok(grid: Array, size: int, pattern: Array, ox: int, oy: int) -> bool:
	var pw: int = (pattern[0] as Array).size()
	var ph: int = pattern.size()
	# Chaque case du schema doit correspondre — y compris les cases vides du
	# schema, qui doivent l'etre reellement dans la grille.
	for y in ph:
		var row: Array = pattern[y]
		for x in pw:
			if int(grid[(oy + y) * size + ox + x]) != int(row[x]):
				return false
	# Et rien ne doit deborder autour du schema.
	for y in size:
		for x in size:
			if x >= ox and x < ox + pw and y >= oy and y < oy + ph:
				continue
			if int(grid[y * size + x]) != EMPTY:
				return false
	return true


## Retire les lignes et colonnes entierement vides d'un schema.
static func _trim(shape: Array) -> Array:
	var rows: Array = []
	for y in shape.size():
		var row: Array = shape[y]
		var empty := true
		for x in row.size():
			if int(row[x]) != EMPTY:
				empty = false
				break
		if not empty:
			rows.append(row)
	if rows.is_empty():
		return []

	var cols: int = (rows[0] as Array).size()
	var lo := 0
	var hi := cols - 1
	while lo <= hi and not _column_used(rows, lo):
		lo += 1
	while hi >= lo and not _column_used(rows, hi):
		hi -= 1
	if hi < lo:
		return []

	var top := 0
	var bottom := rows.size() - 1
	while top <= bottom and not _row_used(rows, top, lo, hi):
		top += 1
	while bottom >= top and not _row_used(rows, bottom, lo, hi):
		bottom -= 1
	if bottom < top:
		return []

	var out: Array = []
	for y in range(top, bottom + 1):
		var row: Array = []
		var source: Array = rows[y]
		for x in range(lo, hi + 1):
			row.append(int(source[x]))
		out.append(row)
	return out


static func _column_used(rows: Array, x: int) -> bool:
	for row in rows:
		if int((row as Array)[x]) != EMPTY:
			return true
	return false


static func _row_used(rows: Array, y: int, lo: int, hi: int) -> bool:
	var row: Array = rows[y]
	for x in range(lo, hi + 1):
		if int(row[x]) != EMPTY:
			return true
	return false
