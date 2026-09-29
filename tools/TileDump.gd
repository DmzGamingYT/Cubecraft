extends SceneTree

## Outil jetable de controle visuel des textures.

## Affiche une tuile de l'atlas en caracteres, pour juger d'un coup d'oeil ce
## qu'elle donne reellement. Sert aux textures, dont l'apparence ne se verifie
## pas dans une capture de terrain — c'est exactement le genre de defaut qu'un
## test automatique ne voit pas.
##
##   godot --headless --script res://tools/TileDump.gd -- grass_side
##   godot --headless --script res://tools/TileDump.gd -- tool_stick

## Noms de tuiles acceptees en ligne de commande.
## Toutes les tuiles de l'atlas sont nommees : n'en declarer que neuf obligeait
## a passer par le code pour voir une tuile, ce qui est exactement le contraire
## du but de cet outil.
const NAMES := {
	"grass_top": Tiles.GRASS_TOP, "grass_side": Tiles.GRASS_SIDE,
	"dirt": Tiles.DIRT, "stone": Tiles.STONE, "cobble": Tiles.COBBLE,
	"sand": Tiles.SAND, "gravel": Tiles.GRAVEL, "bedrock": Tiles.BEDROCK,
	"log_side": Tiles.LOG_SIDE, "log_top": Tiles.LOG_TOP,
	"leaves": Tiles.LEAVES, "planks": Tiles.PLANKS, "water": Tiles.WATER,
	"snow_top": Tiles.SNOW_TOP, "snow_side": Tiles.SNOW_SIDE,
	"coal_ore": Tiles.COAL_ORE, "iron_ore": Tiles.IRON_ORE,
	"iron_block": Tiles.IRON_BLOCK, "lapis_ore": Tiles.LAPI_ORE,
	"table_top": Tiles.TABLE_TOP, "table_side": Tiles.TABLE_SIDE,
	"table_front": Tiles.TABLE_FRONT, "torch": Tiles.TORCH,
	"enchant_top": Tiles.ENCHANT_TOP, "enchant_front": Tiles.ENCHANT_FRONT,
	"tool_stick": Tiles.TOOL_STICK, "coal": Tiles.TOOL_COAL,
	"raw_iron": Tiles.TOOL_RAW_IRON, "iron_ingot": Tiles.TOOL_IRON_INGOT,
	"wood_pickaxe": Tiles.TOOL_WOOD_PICKAXE,
	"stone_pickaxe": Tiles.TOOL_STONE_PICKAXE,
	"iron_pickaxe": Tiles.TOOL_IRON_PICKAXE,
	"wood_sword": Tiles.TOOL_WOOD_SWORD,
	"stone_sword": Tiles.TOOL_STONE_SWORD,
	"iron_sword": Tiles.TOOL_IRON_SWORD,
	"apple": Tiles.APPLE, "lapis": Tiles.LAPIS, "porkchop": Tiles.PORKCHOP,
}


func _init() -> void:
	var names := OS.get_cmdline_user_args()
	if names.is_empty():
		names = ["grass_side", "planks", "leaves", "tool_stick"]
	var atlas: Image = TextureFactory.build_atlas()
	for name in names:
		_show(str(name), NAMES.get(str(name), -1), atlas)
	quit(0)


func _show(label: String, tile: int, atlas: Image) -> void:
	if tile < 0:
		print("---- tuile inconnue ----")
		return
	var o := Vector2i((tile % Tiles.COLS) * Tiles.TILE_PX,
		(tile / Tiles.COLS) * Tiles.TILE_PX)
	print("---- %s (tuile %d) ----" % [label, tile])
	var ramp := " .:-=+*#%@"
	for y in Tiles.TILE_PX:
		var line := ""
		for x in Tiles.TILE_PX:
			var c := atlas.get_pixel(o.x + x, o.y + y)
			if c.a < 0.5:
				line += " "
				continue
			var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			line += ramp[clampi(int(luma * float(ramp.length() - 1)), 0, ramp.length() - 1)]
		print(line)
