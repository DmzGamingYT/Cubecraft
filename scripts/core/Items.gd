class_name Items
extends RefCounted

## Catalogue des objets.
##
## Deux espaces d'identifiants cohabitent :
##   - 0 .. 99    : objets purs (bâton, charbon, outils...)
##   - 100 + bloc : objet "bloc placeable", un par bloc du registre Blocks
## Le rendu d'un bloc placeable (icone, miniature) reutilise son tuile "face avant".

enum {
	STICK,
	COAL,
	RAW_IRON,
	IRON_INGOT,
	WOOD_PICKAXE,
	STONE_PICKAXE,
	IRON_PICKAXE,
	APPLE,
	LAPIS,
	PORKCHOP,
	WOOD_SWORD,
	STONE_SWORD,
	IRON_SWORD,
	# Objets ajoutes apres coup, **ajoutes et non inseres** : comme pour les
	# blocs, l'identifiant est ecrit dans les sauvegardes.
	DIAMOND,
	GOLD_INGOT,
	DIAMOND_PICKAXE,
	DIAMOND_SWORD,
	COUNT,
}

## Enchantements, dans l'ordre du panneau : cout en lapis et en niveaux.
const ENCHANTS := {
	"efficacite": {"name": "Efficacité", "lapis": 1, "levels": 1, "max": 3},
	"fortune": {"name": "Fortune", "lapis": 2, "levels": 2, "max": 3},
	"tranchant": {"name": "Tranchant", "lapis": 2, "levels": 2, "max": 3},
}

const BLOCK_BASE := 100

## Vitesse de minage relative a une main nue (1.0).
const HAND_SPEED := 1.0

## Objets purs declares ici. Les objets "bloc placeable" sont ajoutes a la
## demande par `_ensure_blocks()` : les construire statiquement ferait dependre
## l'initialisation de Items de celle de Blocks, et l'une des deux trouverait un
## registre a moitie rempli.
static var defs: Dictionary = _build_defs()
static var _blocks_registered := false


static func _build_defs() -> Dictionary:
	var d: Dictionary = {}

	d[STICK] = {"name": "Bâton", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0}
	d[COAL] = {"name": "Charbon", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0}
	d[RAW_IRON] = {"name": "Fer brut", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0}
	d[IRON_INGOT] = {"name": "Lingot de fer", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0}

	d[WOOD_PICKAXE] = {
		"name": "Pioche en bois", "stack": 1, "block": -1,
		"tool": "pickaxe", "tier": 1, "speed": 2.0,
	}
	d[STONE_PICKAXE] = {
		"name": "Pioche en pierre", "stack": 1, "block": -1,
		"tool": "pickaxe", "tier": 2, "speed": 4.0,
	}
	d[IRON_PICKAXE] = {
		"name": "Pioche en fer", "stack": 1, "block": -1,
		"tool": "pickaxe", "tier": 3, "speed": 6.0,
	}

	d[APPLE] = {"name": "Pomme", "stack": 64, "block": -1, "tool": "", "tier": 0,
		"speed": 1.0, "food": 4}
	d[LAPIS] = {"name": "Lapis", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0}
	d[PORKCHOP] = {"name": "Côtelette", "stack": 64, "block": -1, "tool": "", "tier": 0,
		"speed": 1.0, "food": 3}

	d[WOOD_SWORD] = {
		"name": "Épée en bois", "stack": 1, "block": -1,
		"tool": "sword", "tier": 1, "speed": 1.0, "damage": 4,
	}
	d[STONE_SWORD] = {
		"name": "Épée en pierre", "stack": 1, "block": -1,
		"tool": "sword", "tier": 2, "speed": 1.0, "damage": 5,
	}
	d[IRON_SWORD] = {
		"name": "Épée en fer", "stack": 1, "block": -1,
		"tool": "sword", "tier": 3, "speed": 1.0, "damage": 6,
	}

	d[DIAMOND] = {"name": "Diamant", "stack": 64, "block": -1, "tool": "", "tier": 0,
		"speed": 1.0}
	d[GOLD_INGOT] = {"name": "Lingot d'or", "stack": 64, "block": -1, "tool": "",
		"tier": 0, "speed": 1.0}
	d[DIAMOND_PICKAXE] = {
		# Palier 4 : c'est elle qui ouvre le minerai de diamant, et rien d'autre.
		"name": "Pioche en diamant", "stack": 1, "block": -1,
		"tool": "pickaxe", "tier": 4, "speed": 9.0,
	}
	d[DIAMOND_SWORD] = {
		"name": "Épée en diamant", "stack": 1, "block": -1,
		"tool": "sword", "tier": 4, "speed": 1.0, "damage": 8,
	}

	return d


## Un objet par bloc placeable, sauf l'air. Ajoute au registre si necessaire.
static func _ensure_blocks() -> void:
	if _blocks_registered:
		return
	_blocks_registered = true
	for block_id in range(1, Blocks.COUNT):
		var bd := Blocks.def(block_id)
		defs[block_item(block_id)] = {
			"name": bd["name"], "stack": 64, "block": block_id,
			"tool": "", "tier": 0, "speed": 1.0,
		}


## Registre complet, objets purs et blocs compris.
static func all() -> Dictionary:
	_ensure_blocks()
	return defs


static func block_item(block_id: int) -> int:
	return BLOCK_BASE + block_id


static func is_block_item(item_id: int) -> bool:
	return item_id >= BLOCK_BASE


static func def(item_id: int) -> Dictionary:
	_ensure_blocks()
	return defs.get(item_id, {"name": "?", "stack": 64, "block": -1, "tool": "", "tier": 0, "speed": 1.0})


static func name_of(item_id: int) -> String:
	return def(item_id)["name"]


static func max_stack(item_id: int) -> int:
	return def(item_id)["stack"]


## Bloc placeable associe a l'objet, ou -1.
static func block_of(item_id: int) -> int:
	return def(item_id)["block"]


## Tuile d'icone dans l'atlas.
static func icon_tile(item_id: int) -> int:
	var block_id := block_of(item_id)
	if block_id >= 0:
		return Blocks.tile_for_face(block_id, 4)
	# Les outils n'ont pas de tuile : on dessine une dedicated tile pour chacun.
	match item_id:
		STICK: return Tiles.TOOL_STICK
		COAL: return Tiles.TOOL_COAL
		RAW_IRON: return Tiles.TOOL_RAW_IRON
		IRON_INGOT: return Tiles.TOOL_IRON_INGOT
		WOOD_PICKAXE: return Tiles.TOOL_WOOD_PICKAXE
		STONE_PICKAXE: return Tiles.TOOL_STONE_PICKAXE
		IRON_PICKAXE: return Tiles.TOOL_IRON_PICKAXE
		APPLE: return Tiles.APPLE
		LAPIS: return Tiles.LAPIS
		PORKCHOP: return Tiles.PORKCHOP
		WOOD_SWORD: return Tiles.TOOL_WOOD_SWORD
		STONE_SWORD: return Tiles.TOOL_STONE_SWORD
		IRON_SWORD: return Tiles.TOOL_IRON_SWORD
		# Repli quand le dossier d'assets CC0 est absent : les deux gemmes
		# partagent une tuile, les deux outils en diamant reprennent la
		# silhouette de leur equivalent en fer.
		DIAMOND: return Tiles.TOOL_GEM
		GOLD_INGOT: return Tiles.TOOL_GEM
		DIAMOND_PICKAXE: return Tiles.TOOL_IRON_PICKAXE
		DIAMOND_SWORD: return Tiles.TOOL_IRON_SWORD
	return Tiles.DIRT


## Vitesse de minage de l'objet tenu, ou HAND_SPEED.
static func speed_of(item_id: int) -> float:
	if item_id < 0:
		return HAND_SPEED
	return def(item_id)["speed"]


## Degats infliges par un coup (0 pour un objet qui ne frappe pas).
static func damage_of(item_id: int) -> int:
	if item_id < 0:
		return 1
	return int(def(item_id).get("damage", 1))


## Multiplicateur de minage selon l'Efficacite enchantee.
static func enchant_speed(item_id: int, ench: Dictionary) -> float:
	var level := int(ench.get("efficacite", 0))
	return 1.0 + 0.3 * float(level)


## Degats bonus du Tranchant.
static func enchant_damage(ench: Dictionary) -> int:
	return 2 * int(ench.get("tranchant", 0))


## Fortune : probabilite de drop supplementaire par bloc casse.
static func fortune_extra(ench: Dictionary) -> int:
	return int(ench.get("fortune", 0))


## Palier d'outil de l'objet tenu (0 = main nue).
static func tier_of(item_id: int) -> int:
	if item_id < 0:
		return 0
	return def(item_id)["tier"]


## Points de faim restaures en mangeant l'objet (0 = non comestible).
static func food_of(item_id: int) -> int:
	if item_id < 0:
		return 0
	return int(def(item_id).get("food", 0))


## L'objet est-il l'outil adapte pour casser ce bloc ?
static func is_tool_for(item_id: int, block_id: int) -> bool:
	var need: String = Blocks.def(block_id)["tool"]
	if need == "":
		return false
	return def(item_id)["tool"] == need
