class_name Tiles
extends RefCounted

## Index des tuiles dans l'atlas genere par code.
## Chaque tuile fait TILE_PX pixels de cote, l'atlas fait COLS tuiles par ligne.

const TILE_PX := 16
const COLS := 8
## Sept rangees, et non six : la grille de six ne laissait que neuf cases
## libres, et l'ajout des blocs de lave, glace, cactus, verre et briques l'a
## remplie. Une rangee de plus coute 16 x 16 pixels de VRAM et evite de
## devoir choisir quoi retirer a chaque nouveau bloc. `uv_origin` et `uv_size`
## se deduisent de ROWS, donc mailleur, materiaux et test de fumee n'ont rien
## a changer — c'est la meme grille, plus haute.
const ROWS := 7

enum {
	GRASS_TOP,
	GRASS_SIDE,
	DIRT,
	STONE,
	COBBLE,
	SAND,
	LOG_SIDE,
	LOG_TOP,
	LEAVES,
	PLANKS,
	WATER,
	BEDROCK,
	COAL_ORE,
	IRON_ORE,
	TABLE_TOP,
	TABLE_SIDE,
	TABLE_FRONT,
	TORCH,
	SNOW_TOP,
	SNOW_SIDE,
	GRAVEL,
	IRON_BLOCK,
	LAPI_ORE,
	ENCHANT_TOP,
	ENCHANT_SIDE,
	ENCHANT_FRONT,
	# Icones d'objets purs (aucun bloc placeable).
	TOOL_STICK,
	TOOL_COAL,
	TOOL_RAW_IRON,
	TOOL_IRON_INGOT,
	TOOL_WOOD_PICKAXE,
	TOOL_STONE_PICKAXE,
	TOOL_IRON_PICKAXE,
	APPLE,
	LAPIS,
	PORKCHOP,
	TOOL_WOOD_SWORD,
	TOOL_STONE_SWORD,
	TOOL_IRON_SWORD,
	# Tuiles ajoutees apres l'etat initial du jeu. Elles sont **ajoutees a la
	# suite** et non inserees : l'indice d'une tuile est stocke dans les
	# sauvegardes, et les renumeroter ferait reinterpret chaque monde deja
	# enregistre. La grille fait COLS * ROWS = 48 cases ; il en restait 11.
	GLASS,
	BRICK,
	ICE,
	LAVA,
	CACTUS_SIDE,
	CACTUS_TOP,
	PLANKS_RED,
	GOLD_ORE,
	DIAMOND_ORE,
	RED_SAND,
	# Repli generique des nouveaux gemmes (or, diamant) quand le dossier
	# d'assets CC0 est absent : une seule tuile pour deux objets, recoloree a
	# l'affichage. Un atlas n'a pas la place d'un gere par objet.
	TOOL_GEM,
	COUNT,
}


## Rectangle UV normalise du coin superieur gauche d'une tuile dans l'atlas.
static func uv_origin(tile: int) -> Vector2:
	return Vector2(
		float((tile % COLS) * TILE_PX) / float(COLS * TILE_PX),
		float((tile / COLS) * TILE_PX) / float(ROWS * TILE_PX))


## Taille normalise d'une tuile dans l'atlas.
static func uv_size() -> Vector2:
	return Vector2(1.0 / float(COLS), 1.0 / float(ROWS))
