class_name DebugMenu
extends Control

## Menu de diagnostic, ouvert en partie par F4 (ou Ctrl+Alt+D).
##
## Ce que le jeu evaluait jusqu'ici ne sortait que d'une console : les captures
## ASCII, la lecture des sommets du chunk sous la camera et la sequence de
## verifications d'interface, declenchee uniquement au demarrage par
## `--uitest`. Un joueur qui joue ne voit rien de tout cela.
##
## Le menu rassemble ces outils la ou l'on peut les lire : un journal, les
## informations de la partie en cours, une sonde de rendu, et la sequence
## complete de verifications lancee **devant la partie en cours**, avec son
## resultat affiche ligne a ligne.
##
## Le menu ne connait pas le jeu : il lit l'autoload `Game` pour l'affichage,
## et **delegue** chaque bouton a `Main` via `action_requested`. Une action qui
## modifie la partie a besoin du monde, du joueur et de la sauvegarde — autant
## de raisons de rester dans le chef d'orchestre plutot que dans un panneau.

## Le joueur a demande une action. L'identifiant est celui imprime sur le
## bouton : `Main` s'y retrouve sans table de correspondance a maintenir.
signal action_requested(id: String)

## Journal : vert si la verification passe, rouge si elle echoue, gris tant
## qu'elle n'a pas ete lancee. Les memes trois etats que la `Checklist`.
const OK_COLOR := Color(0.60, 0.86, 0.52)
const FAIL_COLOR := Color(0.96, 0.48, 0.42)
const WAIT_COLOR := Color(0.62, 0.62, 0.60)
const WARN_COLOR := Color(0.98, 0.76, 0.36)

## Heures proposees par le bouton « heure », avec leur nom affiche.
const HOURS := [
	[0.05, "aube"], [0.25, "midi"], [0.5, "coucher"], [0.75, "minuit"],
]

## Journal des verifications en cours. Remplace par `Main` avant un lancement :
## tant qu'il est nul, le menu montre une liste vide plutot que de pretendre
## qu'il n'y a rien a verifier.
var checklist: Checklist = null

var _info: Label
var _report: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _log: RichTextLabel
var _action_buttons: Array[Button] = []

var _row_marks: Array[Label] = []
var _row_names: Array[Label] = []
var _tick := 0.0
## La sequence etait-elle en cours au rafraichissement precedent ? Le passage a
## faux declenche le repositionnement du defilement.
var _was_running := false


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Le menu doit rester pilotable pendant la pause, sinon F4 ne pourrait plus
	# le refermer : c'est le seul moment ou l'on a justement envie de le lire.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	# Le fond bloque les clics : sans cela, un clic dans le vide du panneau
	# traverserait le menu et casserait un bloc derriere.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.62)
	UiKit.fill_screen(backdrop)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.BG_SOLID, 2, UiKit.ACCENT, 6))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var heading := UiKit.label("MENU DE DEBUG", 22, UiKit.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var hint := UiKit.label("F4 ou Ctrl+Alt+D pour fermer   •   F3 pour l'overlay", 12, UiKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	column.add_child(HSeparator.new())

	# Tout le contenu defile dans un seul conteneur : sur un petit ecran, un
	# panneau plus haut que la fenetre serait rogne en bas, hors de portee.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(680, 520)
	column.add_child(scroll)
	_scroll = scroll

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_info = UiKit.label("", 12, UiKit.TEXT_DIM)
	body.add_child(_info)

	body.add_child(HSeparator.new())

	# --- Verifications -----------------------------------------------------
	body.add_child(UiKit.label("Vérifications du jeu", 17, UiKit.TEXT))

	var warning := UiKit.label(
		"La séquence vide l'inventaire, déplace et tue le joueur, lâche des créatures, " +
		"puis démonte la partie et la relance depuis l'écran titre. " +
		"La partie en cours sera perdue : sauvegardez-la d'abord.", 12, WARN_COLOR)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size = Vector2(660, 0)
	body.add_child(warning)

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override("separation", 8)
	var run_button := UiKit.mc_button("Lancer les vérifications", 15)
	run_button.custom_minimum_size = Vector2(280, 36)
	run_button.pressed.connect(func(): action_requested.emit("run_checks"))
	run_row.add_child(run_button)
	_report = UiKit.label("", 13, UiKit.TEXT_DIM)
	_report.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	run_row.add_child(_report)
	body.add_child(run_row)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 1)
	body.add_child(_rows)

	body.add_child(HSeparator.new())

	# --- Actions sur la partie ---------------------------------------------
	body.add_child(UiKit.label("Actions", 17, UiKit.TEXT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_action_buttons = []
	for spec in [
		["Retour au spawn", "teleport_spawn"],
		["Monter de 20 blocs", "teleport_up"],
		["Kit de survie", "give"],
		["Soigner et nourrir", "heal"],
		["Heure", "time"],
		["Météo", "weather"],
		["Sonder le chunk", "probe"],
		["Sauvegarder", "save"],
		["Quitter", "quit"],
	]:
		var button := UiKit.mc_button(str(spec[0]), 14)
		button.custom_minimum_size = Vector2(210, 34)
		var action_id := str(spec[1])
		button.pressed.connect(func(): action_requested.emit(action_id))
		grid.add_child(button)
		_action_buttons.append(button)
	body.add_child(grid)

	body.add_child(HSeparator.new())

	# --- Journal ------------------------------------------------------------
	body.add_child(UiKit.label("Journal", 17, UiKit.TEXT))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(660, 150)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_color_override("default_color", UiKit.TEXT)
	body.add_child(_log)


func open() -> void:
	visible = true
	# Un ecran ouvert dessous garderait sa souris et son curseur : le menu est
	# modal, on repart d'un etat neutre.
	Game.close_screens()
	_hold()
	_refresh()


func close() -> void:
	visible = false
	if Game.player != null and not Game.player.dead and not Game.is_screen_open():
		Game.player.can_move = true
	Game._apply_mouse_captured()


## Le menu est modal : la souris reste visible et le joueur immobile, meme si
## la partie vient d'etre relancee par la sequence de verifications — celle-ci
## repasse par `Game.start`, qui recapture la souris.
##
## Exception : pendant la sequence, le joueur n'est **plus** fige. La sequence
## le deplace, le tue et lui fait frapper une creature, et `Player._attack`
## refuse de frapper un joueur immobile : le menu casserait lui-meme les
## verifications qu'il affiche. La souris, elle, reste visible.
func _hold() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if checklist != null and checklist.is_running():
		return
	if Game.player != null and not Game.player.dead and not Game.is_screen_open():
		Game.player.can_move = false


func _process(delta: float) -> void:
	if not visible:
		return
	_hold()
	# Six rafraichissements par seconde suffisent et coute peu : un menu qui
	# reconstruit ses lignes a 60 images/s ferait ce travail pour rien.
	_tick += delta
	if _tick < 0.15:
		return
	_tick = 0.0
	_refresh()


func _refresh() -> void:
	_update_info()
	_update_report()
	_update_rows()
	_update_buttons()


## Etat de la partie, relu a chaque rafraichissement : c'est ce que le joueur
## cherche en general en ouvrant le menu (« combien de chunks ? pourquoi ca
## rame ? »), et l'overlay F3 ne le montre pas.
func _update_info() -> void:
	if Game.world == null or Game.player == null:
		_info.text = "Aucune partie en cours. Lancez-en une, puis revenez ici."
		return
	var pos: Vector3 = Game.player.global_position
	var mem := OS.get_static_memory_usage() / 1048576.0
	var uptime := Time.get_ticks_msec() / 1000
	_info.text = "\n".join([
		"Graine %d   Portée %d   %d FPS   %d chunks   %d torches" % [
			Game.world_seed, Game.world.render_distance,
			Engine.get_frames_per_second(), Game.world.chunks.size(),
			Game.world.torches.size()],
		"XYZ %.1f / %.1f / %.1f   %s   Vie %.0f/20   Faim %.0f/20" % [
			pos.x, pos.y, pos.z, Game.clock_text(),
			Game.player.health, Game.player.food],
		"Mémoire %d Mo   Dessins %d   Objets %d   En jeu %d:%02d" % [
			int(mem),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			uptime / 60, uptime % 60],
	])


func _update_report() -> void:
	if checklist == null:
		_report.text = ""
		return
	if checklist.is_running():
		_report.text = "en cours…  %d/%d" % [checklist.done_count(), checklist.count()]
		return
	_report.text = checklist.report_line() if not checklist.summary.is_empty() else ""
	_report.add_theme_color_override("font_color",
		FAIL_COLOR if checklist.failed_count() > 0 else OK_COLOR)


## Une ligne par verification, ajoutee au fur et a mesure. Les lignes existantes
## sont seulement retextees : la sequence en ajoute 78 d'affilee, et les
## reconstruire entieres six fois par seconde serait du gaspillage visible.
func _update_rows() -> void:
	var total := checklist.count() if checklist != null else 0
	while _row_names.size() < total:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mark := UiKit.label("·", 12, WAIT_COLOR)
		mark.custom_minimum_size = Vector2(14, 0)
		row.add_child(mark)
		var name := UiKit.label("", 12, WAIT_COLOR)
		row.add_child(name)
		_rows.add_child(row)
		_row_marks.append(mark)
		_row_names.append(name)
	for i in total:
		var state = checklist.entries[i]["ok"]
		if state == null:
			_row_marks[i].text = "·"
			_row_marks[i].add_theme_color_override("font_color", WAIT_COLOR)
			_row_names[i].text = checklist.name_of(i)
		elif state:
			_row_marks[i].text = "✓"
			_row_marks[i].add_theme_color_override("font_color", OK_COLOR)
			_row_names[i].text = checklist.name_of(i)
		else:
			_row_marks[i].text = "✗"
			_row_marks[i].add_theme_color_override("font_color", FAIL_COLOR)
			_row_names[i].text = "%s  —  %s" % [checklist.name_of(i),
				checklist.detail_of(i)]
	# Pendant la sequence, on suit la fin de la liste : c'est la que naissent
	# les verifications, et defiler en meme temps qu'elles s'affichent.
	var running := checklist != null and checklist.is_running()
	if running:
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
	elif _was_running:
		# La sequence vient de se terminer sur une longue liste defilee jusqu'en
		# bas. Le joueur cherche alors le premier echec, pas la derniere ligne :
		# on l'y amene, et en haut de liste si tout est passe.
		for i in total:
			if checklist.entries[i]["ok"] == false:
				_scroll_to_row(i)
				return
		_scroll.scroll_vertical = 0
	_was_running = running


## Amene une ligne de verification sous les yeux, en gardant une ligne de
## contexte au-dessus. Les positions viennent de la `VBoxContainer` des lignes :
## c'est elle qui fait la pagination, pas la barre du conteneur.
func _scroll_to_row(index: int) -> void:
	_scroll.scroll_vertical = int(_rows.get_child(maxi(0, index - 1)).position.y)


## Les actions qui travaillent sur une partie sont indisponibles a l'ecran
## titre : mieux vaut un bouton grise qu'une erreur en console.
func _update_buttons() -> void:
	var playing := Game.world != null and Game.player != null
	for button in _action_buttons:
		if button.text in ["Quitter", "Sonder le chunk"]:
			button.disabled = false
		else:
			button.disabled = not playing


## Ajoute une ligne au journal. Une couleur totalement transparente est
## interpretee comme « pas de couleur » : c'est la valeur par defaut du type
## `Color`, et cela evite un parametre `Variant` que l'appelant devrait typer.
func add_log(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	var tinted := color.a > 0.0
	_log.append_text("%s%s%s\n" % [
		"[color=#%s]" % color.to_html(false) if tinted else "", text,
		"[/color]" if tinted else ""])


## Remplace le journal des verifications, avant un lancement.
func set_checklist(value: Checklist) -> void:
	checklist = value
	_was_running = false
	_report.text = ""
	_report.add_theme_color_override("font_color", UiKit.TEXT_DIM)
	for row in _rows.get_children():
		row.queue_free()
	_row_marks.clear()
	_row_names.clear()
