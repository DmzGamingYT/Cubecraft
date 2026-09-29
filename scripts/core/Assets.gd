class_name Assets
extends RefCounted

## Registre des ressources construites au demarrage (atlas, materiaux, icones).
##
## L'autoload `Atlas` les remplit ici, et le reste du jeu les lit par `Assets`.
## Passer par une classe ordinaire plutot que par l'autoload lui-meme permet
## d'utiliser ces ressources depuis un script charge hors du jeu — c'est ce qui
## rend le test de fumee possible sans demarrer la scene.

static var atlas: Texture2D = null
static var materials: Array = [null, null, null]
static var block_materials: Dictionary = {}
static var item_icons: Dictionary = {}
static var tile_images: Dictionary = {}
## Icones isometriques des blocs, pour l'inventaire. Une tuile plate montrait
## un carre ou l'herbe et la pierre se ressemblaient ; le cube en perspective
## dit tout de suite de quoi il s'agit.
static var block_icons: Dictionary = {}
static var is_ready := false


static func material_for(kind: int) -> StandardMaterial3D:
	var material: Variant = materials[kind] if kind >= 0 and kind < materials.size() else null
	return material


static func block_material(block_id: int) -> StandardMaterial3D:
	return block_materials.get(block_id, null)


static func icon_for(item_id: int) -> Texture2D:
	# Un bloc tient un cube en perspective, pas sa tuile : c'est l'icone de
	# l'inventaire de Minecraft, et la seule qui distingue un bloc de terre d'un
	# bloc d'herbe au premier coup d'oeil.
	if item_id >= 0 and Items.is_block_item(item_id):
		var block_id := Items.block_of(item_id)
		if block_icons.has(block_id):
			return block_icons[block_id]
	if item_icons.has(item_id):
		return item_icons[item_id]
	if item_id >= 0 and Items.is_block_item(item_id):
		var block_id := Items.block_of(item_id)
		if block_materials.has(block_id):
			return block_materials[block_id]
	return tile_images.get(Tiles.DIRT, null)
