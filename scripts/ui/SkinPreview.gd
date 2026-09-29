class_name SkinPreview
extends Control

## Apercu 3D du personnage dans le menu titre : un petit monde independant ou
## le personnage cubique marche sur place, avec sa vraie skin, ses bras qui
## balancent et son ombre au sol. Fond transparent pour laisser voir la carte du
## menu derriere.
##
## Le personnage n'est pas dessine ici : c'est `PlayerBody`, le meme objet que
## celui qu'on voit en jeu et en multijoueur. L'apercu ne fait que l'eclairer et
## l'animer, ce qui garantit que le menu ne ment jamais sur le personnage.
##
## Le personnage ne tourne PAS tout seul : il suit la souris, comme le modele
## qu'on fait pivoter au glisser dans l'inventaire de Minecraft. Un mannequin qui
## tourne en boucle ne repond pas a la question qu'on lui pose — « et de dos,
## elle donne quoi, cette tenue ? » — puisqu'il faut attendre qu'il veuille bien
## se retourner.

## Hauteur de la fenetre d'apercu. La largeur, elle, suit la carte : le
## personnage grossit avec la fenetre au lieu de laisser des bandes vides.
const PREVIEW_HEIGHT := 236
## Rotation au glisser : radians par pixel de souris parcouru.
const DRAG_SPEED := 0.012
## Inclinaison maximale, en degres. Juste de quoi regarder le dessus du crane :
## plus fort, le personnage bascule hors de son ombre et a l'air de tomber —
## le pivot est aux pieds, pas au buste.
const PITCH_LIMIT := 14.0
## Orientation de depart, en degres : de trois quarts, visage vers la camera.
##
## Le personnage regarde vers -Z (l'avant de Godot) et la camera est posee a
## 45 degres, dans le coin +X +Z : il faut donc -110 degres pour lui faire face
## en le tournant d'un quart vers la droite. A 0 il montre son dos — ce qui etait
## invisible du temps ou il tournait tout seul, mais saute aux yeux sur une pose
## fixe.
const START_YAW := -110.0

var skin_index := 0

var _root_3d: Node3D
var _body: PlayerBody
var _skin_label: Label
var _shadow: MeshInstance3D
## Orientation courante du personnage. Elle ne bouge qu'a la souris.
var _yaw := deg_to_rad(START_YAW)
var _pitch := 0.0
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, PREVIEW_HEIGHT)
	# L'apercu prend la souris : c'est lui qui la suit. Le `SubViewportContainer`
	# qui le remplit reste transparent aux clics, donc les evenements remontent
	# jusqu'ici sans traverser la carte du menu.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var container := SubViewportContainer.new()
	container.stretch = true
	UiKit.fill_screen(container)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	var view := SubViewport.new()
	view.transparent_bg = true
	view.own_world_3d = true
	view.size = Vector2i(292, PREVIEW_HEIGHT)
	# Seulement quand le menu est visible : un viewport cache en
	# UPDATE_ALWAYS continue de rendre et perturbe la boucle de capture.
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(view)

	# La camera est reculee et cadre plus serre que dans une fenetre haute : la
	# carte du menu est plus large que haute, et le personnage doit y tenir en
	# entier — tete et bottes comprises.
	var camera := Camera3D.new()
	camera.position = Vector3(3.0, 1.72, 3.0)
	camera.fov = 32.0
	camera.current = true
	view.add_child(camera)
	# La cible est a mi-hauteur du buste, pas au sol : la camera cadre alors le
	# personnage en entier au lieu de le couper aux epaules.
	camera.look_at(Vector3(0, 0.90, 0))


	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.25
	view.add_child(sun)

	# Deux lumieres de remplissage opposees : le cote du personnage tourne a
	# l'ecart du soleil reste lisible au lieu de devenir une silhouette noire.
	# L'apercu n'a pas d'environnement, donc pas de lumiere ambiante — sans ces
	# deux lampes, la moitie du personnage serait noire une fois sur deux.
	for offset in [Vector3(-1.6, 1.9, 1.4), Vector3(1.8, 1.2, -1.6)]:
		var fill := OmniLight3D.new()
		fill.position = offset
		fill.light_energy = 0.60
		fill.omni_range = 6.0
		view.add_child(fill)

	# Conteneur du personnage : il pivote sur lui-meme, independamment de la
	# camera — c'est lui que la souris fait tourner, ce qui laisse la lumiere
	# balayer les faces et revele la skin.
	_root_3d = Node3D.new()
	_root_3d.name = "Personnage"
	view.add_child(_root_3d)

	_build_character()

	# Ombre portee : une plaque sombre sous les pieds, sinon le personnage
	# semble flotter dans le vide.
	_shadow = MeshInstance3D.new()
	_shadow.name = "Ombre"
	var plate := BoxMesh.new()
	plate.size = Vector3(0.75, 0.02, 0.75)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.05, 0.04, 0.05, 0.5)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.mesh = plate
	_shadow.material_override = shadow_mat
	_shadow.position = Vector3(0, 0.01, 0)
	view.add_child(_shadow)

	# Une ligne discrete sous l'apercu : sur une image fixe, personne ne devine
	# qu'on peut la faire pivoter. Elle vit dans l'apercu et non dans la carte,
	# donc elle ne change pas la hauteur de la carte du menu.
	var hint := UiKit.label("glisser pour tourner", 11, Color(1, 1, 1, 0.40))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.anchor(hint, Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -16.0
	hint.offset_bottom = -2.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_apply_turn()


## Le personnage suit la souris : on appuie sur l'apercu et on glisse. Rien ne
## bouge tant qu'on ne glisse pas, et l'evenement est consomme — cliquer sur le
## personnage ne doit pas declencher le menu derriere.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		mouse_default_cursor_shape = (Control.CURSOR_DRAG if _dragging
			else Control.CURSOR_POINTING_HAND)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_turn(event.relative)
		accept_event()


## Applique un mouvement de souris : l'horizontale fait pivoter le personnage sur
## lui-meme (sans butee, on peut en faire le tour), la verticale l'incline un peu
## dans les deux sens, borne pour que les pieds restent sur leur ombre.
##
## Le sens est celui d'un objet qu'on attrape : on tire vers la droite, la face
## qu'on regarde part vers la droite.
func _turn(relative: Vector2) -> void:
	_yaw = wrapf(_yaw + relative.x * DRAG_SPEED, -PI, PI)
	_pitch = clampf(_pitch + relative.y * DRAG_SPEED,
		-deg_to_rad(PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
	_apply_turn()


## Le pivot est aux pieds, comme celui d'un modele de Minecraft : incliner fait
## basculer le personnage sur place au lieu de le faire tourner autour du buste.
func _apply_turn() -> void:
	if _root_3d != null:
		_root_3d.rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if _body == null or not is_visible_in_tree():
		return
	# Le personnage marche sur place, a vitesse de marche normale : les bras
	# balancent, les jambes avancent. Une vitesse nulle ferait un mannequin.
	_body.animate(delta, 2.6, true)
	# L'ombre se resserre quand le personnage se penche, et respire avec lui.
	if _shadow != null:
		# L'ombre se contracte quand le personnage se balance, au rythme de la
		# marche : une ombre parfaitement fixe trahirait que le corps est factice.
		_shadow.scale = Vector3.ONE * (1.0 - _body.swing_ratio() * 0.05)


## Nom de la tenue affichee, pour l'etiquette du menu.
func skin_name() -> String:
	return SkinFactory.skin_name(skin_index)


## Tenue suivante : on garde le meme personnage et on change seulement sa
## texture, donc pas de clignotement au changement de skin.
func next_skin() -> void:
	step_skin(1)


## Tenue precedente. Les deux sens existent parce que le menu presente un pas a
## pas : sans retour arriere, retrouver une tenue demandait de faire le tour.
func prev_skin() -> void:
	step_skin(-1)


## Avance ou recule de `delta` tenues, en boucle. Le personnage n'est pas
## reconstruit : seule sa texture change, donc rien ne clignote.
func step_skin(delta: int) -> void:
	skin_index = posmod(skin_index + delta, SkinFactory.count())
	_retexture()
	if _skin_label != null:
		_skin_label.text = skin_name()


func set_label(label: Label) -> void:
	_skin_label = label
	_skin_label.text = skin_name()


## Change la tenue du corps sans le reconstruire : `PlayerBody.set_skin` reutilise
## la hierarchie, et les membres gardent leur pose d'animation.
func _retexture() -> void:
	if _body == null:
		return
	if _body.skin_index == skin_index:
		return
	_body.set_skin(skin_index)


func _build_character() -> void:
	if _body != null:
		_body.queue_free()
	_body = PlayerBody.new()
	_body.name = "Corps"
	_body.skin_index = skin_index
	_root_3d.add_child(_body)
