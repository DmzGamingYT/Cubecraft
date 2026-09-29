class_name Lobby
extends Control

## Salon d'attente : l'ecran que voit un joueur entre le moment ou il se
## connecte et le moment ou le monde existe.
##
## Sans lui, rejoindre une partie signifiait tomber directement dans un terrain
## en cours de generation, avec la tenue qu'on avait choisie dans le menu titre
## et personne autour. Ici on a le temps de se nommer, de choisir sa tenue, et
## de voir qui d'autre est deja arrive — c'est a ce moment qu'on decide de lancer
## ou de changer d'avis.
##
## L'ecran ne fait aucun calcul : il lit `Net.roster()`, et demande a `Net` de
## lancer la session. Toute la logique reste dans `Net`, ou elle est testee sans
## ecran.
##
## Les joueurs sont reellement dessines en 3D — les memes `PlayerBody` qu'en
## jeu, avec les memes skins — plutot que representes par une liste de noms. Voir
## les autres tourner sur eux-memes dans la vraie tenue dit plus, en un coup
## d'oeil, qu'une ligne de texte.

## L'hote a le bouton de lancement ; un client, non.
signal start_requested
## Le joueur a change de tenue : `skin` est le nouvel index.
signal skin_changed(skin: int)
## Le joueur a change de pseudo.
signal name_changed(display_name: String)
## Le joueur veut sortir du salon.
signal quit_requested

## Nombre de joueurs a faire tenir sur une rangee. Au-dela, la rangee s'etire
## et la camera recule plutot que de devenir illisible.
const MAX_SHOWN := 8
## Ecart entre deux personnages de la rangee, en unites de monde.
const SPACING := 1.5
## Hauteur de la camera au-dessus du sol du salon.
const CAMERA_HEIGHT := 2.05
## Distance de la camera a la rangee. Reculee quand les joueurs s'ajoutent.
const CAMERA_DISTANCE := 4.2

var is_host := false
var local_skin := 0
var local_name := "Joueur"

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _avatars: Dictionary = {}
var _rows: VBoxContainer
var _name_field: LineEdit
var _skin_label: Label
var _status: Label
var _start_button: Button
var _spin := 0.0


func _ready() -> void:
	UiKit.fill_screen(self)
	_build_background()
	_build_viewport()
	_build_panel()


## Un voile sombre derriere tout : le salon doit se lire comme un ecran a part
## entiere, et non comme une fenetre posee sur le monde.
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.07, 0.93)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_screen(bg)
	add_child(bg)


## La scene 3D du salon. Les personnages sont les vrais `PlayerBody`, places sur
## une rangee et lumierees comme des portraits.
func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	UiKit.fill_screen(container)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(640, 480)
	# Comme dans le menu titre, le viewport ne rend que lorsqu'il est visible :
	# en `UPDATE_ALWAYS` il tournerait en permanence pour rien.
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_camera.fov = 38.0
	_camera.current = true
	_viewport.add_child(_camera)
	_camera.look_at(Vector3(0, 0.95, 0))

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-25.0), 0.0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.2, 2.6)
	fill.light_energy = 0.5
	fill.omni_range = 9.0
	_viewport.add_child(fill)

	_stage = Node3D.new()
	_stage.name = "Scene"
	_viewport.add_child(_stage)


## Le panneau de droite : le choix de tenue, le pseudo, et la liste.
func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.panel(UiKit.BG_SOLID, 2, UiKit.BORDER, 6))
	panel.custom_minimum_size = Vector2(300, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-20, -190)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var heading := UiKit.label("Salon d'attente", 20)
	column.add_child(heading)

	var hint := UiKit.label(
		"Choisis ton apparence avant le lancement.\nL'hôte décide quand la partie commence.",
		13, UiKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	_name_field = UiKit.mc_field("Ton pseudo")
	_name_field.max_length = 16
	_name_field.text = local_name
	# `text_submitted` seulement : on ne veut pas qu'un coup de clavier
	# quelconque dans le salon parte sur le reseau, un signalement par lettre.
	_name_field.text_submitted.connect(_on_name_entered)
	column.add_child(_name_field)

	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 6)
	column.add_child(skin_row)

	var previous := UiKit.mc_button("<", 18)
	previous.custom_minimum_size = Vector2(44, 40)
	previous.pressed.connect(func(): _shift_skin(-1))
	skin_row.add_child(previous)

	_skin_label = UiKit.label("", 16)
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skin_row.add_child(_skin_label)

	var next := UiKit.mc_button(">", 18)
	next.custom_minimum_size = Vector2(44, 40)
	next.pressed.connect(func(): _shift_skin(1))
	skin_row.add_child(next)

	_skin_label.text = SkinFactory.skin_name(local_skin)

	column.add_child(UiKit.label("Joueurs", 16, UiKit.TEXT))

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.custom_minimum_size = Vector2(0, 90)
	column.add_child(_rows)

	_start_button = UiKit.mc_button("Lancer la partie")
	_start_button.pressed.connect(func(): start_requested.emit())
	column.add_child(_start_button)

	_status = UiKit.label("", 13, UiKit.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var leave := UiKit.mc_button("Quitter le salon")
	leave.pressed.connect(func(): quit_requested.emit())
	column.add_child(leave)

	_refresh_buttons()


## Le role decide qui peut lancer, et l'etat de la partie est dit en toutes
## lettres : un client qui attend doit comprendre pourquoi il attend.
func _refresh_buttons() -> void:
	_start_button.visible = is_host
	if is_host:
		_status.text = "Tu heberges la partie."
		_status.add_theme_color_override("font_color", UiKit.ACCENT)
	else:
		_status.text = "En attente du lancement par l'hôte…"
		_status.add_theme_color_override("font_color", UiKit.TEXT_DIM)


func set_host(value: bool) -> void:
	is_host = value
	if is_instance_valid(_start_button):
		_refresh_buttons()


## Remplace la liste des joueurs par celle que `Net` connait. Un `RemotePlayer`
## par joueur, place sur la rangee ; ceux qui partaient sont liberes.
##
## `roster` vient de `Net.roster()` : un tableau de `{id, name, skin, host}`.
func set_roster(roster: Array) -> void:
	# 1. Les departs.
	for id in _avatars.keys():
		if not _has_peer(roster, int(id)):
			var gone: Node = _avatars[id]
			if gone != null and is_instance_valid(gone):
				gone.queue_free()
			_avatars.erase(id)

	# 2. Les arrives et les changements de tenue.
	var shown := mini(roster.size(), MAX_SHOWN)
	for i in shown:
		var entry: Dictionary = roster[i]
		var id := int(entry.get("id", 0))
		var skin := int(entry.get("skin", 0))
		var avatar: PlayerBody = _avatars.get(id, null)
		if avatar == null or not is_instance_valid(avatar):
			avatar = PlayerBody.new()
			avatar.name = str(entry.get("name", "Joueur"))
			avatar.skin_index = skin
			_stage.add_child(avatar)
			_avatars[id] = avatar
		elif avatar.skin_index != skin:
			# `set_skin` n'echange que la texture : le personnage ne clignote pas.
			avatar.set_skin(skin)
		avatar.position = _slot(i, shown)

	# 3. Les joueurs au-dela de la limite restent connectes, simplement invisibles.
	for i in range(MAX_SHOWN, roster.size()):
		var hidden_id := int(roster[i].get("id", 0))
		if _avatars.has(hidden_id):
			var hidden: Node = _avatars[hidden_id]
			if hidden != null and is_instance_valid(hidden):
				hidden.queue_free()
			_avatars.erase(hidden_id)

	_frame_camera(shown)
	_rebuild_rows(roster)


func _has_peer(roster: Array, id: int) -> bool:
	for entry in roster:
		if int((entry as Dictionary).get("id", -1)) == id:
			return true
	return false


## Position d'un personnage sur la rangee. La rangee est centree, et l'ecart
## reste fixe : ajouter un joueur decale les autres plutot que de les
## resserrer, pour que personne ne soit change de place sous les yeux de
## quelqu'un d'autre.
func _slot(index: int, total: int) -> Vector3:
	var offset := (float(index) - float(total - 1) * 0.5) * SPACING
	return Vector3(offset, 0.0, 0.0)


## La camera recule quand la rangee s'allonge, pour garder tout le monde cadre.
func _frame_camera(total: int) -> void:
	if _camera == null or total <= 0:
		return
	var width := maxf(float(total - 1) * SPACING, 0.0)
	var distance := CAMERA_DISTANCE + width * 0.42
	_camera.position = Vector3(0.0, CAMERA_HEIGHT, distance)
	_camera.look_at(Vector3(0.0, 0.95, 0.0))


## La liste textuelle sous le portrait 3D. Elle ne remplace pas la scene : elle
## donne le pseudo, que l'etiquette 3D ne peut pas porter lisiblement a cette
## taille, et distingue l'hote.
func _rebuild_rows(roster: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()
	for entry in roster:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# L'identifiant sert de cle de tri et de rappel : deux joueurs peuvent
		# choisir le meme pseudo, et il faut alors pouvoir les distinguer.
		row.tooltip_text = "joueur %d" % int(entry.get("id", 0))
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.color = Color(0.45, 0.78, 0.42) if bool(entry.get("host", false)) \
			else Color(0.55, 0.55, 0.60)
		row.add_child(dot)

		var name_label := UiKit.label(str(entry.get("name", "Joueur")), 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		if bool(entry.get("host", false)):
			row.add_child(UiKit.label("hôte", 12, UiKit.ACCENT))
		else:
			row.add_child(UiKit.label(SkinFactory.skin_name(int(entry.get("skin", 0))),
				12, UiKit.TEXT_DIM))
		_rows.add_child(row)


func _process(delta: float) -> void:
	# Les personnages tournent lentement sur eux-memes : c'est la seule facon de
	# juger une tenue sur un personnage cubique, et cela evite que le salon
	# ressemble a une galerie de mannequins figes.
	_spin += delta
	for id in _avatars.keys():
		var avatar: Node3D = _avatars[id]
		if avatar == null or not is_instance_valid(avatar):
			continue
		avatar.rotation.y = _spin * 0.5 + float(int(id) % 7) * 0.9
		var body := avatar as PlayerBody
		if body != null:
			# Une marche sur place tres lente : le personnage vit, sans donner
			# l'impression de courir sur un podium.
			body.animate(delta, 0.8, true)


func _shift_skin(step: int) -> void:
	local_skin = wrapi(local_skin + step, 0, SkinFactory.count())
	_skin_label.text = SkinFactory.skin_name(local_skin)
	skin_changed.emit(local_skin)


func _on_name_entered(value: String) -> void:
	var clean := value.strip_edges().left(16)
	if clean.is_empty():
		# Un pseudo vide eloignerait le joueur de la liste : on garde le
		# precedent plutot que de l'effacer.
		_name_field.text = local_name
		return
	local_name = clean
	_name_field.text = clean
	name_changed.emit(clean)


## Le choix de tenue fait par le menu titre, repris a l'ouverture du salon.
func set_local(skin: int, display_name: String) -> void:
	local_skin = skin
	local_name = display_name
	if is_instance_valid(_skin_label):
		_skin_label.text = SkinFactory.skin_name(local_skin)
	if is_instance_valid(_name_field):
		_name_field.text = local_name
