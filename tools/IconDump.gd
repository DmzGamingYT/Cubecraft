extends SceneTree

## Controle visuel des icones isometriques des blocs.
##
##   godot --headless --script res://tools/IconDump.gd
##
## Une face du cube dont les aretes partent a l'envers reste un cube a l'oeil
## sur une capture d'inventaire — mais le fond se decale de quelques pixels.
## On imprime donc l'icone en clair, teinte de biome comprise.

func _initialize() -> void:
	var atlas := TextureFactory.build_atlas()
	for block_id in [Blocks.GRASS, Blocks.DIRT, Blocks.PLANKS, Blocks.STONE,
			Blocks.LOG, Blocks.CRAFTING_TABLE]:
		var tint := Color(1, 1, 1)
		match Blocks.tint_of(block_id):
			"grass":
				tint = Biomes.grass_tint(Biomes.PLAINS)
			"leaves":
				tint = Biomes.foliage_tint(Biomes.PLAINS)
		var icon := BlockIcons.build(atlas, block_id, tint)
		print("---- %s ----" % Blocks.name_of(block_id))
		var ramp := " .:-=+*#%@"
		for y in icon.get_height():
			var line := ""
			for x in icon.get_width():
				var c := icon.get_pixel(x, y)
				if c.a < 0.5:
					line += " "
					continue
				var luma := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				line += ramp[clampi(int(luma * float(ramp.length() - 1)), 0,
					ramp.length() - 1)]
			print(line)
	quit(0)
