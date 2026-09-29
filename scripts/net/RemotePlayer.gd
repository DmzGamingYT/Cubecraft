class_name RemotePlayer
extends Node3D

## Avatar d'un joueur distant : le meme `PlayerBody` que le joueur local, mais
## anime par les poses recues sur le reseau au lieu du clavier.
##
## Les poses arrivent quinze fois par seconde, et le rendu tourne soixante fois :
## le personnage se deplacerait donc par bonds de soixante millimetres. On le
## lisse donc en interpolant vers la derniere position connue, a une vitesse
## proportionnelle au temps — ainsi l'ecart reste le meme a 30 comme a 144
## images par seconde.
##
## Le personnage ne fait pas de physique : il traverse les murs plutot que de
## buter dessus. Un joueur distant qui traverse un mur est agacant, mais lui
## faire de la collision demanderait de rejouer tout son chemin de collision a
## chaque image, pour un resultat approximatif. La position recue fait foi.

## Vitesse de rattrapage, en unites de distance par seconde restantes. Plus
## haute, l'avatar colle a sa cible mais parait plus « colle » ; plus basse, il
## glisse.
const FOLLOW_RATE := 14.0
## Au-dela, la cible est tenue pour obsolete : le joueur a coupe sa connexion
## sans que l'hote nous previenne, et l'avatar doit s'arreter net plutot que de
## continuer a deriver vers un point qu'il n'atteindra jamais.
const STALE_AFTER := 2.0
## Au-dela de cette distance, l'avatar est replace d'un coup plutot que glisse :
## une teleportation n'a pas d'historique, et interpoler dessus ferait traverser
## tout le monde.
const TELEPORT_DISTANCE := 12.0

var peer_id := 1
var player_name := "Joueur"
var skin_index := 0
## Angle de regard, en radians autour de l'axe vertical.
var yaw := 0.0

var _body: PlayerBody
var _label: Label3D
var _target := Vector3.ZERO
var _target_yaw := 0.0
var _speed := 0.0
var _grounded := true
var _since_update := 0.0


func _ready() -> void:
	# L'etiquette reste lisible de loin : `Label3D` est billboard, et sa taille
	# est en unites de monde, donc elle grandit avec la distance au lieu de
	# devenir illisible comme le ferait un texte plaque sur un quad.
	_label = Label3D.new()
	_label.text = player_name
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.0035
	_label.position = Vector3(0, PlayerBody.HEAD_Y + 0.28, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.shaded = false
	_label.double_sided = true
	_label.outline_render_priority = 1
	add_child(_label)
	_rebuild_body()


func set_player_info(display_name: String, skin: int) -> void:
	player_name = display_name
	skin_index = skin
	if _label != null:
		_label.text = display_name
		if _body != null and is_instance_valid(_body):
			# On ne reconstruit que si la tenue change reellement : le corps est
			# anime en permanence, le detruire a chaque appel le ferait clignoter.
			if _body.skin_index != skin:
				_body.set_skin(skin)


## Nouvelle pose recue. C'est la seule voie d'entree de l'animation : l'avatar
## ne devine jamais rien de ce que fait le joueur distant.
func push_target(pos: Vector3, new_yaw: float, speed: float, grounded: bool) -> void:
	_target = pos
	_target_yaw = new_yaw
	# Le champ public `yaw` reflete l'orientation **visee**, pas la
	# rotation effectivement rendue, qui suit par interpolation. Il doit
	# changer des la reception : c'est lui que lisent l'etiquette et le HUD,
	# et `Net.avatar_yaw()` s'en sert pour verifier une pose recue.
	yaw = new_yaw
	_speed = speed
	_grounded = grounded
	_since_update = 0.0


func _process(delta: float) -> void:
	_since_update += delta
	if _body == null or not is_instance_valid(_body):
		return

	# Une pose obsolete ne doit plus deplacer l'avatar : sinon il glisse
	# indefiniment vers sa derniere cible connue.
	var stale := _since_update > STALE_AFTER
	var speed_for_anim := 0.0 if stale else _speed
	# En l'air, les membres se replient ; on garde le dernier solage connu.
	_body.animate(delta, speed_for_anim, _grounded)

	if stale:
		# L'avatar garde sa position mais se tourne vers sa cible s'il en
		# reste une : un joueur coupe ne doit pas figer face au mur.
		return

	var to_target := _target - global_position
	if to_target.length() > TELEPORT_DISTANCE:
		# Trop loin pour etre un mouvement : c'est une apparition, un rendu
		# qui s'ecarte, ou une reprise apres une coupure. On se replace.
		global_position = _target
		rotation.y = _target_yaw
		return
	global_position += to_target * (1.0 - exp(-FOLLOW_RATE * delta))
	# L'orientation est interpolee par le plus court chemin : sans cela un
	# avatar qui passe de 3,13 a -3,13 radians fait un tour complet.
	rotation.y = lerp_angle(rotation.y, _target_yaw, 1.0 - exp(-12.0 * delta))


## La tenue a change : on reconstruit le corps.
func _rebuild_body() -> void:
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = PlayerBody.new()
	_body.name = "Corps"
	_body.skin_index = skin_index
	add_child(_body)
	_body.animate(0.016, 0.0, true)


## Le joueur distant mine ou pose un bloc : on leve les bras.
func set_arms_raised(raised: bool) -> void:
	if _body != null and is_instance_valid(_body):
		_body.raise_arm(raised)
