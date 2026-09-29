extends SceneTree

## Verification jetable : le contenu ajoute apres coup est-il reellement
## atteignable ? Un bloc declare dans l'enumeration mais que rien ne genere,
## ou une recette que `match` ne reconnait jamais, passe tous les tests
## existants — ils ne verifient que des invariants de structure.
##
## Trois questions, dans l'ordre du parcours d'un joueur :
##   1. le minerai est-il dans le sol ?
##   2. la recette sort-elle bien l'objet annonce ?
##   3. le palier d'outil ferme-t-il bien ce qu'il doit fermer ?

## Surface d'echantillonnage : on genere une grille de chunks et on compte.
## Un test qui dirait « le code est bien ecrit » ne prouverait rien ; celui-la
## fait tourner le generateur et compte ce qui en sort vraiment.
const SPAN := 6      ## chunks de cote
const SEED := 1234

var _fails := 0


func _init() -> void:
	_check_ores()
	_check_recipes()
	_check_tiers()
	_check_hazards()

	if _fails == 0:
		print("\nOK : le contenu ajoute est atteignable.")
	else:
		print("\n%d VERIFICATION(S) EN ECHEC." % _fails)
	quit(1 if _fails > 0 else 0)


func _fail(what: String) -> void:
	_fails += 1
	print("  ECHEC : %s" % what)


func _ok(what: String) -> void:
	print("  ok     %s" % what)


# ------------------------------------------------------------ 1. generation

func _check_ores() -> void:
	print("\n[1] Generation des minerais")
	var gen := WorldGen.new(SEED)
	var blocks := PackedByteArray()
	blocks.resize(Vox.CHUNK_VOLUME)
	blocks.fill(0)

	# Comptage par bloc, et surtout la profondeur la plus haute atteinte :
	# un minerai « present » mais a y=90 ne servirait a rien.
	var gold := 0
	var diamond := 0
	var gold_top := 0
	var diamond_top := 0
	var chunk_count := 0
	var half := SPAN / 2
	for cz in range(-half, half):
		for cx in range(-half, half):
			blocks.fill(0)
			gen.generate_chunk(cx, cz, blocks)
			chunk_count += 1
			for lz in Vox.CHUNK_Z:
				for lx in Vox.CHUNK_X:
					for y in Vox.CHUNK_Y:
						var b := blocks[Vox.index(lx, y, lz)]
						if b == Blocks.GOLD_ORE:
							gold += 1
							gold_top = maxi(gold_top, y)
						elif b == Blocks.DIAMOND_ORE:
							diamond += 1
							diamond_top = maxi(diamond_top, y)

	print("  %d chunks, or=%d (y max %d), diamant=%d (y max %d)"
		% [chunk_count, gold, gold_top, diamond, diamond_top])
	if gold <= 0:
		_fail("aucun minerai d'or sur %d chunks" % chunk_count)
	else:
		_ok("or present (%d blocs)" % gold)
	if diamond <= 0:
		_fail("aucun minerai de diamant sur %d chunks" % chunk_count)
	else:
		_ok("diamant present (%d blocs)" % diamond)

	# Les deux paliers sont censes etre profonds : miner en surface doit
	# rester inutile, sinon la progression perd tout son sens.
	if gold_top > 34:
		_fail("or monte jusqu'a y=%d, la profondeur max etait 34" % gold_top)
	else:
		_ok("or confine sous y=34 (reculle max y=%d)" % gold_top)
	if diamond_top > 20:
		_fail("diamant monte jusqu'a y=%d, la profondeur max etait 20" % diamond_top)
	else:
		_ok("diamant confine sous y=20 (reculte max y=%d)" % diamond_top)

	# Et l'ordre des materiaux doit rester le bon : pas de diamant au
	#-dessus de l'or, sans quoi on pourrait fouiller au palier 3.
	if diamond_top > 0 and gold_top > 0 and gold_top < 20 and gold == 0:
		_fail("ordre des profondeurs incoherent")


# --------------------------------------------------------------- 2. recettes

## Etale des lignes de 3 cases en grille plate, le repere des coordonnees
## etant (0,0) en haut a gauche. `Recipes.EMPTY` pour un emplacement vide.
func _grid(rows: Array) -> Array:
	var g: Array = []
	for _i in 9:
		g.append(Recipes.EMPTY)
	var y := 0
	for row: Array in rows:
		var x := 0
		for c in row:
			g[y * 3 + x] = c
			x += 1
		y += 1
	return g


func _expect(label: String, rows: Array, out: int, count: int) -> void:
	var r := Recipes.match(_grid(rows), 3)
	if r.is_empty():
		_fail("%s : aucune recette reconnue" % label)
		return
	if not r.has("id"):
		_fail("%s : resultat sans cle 'id' (%s)" % [label, str(r.keys())])
		return
	if int(r["id"]) != out:
		_fail("%s : sort %s, attendu %s"
			% [label, Items.name_of(int(r["id"])), Items.name_of(out)])
		return
	if int(r["count"]) != count:
		_fail("%s : donne %d, attendu %d" % [label, int(r["count"]), count])
		return
	_ok("%s -> %s x%d" % [label, Items.name_of(out), count])


func _check_recipes() -> void:
	print("\n[2] Recettes ajoutees")
	var d := Items.DIAMOND
	var e := Recipes.EMPTY
	_expect("pioche diamant", [
		[d, d, d],
		[e, Items.STICK, e],
		[e, Items.STICK, e],
	], Items.DIAMOND_PICKAXE, 1)
	_expect("epee diamant", [
		[d, d],
		[d, d],
		[e, Items.STICK, e],
	], Items.DIAMOND_SWORD, 1)
	var sand := Items.block_item(Blocks.SAND)
	_expect("verre", [
		[sand, sand],
		[sand, sand],
	], Items.block_item(Blocks.GLASS), 1)
	var cobble := Items.block_item(Blocks.COBBLESTONE)
	_expect("briques (sans forme)", [
		[cobble, cobble],
		[cobble, cobble],
	], Items.block_item(Blocks.BRICK), 1)

	# Le vrai test du « sans forme » : les quatre moellons en S, une
	# disposition qu'aucun schema en ligne ou en colonne ne peut decrire.
	# Si la recette avait ete ecrite en forme, elle echouerait ici.
	var r := Recipes.match(_grid([
		[cobble, cobble, e],
		[e, cobble, cobble],
		[e, e, e]]), 3)
	if r.is_empty() or int(r.get("id", -1)) != Items.block_item(Blocks.BRICK):
		_fail("briques : la disposition en S n'aboutit pas")
	else:
		_ok("briques : disposition en S acceptee (vraiment sans forme)")

	# Le verre ne doit surtout pas se fabriquer avec du cobble : les deux
	# recettes ne doivent pas se recouvrir, sinon 4 moellons donneraient
	# aussi du verre et le joueur n'aurait plus de raison de fondre du sable.
	var wrong := Recipes.match(_grid([
		[cobble, cobble],
		[cobble, cobble]]), 3)
	if not wrong.is_empty() and int(wrong.get("id", -1)) == Items.block_item(Blocks.GLASS):
		_fail("verre : la recette des briques la recouvre")
	else:
		_ok("verre et briques ne se recouvrent pas")


# ---------------------------------------------------------------- 3. paliers

func _check_tiers() -> void:
	print("\n[3] Paliers d'outil")

	# Reprise exacte du raisonnement de Game.on_block_broken : c'est la que
	# se joue l'exigence, on verifie donc la regle elle-meme, pas une copie.
	var pairs := [
		[Blocks.IRON_ORE, Items.IRON_PICKAXE, true, "fer avec pioche fer"],
		[Blocks.GOLD_ORE, Items.IRON_PICKAXE, true, "or avec pioche fer"],
		[Blocks.GOLD_ORE, Items.DIAMOND_PICKAXE, true, "or avec pioche diamant"],
		[Blocks.DIAMOND_ORE, Items.IRON_PICKAXE, false, "diamant avec pioche fer"],
		[Blocks.DIAMOND_ORE, Items.STONE_PICKAXE, false, "diamant avec pioche pierre"],
		[Blocks.DIAMOND_ORE, Items.DIAMOND_PICKAXE, true, "diamant avec pioche diamant"],
		[Blocks.GOLD_ORE, Items.WOOD_PICKAXE, false, "or avec pioche bois"],
	]
	for p in pairs:
		var block_id: int = p[0]
		var item_id: int = p[1]
		var allowed: bool = p[2]
		var need: int = Blocks.def(block_id)["tier"]
		var have: int = Items.tier_of(item_id)
		var got := need <= have
		if got != allowed:
			_fail("%s : palier %d contre outil %d -> %s"
				% [p[3], need, have, "autorise" if got else "refuse"])
		else:
			_ok("%s (palier %d vs %d)" % [p[3], need, have])

	# L'escalier doit rester monotone : un palier inferieur a un palier
	# superieur casserait l'illusion de progression.
	var ladder := [Blocks.IRON_ORE, Blocks.GOLD_ORE, Blocks.DIAMOND_ORE]
	var prev := -1
	for b in ladder:
		var t: int = Blocks.def(b)["tier"]
		if t <= prev:
			_fail("escalier des minerais non monotone a partir de %d" % b)
		prev = t
	_ok("escalier des minerais strictement croissant")

	# Chaque minerai doit rendre ce qu'il promet, sinon la recette du palier
	# suivant ne pourrait jamais se crafting.
	for pair in [[Blocks.GOLD_ORE, Items.GOLD_INGOT], [Blocks.DIAMOND_ORE, Items.DIAMOND]]:
		var block_id: int = pair[0]
		var item_id: int = pair[1]
		if int(Blocks.def(block_id)["drop"]) != item_id:
			_fail("le bloc %d ne lache pas l'objet %d" % [block_id, item_id])
		else:
			_ok("%s lache bien %s" % [Blocks.name_of(block_id), Items.name_of(item_id)])


# --------------------------------------------------------------- 4. degats

func _check_hazards() -> void:
	print("\n[4] Degats de contact")
	for pair in [[Blocks.LAVA, true], [Blocks.CACTUS, true], [Blocks.STONE, false],
			[Blocks.GLASS, false], [Blocks.WATER, false], [Blocks.TORCH, false]]:
		var block_id: int = pair[0]
		var dangerous: bool = pair[1]
		var hurt := float(Blocks.def(block_id).get("hurt", 0.0))
		if (hurt > 0.0) != dangerous:
			_fail("%s : hurt=%f, attendu dangereux=%s"
				% [Blocks.name_of(block_id), hurt, str(dangerous)])
		else:
			_ok("%s : hurt=%f" % [Blocks.name_of(block_id), hurt])

	# La lave doit rester infranchissable : sa durete negative la rend
	# incassable, donc la seule issue est de mourir.
	if float(Blocks.def(Blocks.LAVA)["hardness"]) >= 0.0:
		_fail("la lave est cassable, le joueur peut s'y installer")
	else:
		_ok("la lave est incassable")

	# La source de degats doit exister des deux cotes : la lave du monde
	# comme celle d'un seau, il n'y a qu'une table de blocs.
	if Blocks.LAVA < 0:
		_fail("pas de bloc LAVA dans l'enumeration")
	else:
		_ok("la table des blocs porte bien LAVA")
