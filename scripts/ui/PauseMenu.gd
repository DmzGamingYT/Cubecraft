class_name PauseMenu
extends Control

## Menu de pause : reprendre, sauvegarder, recharger, regler la portee de
## rendu, quitter. Le jeu tourne en arriere-plan mais reste fige.

signal resume_requested
signal title_requested

var _distance_label: Label
var _weather_label: Label
var _render_label: Label
var _status: Label


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.6)
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

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.BG_SOLID, 2, UiKit.ACCENT, 6))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := UiKit.label("Pause", 22, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var resume := UiKit.mc_button("Reprendre", 16)
	resume.pressed.connect(func(): resume_requested.emit())
	column.add_child(resume)

	var save_button := UiKit.mc_button("Sauvegarder")
	save_button.pressed.connect(_on_save)
	column.add_child(save_button)

	var load_button := UiKit.mc_button("Charger la sauvegarde")
	load_button.pressed.connect(_on_load)
	column.add_child(load_button)

	# --- Portee de rendu : plus elle est grande, plus le monde coute cher.
	var distance_row := HBoxContainer.new()
	distance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	distance_row.add_theme_constant_override("separation", 8)
	var minus := UiKit.mc_button("−", 18)
	minus.custom_minimum_size = Vector2(44, 40)
	minus.pressed.connect(func(): _change_distance(-1))
	distance_row.add_child(minus)

	_distance_label = UiKit.label("", 16)
	_distance_label.custom_minimum_size = Vector2(180, 40)
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	distance_row.add_child(_distance_label)

	var plus := UiKit.mc_button("+", 18)
	plus.custom_minimum_size = Vector2(44, 40)
	plus.pressed.connect(func(): _change_distance(1))
	distance_row.add_child(plus)
	column.add_child(distance_row)

	column.add_child(UiKit.label("Portée de rendu (chunks)", 12, UiKit.TEXT_DIM))

	# --- Meteo : forcee ou automatique.
	_weather_label = UiKit.label("", 16)
	_weather_label.custom_minimum_size = Vector2(0, 24)
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_weather_label)
	var weather_row := HBoxContainer.new()
	weather_row.alignment = BoxContainer.ALIGNMENT_CENTER
	weather_row.add_theme_constant_override("separation", 8)
	var weather_prev := UiKit.mc_button("◀", 18)
	weather_prev.custom_minimum_size = Vector2(44, 40)
	weather_prev.pressed.connect(func(): _change_weather(-1))
	weather_row.add_child(weather_prev)
	var weather_next := UiKit.mc_button("▶", 18)
	weather_next.custom_minimum_size = Vector2(44, 40)
	weather_next.pressed.connect(func(): _change_weather(1))
	weather_row.add_child(weather_next)
	column.add_child(weather_row)
	column.add_child(UiKit.label("Météo (◀ ▶)", 12, UiKit.TEXT_DIM))

	_build_render_row(column)

	_status = UiKit.label("", 13, UiKit.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	column.add_child(HSeparator.new())

	var title_button := UiKit.mc_button("Retour au titre")
	title_button.pressed.connect(func(): title_requested.emit())
	column.add_child(title_button)

	var quit := UiKit.mc_button("Quitter")
	quit.pressed.connect(func(): Game.quit_game())
	column.add_child(quit)

	var hint := UiKit.label("Échap reprendre   •   F3 informations   •   F4 diagnostic   •   F6 rendu", 12, UiKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


## Le reglage du rendu : le meme cycle que la touche F6, avec ses deux sens.
func _build_render_row(column: VBoxContainer) -> void:
	_render_label = UiKit.label("", 16)
	_render_label.custom_minimum_size = Vector2(0, 24)
	_render_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_render_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var previous := UiKit.mc_button("◀", 18)
	previous.custom_minimum_size = Vector2(44, 40)
	previous.pressed.connect(func(): _change_render(-1))
	row.add_child(previous)
	var following := UiKit.mc_button("▶", 18)
	following.custom_minimum_size = Vector2(44, 40)
	following.pressed.connect(func(): _change_render(1))
	row.add_child(following)
	column.add_child(row)
	column.add_child(UiKit.label("Rendu (F6)", 12, UiKit.TEXT_DIM))


func _change_render(delta: int) -> void:
	if Game.postfx == null:
		return
	Game.postfx.step(delta)
	_update_render()


func _update_render() -> void:
	if _render_label == null:
		return
	_render_label.text = "Rendu : %s" % (
		Game.postfx.preset_name() if Game.postfx != null else "—")


func open() -> void:
	visible = true
	_update_distance()
	_update_weather()
	_update_render()
	_status.text = ""


func close() -> void:
	visible = false


func _change_distance(delta: int) -> void:
	Game.world.set_render_distance(Game.world.render_distance + delta)
	_update_distance()


func _update_distance() -> void:
	if _distance_label == null or Game.world == null:
		return
	_distance_label.text = "%d chunks   (%d de large)" % [
		Game.world.render_distance, Game.world.render_distance * 2 + 1]


func _change_weather(delta: int) -> void:
	if Game.weather == null:
		return
	var count := Weather.MODES.size()
	Game.weather.set_mode(posmod(Game.weather.mode_index() + delta, count))
	_update_weather()


func _update_weather() -> void:
	if _weather_label == null:
		return
	_weather_label.text = "Météo : %s" % (
		Game.weather.mode_name() if Game.weather != null else "—")


func _on_save() -> void:
	_status.text = "Sauvegardé." if Game.save_game() else "Échec de la sauvegarde."
	_status.modulate = Color(0.7, 1.0, 0.7)


func _on_load() -> void:
	_status.text = "Sauvegarde introuvable." if not Game.load_game() else "Chargé."
	_status.modulate = Color(0.7, 1.0, 0.7)
