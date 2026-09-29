class_name PauseMenu
extends Control

## Menu de pause, compose comme le « Game Menu » de Minecraft : un panneau
## centre et etroit qui ne mord pas sur la partie, une colonne de boutons de
## meme largeur — le premier en vert, celui qu'on presse dans presque tous les
## cas — les reglages dans un encart a part, les deux boutons de sortie en bas,
## et les raccourcis sous le panneau, ou ils n'ecrasent plus sa largeur.
##
## Les lignes de reglage viennent de `UiKit.mc_stepper` : c'est le meme composant
## que celui du panneau « Reglages » du menu de lancement, et les deux se
## ressemblent ligne pour ligne. Pas les valeurs, toutefois : celles du
## titre viennent de `Settings` et s'appliquent au lancement suivant,
## ceux d'ici agissent sur la partie en cours.
##
## L'ecran ne se pilote pas par `open()` : c'est le HUD qui l'affiche, chaque
## image, d'apres l'etat de pause. Les valeurs des reglages sont donc
## rafraichies sur `visibility_changed` — `open()`, appele par personne,
## laissait les trois reglages vides tant qu'on n'avait pas clique sur une
## fleche.

signal resume_requested
signal title_requested

## Duree de l'apparition. Le panneau ne tombe pas du ciel : il s'eclaire et se
## pose, comme le menu de l'ecran titre.
const FADE_IN := 0.16
## Taille de depart du panneau : legerement reduit, il reprend la sienne.
const ENTRY_SCALE := 0.96
## Opacite du voile derriere le panneau. Au-dela, le monde gele disparait et le
## menu flotte dans le noir ; en dessous, la partie reste lisible a travers.
const BACKDROP_ALPHA := 0.66
## Largeur demandee pour une ligne de reglage. Elle vaut ici bien moins que les
## 340 px du panneau « Reglages » du titre : la ligne se retracte a la largeur
## de ses contenus, l'encart se referme sur la colonne de boutons, et le menu
## garde la taille d'un panneau de jeu plutot que celle d'une page de reglage.
const ROW_WIDTH := 240.0

var _view_label: Label
var _status: Label
var _panel: PanelContainer
var _tween: Tween
## Les lignes de reglage, par cle. Elles sont recuperees par leur nom
## d'enfant (« Valeur », « Moins », « Plus ») plutot que par des variables :
## une ligne reconstruite ne laisse pas un pointeur vers un bouton disparu.
var _settings: Dictionary = {}


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	# L'ecran reste vivant pendant la pause : c'est ce qui permet a la
	# transition d'animer alors que l'arbre est fige, et a F4 de donner le menu
	# de diagnostic par-dessus.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visibility_changed.connect(_on_visibility_changed)
	visible = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, BACKDROP_ALPHA)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_screen(backdrop)
	add_child(backdrop)

	# Un `Control` seul ne se centre pas : `set_anchors_preset` pose les
	# ancres sur 0.5 mais laisse les offsets heritagees de la taille precedente,
	# ce qui decale le panneau. On passe donc par un `CenterContainer`, qui
	# recalcule la position a chaque image.
	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Le bloc contient le panneau **et** la ligne d'aide, qui est plus large que
	# lui : les deux se centrent ensemble. Le panneau se retracte a sa largeur
	# minimale plutot que de s'etaler sur celle de l'aide, d'ou le
	# `SIZE_SHRINK_CENTER` — sans lui, la ligne de raccourcis elargissait le
	# panneau de plus de 80 px, ce qu'elle faisait avant.
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(block)

	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_stylebox_override("panel",
		UiKit.panel(UiKit.BG_SOLID, 2, UiKit.ACCENT, 6))
	block.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	# Le nom de l'ecran est celui de Minecraft : « Menu de jeu ». « Pause » ne
	# dit pas ce qu'on y fait, et ne se retrouve dans aucun autre jeu.
	var title := UiKit.label("Menu de jeu", 20, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var resume := UiKit.mc_primary_button("Reprendre")
	resume.pressed.connect(func(): resume_requested.emit())
	column.add_child(resume)

	var save_button := UiKit.mc_button("Sauvegarder")
	save_button.pressed.connect(_on_save)
	column.add_child(save_button)

	var load_button := UiKit.mc_button("Charger la sauvegarde")
	load_button.pressed.connect(_on_load)
	column.add_child(load_button)

	_build_settings(column)

	# Ligne de retour : hauteur fixe, sinon le panneau saute d'une ligne a la
	# premiere sauvegarde.
	_status = UiKit.label("", 13, UiKit.TEXT_DIM)
	_status.custom_minimum_size = Vector2(0, 18)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_status)

	# Largeur nulle : le trait prend la place disponible, celle de la colonne.
	column.add_child(UiKit.divider(0.0))

	var title_button := UiKit.mc_button("Retour au titre")
	title_button.pressed.connect(func(): title_requested.emit())
	column.add_child(title_button)

	var quit := UiKit.mc_button("Quitter")
	quit.pressed.connect(func(): Game.quit_game())
	column.add_child(quit)

	# Sous le panneau, et plus dedans : Minecraft ecrit « Esc to close » sous
	# la fenetre, jamais dans la colonne de boutons. C'est aussi ce qui rend le
	# panneau etroit.
	var hint := UiKit.label("Échap  reprendre   •   F3  informations   •   "
		+ "F4  diagnostic   •   F6  rendu", 12, UiKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	block.add_child(hint)


## Les trois reglages, dans un encart qui les separe des actions.
##
## Ils occupaient chacun trois lignes — les fleches, la valeur au-dessus, le
## libelle en dessous — et repetaient le libelle que la valeur portait deja
## (« Rendu : Vif » puis « Rendu (F6) »). Une ligne chacun, libelle a gauche et
## controle a droite, comme le menu d'options de Minecraft.
func _build_settings(column: VBoxContainer) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	column.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	# En gris, et non dans la couleur d'accent comme un titre de section : le
	# panneau porte deja le vert de son titre et de son arete, un second vert
	# dans l'encart competitionnerait avec lui.
	var caption := UiKit.label("Réglages", 13, UiKit.TEXT_DIM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)

	# --- Portee de rendu : plus elle est grande, plus le monde coute cher.
	_add_setting(box, "distance", "Portée de rendu", _change_distance)

	# --- Meteo : forcee ou automatique.
	_add_setting(box, "weather", "Météo", _change_weather)

	# --- Rendu : le meme cycle que la touche F6, avec ses deux sens.
	_add_setting(box, "render", "Rendu", _change_render)

	# Ce que vaut la distance en blocs : l'information que la valeur ne porte
	# plus, et qui se lisait dans la colonne de droite avant.
	_view_label = UiKit.label("", 12, UiKit.TEXT_DIM)
	_view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_view_label)


## Encart des reglages : un fond plus sombre que le panneau et une arete
## discrete. Le panneau du jeu est deja sombre — un fond plus clair se
## confondrait avec les boutons ; c'est en s'enfonçant qu'on distingue un
## reglage d'une action.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.08, 1.0)
	style.border_color = Color(0.30, 0.31, 0.34, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## Une ligne de reglage du composant commun, cablee sur les deux pas. La ligne
## est retenue sous sa cle : sa valeur se relit ensuite par son nom d'enfant.
func _add_setting(box: VBoxContainer, key: String, caption: String,
		step: Callable) -> void:
	var row := UiKit.mc_stepper(caption, "", ROW_WIDTH)
	var minus: Button = row.get_node("Moins")
	var plus: Button = row.get_node("Plus")
	minus.pressed.connect(func(): step.call(-1))
	plus.pressed.connect(func(): step.call(1))
	box.add_child(row)
	_settings[key] = row


## Ecrit la valeur d'une ligne. Le noeud est cherche a chaque fois plutot que
## conserve dans une variable : c'est la ligne qui fait autorite, et une ligne
## reconstruite ne peut pas laisser un pointeur vers l'ancienne.
func _set_setting(key: String, text: String) -> void:
	var row: HBoxContainer = _settings.get(key)
	if row == null:
		return
	var value: Label = row.get_node("Valeur")
	value.text = text


# -------------------------------------------------------------- apparition

## Le HUD affiche et masque l'ecran directement sur l'etat de pause : c'est
## donc le passage a visible qui doit rafraichir les reglages, et non
## `open()`. Sans cela les trois valeurs restaient vides tant que le joueur
## n'avait pas clique sur une fleche — et elles etaient vide a chaque
## premiere ouverture, les captures du menu pause le montraient.
func _on_visibility_changed() -> void:
	if not visible:
		return
	_status.text = ""
	_update_distance()
	_update_weather()
	_update_render()
	_play_entry()


## Le panneau s'eclaire et se pose depuis 96 % de sa taille. Il est deja la,
## a sa place : la transition ne sert qu'a dire qu'il vient d'arriver.
func _play_entry() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# Un `Control` tourne autour de son coin superieur gauche par defaut :
	# sans pivot au centre, la pose partirait de travers.
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * ENTRY_SCALE
	_panel.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.tween_property(_panel, "scale", Vector2.ONE, FADE_IN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ reglages

## Le reglage du rendu : le meme cycle que la touche F6, avec ses deux sens.
func _change_render(delta: int) -> void:
	if Game.postfx == null:
		return
	Game.postfx.step(delta)
	_update_render()


func _update_render() -> void:
	_set_setting("render", Game.postfx.preset_name() if Game.postfx != null else "—")


func open() -> void:
	visible = true
	_on_visibility_changed()


func close() -> void:
	visible = false


func _change_distance(delta: int) -> void:
	Game.world.set_render_distance(Game.world.render_distance + delta)
	_update_distance()


func _update_distance() -> void:
	if Game.world == null:
		return
	_set_setting("distance", "%d chunks" % Game.world.render_distance)
	# La valeur ne porte plus la largeur vue en blocs : elle revient sous
	# l'encart, ou elle se lit sans ecarter les fleches.
	_view_label.text = "Vue de %d × %d blocs" % [
		Game.world.render_distance * 2 + 1, Game.world.render_distance * 2 + 1]


func _change_weather(delta: int) -> void:
	if Game.weather == null:
		return
	var count := Weather.MODES.size()
	Game.weather.set_mode(posmod(Game.weather.mode_index() + delta, count))
	_update_weather()


func _update_weather() -> void:
	_set_setting("weather", Game.weather.mode_name() if Game.weather != null else "—")


func _on_save() -> void:
	_status.text = "Sauvegardé." if Game.save_game() else "Échec de la sauvegarde."
	_status.modulate = Color(0.7, 1.0, 0.7)


func _on_load() -> void:
	_status.text = "Sauvegarde introuvable." if not Game.load_game() else "Chargé."
	_status.modulate = Color(0.7, 1.0, 0.7)
