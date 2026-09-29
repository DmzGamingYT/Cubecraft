class_name Blocks
extends RefCounted

## Catalogue de tous les types de blocs du jeu.
##
## Chaque bloc est decrit par un dictionnaire immuable :
##   name    : libelle affiche dans l'interface
##   tile    : tuile de l'atlas, ou {top, bottom, side} / {top, bottom, side, front}
##   solid   : genere de la collision
##   opaque  : masque les faces voisines (culling) et bloque la lumiere
##   shape   : "cube" | "cross" (croix billboard) | "liquid"
##   hardness: duree de minage en secondes avec l'outil ideal ; < 0 = incassable
##   tier    : palier d'outil requis pour obtenir un drop (0 main, 1 bois, 2 pierre, 3 fer)
##   tool    : outil prefere ("pickaxe" | "axe" | "shovel" | "")
##   drop    : item id obtenu, -1 pour "rien", ou SELF
##   tint    : nom du biome-tint applique aux sommets, "" sinon
##   light   : niveau de lumiere emis (torche)

enum {
	AIR,
	STONE,
	DIRT,
	GRASS,
	SAND,
	WATER,
	BEDROCK,
	LOG,
	LEAVES,
	PLANKS,
	COBBLESTONE,
	COAL_ORE,
	IRON_ORE,
	CRAFTING_TABLE,
	TORCH,
	SNOW,
	GRAVEL,
	IRON_BLOCK,
	LAPI_ORE,
	ENCHANTING_TABLE,
	# Blocs ajoutes apres l'etat initial. **Ajoutes, pas inseres** : l'identifiant
	# d'un bloc est ecrit dans les sauvegardes, et les renumeroter ferait
	# relire chaque monde deja enregistre avec le mauvais materiau. L'ordre
	# ci-dessous fait partie du format de sauvegarde.
	GLASS,
	BRICK,
	ICE,
	LAVA,
	CACTUS,
	RED_PLANKS,
	GOLD_ORE,
	DIAMOND_ORE,
	RED_SAND,
	COUNT,
}

const SELF := -2
const NOTHING := -1

## Formes de rendu.
enum Shape { CUBE, CROSS, LIQUID }

static var defs: Dictionary = _build_defs()


static func _build_defs() -> Dictionary:
	var d: Dictionary = {}

	d[AIR] = {
		"name": "Air", "tile": 0, "solid": false, "opaque": false, "shape": Shape.CUBE,
		"hardness": -1.0, "tier": 0, "tool": "", "drop": NOTHING, "tint": "", "light": 0,
	}

	d[STONE] = {
		"name": "Pierre", "tile": Tiles.STONE, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 1.5, "tier": 1, "tool": "pickaxe", "drop": COBBLESTONE, "tint": "", "light": 0,
	}
	d[DIRT] = {
		"name": "Terre", "tile": Tiles.DIRT, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.5, "tier": 0, "tool": "shovel", "drop": SELF, "tint": "", "light": 0,
	}
	d[GRASS] = {
		"name": "Herbe", "tile": {"top": Tiles.GRASS_TOP, "bottom": Tiles.DIRT, "side": Tiles.GRASS_SIDE},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.6, "tier": 0, "tool": "shovel", "drop": DIRT, "tint": "grass", "light": 0,
	}
	d[SAND] = {
		"name": "Sable", "tile": Tiles.SAND, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.5, "tier": 0, "tool": "shovel", "drop": SELF, "tint": "", "light": 0,
	}
	d[WATER] = {
		"name": "Eau", "tile": Tiles.WATER, "solid": false, "opaque": false, "shape": Shape.LIQUID,
		"hardness": -1.0, "tier": 0, "tool": "", "drop": NOTHING, "tint": "", "light": 0,
	}
	d[BEDROCK] = {
		"name": "Bedrock", "tile": Tiles.BEDROCK, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": -1.0, "tier": 99, "tool": "pickaxe", "drop": NOTHING, "tint": "", "light": 0,
	}
	d[LOG] = {
		"name": "Brique", "tile": {"top": Tiles.LOG_TOP, "bottom": Tiles.LOG_TOP, "side": Tiles.LOG_SIDE},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 2.0, "tier": 0, "tool": "axe", "drop": SELF, "tint": "", "light": 0,
	}
	d[LEAVES] = {
		"name": "Feuilles", "tile": Tiles.LEAVES, "solid": true, "opaque": false, "shape": Shape.CUBE,
		"hardness": 0.25, "tier": 0, "tool": "", "drop": NOTHING, "tint": "leaves", "light": 0,
	}
	d[PLANKS] = {
		"name": "Planches", "tile": Tiles.PLANKS, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 2.0, "tier": 0, "tool": "axe", "drop": SELF, "tint": "", "light": 0,
	}
	d[COBBLESTONE] = {
		"name": "Pierre taillée", "tile": Tiles.COBBLE, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 2.0, "tier": 1, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 0,
	}
	d[COAL_ORE] = {
		"name": "Minerai de charbon", "tile": Tiles.COAL_ORE, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 3.0, "tier": 1, "tool": "pickaxe", "drop": Items.COAL, "tint": "", "light": 0,
		"xp": 2,
	}
	d[IRON_ORE] = {
		"name": "Minerai de fer", "tile": Tiles.IRON_ORE, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 3.0, "tier": 2, "tool": "pickaxe", "drop": Items.RAW_IRON, "tint": "", "light": 0,
		"xp": 3,
	}
	d[CRAFTING_TABLE] = {
		"name": "Établi", "tile": {"top": Tiles.TABLE_TOP, "bottom": Tiles.PLANKS, "side": Tiles.TABLE_SIDE, "front": Tiles.TABLE_FRONT},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 2.5, "tier": 0, "tool": "axe", "drop": SELF, "tint": "", "light": 0,
	}
	d[TORCH] = {
		"name": "Torche", "tile": Tiles.TORCH, "solid": false, "opaque": false, "shape": Shape.CROSS,
		"hardness": 0.05, "tier": 0, "tool": "", "drop": SELF, "tint": "", "light": 14,
		"cross_inset": 0.4375, "cross_height": 0.625,
	}
	d[SNOW] = {
		"name": "Neige", "tile": {"top": Tiles.SNOW_TOP, "bottom": Tiles.DIRT, "side": Tiles.SNOW_SIDE},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.3, "tier": 0, "tool": "shovel", "drop": SELF, "tint": "", "light": 0,
	}
	d[GRAVEL] = {
		"name": "Gravier", "tile": Tiles.GRAVEL, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.6, "tier": 0, "tool": "shovel", "drop": SELF, "tint": "", "light": 0,
	}
	d[IRON_BLOCK] = {
		"name": "Bloc de fer", "tile": Tiles.IRON_BLOCK, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 5.0, "tier": 3, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 0,
	}
	d[LAPI_ORE] = {
		"name": "Minerai de lapis", "tile": Tiles.LAPI_ORE, "solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 3.0, "tier": 2, "tool": "pickaxe", "drop": Items.LAPIS, "tint": "", "light": 0,
		"xp": 3,
	}
	d[ENCHANTING_TABLE] = {
		"name": "Table d'enchantement",
		"tile": {"top": Tiles.ENCHANT_TOP, "bottom": Tiles.PLANKS,
			"side": Tiles.ENCHANT_SIDE, "front": Tiles.ENCHANT_FRONT},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 5.0, "tier": 0, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 7,
		"interact": "enchant",
	}

	# --- Blocs ajoutes apres coup. Meme contrat que les autres : une face
	# `tile`, la solidite, l'opacite, la duree, le palier d'outil et le drop.
	# Le verre est le premier bloc **non opaque** du jeu qui ne soit ni une
	# feuille ni un liquide : il part donc dans la surface alpha-cut comme eux,
	# et son centre transparent laisse voir ce qu'il y a derriere.

	d[GLASS] = {
		"name": "Verre", "tile": Tiles.GLASS, "solid": true, "opaque": false,
		"shape": Shape.CUBE,
		"hardness": 0.4, "tier": 0, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 0,
	}
	d[BRICK] = {
		"name": "Briques", "tile": Tiles.BRICK, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": 2.0, "tier": 0, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 0,
	}
	d[ICE] = {
		"name": "Glace", "tile": Tiles.ICE, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": 0.6, "tier": 0, "tool": "pickaxe", "drop": SELF, "tint": "", "light": 0,
	}
	d[LAVA] = {
		# Le seul bloc qui bouche les degats sans armer : c'est ce qui le rend
		# utile dans une base. Il emet de la lumiere, ce qui donne enfin un
		# interet au `light` des blocs autres que la torche.
		"name": "Lave", "tile": Tiles.LAVA, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": -1.0, "tier": 0, "tool": "", "drop": NOTHING, "tint": "", "light": 15,
		"hurt": 4.0,
	}
	d[CACTUS] = {
		"name": "Cactus", "tile": {"top": Tiles.CACTUS_TOP, "bottom": Tiles.CACTUS_TOP,
			"side": Tiles.CACTUS_SIDE},
		"solid": true, "opaque": true, "shape": Shape.CUBE,
		"hardness": 0.5, "tier": 0, "tool": "", "drop": SELF, "tint": "", "light": 0,
		"hurt": 1.0,
	}
	d[RED_PLANKS] = {
		"name": "Planches rouges", "tile": Tiles.PLANKS_RED, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": 2.0, "tier": 0, "tool": "axe", "drop": SELF, "tint": "", "light": 0,
	}
	d[GOLD_ORE] = {
		"name": "Minerai d'or", "tile": Tiles.GOLD_ORE, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": 3.0, "tier": 3, "tool": "pickaxe", "drop": Items.GOLD_INGOT,
		"tint": "", "light": 0,
	}
	d[DIAMOND_ORE] = {
		# Palier 4 : seul un outil en diamant l'ouvre. C'est la que sert la
		# pioche en diamant — sans elle, ce minerai serait du decor.
		"name": "Minerai de diamant", "tile": Tiles.DIAMOND_ORE, "solid": true,
		"opaque": true, "shape": Shape.CUBE,
		"hardness": 3.5, "tier": 4, "tool": "pickaxe", "drop": Items.DIAMOND,
		"tint": "", "light": 0,
	}
	d[RED_SAND] = {
		"name": "Sable rouge", "tile": Tiles.RED_SAND, "solid": true, "opaque": true,
		"shape": Shape.CUBE,
		"hardness": 0.5, "tier": 0, "tool": "shovel", "drop": SELF, "tint": "", "light": 0,
	}

	return d


static func def(id: int) -> Dictionary:
	return defs.get(id, defs[AIR])


static func name_of(id: int) -> String:
	return def(id)["name"]


static func is_solid(id: int) -> bool:
	return def(id)["solid"]


static func is_opaque(id: int) -> bool:
	return def(id)["opaque"]


static func is_liquid(id: int) -> bool:
	return def(id)["shape"] == Shape.LIQUID


static func is_cross(id: int) -> bool:
	return def(id)["shape"] == Shape.CROSS


static func shape_of(id: int) -> Shape:
	return def(id)["shape"]


static func light_of(id: int) -> int:
	return int(def(id).get("light", 0))


## Experience accordee en minant le bloc (0 si rien).
static func xp_of(id: int) -> int:
	return int(def(id).get("xp", 0))


## Interaction speciale du bloc ("enchant"), ou "" si aucune.
static func interact_of(id: int) -> String:
	return str(def(id).get("interact", ""))


static func tint_of(id: int) -> String:
	return def(id)["tint"]


## Duree de minage en secondes. `tool_speed` = 1.0 a mains nues.
static func break_time(id: int, has_correct_tool: bool) -> float:
	var hardness: float = def(id)["hardness"]
	if hardness < 0.0:
		return INF
	if has_correct_tool:
		return hardness
	return hardness * 5.0


## Tuile de l'atlas pour une face donnee.
## `face` : 0=+X 1=-X 2=+Y 3=-Y 4=+Z 5=-Z
static func tile_for_face(id: int, face: int) -> int:
	var t: Variant = def(id)["tile"]
	if t is int:
		return t
	match face:
		2: return t["top"]
		3: return t["bottom"]
		4: return t.get("front", t["side"])
		_: return t["side"]


## Un bloc masque-t-il la face voisine (occlusion ambiante) ?
static func occludes(id: int) -> bool:
	return is_opaque(id) or id == LEAVES or is_liquid(id)


## La face de `block_id` tournee vers `neighbor_id` doit-elle etre generee ?
## Supprime le double dessin des faces internes et des coeurs de feuillage.
static func face_visible(block_id: int, neighbor_id: int) -> bool:
	if neighbor_id == AIR:
		return true
	if is_opaque(neighbor_id):
		return false
	if block_id == neighbor_id:
		# Les feuilles se dessinent **entre elles**, l'eau ne se double jamais.
		#
		# Masquer les faces internes du feuillage faisait de chaque couronne une
		# **coque creuse** : le moindre bloc manquant — et il en manque, la
		# silhouette est irreguliere par construction — ouvrait un trou
		# traversant. Comme la face interne de la coque est eliminee, le rayon
		# ressortait de l'autre cote : on voyait le ciel au milieu de l'arbre,
		# puis a travers l'arbre. C'est ce que le joueur signalait.
		return not is_liquid(block_id)
	return true


## Identifiant d'item du bloc placeable, ou NOTHING (-1).
static func item_id(id: int) -> int:
	if id == AIR:
		return NOTHING
	return Items.block_item(id)
