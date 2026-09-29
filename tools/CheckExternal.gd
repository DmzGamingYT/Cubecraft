extends SceneTree

## Verification jetable : le survol par des images CC0 est-il reellement
## applique, et sur combien de tuiles ? Un appel qui renvoie 0 ne casse
## aucun test — c'est exactement le defaut que la suite automatisee ne voit pas.

func _init() -> void:
	var img := TextureFactory.build_atlas()
	print("atlas: %s" % img.get_size())
	var replaced := ExternalTiles.apply_to_atlas(img)
	print("tuiles recouvrees: %d / %d declarees" % [replaced, ExternalTiles.TILE_FILES.size()])

	# Couleur moyenne de quelques tuiles, pour verifier qu'elles portent bien
	# l'image tierce (le gazon de Kenney est un vert d'une autre teinte que la
	# peinture procedurale, qui part d'un gris-vert volontairement terne).
	for pair in [[Tiles.GRASS_TOP, "grass_top"], [Tiles.STONE, "stone"],
			[Tiles.LEAVES, "leaves"], [Tiles.TORCH, "torch (non couvert)"],
			[Tiles.TOOL_STICK, "stick (objet, non couvert)"]]:
		var tile: int = pair[0]
		var o := Vector2i((tile % Tiles.COLS) * Tiles.TILE_PX,
			(tile / Tiles.COLS) * Tiles.TILE_PX)
		var r := 0.0
		var g := 0.0
		var b := 0.0
		for y in Tiles.TILE_PX:
			for x in Tiles.TILE_PX:
				var c := img.get_pixel(o.x + x, o.y + y)
				r += c.r
				g += c.g
				b += c.b
		var n := float(Tiles.TILE_PX * Tiles.TILE_PX)
		print("  %-24s moyenne = (%.2f, %.2f, %.2f)" % [pair[1], r / n, g / n, b / n])

	# Les icones d'objets : un `null` ici signifie « le pack n'a rien », et
	# l'appelant retombe sur la tuile de l'atlas.
	for item in [Items.IRON_PICKAXE, Items.APPLE, Items.WOOD_PICKAXE]:
		var tex := ExternalTiles.item_icon(item)
		print("  icone objet %d : %s" % [item, "64x64" if tex != null else "absente (repli)"])
	quit()
