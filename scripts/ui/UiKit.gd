class_name UiKit
extends RefCounted

## Petite charte graphique de l'interface : couleurs, tailles, fabrique de
## plaques. Tout est en pixels pour rester net quelle que soit la resolution.

const BG := Color(0.09, 0.09, 0.11, 0.94)
const BG_SOLID := Color(0.12, 0.12, 0.14, 1.0)
const SLOT := Color(0.28, 0.28, 0.31, 0.95)
const SLOT_HOVER := Color(0.44, 0.52, 0.40, 1.0)
const SLOT_SELECTED := Color(0.72, 0.76, 0.66, 1.0)
const BORDER := Color(0.05, 0.05, 0.06, 0.9)
const ACCENT := Color(0.55, 0.80, 0.45)
const TEXT := Color(0.93, 0.93, 0.91)
const TEXT_DIM := Color(0.68, 0.68, 0.66)

const SLOT_SIZE := 42
const SLOT_GAP := 4

## Plaques de bouton, du repos a l'appui. La face change de teinte, l'arete
## s'eclaircit et l'ombre portee se raccourcit a l'appui : le bouton s'enfonce.
const MC_FILL := Color(0.42, 0.44, 0.47)
const MC_FILL_HOVER := Color(0.46, 0.52, 0.66)
const MC_FILL_PRESSED := Color(0.30, 0.31, 0.34)
const MC_FILL_DISABLED := Color(0.26, 0.27, 0.29)
const MC_EDGE := Color(0.62, 0.65, 0.70)
const MC_EDGE_HOVER := Color(0.76, 0.84, 0.98)
const MC_EDGE_DIM := Color(0.36, 0.37, 0.39)
const MC_EDGE_FOCUS := Color(0.97, 0.97, 0.84)
const MC_PRIMARY := Color(0.29, 0.49, 0.28)
const MC_PRIMARY_HOVER := Color(0.36, 0.62, 0.33)
const MC_PRIMARY_EDGE := Color(0.64, 0.86, 0.56)
const MC_SHADOW := Color(0.0, 0.0, 0.0, 0.45)


static func panel(bg: Color = BG, border_width: int = 2, border_color: Color = BORDER,
		radius: int = 5) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func slot_style(fill: Color = SLOT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	return style


static func label(text: String, font_size: int = 15, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


static func button(text: String, font_size: int = 16) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.custom_minimum_size = Vector2(240, 40)
	_add_ui_sound(node)
	return node


## Bouton facon Minecraft : plaque bevelisee, arete claire, ombre portee sous la
## plaque. Au survol la face bleuit et l'arete s'eclaircit ; a l'appui l'ombre se
## raccourcit et la face s'assombrit. Utilise par tous les menus du jeu.
static func mc_button(text: String, font_size: int = 16) -> Button:
	var node := _mc_base(text, font_size)
	node.add_theme_stylebox_override("normal",
		_mc_plate(MC_FILL, MC_EDGE, Vector2(0.0, 3.0)))
	node.add_theme_stylebox_override("hover",
		_mc_plate(MC_FILL_HOVER, MC_EDGE_HOVER, Vector2(0.0, 3.0)))
	node.add_theme_stylebox_override("pressed",
		_mc_plate(MC_FILL_PRESSED, MC_EDGE_HOVER, Vector2(0.0, 1.0)))
	node.add_theme_stylebox_override("disabled",
		_mc_plate(MC_FILL_DISABLED, MC_EDGE_DIM, Vector2(0.0, 2.0)))
	node.add_theme_stylebox_override("focus",
		_mc_plate(MC_FILL, MC_EDGE_FOCUS, Vector2(0.0, 3.0)))
	return node


## Bouton principal : la meme plaque, en vert. Un seul par ecran, sur l'action
## que le joueur veut faire dans l'immense majorite des cas — « Jouer » au menu
## de lancement, « Creer le monde » dans le panneau des graines.
static func mc_primary_button(text: String, font_size: int = 17) -> Button:
	var node := _mc_base(text, font_size)
	node.add_theme_stylebox_override("normal",
		_mc_plate(MC_PRIMARY, MC_PRIMARY_EDGE, Vector2(0.0, 3.0)))
	node.add_theme_stylebox_override("hover",
		_mc_plate(MC_PRIMARY_HOVER, MC_EDGE_FOCUS, Vector2(0.0, 3.0)))
	node.add_theme_stylebox_override("pressed",
		_mc_plate(MC_PRIMARY.darkened(0.25), MC_PRIMARY_EDGE, Vector2(0.0, 1.0)))
	node.add_theme_stylebox_override("disabled",
		_mc_plate(MC_FILL_DISABLED, MC_EDGE_DIM, Vector2(0.0, 2.0)))
	node.add_theme_stylebox_override("focus",
		_mc_plate(MC_PRIMARY, MC_EDGE_FOCUS, Vector2(0.0, 3.0)))
	return node


## Charte commune aux deux boutons : texte clair ombre, survol jaune, et le bruit
## d'interface branche une fois pour toutes.
##
## `font_focus_color` est pose explicitement : sans lui, le bouton qui a le focus
## — le premier du menu, des l'ouverture — prend la couleur du theme par defaut
## et parait gris a cote de ses voisins.
static func _mc_base(text: String, font_size: int) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color(0.94, 0.94, 0.94))
	node.add_theme_color_override("font_focus_color", Color(0.94, 0.94, 0.94))
	node.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.78))
	node.add_theme_color_override("font_hover_pressed_color", Color(1.0, 1.0, 0.78))
	node.add_theme_color_override("font_pressed_color", Color(0.96, 0.96, 0.96))
	node.add_theme_color_override("font_disabled_color", Color(0.58, 0.58, 0.58))
	node.add_theme_color_override("font_shadow_color", Color(0.10, 0.10, 0.12))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 1)
	node.custom_minimum_size = Vector2(240, 40)
	_add_ui_sound(node)
	return node


## Branche les sons d'interface sur un bouton. C'est fait ici plutot qu'a
## chaque ecrat pour que le clic ne puisse pas etre oublie : un bouton du jeu
## qui ne fait pas de bruit se remarque immediatement.
##
## Le survol est coupe quand le bouton est desactive, sinon passer la souris
## sur une option indisponible produit quand meme un bruit.
static func _add_ui_sound(node: Button) -> void:
	node.pressed.connect(func():
		if node.disabled:
			return
		_play_ui_sound("ui_click", -3.0))
	node.mouse_entered.connect(func():
		if node.disabled:
			return
		_play_ui_sound("ui_hover", -16.0))


## Joue un son d'interface en retenant l'autoload par son nom, et non par
## son identifiant : le test de fumee instancie des ecrans hors du jeu, ou les
## autoloads n'existent pas, et un `Sounds.play_ui` ecrit directement ne
## compilerait meme pas dans ce contexte.
static func _play_ui_sound(sound: String, volume_db: float) -> void:
	var sounds := _sounds_node()
	if sounds == null:
		return
	sounds.play_ui(sound, volume_db)


static func _sounds_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Sounds")


## Plaque bevelisee : face pleine, arete claire de 2 px, coins carres, et une
## ombre portee decalee vers le bas. C'est l'ombre qui fait l'epaisseur de la
## plaque ; a l'appui elle se raccourcit et le bouton parait s'enfoncer.
static func _mc_plate(fill: Color, edge: Color, shadow_offset: Vector2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.shadow_color = MC_SHADOW
	style.shadow_size = 3
	style.shadow_offset = shadow_offset
	return style


## Carte de menu : fond translucide, arete claire, coins arrondis. Meme chose que
## `panel`, avec l'intention en plus : une carte laisse voir le decor derriere
## elle, un panneau du jeu en partie le cache.
static func card(bg: Color, edge: Color, radius: int = 8) -> StyleBoxFlat:
	return panel(bg, 2, edge, radius)


## Degrade vertical d'un pixel de large : la couleur du haut, celle du bas, et le
## nombre de paliers. Une seule colonne suffit — le `TextureRect` qui l'affiche
## l'etire a la taille voulue, et c'est ce qui remplace un fichier image.
static func gradient_texture(top: Color, bottom: Color, steps: int = 64) -> ImageTexture:
	var height := maxi(2, steps)
	var img := Image.create(1, height, false, Image.FORMAT_RGBA8)
	for y in height:
		img.set_pixel(0, y, top.lerp(bottom, float(y) / float(height - 1)))
	return ImageTexture.create_from_image(img)


## Champ de saisie sombre a bordure grise, pour la graine du monde.
static func mc_field(placeholder: String, font_size: int = 16) -> LineEdit:
	var node := LineEdit.new()
	node.placeholder_text = placeholder
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.08, 1.0)
	style.border_color = Color(0.55, 0.55, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	node.add_theme_stylebox_override("normal", style)
	node.add_theme_stylebox_override("focus", style)
	node.custom_minimum_size = Vector2(240, 40)
	return node


## Barre de progression carree, facon Minecraft : creux sombre a bordure
## claire, remplissage vert. Sans pourcentage : le chiffre est ecrit a cote,
## ce qui laisse la barre lisible meme quand elle est courte.
static func progress_bar(width: int = 380, height: int = 16) -> ProgressBar:
	var node := ProgressBar.new()
	node.show_percentage = false
	node.custom_minimum_size = Vector2(width, height)

	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	trough.border_color = Color(0.55, 0.55, 0.55)
	trough.set_border_width_all(2)
	trough.set_corner_radius_all(0)
	node.add_theme_stylebox_override("background", trough)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(0)
	node.add_theme_stylebox_override("fill", fill)
	return node


## Grille de boutons d'emplacements alignes sur une meme pas.
static func grid(columns: int, rows: int) -> GridContainer:
	var node := GridContainer.new()
	node.columns = columns
	node.add_theme_constant_override("h_separation", SLOT_GAP)
	node.add_theme_constant_override("v_separation", SLOT_GAP)
	return node


## Occupe toute la fenetre : ancres ET offsets.
##
## `set_anchors_preset(PRESET_FULL_RECT)` ne remet PAS les offsets a zero. Il ne
## pose que les ancres (0,0,1,1) et conserve les offsets existants, qui valent
## `-largeur, -hauteur` sur un `Control` deja dimensionne : le resultat est un
## rect de taille nulle en (0,0). Tout ce qui se centre dedans se retrouve
## alors colle en haut a gauche. C'est ce helper qu'il faut utiliser.
static func fill_screen(node: Control) -> void:
	anchor(node, Control.PRESET_FULL_RECT)


## Comme `set_anchors_preset`, mais les offsets repartent de zero.
static func anchor(node: Control, preset: int) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
