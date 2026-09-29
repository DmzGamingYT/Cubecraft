extends SceneTree

## Controle visuel de la forme des arbres.
##
##   godot --headless --script res://tools/TreeDump.gd
##
## Une couronne qui se lit comme un parasol au bout d'un baton ne se voit dans
## aucun test : elle se voit dans le dessin. On cherche donc un tronc **loin des
## bords du chunk** (une couronne a cheval sur deux chunks se lirait de travers)
## et on imprime deux coupes : verticale le long du tronc, et horizontale a
## chaque etage.

const SEED := 1234


func _initialize() -> void:
	var gen := WorldGen.new(SEED)
	var shown := {"chene": false, "epicea": false}
	for cz in range(-8, 9):
		for cx in range(-8, 9):
			var blocks := PackedByteArray()
			blocks.resize(Vox.CHUNK_VOLUME)
			gen.generate_chunk(cx, cz, blocks)
			for lz in range(4, 12):
				for lx in range(4, 12):
					# Les deux couronnes ont leurs propres defauts : on en montre
					# une de chaque espece.
					var kind := "epicea" if Biomes.is_spruce(
						gen.biome_at(cx * 16 + lx, cz * 16 + lz)) else "chene"
					if shown[kind]:
						continue
					for y in range(2, Vox.CHUNK_Y - 1):
						if blocks[Vox.index(lx, y, lz)] != Blocks.LOG:
							continue
						if blocks[Vox.index(lx, y - 1, lz)] == Blocks.LOG:
							continue
						shown[kind] = true
						_show(blocks, lx, lz, cx, cz, y, kind)
			if shown["chene"] and shown["epicea"]:
				quit(0)
				return
	print("trouve : %s" % shown)
	quit(0)


func _show(blocks: PackedByteArray, lx: int, lz: int, cx: int, cz: int,
		base: int, kind: String) -> void:
	var trunk := 0
	while blocks[Vox.index(lx, base + trunk, lz)] == Blocks.LOG:
		trunk += 1
	print("---- %s en (%d,%d), base y=%d, tronc %d blocs ----"
		% [kind, cx * 16 + lx, cz * 16 + lz, base, trunk])
	print("coupe verticale (x de -4 a +4) :")
	for y in range(base + trunk + 4, base - 1, -1):
		var line := "y%3d " % y
		for x in range(lx - 4, lx + 5):
			var id := blocks[Vox.index(x, y, lz)]
			line += " " if id == Blocks.AIR else ("L" if id == Blocks.LOG else "#")
		print(line)
	print("coupe horizontale (x de -4 a +4, z de -4 a +4) :")
	for y in range(base + trunk + 3, base + trunk - 5, -1):
		print("y%3d" % y)
		for z in range(lz - 4, lz + 5):
			var line := "     "
			for x in range(lx - 4, lx + 5):
				var id := blocks[Vox.index(x, y, z)]
				line += " " if id == Blocks.AIR else ("L" if id == Blocks.LOG else "#")
			print(line)
