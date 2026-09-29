class_name TorchLights
extends Node3D

## Eclairage dynamique des sources de lumiere du monde.
##
## Plutot que d'allumer une OmniLight3D par torche (couts incontrolables), un
## petit pool de lumieres est assigne en continu aux sources les plus proches
## du joueur. Le monde tient a jour la liste des blocs emissifs (voir
## World.set_block), ce qui evite tout balayage de la grille.
##
## Deux choses distinguent cette version de la precedente.
##
## L'affectation est **collante**. A chaque recalcul on redistribue les sources
## par distance, ce qui fait sauter la lumiere n-ieme d'une torche a l'autre
## des que le joueur avance : huit lumieres invisibles qui se teleportent
## toutes les deux frames. Ici une source garde sa lumiere tant qu'elle reste
## dans le champ, si bien que le joueur traverse un couloir de torches sans
## voir bouger la lumiere qui l'eclaire. Les emplacements libres — et eux seuls
## — recoivent alors les sources restantes, les plus proches d'abord. Une lumiere
## qui se libere s'eteint sur place et ne redevient disponible qu'une fois
## completement noire : sans cela elle se deplacerait en plein fondu.
##
## L'apparence suit la source. Le monde ne compte pas que des torches : la lave
## et la table d'enchantement emissent aussi, avec des `light` et des couleurs
## tres differents. Une copie unique du meme couple couleur/energie donnait une
## table d'enchantement orangée aussi vive qu'une torche. La couleur et la
## portee sont donc lues sur le bloc, et seule la torche vacille vraiment.

## Nombre de lumieres simultanees. Le cout est lineraire en OmniLight3D, et
## le moteur plafonne le nombre de lumieres affectant un objet : au-dela de ce
## reservoir, les lumieres les plus lointaines ne sont plus calculees du tout.
const COUNT := 16

## Portee maximale, avant correction selon la source : une torche l'emporte
## sur la table d'enchantement, qui n'illumine que le pied du joueur.
const BASE_RANGE := 5.0
const RANGE_PER_LIGHT := 0.35

## Energie a pleine puissance. Calibrée pour que la torche garde exactement
## l'eclat qu'elle avait quand c'etait la seule source presente au projet.
const BASE_ENERGY := 0.6
const ENERGY_PER_LIGHT := 0.075

## Vitesse de montee et de descente. Une torche posee doit laisser une
## empreinte immediate — une lampe qui s'allume en trois secondes donne
## l'impression d'un bug — mais l'extinction peut etre plus progressive :
## c'est ce que distingue la lumiere posee de celle qu'on vient de retirer.
const FADE_IN := 6.0
const FADE_OUT := 4.0

## Vacillement. Amplitude relative et vitesse angulaire, en radians par
## seconde. Deux sources voisines ne doivent pas pulser en phase, sinon
## l'illusion de flamme s'effondre en un clignotement collectif.
const FLICKER := 0.06
const FLICKER_SPEED := 6.0

## Decalage vertical du centre lumineux. La torche est un bloc entier mais sa
## flamme n'occupe que le haut : eclairer le centre du bloc creuserait un
## trou noir juste sous le feu.
const OFFSET := Vector3(0.5, 0.55, 0.5)

## Cadence du recalcul d'affectation. L'energie, elle, est integree a chaque
## image — separer les deux evite de faire vibrer la flamme par pas de 0,2 s.
const UPDATE_INTERVAL := 0.2

## Distance au-dela de laquelle une source cesse d'etre suivie. Un peu
## generous : une lumiere qu'on laisse tourner hors de vue coute moins cher
## qu'un coude qui s'allume une fraction de seconde apres le deplacement.
const LEASH := 1.6

## Position sentinelle : aucune source. Y ne peut pas valoir -1 dans le monde
## (les blocs commencent a 0), donc aucune vraie position ne peut se confondre
## avec elle.
const NONE := Vector3i(-1, -1, -1)

## Teintes des sources connues. Cle : identifiant de bloc.
const COLORS := {
	Blocks.LAVA: Color(1.0, 0.40, 0.14),
	Blocks.ENCHANTING_TABLE: Color(0.46, 0.62, 1.0),
}

## Couleur par defaut : le orange chaud d'une flamme, bon aussi pour toute
## source future qu'on oublierait d'inscrire ci-dessus.
const DEFAULT_COLOR := Color(1.0, 0.78, 0.48)

## Sources qui ne doivent pas vaciller. La lave bout de facon reguliere ; lui
## donner le tremblelement d'une flamme la ferait ressembler a une torche.
const STEADY := [Blocks.LAVA, Blocks.ENCHANTING_TABLE]

var world: World

## Cible suivie par le pool. `Main` y branche le joueur. On ne va pas lire
## `Game.player` directement : un composant d'eclairage n'a rien a faire du
## singleton global, et surtout il devient testable hors du jeu.
var follow: Node3D

var _pool: Array[OmniLight3D] = []
var _held: Array[Vector3i] = []     ## source servie par chaque lumiere
var _energy: Array[float] = []      ## energie courante, pour les fondus
var _phase: Array[float] = []       ## decalage de phase, pour decoreler
var _timer := 0.0
var _age := 0.0


func _ready() -> void:
	for i in COUNT:
		var light := OmniLight3D.new()
		light.light_color = DEFAULT_COLOR
		light.light_energy = 0.0
		light.omni_range = BASE_RANGE
		light.omni_attenuation = 1.15
		# Seize ombres portees de plus de six faces, ca ne tient sur aucune
		# carte d'integrateur d'un jeu qui doit garder soixante images par
		# seconde. Les torches n'en projettent aucune : c'est un compromis
		# conscient, et le seul endroit du projet ou il l'etait.
		light.shadow_enabled = false
		add_child(light)
		_pool.append(light)
		_held.append(NONE)
		_energy.append(0.0)
		# e en or, e en pi : deux torches posees cote a cote ne doivent pas
		# respirer ensemble.
		_phase.append(float(i) * 2.39996)


func _process(delta: float) -> void:
	if world == null or follow == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_INTERVAL
		_reassign()
	_advance(delta)


## Repartition des sources sur le pool, une fois toutes les cinq images.
func _reassign() -> void:
	var origin := follow.global_position

	# 1. Les sources dans le ressort, les plus proches d'abord. On borne par
	#    le ressort et non par la portee maximale constante : une table
	#    d'enchantement n'eclaire que sept cases, inutile de la suivre jusque
	#    dans la piece d'a cote.
	var leash := (BASE_RANGE + 15.0 * RANGE_PER_LIGHT) * LEASH
	var leash2 := leash * leash
	var candidates: Array = []
	for pos: Vector3i in world.torches:
		if origin.distance_squared_to(Vector3(pos)) <= leash2:
			candidates.append(pos)
	candidates.sort_custom(func(a, b):
		return origin.distance_squared_to(Vector3(a)) < origin.distance_squared_to(Vector3(b)))

	# 2. Ce que chaque lumiere garde. Une source encore dans le ressort garde
	#    sa lumiere : c'est tout l'interet de l'affectation collante.
	var wanted: Array[Vector3i] = []
	var taken := {}
	for i in COUNT:
		var pos: Vector3i = _held[i]
		if pos != NONE and not taken.has(pos) and candidates.has(pos):
			wanted.append(pos)
			taken[pos] = true
		else:
			wanted.append(NONE)

	# 3. Les emplacements libres — et eux seuls — recoivent le reste, par
	#    ordre de distance. Une lumiere qui s'eteint n'est pas encore libre :
	#    la reconnecter ici la ferait bouger en plein fondu.
	var free: Array[int] = []
	for i in COUNT:
		if wanted[i] == NONE and _energy[i] <= 0.0:
			free.append(i)
	for pos: Vector3i in candidates:
		if taken.has(pos):
			continue
		if free.is_empty():
			break
		var i: int = free.pop_front()
		wanted[i] = pos
		taken[pos] = true

	# 4. Application. Une lumiere qui change de source se deplace a froid : on
	#    la pose sur la nouvelle position avant meme de lui rendre son
	#    energie, le joueur n'a donc rien vu bouger.
	for i in COUNT:
		if wanted[i] == _held[i]:
			continue
		_held[i] = wanted[i]
		if wanted[i] == NONE:
			continue   # elle s'eteindra sur place
		_pool[i].global_position = Vector3(wanted[i]) + OFFSET
		_looks(i, world.get_block(wanted[i]))


## Energie de chaque lumiere, image par image : c'est ici que le fondu et le
## vacillement vivent, hors du pas de 0,2 s du recalcul d'affectation.
func _advance(delta: float) -> void:
	_age += delta
	for i in COUNT:
		var lit: bool = _held[i] != NONE
		var target := _target_energy(i) if lit else 0.0
		var speed := FADE_IN if lit else FADE_OUT
		_energy[i] = move_toward(_energy[i], target, speed * delta)
		var e := _energy[i]
		# Un multiplicateur, jamais un offset : un fondu doit finir exactement
		# a zero, sans trainard numerique.
		if lit:
			e *= 1.0 + FLICKER * sin(_age * FLICKER_SPEED + _phase[i])
		_pool[i].light_energy = e
		# Une lumiere completement noire a rendu sa place : on le dit ici,
		# parce que c'est le seul endroit ou l'on sait qu'elle l'a rendu.
		if _held[i] != NONE and e <= 0.0:
			_held[i] = NONE


## Energie cible d'une lumiere, lue sur la source qu'elle sert.
func _target_energy(i: int) -> float:
	var block_id := world.get_block(_held[i]) if world != null else -1
	return BASE_ENERGY + ENERGY_PER_LIGHT * Blocks.light_of(block_id)


## Applique couleur et portee correspondant au bloc emissif. Les lumieres
## n'etaient pas interchangeables : une meme couleur pour la lave et pour la
## torche transformait une coulée en feu de camp.
func _looks(index: int, block_id: int) -> void:
	var light := _pool[index]
	light.light_color = COLORS.get(block_id, DEFAULT_COLOR)
	light.omni_range = BASE_RANGE + RANGE_PER_LIGHT * Blocks.light_of(block_id)
	if STEADY.has(block_id):
		# Pas de phase, pas de vacillement : la lave bout de facon reguliere.
		_phase[index] = 0.0
