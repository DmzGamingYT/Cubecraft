class_name ExternalTiles
extends RefCounted

## Habillage optionnel de l'atlas et des icones par des images externally CC0.
##
## Le jeu peint normalement ses tuiles par le code (`TextureFactory`). Ce module
## ne change rien a cette fabrication : il **recouvre** ensuite certaines
## tuiles par des fichiers PNG presents dans `res://assets/kenney/` quand ils
## existent, et ne fait rien du tout quand ils sont absents.
##
## Pourquoi une surcouche et pas un remplacement :
##
##   - L'atlas garde exactement sa grille (`Tiles.COLS` x `Tiles.ROWS` de
##     `Tiles.TILE_PX`), donc ni le mailleur, ni les UV, ni les materiaux, ni le
##     test de fumee n'ont besoin d'etre relus. On change des pixels, pas une
##     seule ligne de geometrie.
##   - Les tuiles absentes du jeu (torche, table d'enchantement) gardent leur
##     peinture d'origine : la surcouche est partielle par construction.
##   - Supprimer `assets/kenney/` rend le jeu exactement tel qu'il etait. Aucun
##     asset n'est obligatoire, ce qui etait la contrainte du projet.
##
## L'eau n'est volontairement pas recouverte : elle a sa propre texture animee
## dont la periodicite est verifiee par le test de fumee (voir `Atlas`), et une
## image fixe la rendrait statique.
##
## Source des images : « Voxel pack » de Kenney Vleugels, CC0 1.0
## (https://creativecommons.org/publicdomain/zero/1.0/). Voir
## `assets/kenney/LICENSE-kenney.txt`.

const TILE_DIR := "res://assets/kenney/tiles/"
const ITEM_DIR := "res://assets/kenney/items/"

## Cote auquel une tuile Kenney est ramenee dans l'atlas. 128 -> 16 : c'est la
## resolution native d'une tuile du jeu : l'image tierce s'y range sans
## etirement.
const TILE_PX := 16
## Cote des icones d'objets livrees telles quelles a l'interface. Elles sont
## dessinees par `Slot` dans un carre d'une quarantaine de pixels : on garde
## assez de resolution pour que le lissage ne degrade pas le trait, en
## moins qu'on n'impose un 128x128 en texture pour un icone de 32 px.
const ICON_PX := 64

## Tuiles de blocs, de l'enumeration `Tiles` vers le fichier Kenney.
##
## Volontairement court : on ne recouvre que ce qui a un equivalent lisible.
## Une tuile sans equivalent garde sa peinture procedurale, qui est faite pour.
const TILE_FILES := {
	Tiles.GRASS_TOP: "grass_top.png",
	Tiles.GRASS_SIDE: "dirt_grass.png",
	Tiles.DIRT: "dirt.png",
	Tiles.STONE: "stone.png",
	Tiles.COBBLE: "greystone.png",
	Tiles.SAND: "sand.png",
	Tiles.LOG_SIDE: "trunk_side.png",
	Tiles.LOG_TOP: "trunk_top.png",
	# `leaves.png` et non `leaves_transparent.png` : la tuile de feuillage doit
	# etre entierement peinte (le test de fumee compte ses pixels transparents).
	# Un trou ici ouvrirait le ciel au coeur de la couronne.
	Tiles.LEAVES: "leaves.png",
	Tiles.PLANKS: "wood.png",
	Tiles.BEDROCK: "rock.png",
	Tiles.COAL_ORE: "stone_coal.png",
	Tiles.IRON_ORE: "stone_iron.png",
	Tiles.TABLE_TOP: "table.png",
	Tiles.TABLE_SIDE: "table.png",
	Tiles.TABLE_FRONT: "table.png",
	Tiles.SNOW_TOP: "snow.png",
	Tiles.SNOW_SIDE: "dirt_snow.png",
	Tiles.GRAVEL: "gravel_stone.png",
	# Tuiles ajoutees avec les blocs de meme nom.
	Tiles.GLASS: "glass.png",
	Tiles.BRICK: "brick_red.png",
	Tiles.ICE: "ice.png",
	Tiles.LAVA: "lava.png",
	Tiles.CACTUS_SIDE: "cactus_side.png",
	Tiles.CACTUS_TOP: "cactus_top.png",
	Tiles.PLANKS_RED: "wood_red.png",
	Tiles.GOLD_ORE: "stone_gold.png",
	Tiles.DIAMOND_ORE: "stone_diamond.png",
	Tiles.RED_SAND: "redsand.png",
}

## Icones d'objets purs, de l'enumeration `Items` vers le fichier Kenney.
## Le pack n'a pas de pioche en bois ni d'epee en pierre : on ne remplace pas
## une pioche en bois par une pioche en bronze, on garde la peinture d'origine.
const ITEM_FILES := {
	Items.IRON_PICKAXE: "pick_iron.png",
	Items.IRON_SWORD: "sword_iron.png",
	Items.COAL: "ore_coal.png",
	Items.RAW_IRON: "ore_iron.png",
	Items.APPLE: "apple.png",
	Items.DIAMOND: "ore_diamond.png",
	Items.GOLD_INGOT: "ore_gold.png",
	Items.DIAMOND_PICKAXE: "pick_diamond.png",
	Items.DIAMOND_SWORD: "sword_diamond.png",
}

## `ResourceLoader.exists` est la seule facon fiable de savoir si un PNG a ete
## importe : le fichier peut etre absent du depot comme present mais non compile.
static func _read(dir: String, file: String) -> Image:
	var path := dir + file
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Recouvre les tuiles de `atlas` pour lesquelles un fichier est present.
##
## Appelee a la toute fin de `TextureFactory.build_atlas()`, une fois les
## `Tiles.COUNT` tuiles procedurales peintes : une surcouche absente laisse
## donc l'image strictement identique a ce qu'elle etait.
##
## Retourne le nombre de tuiles effectivement recouvrees, pour le diagnostic.
static func apply_to_atlas(atlas: Image) -> int:
	var replaced := 0
	for tile in TILE_FILES:
		var img := _read(TILE_DIR, TILE_FILES[tile])
		if img == null:
			continue
		if img.get_width() != TILE_PX or img.get_height() != TILE_PX:
			img.resize(TILE_PX, TILE_PX, Image.INTERPOLATE_LANCZOS)
		var o := Vector2i((tile % Tiles.COLS) * TILE_PX, (tile / Tiles.COLS) * TILE_PX)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(TILE_PX, TILE_PX)), o)
		replaced += 1
	return replaced


## Icone d'un objet, ou `null` si le pack n'a rien pour lui — l'appelant garde
## alors la tuile de l'atlas. C'est ce `null` qui fait la degradation propre.
static func item_icon(item_id: int) -> Texture2D:
	if not ITEM_FILES.has(item_id):
		return null
	var img := _read(ITEM_DIR, ITEM_FILES[item_id])
	if img == null:
		return null
	if img.get_width() != ICON_PX or img.get_height() != ICON_PX:
		img.resize(ICON_PX, ICON_PX, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)
