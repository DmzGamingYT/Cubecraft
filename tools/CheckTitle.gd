extends SceneTree

## Verification du relief de l'ecran titre.
##
## Le test de fumee instancie l'ecran sans arbre de scene, et verifie surtout
## que rien n-explose. Il ne dit rien de ce que le menu montre reellement.
## Ici on regarde les trois proprietes dont depend l'illustration :
##
##   1. le relief existe, tient au-dessus de la bande d'herbe et ne la
##      recouvre pas ;
##   2. le profil est **periodique**, donc les deux bords de la fenetre se
##      rejoignent quelle que soit sa largeur — sans quoi un redimensionnement
##      fait sauter l'horizon ;
##   3. les arbres sont poses sur des sommets, espace, et seulement sur la
##      couche proche.

var _fails := 0
var _screen: TitleScreen
var _frames := 0


func _init() -> void:
	_frames = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	# L'atlas existe hors du jeu : on le fabrique pour que le relief ait ses
	# vraies tuiles, et pas seulement des aplats de repli.
	_assets()

	# Pas de `size` pose a la main : l'ecran est ancre sur toute la fenetre,
	# qui la remplacerait immediatement. C'est `_viewport_size` qui fait foi,
	# et c'est donc lui qu'il faut interroger.
	_screen = TitleScreen.new()
	root.add_child(_screen)
	_screen._layout()

	_shapes()
	_periodic()
	_geometry()
	_trees()
	_depth()

	# Detruit et non `queue_free` : la liberation par `queue_free` est differee
	# a la fin de l'image, et `quit` part immediatement apres — elle n'aurait
	# donc jamais lieu. Detruit explicitement, l'ecran disparait vraiment ; les
	# RIDs qui restaient a la sortie venaient des deux `Ridge` ci-dessous.
	root.remove_child(_screen)
	_screen.free()
	_screen = null
	if _fails == 0:
		print("\nOK : le relief du menu est correct.")
	else:
		print("\n%d VERIFICATION(S) EN ECHEC." % _fails)
	quit(1 if _fails > 0 else 0)
	return true


func _fail(what: String) -> void:
	_fails += 1
	print("  ECHEC : %s" % what)


func _ok(what: String) -> void:
	print("  ok     %s" % what)


## Remplit le registre partage, comme le fait l'autoload `Atlas` au demarrage.
func _assets() -> void:
	var image := TextureFactory.build_atlas()
	image.generate_mipmaps()
	Assets.atlas = ImageTexture.create_from_image(image)
	for tile in range(Tiles.COUNT):
		var region := Rect2i(
			(tile % Tiles.COLS) * Tiles.TILE_PX,
			(tile / Tiles.COLS) * Tiles.TILE_PX,
			Tiles.TILE_PX, Tiles.TILE_PX)
		Assets.tile_images[tile] = ImageTexture.create_from_image(image.get_region(region))
	Assets.is_ready = true


func _peak(node: TitleScreen.Ridge) -> int:
	var top := 0
	for h in node.heights:
		top = maxi(top, h)
	return top


# --------------------------------------------------------------- 1. presence

func _shapes() -> void:
	print("\n[1] Les deux couches existent et sontDessinees")
	for pair in [[_screen._ridge_far, "lointaine"], [_screen._ridge_near, "proche"]]:
		var node: TitleScreen.Ridge = pair[0]
		if node == null:
			_fail("la couche %s est absente" % pair[1])
			return
		if node.heights.is_empty():
			_fail("la couche %s n'a aucun profil" % pair[1])
			return
		if _peak(node) < 1:
			_fail("la couche %s est entierement plate" % pair[1])
			return
		if node.cell <= 0.0:
			_fail("la couche %s a un cote de bloc nul" % pair[1])
			return
		_ok("%s : %d colonnes, crete a %d blocs, %d px le bloc"
			% [pair[1], node.heights.size(), _peak(node), int(node.cell)])

	# Les hauteurs doivent rester dans la plage demandee, sinon le relief peut
	# deborder de l'ecran sur une fenetre basse.
	for pair in [[_screen._ridge_far, TitleScreen.RIDGE_MAX_FAR, "lointaine"],
			[_screen._ridge_near, TitleScreen.RIDGE_MAX_NEAR, "proche"]]:
		var node: TitleScreen.Ridge = pair[0]
		var limit: int = pair[1]
		var label: String = pair[2]
		var over := 0
		for h in node.heights:
			if h > limit or h < 1:
				over += 1
		if over > 0:
			_fail("la couche %s a %d colonnes hors de [1, %d]" % [label, over, limit])
		else:
			_ok("%s : toutes les colonnes entre 1 et %d blocs" % [label, limit])

	# Le relief n'a pas d'interet s'il est parfaitement plat : on veut une
	# vraie ligne d'horizon, pas une bande de plus.
	var varied := false
	for h in _screen._ridge_near.heights:
		if h != _screen._ridge_near.heights[0]:
			varied = true
			break
	if not varied:
		_fail("le relief proche est parfaitement plat")
	else:
		_ok("le relief proche a un vrai profil")


# ------------------------------------------------------------- 2. periodicite

func _periodic() -> void:
	print("\n[2] Le profil boucle proprement")
	# La periode doit-etre un multiple EXACT du cote de bloc, sinon le
	# raccord ne tombe jamais sur une colonne et la couture se voit des que
	# la fenetre depasse la periode.
	for pair in [[TitleScreen.RIDGE_CELL_NEAR, "proche"],
			[TitleScreen.RIDGE_CELL_FAR, "lointaine"]]:
		var cell: float = pair[0]
		var label: String = pair[1]
		var rest := fmod(TitleScreen.RIDGE_SPAN, cell)
		if absf(rest) > 0.001:
			_fail("la periode %.0f n'est pas un multiple de la couche %s (%.0f px), "
				% [TitleScreen.RIDGE_SPAN, label, cell] + "le raccord ne tombe sur aucune colonne")
		else:
			_ok("la periode se termine exactement sur une colonne (%s, %.0f colonnes)"
				% [label, TitleScreen.RIDGE_SPAN / cell])

	# Le raccord, donc : a une periode d'ecart, la hauteur est la meme. La
	# fenetre de test est bien plus etroite qu'une periode — on construit donc
	# le profil sur une largeur forcee, ce que `_shape_ridge` accepte pour ce
	# seul usage.
	var cell := TitleScreen.RIDGE_CELL_NEAR
	var period := int(TitleScreen.RIDGE_SPAN / cell)
	var wide := TitleScreen.RIDGE_SPAN * 1.5
	var probe := TitleScreen.Ridge.new()
	probe.cell = cell
	_screen._shape_ridge(probe, cell, TitleScreen.RIDGE_MAX_NEAR, true, wide)
	var n := probe.heights.size()
	if n <= period:
		_fail("le profil force sur %.0f px ne couvre qu'une periode" % wide)
		probe.free()
		return
	_ok("profil de %.0f px : %d colonnes, une periode en %d" % [wide, n, period])

	var mismatch := 0
	for i in mini(period, n - period):
		if probe.heights[i] != probe.heights[i + period]:
			mismatch += 1
	if mismatch > 0:
		_fail("%d colonnes sur %d ne se raccordent pas sur une periode"
			% [mismatch, period])
	else:
		_ok("les %d colonnes se raccordent exactement a une periode" % period)

	# Le profil est reproductible : deux reliefs de meme largeur doivent etre
	# identiques, sinon le menu change de silhouette a chaque lancement.
	var again := TitleScreen.Ridge.new()
	again.cell = cell
	_screen._shape_ridge(again, cell, TitleScreen.RIDGE_MAX_NEAR, true, wide)
	if again.heights != probe.heights:
		_fail("deux reliefs de meme largeur n'ont pas le meme profil")
	else:
		_ok("profil reproductible d'un ecran a l'autre")

	# `Ridge` herite de `Control` et n'est construit que pour porter le profil :
	# hors de tout arbre, il n'a personne pour le detruire. Deux controles et
	# leurs `CanvasItem` restaient donc vivants a la sortie.
	again.free()
	probe.free()

	# Et le relief reellement affiche n'a pas bougé pendant ces essais : les
	# vérifications ne doivent pas laisser le menu dans un etat different.
	_screen._layout()
	if _screen._ridge_near.heights.size() == 0:
		_fail("le relief affiche a disparu apres les essais")


# --------------------------------------------------------------- 3. position

func _geometry() -> void:
	print("\n[3] Position dans l'ecran")
	_screen._layout()
	# La reference n'est ni la fenetre ni un calcul refait ici : c'est le
	# **noeud** de la bande d'herbe.Comparer a la fenetre donnerait un resultat
	# qui bouge avec le moment ou la fenetre s'est stabilisee, et ne prouverait
	# rien. Comparer les deux couches a l'herbe, elles, prouve ce qui compte :
	# le relief repose sur la meme ligne de sol que le sol du menu.
	var grass := _screen._grass
	if grass == null:
		_fail("pas de bande d'herbe a quoi comparer")
		return
	var grass_rect := grass.get_global_rect()
	var ground_line := grass_rect.end.y
	_ok("ligne de sol du menu a y=%.0f" % ground_line)

	for pair in [[_screen._ridge_far, "lointaine", TitleScreen.GRASS_HEIGHT * 0.45],
			[_screen._ridge_near, "proche", 0.0]]:
		var node: TitleScreen.Ridge = pair[0]
		var label: String = pair[1]
		var sink: float = pair[2]
		var rect := node.get_global_rect()
		# Le bas du relief se pose sur la **ligne de sol**, celle ou le gazon
		# commence a cacher la terre, et s'y enfonce de `sink`. La couche
		# proche a `sink` nul : c'est la bande d'herbe, posee apres, qui la
		# recouvre sur sa hauteur.
		if absf(rect.end.y - (ground_line - sink)) > 1.0:
			_fail("la couche %s repose a y=%.0f, la ligne de sol est a %.0f"
					% [label, rect.end.y, ground_line - sink]
				+ " (enfoncement %.0f)" % sink)
		else:
			_ok("%s : posee sur la ligne de sol, enfoncee de %.0f px"
				% [label, sink])
		if rect.position.y >= rect.end.y:
			_fail("la couche %s n'a aucune hauteur" % label)
		elif rect.position.y < grass_rect.position.y:
			_ok("%s : %.0f px de relief au-dessus du gazon"
				% [label, grass_rect.position.y - rect.position.y])
		else:
			_fail("la couche %s reste cachee sous le gazon" % label)
		if node.position.x != 0.0 or node.size.x <= 0.0:
			_fail("la couche %s ne couvre pas toute la largeur" % label)
		else:
			_ok("%s : largeur couverte (%.0f px)" % [label, node.size.x])

	# La couche proche doit etre posee **apres** la lointaine, donc la
	# recouvrir : c'est ce chevauchement qui fabrique le plan, pas la taille.
	if _ridge_is_after():
		_ok("la couche proche est posee apres la lointaine, elle la recouvre")
	else:
		_fail("la couche lointaine est posee par-dessus la proche")


func _ridge_is_after() -> bool:
	return _screen._ridge_far.get_index() < _screen._ridge_near.get_index()


# ---------------------------------------------------------------- 4. arbres

func _trees() -> void:
	print("\n[4] Les arbres")
	var near: TitleScreen.Ridge = _screen._ridge_near
	if near.trees.is_empty():
		_fail("aucun arbre sur la couche proche")
		return
	_ok("%d arbres sur la couche proche" % near.trees.size())

	# La couche lointaine n'en porte pas : sans cela les deux plans se
	# confondent et rien ne donne l'echelle.
	if not _screen._ridge_far.trees.is_empty():
		_fail("la couche lointaine porte %d arbres, elle doit rester nue"
			% _screen._ridge_far.trees.size())
	else:
		_ok("la couche lointaine reste nue")

	var floating := 0
	var last := -99
	var too_close := 0
	for tree in near.trees:
		var col: int = int(tree["col"])
		if col < 0 or col >= near.heights.size():
			floating += 1
			continue
		if near.heights[col] < 2:
			floating += 1
		if col - last < 4:
			too_close += 1
		last = col
	if floating > 0:
		_fail("%d arbres poses hors d'un sommet (colonne absente ou creuse)" % floating)
	else:
		_ok("tous les arbres sont poses sur un sommet")
	if too_close > 0:
		_fail("%d arbres a moins de 4 colonnes d'ecart" % too_close)
	else:
		_ok("les arbres sont espaces d'au moins 4 colonnes")

	# La couronne doit rester au-dessus du tronc, sinon l'arbre a la tete en
	# bas — ce qui se voit aussitot sur l'horizon.
	var bad := 0
	for tree in near.trees:
		var trunk: int = int(tree.get("trunk", 0))
		var crown: int = int(tree.get("crown", 0))
		if trunk < 1 or crown < 0:
			bad += 1
	if bad > 0:
		_fail("%d arbres ont un tronc ou une couronne sans epaisseur" % bad)
	else:
		_ok("tous les arbres ont un tronc et une couronne")


# -------------------------------------------------------------- 5. profondeur

func _depth() -> void:
	print("\n[5] Les deux plans se distingueront")
	if _screen._ridge_far.cell >= _screen._ridge_near.cell:
		_fail("la couche lointaine n'est pas plus petite (%.0f contre %.0f)"
			% [_screen._ridge_far.cell, _screen._ridge_near.cell])
	else:
		_ok("la couche lointaine est deux fois plus petite")
	if _peak(_screen._ridge_far) > _peak(_screen._ridge_near):
		_fail("la couche lointaine depasse la proche en hauteur")
	else:
		_ok("la couche lointaine reste plus basse")

	# Pale vers le ciel : c'est la **distance au bleu du ciel** qui compte, pas
	# la luminosite. Une brume peut etre plus claire ou plus sombre que la
	# couleur qu'elle voile — comparer les luminances donnerait un resultat
	# arbitraire, et un melange vers le blanc passerait pour correct.
	# `Color` n'a pas de `distance_to` : on passe par le RGB nu, ce qui suffit
	# largement et evite decomparer des luminances.
	var sky := Vector3(TitleScreen.SKY_TOP.r, TitleScreen.SKY_TOP.g, TitleScreen.SKY_TOP.b)
	var far_d := sky.distance_to(Vector3(_screen._ridge_far.tint.r,
		_screen._ridge_far.tint.g, _screen._ridge_far.tint.b))
	var near_d := sky.distance_to(Vector3(_screen._ridge_near.tint.r,
		_screen._ridge_near.tint.g, _screen._ridge_near.tint.b))
	# C'est la lointaine qui doit se rapprocher du ciel, pas l'inverse.
	if far_d >= near_d:
		_fail("la couche lointaine n'est pas plus pres du ciel que la proche"
				+ " (%.3f contre %.3f)" % [far_d, near_d])
	else:
		_ok("la couche lointaine se rapproche du ciel (%.3f contre %.3f)"
			% [far_d, near_d])
	if _screen._ridge_far.tint.is_equal_approx(_screen._ridge_near.tint):
		_fail("les deux plans ont exactement la meme teinte")
