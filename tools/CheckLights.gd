extends SceneTree

## Verification du pool de lumieres. Les invariants de structure — seize
## lumieres, un pool de cette taille — ne diraient rien du comportement : ce
## qui compte est qu'une torche garde sa lumiere quand on marche, qu'une
## source disparue s'eteint sur place, et que la lave n'a pas la meme
## apparence qu'un feu de camp.
##
## Le test pilote le vrai composant : il pose des blocs dans un monde factice,
## appelle `_reassign` et `_advance` comme le jeu le ferait, et regarde ce que
## les OmniLight3D contiennent reellement.

## Monde factice : la liste des sources suffit, on n'a besoin ni de chunks ni
## de maillage pour eclairer.
class _FakeWorld:
	extends World
	var grid := {}

	func get_block(pos: Vector3i) -> int:
		return int(grid.get(pos, Blocks.AIR))


var _fails := 0
var _world: _FakeWorld
var _rig: Node3D
var _lights: TorchLights
var _player: Node3D


func _init() -> void:
	# Rien ici : pendant `_init` l'arbre n'existe pas encore, et un Node3D
	# qui n'y est pas encore accroche renvoie une transformee nulle — la
	# position du joueur, donc tout le calcul d'affectation, serait du vent.
	# Le meme piege est deja signale dans SmokeTest pour les autoloads.
	_frames = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	_setup()
	_pool_shape()
	_sticky()
	_expires()
	_overflow()
	_looks_differ()

	_lights.free()
	_player.free()
	_rig.free()
	_world.free()

	if _fails == 0:
		print("\nOK : l'eclairage dynamique se comporte comme prevu.")
	else:
		print("\n%d VERIFICATION(S) EN ECHEC." % _fails)
	quit(1 if _fails > 0 else 0)
	return true


var _frames := 0


func _setup() -> void:
	_world = _FakeWorld.new()
	root.add_child(_world)

	_rig = Node3D.new()
	root.add_child(_rig)
	_player = Node3D.new()
	_rig.add_child(_player)

	_lights = TorchLights.new()
	_lights.world = _world
	_lights.follow = _player
	_rig.add_child(_lights)
	# `_ready` part tout seul a l'accrochage, mais on ne compte pas sur
	# l'ordre : on garantit le pool avant d'y toucher.
	if _lights._pool.is_empty():
		_lights._ready()


func _fail(what: String) -> void:
	_fails += 1
	print("  ECHEC : %s" % what)


func _ok(what: String) -> void:
	print("  ok     %s" % what)


# ------------------------------------------------------------------ outils

## Pose une source et la fait tourner assez longtemps pour qu'elle atteigne
## son energie pleine.
func _place(pos: Vector3i, block_id: int) -> void:
	_world.grid[pos] = block_id
	_world.torches[pos] = true


func _drop(pos: Vector3i) -> void:
	_world.grid.erase(pos)
	_world.torches.erase(pos)


## Un pas de jeu : recalcul d'affectation puis integration de l'energie.
func _step(ticks: int = 12) -> void:
	for _i in ticks:
		_lights._reassign()
		_lights._advance(0.2)


## Les positions des sources actuellement servies, lues dans le composant
## lui-meme plutot que dans ses variables internes.
func _lit_positions() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for light in _lights._pool:
		if light.light_energy > 0.001:
			# Rendu en position de bloc : on compare des entiers, pas des
			# transformees flottantes. `Vector3i` et non `Vector3.round()`,
			# qui rend encore un Vector3 et ferait echouer le `!=` d'en face.
			out.append(Vector3i((light.global_position - TorchLights.OFFSET).round()))
	return out


func _clear() -> void:
	for pos in _world.torches.keys():
		_world.torches.erase(pos)
	_world.grid.clear()
	for light in _lights._pool:
		light.light_energy = 0.0
	_lights._held.clear()
	_lights._energy.clear()
	for i in TorchLights.COUNT:
		_lights._held.append(TorchLights.NONE)
		_lights._energy.append(0.0)


# -------------------------------------------------------------------- tests

func _pool_shape() -> void:
	print("\n[1] Forme du pool")
	if TorchLights.COUNT < 16:
		_fail("le pool ne compte que %d lumieres" % TorchLights.COUNT)
	else:
		_ok("pool de %d lumieres" % TorchLights.COUNT)
	if _lights._pool.size() != TorchLights.COUNT:
		_fail("le composant a construit %d lumieres pour un COUNT de %d"
			% [_lights._pool.size(), TorchLights.COUNT])
	else:
		_ok("une OmniLight3D par emplacement")
	# Le moteur plafonne les lumieres par objet : si le reservoir ne depasse
	# pas ce plafond, les torches lointaines ne sont jamais calculees.
	var ceiling := int(ProjectSettings.get_setting(
		"rendering/limits/opengl/max_lights_per_object", 0))
	if ceiling > 0 and TorchLights.COUNT > ceiling:
		_fail("le pool (%d) depasse le plafond du moteur (%d), le surplus "
			% [TorchLights.COUNT, ceiling] + "ne sera jamais calcule")
	else:
		_ok("le pool tient sous le plafond de lumieres par objet (%d)" % ceiling)


func _sticky() -> void:
	print("\n[2] Une source garde sa lumiere quand on marche")
	_clear()
	_player.global_position = Vector3(0, 0, 0)
	_place(Vector3i(2, 0, 0), Blocks.TORCH)
	_step()
	var before := _lit_positions()
	if before.size() != 1 or before[0] != Vector3i(2, 0, 0):
		_fail("la torche en (2,0,0) n'est pas allumee seule (%s)" % str(before))
		return
	_ok("une seule torche, une seule lumiere, au bon endroit")

	# Un pas de marche. L'ancien code redistribuait par distance a chaque
	# recalcul : la lumiere sautait d'une torche a l'autre des que le joueur
	# bougeait, meme si la plus proche n'avait pas change.
	for step in range(1, 6):
		_player.global_position = Vector3(float(step), 0, 0)
		_lights._reassign()
		var now := _lit_positions()
		if now.size() != 1 or now[0] != Vector3i(2, 0, 0):
			_fail("la lumiere a quitte la torche apres un pas de %d cases (%s)"
				% [step, str(now)])
			return
	_ok("elle reste sur la meme torche sur 5 cases de marche")

	# Et l'energie ne doit pas retomber au passage : c'est le fondu qui fait
	# le clignotement, pas le deplacement.
	if _lights._pool[0].light_energy <= 0.0:
		_fail("la lumiere s'est eteinte en marchant")
	else:
		_ok("energie maintenue en marche (%.2f)" % _lights._pool[0].light_energy)


func _expires() -> void:
	print("\n[3] Une source qui s'eteint s'eteint sur place")
	_clear()
	_player.global_position = Vector3(0, 0, 0)
	_place(Vector3i(2, 0, 0), Blocks.TORCH)
	_step()
	_drop(Vector3i(2, 0, 0))
	_step(1)
	if _lit_positions().size() != 0:
		_ok("elle ne disparait pas d'un coup, elle s'eteint (%d encore allumee(s))"
			% _lit_positions().size())
	else:
		_ok("elle s'eteint")
	# Une fois completement noire, l'emplacement doit redevenir disponible :
	# sinon le pool se vide a chaque torches posee puis cassee.
	_step(20)
	var dark := 0
	for light in _lights._pool:
		if light.light_energy <= 0.001:
			dark += 1
	if dark != TorchLights.COUNT:
		_fail("apres extinction, %d/%d lumieres sont noires"
			% [dark, TorchLights.COUNT])
	else:
		_ok("les %d emplacements sont de nouveau libres" % dark)


func _overflow() -> void:
	print("\n[4] Plus de torches que de lumieres")
	_clear()
	_player.global_position = Vector3(0, 0, 0)
	# Vingt-cinq torches en couronne : plus que le pool, et toutes a portee.
	for i in range(25):
		var a := TAU * float(i) / 25.0
		_place(Vector3i(int(cos(a) * 4.0), 0, int(sin(a) * 4.0)), Blocks.TORCH)
	_step()
	var lit := _lit_positions()
	if lit.size() != TorchLights.COUNT:
		_fail("%d lumieres allumees pour %d torches, attendu %d"
			% [lit.size(), 25, TorchLights.COUNT])
	else:
		_ok("les %d emplacements sont occupes, le surplus est ignore"
			% TorchLights.COUNT)

	# Les retenues doivent etre les plus proches du joueur, sinon la torche
	# qu'on a posee devant soi resterait sans lumiere. On en remet une tres
	# eloignee : le pool etant plein, elle n'a pas sa place, et surtout elle ne
	# doit pas evincer une torche proche pour la prendre.
	var far := Vector3i(40, 0, 0)
	_place(far, Blocks.TORCH)
	_step()
	var after := _lit_positions()
	if after.has(far):
		_fail("une torche a 40 cases a ete retenue au detriment d'une plus proche")
	elif after.size() != TorchLights.COUNT:
		_fail("%d lumieres allumees apres ajout d'une torche lointaine, attendu %d"
			% [after.size(), TorchLights.COUNT])
	else:
		_ok("la torche lointaine est refusee, les %d proches restent servies"
			% TorchLights.COUNT)
	_clear()


func _looks_differ() -> void:
	print("\n[5] Apparence propre a chaque source")
	_clear()
	_player.global_position = Vector3(0, 0, 0)
	_place(Vector3i(2, 0, 0), Blocks.TORCH)
	_place(Vector3i(-2, 0, 0), Blocks.LAVA)
	_step()

	var torch_light: OmniLight3D = null
	var lava_light: OmniLight3D = null
	for light in _lights._pool:
		if light.light_energy <= 0.001:
			continue
		if light.global_position.distance_to(Vector3(Vector3i(2, 0, 0)) + TorchLights.OFFSET) < 0.01:
			torch_light = light
		elif light.global_position.distance_to(Vector3(Vector3i(-2, 0, 0)) + TorchLights.OFFSET) < 0.01:
			lava_light = light

	if torch_light == null or lava_light == null:
		_fail("torche et lave ne sont pas toutes deux eclairees")
		return
	if torch_light.light_color.is_equal_approx(lava_light.light_color):
		_fail("la lave et la torche ont exactement la meme couleur (%s)"
			% str(torch_light.light_color))
	else:
		_ok("la lave est rouge et la torche orangee")
	if is_equal_approx(torch_light.omni_range, lava_light.omni_range):
		_fail("la lave et la torche ont la meme portee (%.2f)" % torch_light.omni_range)
	else:
		_ok("portees differentes : torche %.2f, lave %.2f"
			% [torch_light.omni_range, lava_light.omni_range])

	# Le vacillement doit decoreler les deux torches voisines, sinon elles
	# respirent en phase et l'effet de flamme s'effondre.
	_clear()
	for x in [2, 3]:
		_place(Vector3i(x, 0, 0), Blocks.TORCH)
	_step()
	var samples: Array[float] = []
	for i in 20:
		_lights._advance(0.05)
		samples.append(_lights._pool[0].light_energy)
	var lo := samples[0]
	var hi := samples[0]
	for s in samples:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	if hi - lo <= 0.0001:
		_fail("l'energie ne vacille pas du tout")
	else:
		_ok("la flamme vacille (%.3f a %.3f)" % [lo, hi])
