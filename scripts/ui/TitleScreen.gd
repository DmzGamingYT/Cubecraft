class_name TitleScreen
extends Control

## Menu de lancement, ecrit from scratch : ciel procedural, soleil cube, deux
## couches de nuages en parallaxe et bande de terre, puis le logo, la carte de
## menu et celle du personnage.
##
## Signaux vers Main : `play_requested` (nouveau monde, graine + portee),
## `load_requested` (reprendre la sauvegarde), `quit_requested` (fermer le jeu),
## `host_requested` et `join_requested` (reseau), `skin_changed` (la tenue
## choisie dans l'apercu, que Main retient pour l'annoncer en multijoueur).
## Cet ecran ne connait pas l'autoload `Game` : c'est Main qui branche.
## Le test de fumee compile ce fichier sans arbre de scene.

signal play_requested(seed_value: int, distance: int)
signal load_requested
signal quit_requested
signal host_requested(seed_value: int, distance: int)
signal join_requested(address: String, port: int)
## La tenue de l'apercu a change.
signal skin_changed(index: int)

const SPLASHES := [
	"100% code !",
	"Sans aucun asset !",
	"Avec des arbres !",
	"Fait avec Godot !",
	"Punch trees !",
	"Gare a la bedrock !",
	"Torches incluses !",
	"Graines aleatoires !",
	"Caves garanties !",
	"97% d'air !",
]

## Duree du fondu depuis le noir quand l'ecran apparait.
const FADE_IN := 0.55
## Duree du fondu vers le noir quand on lance une partie.
const FADE_OUT := 0.30
## Secondes entre deux textes d'accroche.
const SPLASH_PERIOD := 5.5
## Decalage entre deux elements qui apparaissent.
const ENTRY_STEP := 0.05

# ------------------------------------------------------------------ geometrie
#
# Tout le menu tient dans une seule colonne large : le bandeau du logo, la
# rangee de cartes et la ligne d'aide partagent cet axe. C'est lui qui centre
# l'ensemble sur l'ecran — avant, le logo etait centre sur les boutons seuls, et
# le vide laisse a gauche se voyait.

## Largeur du bloc de menu.
const BLOCK_WIDTH := 814.0
## Largeur de la carte des boutons.
const MENU_WIDTH := 460.0
## Largeur de la carte du personnage.
const CARD_WIDTH := 320.0
## Hauteur du bandeau du logo.
const LOGO_HEIGHT := 96.0
## Largeur de la zone reservee a l'accroche, a droite du mot, et l'ecart entre
## les deux. Le mot et l'accroche forment un seul bloc, centre ensemble sur la
## bande : le mot n'est donc pas au milieu de l'ecran, mais le couple l'est —
## c'est ce que l'oeil voit. Les deux zones ne se chevauchent jamais, donc
## l'accroche ne peut plus passer sur les lettres.
##
## La zone fait la largeur d'une accroche courante — au corps 16, l'encre d'un
## texte tourne autour de 130 px, inclinaison comprise — et non celle de la plus
## longue. A 170 px, le couple se centrait 20 px trop a gauche : le vide de la
## zone se voyait. Elle est FIXE : une zone qui suivrait le texte ferait sauter
## le logo a chaque nouvelle accroche.
const SPLASH_WIDTH := 148.0
const LOGO_GAP := 20.0
## Texte et corps du logo. Le mot est mesure sur la police du theme pour etre
## place : c'est la seule mesure qui ne depende que du texte.
const LOGO_TEXT := "CUBECRAFT"
const LOGO_FONT_SIZE := 52
## Decalage de la derniere copie du logo. Il entre dans la largeur du bloc : sans
## lui, la tranche epaisse mordrait sur la zone de l'accroche.
const LOGO_STAGGER := 6.0
## Hauteur de la rangee de cartes. Les deux cartes la partagent, donc la
## composition garde exactement la meme hauteur d'un panneau a l'autre :
## changer de panneau ne fait plus sauter le menu.
const ROW_HEIGHT := 392.0
## Hauteur utile dans une carte : la rangee moins ses marges (14 px de chaque
## cote, voir `UiKit.card`).
const CARD_INNER := ROW_HEIGHT - 28.0
## Taille des boutons du menu du titre. Plus larges que ceux du jeu en partie :
## ici ils portent le nom d'une action, pas un objet.
const BUTTON_SIZE := Vector2(340, 46)
## Hauteur de la bande de terre, en part de la fenetre.
const GROUND_FRACTION := 0.22
## Hauteur de la bande d'herbe et de la brume d'horizon.
const GRASS_HEIGHT := 24.0
const HAZE_HEIGHT := 52.0
## Separations verticales du bloc de menu.
const BLOCK_GAP := 10.0
const HINT_HEIGHT := 20.0

# --------------------------------------------------------------------- teintes
## Fond des deux cartes : translucide, le ciel doit rester lisible derriere.
const CARD_BG := Color(0.07, 0.09, 0.12, 0.66)
const CARD_EDGE := Color(0.95, 0.97, 1.0, 0.18)
## Carte du personnage, un peu plus claire : le personnage s'y detache.
const SKIN_BG := Color(0.10, 0.12, 0.16, 0.78)
const HINT_COLOR := Color(1.0, 1.0, 1.0, 0.62)
const SKY_TOP := Color(0.25, 0.49, 0.93)
const SKY_BOTTOM := Color(0.80, 0.89, 0.98)
const SUN_COLOR := Color(1.0, 0.97, 0.80)
const SUN_CORE_COLOR := Color(1.0, 1.0, 0.94)
## Largeur de la lueur du soleil, en multiples de son cote, et son opacite au
## centre. La lueur est une tache radiale, pas un empilement de carres : leurs
## aretes se lisaient comme des rectangles colles dans le coin du ciel.
const GLOW_SCALE := 3.4
const GLOW_ALPHA := 0.55

# ------------------------------------------------------------------- etat
var _distance := 5
var _distance_label: Label
var _seed_field: LineEdit
var _main_box: VBoxContainer
var _new_box: VBoxContainer
var _net_box: VBoxContainer
var _address_field: LineEdit
var _port_field: LineEdit
var _message_label: Label
var _local_ip_label: Label
var _load_button: Button
var _play_button: Button
var _preview: SkinPreview
var _skin_index_label: Label
var _hint: Label
var _compo: VBoxContainer
var _splash: Label
var _splash_time := 0.0
var _splash_pop := 0.0
var _logo_holder: Control
## Le socle du mot : c'est lui qui donne sa largeur reelle au logo, mesuree au
## placement. Toutes les copies du mot font la meme taille, une seule suffit.
var _logo_ref: Label
var _splash_holder: Control
var _logo_time := 0.0
var _sun: Control
var _halo_layer: Control
var _glow: TextureRect
var _disc: ColorRect
var _core: ColorRect
var _sky: TextureRect
var _haze: TextureRect
var _grass: TextureRect
var _dirt: TextureRect
var _grass_edge: TextureRect
var _dirt_edge: TextureRect
var _ground_shade: TextureRect
var _vignette: TextureRect
var _clouds: Array = []
var _fade: ColorRect
var _fading_out := false
var _last_view := Vector2.ZERO
var _entry_nodes: Array[Control] = []
var _buttons: Array[Control] = []
var _entry_time := 0.0
var _entry_active := false
var _music_started := false


## Convertit le texte du champ graine : vide = aleatoire, entier = tel quel,
## autre texte = hache de facon deterministe. Fonction pure, testee en fumee.
static func parse_seed(text: String) -> int:
	var clean := text.strip_edges()
	if clean.is_empty():
		return randi()
	if clean.is_valid_int():
		return int(clean)
	return absi(hash(clean))


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_menu()
	# Le voile de fondu est pose en dernier : il couvre tout l'ecran titre,
	# ciel compris, et disparait a l'ouverture.
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.03, 0.05, 1.0)
	UiKit.fill_screen(_fade)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_layout()
	_play_entry()
	# La musique part au premier affichage de l'ecran, pas a la construction :
	# le noeud passe par un fondu d'ouverture de FADE_IN secondes, et une
	# musique qui demarre dessous se fait couper par l'entree.
	if visible:
		start_music()


## Lance la musique du menu apres le fondu d'ouverture. Le son ne demarre pas
## au meme instant que l'image : sur un ecran qui apparait, le son doit suivre
## de quelques dixiemes, sinon il semble declenche trop tot.
func start_music() -> void:
	if _music_started:
		return
	_music_started = true
	if _sounds_node() == null:
		return
	var timer := get_tree().create_timer(FADE_IN, true, false, true)
	timer.timeout.connect(func():
		if visible:
			var sounds := _sounds_node()
			if sounds != null:
				sounds.start_music())


## Coupe la musique en partant vers une partie : le fondu de FADE_OUT secondes
## doit rester sur un silence de plus en sourd, pas sur une note coupee.
func stop_music() -> void:
	var sounds := _sounds_node()
	if sounds != null:
		sounds.stop_music(FADE_OUT)


## L'autoload est cherche par son nom et non par son identifiant : le test de
## fumee instancie cet ecran hors du jeu, ou les autoloads n'existent pas.
static func _sounds_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Sounds")


func _process(delta: float) -> void:
	if not visible:
		return
	# Le decor suit la fenetre : le soleil, les nuages et le sol se replacent
	# des que sa taille change. Sans cela, agrandir la fenetre laissait le
	# soleil et les nuages la ou ils etaient, dans un coin de l'ecran.
	if _viewport_size() != _last_view:
		_layout()
	_animate_splash(delta)
	_animate_logo(delta)
	_animate_glow(delta)
	_animate_clouds(delta)
	_animate_entry(delta)


## Texte d'accroche : inclinaison qui oscille, et nouveau texte de temps en
## temps avec un petit rebond d'echelle, comme dans l'original.
func _animate_splash(delta: float) -> void:
	if _splash == null:
		return
	_center_pivot(_splash)
	_splash_time += delta
	_splash_pop = maxf(0.0, _splash_pop - delta * 3.5)
	_splash.rotation = -0.30 + 0.04 * sin(_splash_time * 2.2)
	_splash.scale = Vector2.ONE * (1.0 + 0.30 * _splash_pop)
	if _splash_time > SPLASH_PERIOD:
		_splash_time = 0.0
		_splash_pop = 1.0
		_splash.text = _pick_splash()


## Le logo flotte doucement : c'est ce qui donne vie a l'ecran d'accueil.
func _animate_logo(delta: float) -> void:
	if _logo_holder == null:
		return
	_logo_time += delta
	_logo_holder.position.y = sin(_logo_time * 0.9) * 3.0


## Le halo du soleil respire, tres lentement. Seul le halo : un soleil qui
## pulse se lit comme un bug, pas comme une intention.
func _animate_glow(_delta: float) -> void:
	if _halo_layer == null:
		return
	_halo_layer.modulate.a = 0.72 + 0.28 * sin(_logo_time * 1.3)


func _animate_clouds(delta: float) -> void:
	var width := _viewport_size().x
	for entry in _clouds:
		var node: Control = entry["node"]
		node.position.x += float(entry["speed"]) * delta
		if node.position.x > width + 40.0:
			node.position.x = -float(entry["width"]) - 40.0


## Fondu d'ouverture, panneaux qui se posent, puis boutons qui montent l'un
## apres l'autre : l'arrivee sur le menu n'est plus un bloc qui apparait d'un
## coup.
func _animate_entry(delta: float) -> void:
	if _fade != null and not _fading_out and _fade.color.a > 0.0:
		_fade.color.a = maxf(0.0, _fade.color.a - delta / FADE_IN)
	if not _entry_active:
		return
	_entry_time += delta
	var done := true
	for i in _entry_nodes.size():
		var node: Control = _entry_nodes[i]
		if node == null:
			continue
		var t := clampf((_entry_time - 0.06 - ENTRY_STEP * float(i)) / 0.32, 0.0, 1.0)
		node.modulate.a = t
		if t < 1.0:
			done = false
	for i in _buttons.size():
		var button: Control = _buttons[i]
		_center_pivot(button)
		var t := clampf((_entry_time - 0.16 - ENTRY_STEP * float(i)) / 0.28, 0.0, 1.0)
		button.modulate.a = t
		button.scale = Vector2.ONE * lerpf(0.94, 1.0, ease(t, 0.35))
		if t < 1.0:
			done = false
	_entry_active = not done


## Rejoue l'entree en scene (premiere ouverture et retours depuis une partie).
func _play_entry() -> void:
	if _fade != null:
		_fade.color.a = 1.0
	_fading_out = false
	_entry_time = 0.0
	for node in _entry_nodes:
		if node != null:
			node.modulate.a = 0.0
	for button in _buttons:
		button.modulate.a = 0.0
	_entry_active = true


## Eteint le menu avant de partir en jeu : le passage a l'ecran de chargement
## devient un vrai fondu au noir. `await` rend la main une fois l'ecran noir.
func fade_out() -> void:
	if _fade == null or _fading_out:
		return
	_entry_active = false
	_fading_out = true
	visible = true
	# La musique s'eteint sur la meme duree que le fondu : la transition vers la
	# partie commence des que l'image commence a s'assombrir.
	stop_music()
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, FADE_OUT)
	await tween.finished


## Un `Control` tourne ou grossit autour de son coin superieur gauche par
## defaut : sans pivot au centre, l'animation part de travers.
func _center_pivot(node: Control) -> void:
	var half := node.size * 0.5
	if node.pivot_offset != half:
		node.pivot_offset = half


## Un texte d'accroche, jamais deux fois de suite le meme.
func _pick_splash() -> String:
	if SPLASHES.is_empty():
		return ""
	var choice: String = SPLASHES[randi() % SPLASHES.size()]
	if _splash == null or SPLASHES.size() <= 1:
		return choice
	var guard := 0
	while choice == _splash.text and guard < 8:
		choice = SPLASHES[randi() % SPLASHES.size()]
		guard += 1
	return choice


## Le titre revient a l'ecran : panneau principal, etat remis a neuf, puis
## entree en scene rejouee. C'est le chemin pris au demarrage et a chaque retour
## depuis une partie.
func show_menu(has_save: bool, default_distance: int) -> void:
	visible = true
	_main_box.visible = true
	_new_box.visible = false
	_net_box.visible = false
	_load_button.disabled = not has_save
	_distance = clampi(default_distance, 2, 14)
	_update_distance()
	show_message("")
	if _local_ip_label != null:
		_local_ip_label.text = "Ton adresse : %s" % local_address()
	if _splash != null:
		_splash.text = _pick_splash()
	_layout()
	_play_entry()
	if _play_button != null:
		_play_button.grab_focus()


func hide_menu() -> void:
	visible = false
	_fading_out = false
	# Sans cette remise a zero, le voile noir resterait pose sur le jeu : le
	# titre est cache mais ses enfants existent toujours.
	if _fade != null:
		_fade.color.a = 0.0


## Message d'etat du panneau reseau : echec de connexion, partie pleine… Un
## message affiche alors que le panneau est ferme ne se verrait pas du tout :
## on ouvre donc le panneau pour le montrer.
func show_message(text: String) -> void:
	if _message_label != null:
		_message_label.text = text
	if not text.is_empty() and _net_box != null and not _net_box.visible:
		_show_net_panel()


## Taille de reference du decor : celle du viewport, avec repli sur la taille du
## controle tant que l'ecran n'est pas en place.
func _viewport_size() -> Vector2:
	var view := get_viewport_rect().size
	return view if view.x > 1.0 and view.y > 1.0 else size


## Repose tout le decor pour la taille courante de la fenetre : sol, brume,
## soleil, nuages et bloc de menu. Chaque position est recalculee a partir de la
## taille, donc un redimensionnement ne laisse plus le decor d'origine en place.
func _layout() -> void:
	var view := _viewport_size()
	if view.x <= 1.0 or view.y <= 1.0:
		return
	_last_view = view
	var ground := clampf(roundf(view.y * GROUND_FRACTION), 96.0, view.y * 0.4)
	var ground_top := view.y - ground

	# --- sol : herbe, terre, et les deux aretes qui marquent le passage de l'une
	# a l'autre.
	UiKit.anchor(_grass, Control.PRESET_BOTTOM_WIDE)
	_grass.offset_top = -(ground + GRASS_HEIGHT)
	_grass.offset_bottom = -ground
	UiKit.anchor(_dirt, Control.PRESET_BOTTOM_WIDE)
	_dirt.offset_top = -ground
	_dirt.offset_bottom = 0.0
	UiKit.anchor(_ground_shade, Control.PRESET_BOTTOM_WIDE)
	_ground_shade.offset_top = -(ground + GRASS_HEIGHT)
	_ground_shade.offset_bottom = 0.0
	# Arete claire en haut de l'herbe : c'est elle qui donne son epaisseur a la
	# bande, sans quoi le gazon se lit comme un aplat vert.
	UiKit.anchor(_grass_edge, Control.PRESET_BOTTOM_WIDE)
	_grass_edge.offset_top = -(ground + GRASS_HEIGHT)
	_grass_edge.offset_bottom = -(ground + GRASS_HEIGHT - 5.0)
	# Ombre courte sous l'herbe : la terre passe sous le gazon.
	UiKit.anchor(_dirt_edge, Control.PRESET_BOTTOM_WIDE)
	_dirt_edge.offset_top = -ground
	_dirt_edge.offset_bottom = -(ground - 7.0)

	UiKit.anchor(_haze, Control.PRESET_BOTTOM_WIDE)
	_haze.offset_top = -(ground + GRASS_HEIGHT + HAZE_HEIGHT)
	_haze.offset_bottom = -(ground + GRASS_HEIGHT * 0.6)

	# --- soleil : ancre au coin haut droit, a une marge de la fenetre.
	var side := clampf(roundf(view.y * 0.10), 54.0, 130.0)
	var margin_x := roundf(view.x * 0.055)
	var margin_y := roundf(view.y * 0.07)
	_sun.anchor_left = 1.0
	_sun.anchor_right = 1.0
	_sun.anchor_top = 0.0
	_sun.anchor_bottom = 0.0
	_sun.offset_left = -margin_x - side
	_sun.offset_right = -margin_x
	_sun.offset_top = margin_y
	_sun.offset_bottom = margin_y + side
	var glow := roundf(side * GLOW_SCALE)
	_glow.position = Vector2((side - glow) * 0.5, (side - glow) * 0.5)
	_glow.size = Vector2(glow, glow)
	_disc.position = Vector2.ZERO
	_disc.size = Vector2(side, side)
	var inset := roundf(side * 0.22)
	_core.position = Vector2(inset, inset)
	_core.size = Vector2(side - inset * 2.0, side - inset * 2.0)

	# --- nuages : la bande verticale suit la fenetre, l'horizontale defile.
	for entry in _clouds:
		var node: Control = entry["node"]
		node.position.y = view.y * float(entry["frac"])
		if node.position.x > view.x + 40.0:
			node.position.x = -float(entry["width"]) - 40.0

	# --- bloc de menu. Sa hauteur est connue d'avance (bandeau, rangee et ligne
	# d'aide) et c'est elle qui le centre dans le ciel : la composition garde
	# donc le meme axe vertical d'un panneau a l'autre. `need` ne peut pas etre
	# plus petite que le contenu reel, sinon le bloc ecraserait ses cartes.
	_place_logo()
	var need := maxf(LOGO_HEIGHT + BLOCK_GAP * 2.0 + ROW_HEIGHT + HINT_HEIGHT,
		_compo.get_combined_minimum_size().y)
	var top := maxf(10.0, (ground_top - need) * 0.5)
	_compo.anchor_left = 0.5
	_compo.anchor_right = 0.5
	_compo.anchor_top = 0.0
	_compo.anchor_bottom = 0.0
	_compo.offset_left = -BLOCK_WIDTH * 0.5
	_compo.offset_right = BLOCK_WIDTH * 0.5
	_compo.offset_top = top
	_compo.offset_bottom = top + need

# ---------------------------------------------------------------------- decor

## Le decor est empile dans l'ordre du monde : ciel, nuages, brume, sol, voile
## sombre, soleil, vignette. La place de chacun compte — un nuage devant le
## soleil le coupe en deux, et le soleil sous le voile devient gris.
func _build_background() -> void:
	_sky = _texture_rect(UiKit.gradient_texture(SKY_TOP, SKY_BOTTOM, 96),
		TextureRect.STRETCH_SCALE)
	_sky.name = "Ciel"
	UiKit.fill_screen(_sky)
	add_child(_sky)

	# Deux couches de nuages : les lointains sont plus petits, plus pales et
	# plus lents. C'est le parallaxe qui donne la profondeur, aucun flou n'est
	# necessaire.
	var far := _layer("NuagesLointains")
	_make_cloud(far, 3, 0.09, 0.55, 0.34, 0.45)
	_make_cloud(far, 7, 0.17, 0.45, 0.28, 0.55)
	_make_cloud(far, 13, 0.26, 0.60, 0.32, 0.40)

	# Proches : presque opaques. Deux blocs translucides qui se chevauchent
	# s'eclaircissent a l'intersection, et le nuage se lit alors comme une suite
	# de rectangles gris. Opagues, il redevient un nuage — le voile sombre du
	# ciel l'assombrit deja assez pour qu'il ne mange pas le menu.
	var near := _layer("NuagesProches")
	_make_cloud(near, 11, 0.20, 1.0, 0.97, 1.0)
	_make_cloud(near, 22, 0.31, 0.80, 0.88, 1.15)
	_make_cloud(near, 33, 0.41, 1.20, 1.0, 0.90)
	_make_cloud(near, 44, 0.50, 0.70, 0.82, 1.30)

	# Brume d'horizon : elle adoucit la rencontre du ciel et de l'herbe.
	_haze = _texture_rect(UiKit.gradient_texture(
		Color(0.90, 0.94, 1.0, 0.0), Color(0.93, 0.96, 1.0, 0.42), 24),
		TextureRect.STRETCH_SCALE)
	_haze.name = "Brume"
	add_child(_haze)

	_grass = _texture_rect(_grass_texture(), TextureRect.STRETCH_TILE)
	_grass.name = "Herbe"
	# La tuile du jeu est gris-vert : la couleur vient du tint de biome applique
	# aux sommets du terrain. Sans ce modulate, le sol du menu montrerait
	# l'herbe que l'on voit **avant** la recoloration, c'est-a-dire un gris-vert
	# qui n'existe nulle part en jeu.
	_grass.modulate = Biomes.grass_tint(Biomes.PLAINS)
	add_child(_grass)

	_dirt = _texture_rect(_dirt_texture(), TextureRect.STRETCH_TILE)
	_dirt.name = "Terre"
	add_child(_dirt)

	# Assombrissement du sol vers le bas : sans lui, la bande de terre est un
	# aplat et le bas de l'ecran ne se distingue plus du haut.
	_ground_shade = _texture_rect(UiKit.gradient_texture(
		Color(0.0, 0.0, 0.0, 0.0), Color(0.02, 0.02, 0.04, 0.38), 32),
		TextureRect.STRETCH_SCALE)
	_ground_shade.name = "OmbreSol"
	add_child(_ground_shade)

	_grass_edge = _texture_rect(UiKit.gradient_texture(
		Color(0.78, 0.96, 0.55, 0.45), Color(0.78, 0.96, 0.55, 0.0), 6),
		TextureRect.STRETCH_SCALE)
	_grass_edge.name = "AreteHerbe"
	add_child(_grass_edge)

	_dirt_edge = _texture_rect(UiKit.gradient_texture(
		Color(0.0, 0.0, 0.0, 0.44), Color(0.0, 0.0, 0.0, 0.0), 8),
		TextureRect.STRETCH_SCALE)
	_dirt_edge.name = "AreteTerre"
	add_child(_dirt_edge)

	# Voile sombre : le menu doit rester lisible sur un ciel clair.
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.22)
	shade.name = "Voile"
	UiKit.fill_screen(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Soleil, lueur et disque, poses APRES le voile, APRES les nuages et APRES la
	# vignette : dans le monde le soleil est au-dessus de tout cela. Un nuage ne
	# peut donc plus le couper, et la vignette ne l'eteint plus dans son coin.
	_vignette = _texture_rect(_vignette_texture(), TextureRect.STRETCH_SCALE)
	_vignette.name = "Vignette"
	UiKit.fill_screen(_vignette)
	add_child(_vignette)

	_sun = Control.new()
	_sun.name = "Soleil"
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.anchor_left = 1.0
	_sun.anchor_right = 1.0
	add_child(_sun)

	_halo_layer = Control.new()
	_halo_layer.name = "Halo"
	_halo_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_screen(_halo_layer)
	_sun.add_child(_halo_layer)
	_glow = _texture_rect(_glow_texture(), TextureRect.STRETCH_SCALE)
	_glow.name = "Lueur"
	_halo_layer.add_child(_glow)

	_disc = ColorRect.new()
	_disc.color = SUN_COLOR
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.add_child(_disc)

	_core = ColorRect.new()
	_core.color = SUN_CORE_COLOR
	_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.add_child(_core)


## Une couche du ciel : plein ecran, et elle ne prend jamais la souris — c'est
## elle qui laisse les boutons du menu cliquer au travers.
func _layer(node_name: String) -> Control:
	var node := Control.new()
	node.name = node_name
	UiKit.fill_screen(node)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


func _texture_rect(texture: Texture2D, stretch: int) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = stretch
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## Bande d'herbe : la tuile **du jeu**, repetee en carres de 16 px.
##
## Le sol du menu etait peint a part, avec son propre bruit et sa propre
## teinte — donc un vert qui ne correspondait a aucun biome. Il montre
## maintenant la tuile que le joueur foulera, coloree par le tint de plaine :
## le menu et le monde se repondent au lieu de se ressembler vaguement.
##
## L'atlas n'existe pas hors du jeu (le test de fumee instancie cet ecran sans
## autoload) : a defaut, on retombe sur un bruit local, comme avant.
static func _grass_texture() -> Texture2D:
	var tile: Texture2D = Assets.tile_images.get(Tiles.GRASS_TOP, null) \
		if Assets.is_ready else null
	if tile != null:
		return tile
	var r := RandomNumberGenerator.new()
	r.seed = 777
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := r.randf_range(-0.06, 0.06)
			var c := Color(0.40 + d, 0.66 + d, 0.26 + d)
			if r.randf() < 0.16:
				c = c.darkened(0.22)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Bande de terre : la tuile du jeu, pour la meme raison que l'herbe.
static func _dirt_texture() -> Texture2D:
	var tile: Texture2D = Assets.tile_images.get(Tiles.DIRT, null) \
		if Assets.is_ready else null
	if tile != null:
		return tile
	var r := RandomNumberGenerator.new()
	r.seed = 20240917
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := r.randf_range(-0.035, 0.035)
			var c := Color(0.42 + d, 0.29 + d, 0.18 + d)
			if r.randf() < 0.12:
				c = c.darkened(0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Vignette : alpha qui monte vers les coins. Generee en 64x36 puis etiree,
## c'est assez doux pour ne pas se voir.
static func _vignette_texture() -> ImageTexture:
	var w := 64
	var h := 36
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var d := clampf(sqrt(u * u + v * v) - 0.35, 0.0, 1.4)
			img.set_pixel(x, y, Color(0.0, 0.02, 0.05, minf(d * 0.60, 0.62)))
	return ImageTexture.create_from_image(img)


## Lueur du soleil : une tache radiale qui s'eteint vers son bord.
##
## Elle etait faite de carres translucides empiles. Dans un coin de ciel uni,
## leurs aretes se lisaient comme des rectangles colles les uns aux autres — le
## contraire d'une lueur. Une tache radiale generee en 64x64 puis etiree n'a,
## elle, aucune arete : le carre du soleil garde son contour net, et la lumiere
## qui l'entoure se fond dans le ciel sans marche.
static func _glow_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var u := (float(x) - center) / center
			var v := (float(y) - center) / center
			var d := clampf(sqrt(u * u + v * v), 0.0, 1.0)
			# Exposant 2,4 : la lueur reste dense pres du disque puis tombe
			# vite, ce qui evite un voile pale sur toute la moitie du ciel.
			var falloff := pow(1.0 - d, 2.4)
			img.set_pixel(x, y, Color(SUN_COLOR.r, SUN_COLOR.g, SUN_COLOR.b,
				falloff * GLOW_ALPHA))
	return ImageTexture.create_from_image(img)


## Deux a quatre blocs blancs qui se chevauchent : un nuage cubique.
##
## `frac` est la bande verticale du ciel ou il vit, en part de la fenetre ;
## `alpha` et `speed_scale` servent a la couche lointaine, plus pale et plus
## lente. La largeur du nuage est retenue : c'est elle qui dit quand le faire
## repasser de l'autre cote de l'ecran.
func _make_cloud(parent: Control, seed_value: int, frac: float, scale: float,
		alpha: float, speed_scale: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var cloud := Control.new()
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var x := 0.0
	for i in r.randi_range(2, 4):
		var block := ColorRect.new()
		block.color = Color(1, 1, 1, alpha)
		block.position = Vector2(x, r.randf_range(-6.0, 6.0))
		block.size = Vector2(r.randf_range(60.0, 140.0) * scale,
			r.randf_range(16.0, 26.0) * scale)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.add_child(block)
		# Face du dessus, un peu plus claire : un nuage de Minecraft est un
		# empilement de blocs, pas un rectangle plat. Sans cette arete, la
		# couche se lit comme du papier decoupe.
		var top := ColorRect.new()
		top.color = Color(1, 1, 1, minf(alpha + 0.12, 1.0))
		top.position = Vector2(x, block.position.y)
		top.size = Vector2(block.size.x, maxf(3.0, block.size.y * 0.22))
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.add_child(top)
		# Ombre du dessous : elle detache le nuage du ciel et donne l'epaisseur.
		var bottom := ColorRect.new()
		bottom.color = Color(0.72, 0.76, 0.84, alpha * 0.9)
		bottom.position = Vector2(x, block.position.y + block.size.y * 0.78)
		bottom.size = Vector2(block.size.x, block.size.y * 0.22)
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.add_child(bottom)
		x += block.size.x * r.randf_range(0.5, 0.8)
	var view := _viewport_size()
	cloud.position = Vector2(r.randf_range(0.0, maxf(view.x, 1.0)),
		maxf(view.y, 1.0) * frac)
	parent.add_child(cloud)
	_clouds.append({
		"node": cloud,
		"speed": r.randf_range(6.0, 14.0) * speed_scale,
		"frac": frac,
		"width": x,
	})

# ------------------------------------------------------------------------ menu

## Le bloc de menu : le bandeau du logo, la rangee des deux cartes, puis la ligne
## d'aide. Tout partage la meme largeur et le meme axe — c'est ce qui remplace
## l'ancien logo centre sur les boutons seuls, qui laissait toute la moitie
## gauche de l'ecran vide.
func _build_menu() -> void:
	_compo = VBoxContainer.new()
	_compo.name = "Menu"
	_compo.add_theme_constant_override("separation", int(BLOCK_GAP))
	_compo.alignment = BoxContainer.ALIGNMENT_BEGIN
	_compo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compo)

	var band := _logo_band()
	_compo.add_child(band)

	var row := HBoxContainer.new()
	row.name = "Rangee"
	row.add_theme_constant_override("separation",
		int(BLOCK_WIDTH - MENU_WIDTH - CARD_WIDTH))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_compo.add_child(row)
	row.add_child(_menu_card())
	row.add_child(_skin_card())

	_hint = UiKit.label("Z Q S D se déplacer   •   E inventaire   •   Échap pause   •   F6 rendu",
		13, HINT_COLOR)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(0.0, HINT_HEIGHT)
	_compo.add_child(_hint)

	_entry_nodes = [band, row, _hint]

	# Ligne de version, en bas a gauche, comme dans l'original. Elle vit hors du
	# bloc de menu : elle n'entre donc pas dans son calcul de hauteur.
	var version := UiKit.label(
		"Cubecraft — Godot 4.7 — 100% procédural, sans asset", 12,
		Color(1.0, 1.0, 1.0, 0.55))
	UiKit.anchor(version, Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 12.0
	version.offset_top = -26.0
	version.offset_bottom = -8.0
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)


## Le mot empile en six copies decalees vers le bas et la droite : cela donne une
## tranche epaisse, du clair (dessus) au sombre (dessous). Le tout vit dans
## `_logo_holder`, qui flotte lentement.
##
## La bande est coupee en deux zones : le mot se centre dans celle de gauche,
## l'accroche jaune vit dans celle de droite. Elles ne se chevauchent jamais,
## donc l'accroche ne peut plus passer sur les lettres.
func _logo_band() -> Control:
	var band := Control.new()
	band.name = "Bandeau"
	band.custom_minimum_size = Vector2(BLOCK_WIDTH, LOGO_HEIGHT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_logo_holder = Control.new()
	_logo_holder.name = "Logo"
	_logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.fill_screen(_logo_holder)
	band.add_child(_logo_holder)

	# Huit tranches au lieu de six : la tranche est plus epaisse, donc le mot se
	# detache davantage du ciel clair. La derniere est franchement sombre, ce qui
	# sert d'ombre portee sous les lettres.
	for step in range(8, 0, -1):
		_logo_holder.add_child(_logo_slice(
			Color(0.74, 0.76, 0.80).darkened(0.05 * float(step)), float(step)))
	_logo_ref = _logo_slice(Color(0.97, 0.98, 1.0), 0.0)
	# Contour sombre autour des lettres : c'est lui qui fait lire le mot comme
	# un logo grave plutot que comme un titre ecrit a la police du theme.
	_logo_ref.add_theme_color_override("font_outline_color", Color(0.13, 0.13, 0.16))
	_logo_ref.add_theme_constant_override("outline_size", 6)
	_logo_holder.add_child(_logo_ref)

	_splash_holder = Control.new()
	_splash_holder.name = "Accroche"
	_splash_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_holder.anchor_left = 1.0
	_splash_holder.anchor_right = 1.0
	_splash_holder.offset_top = 0.0
	_splash_holder.offset_bottom = LOGO_HEIGHT
	band.add_child(_splash_holder)

	_splash = UiKit.label(_pick_splash(), 16, Color(1.0, 0.96, 0.30))
	_splash.add_theme_color_override("font_shadow_color", Color(0.16, 0.13, 0.0))
	_splash.add_theme_constant_override("shadow_offset_x", 2)
	_splash.add_theme_constant_override("shadow_offset_y", 2)
	# Le texte est pose dans le bas de sa zone : il penche vers le haut a droite,
	# donc sa pointe monte au niveau du mot sans jamais le toucher.
	_splash.position = Vector2(0.0, LOGO_HEIGHT * 0.62)
	_splash.rotation = -0.30
	_splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_holder.add_child(_splash)
	return band


## Place le mot et l'accroche comme un seul bloc centre sur la bande.
##
## On mesure le mot, jamais l'accroche : celle-ci change de texte toutes les
## 5,5 secondes, et un placement qui suivrait sa longueur ferait sauter le logo a
## chaque nouvelle accroche. L'accroche garde donc une zone de largeur fixe, et
## se dessine dedans depuis la gauche.
func _place_logo() -> void:
	if _logo_holder == null or _splash_holder == null:
		return
	var word := _logo_width()
	var total := word + LOGO_GAP + SPLASH_WIDTH
	var left := maxf(0.0, (BLOCK_WIDTH - total) * 0.5)
	# Les deux zones sont ancrees a droite de la bande : leurs offsets se
	# comptent donc depuis son bord droit.
	_logo_holder.offset_left = left
	_logo_holder.offset_right = left + word - BLOCK_WIDTH
	_splash_holder.offset_left = left + word + LOGO_GAP - BLOCK_WIDTH
	_splash_holder.offset_right = left + total - BLOCK_WIDTH


## Largeur reelle du mot, mesuree sur la police du theme.
##
## `get_minimum_size()` ne convient pas : un `Label` ancre plein cadre repond la
## taille de sa boite et non celle de son texte, et le mot se retrouvait decale
## de la moitie de l'ecart. La mesure par la police ne depend, elle, que du texte
## et du corps — donc du dessin, et de rien d'autre.
func _logo_width() -> float:
	var font := _logo_ref.get_theme_font("font") if _logo_ref != null else null
	if font == null:
		return float(LOGO_TEXT.length()) * 30.0 + LOGO_STAGGER
	return font.get_string_size(LOGO_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1,
		LOGO_FONT_SIZE).x + LOGO_STAGGER


## Une copie du logo. Le decalage est pose en ANCRES et non en position : une
## position ecrite a la main serait effacee au prochain redimensionnement, et la
## tranche epaisse disparaitrait.
func _logo_slice(color: Color, offset_px: float) -> Label:
	var node := UiKit.label(LOGO_TEXT, LOGO_FONT_SIZE, color)
	node.add_theme_color_override("font_shadow_color", Color(0.10, 0.10, 0.12))
	node.add_theme_constant_override("shadow_offset_x", 2)
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.anchor(node, Control.PRESET_FULL_RECT)
	node.offset_left = offset_px
	node.offset_top = offset_px
	node.offset_right = offset_px
	node.offset_bottom = offset_px
	return node


## La carte des boutons. Ses trois panneaux (principal, nouveau monde,
## multijoueur) y sont empiles et un seul est visible : la carte garde donc la
## meme hauteur d'un panneau a l'autre, et changer de panneau ne fait plus
## sauter le menu.
func _menu_card() -> Control:
	var card := PanelContainer.new()
	card.name = "CarteMenu"
	card.custom_minimum_size = Vector2(MENU_WIDTH, ROW_HEIGHT)
	card.add_theme_stylebox_override("panel", UiKit.card(CARD_BG, CARD_EDGE))

	var host := VBoxContainer.new()
	host.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(host)

	_main_box = _panel_box(10.0)
	host.add_child(_main_box)
	_play_button = UiKit.mc_primary_button("Jouer", 18)
	_play_button.custom_minimum_size = Vector2(BUTTON_SIZE.x, 56.0)
	_play_button.pressed.connect(func(): play_requested.emit(randi(), _distance))
	_main_box.add_child(_play_button)

	var create := UiKit.mc_button("Nouveau monde…")
	create.custom_minimum_size = BUTTON_SIZE
	create.pressed.connect(_show_new_panel)
	_main_box.add_child(create)

	_load_button = UiKit.mc_button("Charger la partie")
	_load_button.custom_minimum_size = BUTTON_SIZE
	_load_button.pressed.connect(func(): load_requested.emit())
	_main_box.add_child(_load_button)

	var online := UiKit.mc_button("Multijoueur…")
	online.custom_minimum_size = BUTTON_SIZE
	online.pressed.connect(_show_net_panel)
	_main_box.add_child(online)

	var quit := UiKit.mc_button("Quitter")
	quit.custom_minimum_size = BUTTON_SIZE
	quit.pressed.connect(func(): quit_requested.emit())
	_main_box.add_child(quit)

	var keys := UiKit.label("F3 informations   •   F5 sauvegarder", 12, HINT_COLOR)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_box.add_child(keys)

	# Les boutons du menu principal apparaissent en cascade (voir `_play_entry`).
	_buttons = [_play_button, create, _load_button, online, quit]

	_new_box = _panel_box(10.0)
	_new_box.visible = false
	host.add_child(_new_box)
	_build_new_panel()

	_net_box = _panel_box(8.0)
	_net_box.visible = false
	host.add_child(_net_box)
	_build_net_panel()
	return card


## Un panneau du menu : une colonne de boutons de largeur fixe, centree dans la
## carte. Sa largeur est celle de ses enfants — les boutons — et non celle de la
## carte : les trois panneaux s'alignent ainsi sur le meme axe.
func _panel_box(separation: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(separation))
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return box


## Panneau « Nouveau monde » : la graine, la portee de rendu, et le depart.
func _build_new_panel() -> void:
	var title := UiKit.label("Nouveau monde", 18, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_box.add_child(title)

	_seed_field = UiKit.mc_field("Graine (vide = aléatoire)")
	_seed_field.custom_minimum_size = BUTTON_SIZE
	# Entree dans le champ = creer le monde : on ne va pas rechercher le bouton
	# quand on vient de taper une graine.
	_seed_field.text_submitted.connect(func(_text: String): _on_create())
	_new_box.add_child(_seed_field)

	_new_box.add_child(_distance_row())

	var start := UiKit.mc_primary_button("Créer le monde")
	start.custom_minimum_size = BUTTON_SIZE
	start.pressed.connect(_on_create)
	_new_box.add_child(start)

	var back := UiKit.mc_button("Retour")
	back.custom_minimum_size = BUTTON_SIZE
	back.pressed.connect(_show_main_panel)
	_new_box.add_child(back)

	var hint := UiKit.label("Plus la portée est grande, plus le monde coûte cher",
		12, HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_box.add_child(hint)


## Panneau « Multijoueur » : heberger une partie, ou rejoindre celle d'un autre.
func _build_net_panel() -> void:
	var title := UiKit.label("Multijoueur", 18, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_box.add_child(title)

	# L'adresse de la machine est affichee telle quelle : l'hote doit pouvoir la
	# lire a voix haute, et la deviner depuis une liste d'adresses candidates
	# serait absurde.
	_local_ip_label = UiKit.label("Ton adresse : %s" % local_address(), 14,
		UiKit.TEXT_DIM)
	_local_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_box.add_child(_local_ip_label)

	var hint := UiKit.label("Donne-la à tes amis pour qu'ils rejoignent", 12,
		HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_box.add_child(hint)

	var host := UiKit.mc_primary_button("Héberger une partie")
	host.custom_minimum_size = BUTTON_SIZE
	host.pressed.connect(_on_host)
	_net_box.add_child(host)

	# Adresse et port sur une meme ligne : deux champs empiles mangeraient la
	# moitie de la carte pour deux valeurs qu'on ne remplit qu'une fois.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_address_field = UiKit.mc_field("Adresse de l'hôte")
	_address_field.text = local_address()
	_address_field.custom_minimum_size = Vector2(240.0, BUTTON_SIZE.y)
	row.add_child(_address_field)
	_port_field = UiKit.mc_field("Port")
	_port_field.text = str(Net.DEFAULT_PORT) if _net_node() != null else "27015"
	_port_field.custom_minimum_size = Vector2(92.0, BUTTON_SIZE.y)
	row.add_child(_port_field)
	_net_box.add_child(row)

	var join := UiKit.mc_button("Rejoindre")
	join.custom_minimum_size = BUTTON_SIZE
	join.pressed.connect(_on_join)
	_net_box.add_child(join)

	# Un echec de connexion ne se remarque que par ce message : sans lui, le
	# joueur clique sur « Rejoindre » et ne sait pas si rien ne s'est passe.
	_message_label = UiKit.label("", 13, Color(0.98, 0.55, 0.48))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.custom_minimum_size = Vector2(BUTTON_SIZE.x, 34.0)
	_net_box.add_child(_message_label)

	var back := UiKit.mc_button("Retour")
	back.custom_minimum_size = BUTTON_SIZE
	back.pressed.connect(_show_main_panel)
	_net_box.add_child(back)


## La carte du personnage : son nom, l'apercu anime et le choix de la tenue. Elle
## a la hauteur de la carte des boutons et reste visible sur tous les panneaux :
## on peut choisir sa tenue en attendant une partie.
func _skin_card() -> Control:
	var card := PanelContainer.new()
	card.name = "CartePersonnage"
	card.custom_minimum_size = Vector2(CARD_WIDTH, ROW_HEIGHT)
	card.add_theme_stylebox_override("panel", UiKit.card(SKIN_BG, CARD_EDGE))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)

	var title := UiKit.label("Personnage", 14, UiKit.TEXT_DIM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var name_label := UiKit.label("Steve", 18, UiKit.ACCENT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	_preview = SkinPreview.new()
	_preview.name = "SkinPreview"
	_preview.set_label(name_label)
	box.add_child(_preview)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var previous := UiKit.mc_button("◀", 18)
	previous.custom_minimum_size = Vector2(52.0, 44.0)
	previous.pressed.connect(func(): _step_skin(-1))
	row.add_child(previous)

	_skin_index_label = UiKit.label("", 15, UiKit.TEXT_DIM)
	_skin_index_label.custom_minimum_size = Vector2(64.0, 44.0)
	_skin_index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_skin_index_label)

	var next := UiKit.mc_button("▶", 18)
	next.custom_minimum_size = Vector2(52.0, 44.0)
	next.pressed.connect(func(): _step_skin(1))
	row.add_child(next)
	box.add_child(row)

	_update_skin_index()
	return card


## Change de tenue et l'annonce : c'est ce signal qui fait que la tenue choisie
## ici est celle que les autres joueurs verront. Sans lui, l'apercu du menu ne
## servait a rien une fois la partie lancee.
func _step_skin(delta: int) -> void:
	if _preview == null:
		return
	_preview.step_skin(delta)
	_update_skin_index()
	skin_changed.emit(_preview.skin_index)


func _update_skin_index() -> void:
	if _skin_index_label == null or _preview == null:
		return
	_skin_index_label.text = "%d/%d" % [_preview.skin_index + 1,
		SkinFactory.count()]


## Le reglage de portee : le meme pas a pas que dans le menu pause.
func _distance_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var minus := UiKit.mc_button("−", 18)
	minus.custom_minimum_size = Vector2(52.0, BUTTON_SIZE.y)
	minus.pressed.connect(func(): _change_distance(-1))
	row.add_child(minus)

	_distance_label = UiKit.label("", 15)
	_distance_label.custom_minimum_size = Vector2(220.0, BUTTON_SIZE.y)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_distance_label)

	var plus := UiKit.mc_button("+", 18)
	plus.custom_minimum_size = Vector2(52.0, BUTTON_SIZE.y)
	plus.pressed.connect(func(): _change_distance(1))
	row.add_child(plus)
	return row

# -------------------------------------------------------------------- panneaux

func _show_main_panel() -> void:
	_main_box.visible = true
	_new_box.visible = false
	_net_box.visible = false
	_fade_in(_main_box)
	# Le focus suit le panneau : au clavier, on ne reste pas sur un bouton
	# devenu invisible, ou la touche Entree ne ferait plus rien de lisible.
	if _play_button != null:
		_play_button.grab_focus()


func _show_new_panel() -> void:
	_main_box.visible = false
	_net_box.visible = false
	_new_box.visible = true
	_fade_in(_new_box)
	if _seed_field != null:
		_seed_field.grab_focus()


func _show_net_panel() -> void:
	_main_box.visible = false
	_new_box.visible = false
	_net_box.visible = true
	if _local_ip_label != null:
		_local_ip_label.text = "Ton adresse : %s" % local_address()
	_fade_in(_net_box)
	if _address_field != null:
		_address_field.grab_focus()


## Petit fondu a l'ouverture d'un panneau : le changement ne claque plus.
func _fade_in(box: Control) -> void:
	box.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(box, "modulate:a", 1.0, 0.18)


## Echap ferme le panneau ouvert et ramene au menu principal : c'est le seul
## retour possible depuis le titre, et il est attendu partout. Sur le panneau
## principal, Echap ne fait rien — quitter le jeu sur une touche reflexe serait
## une mauvaise surprise.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("pause"):
		return
	if _seed_field != null and _seed_field.has_focus():
		_seed_field.release_focus()
		get_viewport().set_input_as_handled()
		return
	if _new_box.visible or _net_box.visible:
		_show_main_panel()
		get_viewport().set_input_as_handled()


# -------------------------------------------------------------------- actions

## Lance l'hote. La graine est celle du champ du panneau « Nouveau monde » : on
## joue sur le meme monde que la partie solo, et l'utilisateur peut ainsi
## retrouver la region qu'il a exploree.
func _on_host() -> void:
	show_message("")
	host_requested.emit(parse_seed(_seed_field.text), _distance)


func _on_join() -> void:
	show_message("")
	join_requested.emit(_address_field.text.strip_edges(), _parse_port())


## Port saisi, ou le port par defaut si le champ est vide ou invalide. Un champ
## mal rempli ne doit pas interdire de jouer : un port par defaut suffit presque
## toujours, et un message d'erreur est plus deroutant qu'un echec.
func _parse_port() -> int:
	var net := _net_node()
	if net == null:
		return 27015
	var text := _port_field.text.strip_edges()
	if text.is_valid_int():
		var value := int(text)
		if value > 0 and value < 65536:
			return value
	return int(net.DEFAULT_PORT)


func _on_create() -> void:
	play_requested.emit(parse_seed(_seed_field.text), _distance)


func _change_distance(delta: int) -> void:
	_distance = clampi(_distance + delta, 2, 14)
	_update_distance()


func _update_distance() -> void:
	if _distance_label == null:
		return
	_distance_label.text = "Portée : %d" % _distance


# ----------------------------------------------------------------------- reseau

## Adresse IPv4 de la machine, telle qu'un autre joueur doit la saisir. Sur un
## reseau local c'est en general 192.168.x.x ou 10.x.x.x.
static func local_address() -> String:
	for address in IP.get_local_addresses():
		# On ignore la boucle locale et les adresses lien-local : ni l'une ni
		# l'autre ne sont saisissables par un autre joueur.
		if address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if address.contains(":"):
			continue
		return address
	return "127.0.0.1"


static func _net_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Net")


func has_preview() -> bool:
	return find_child("SkinPreview", true, false) != null
