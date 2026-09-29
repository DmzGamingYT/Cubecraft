class_name EnchantScreen
extends Control

## Table d'enchantement : trois offres (Efficacite, Fortune, Tranchant) qui
## coutent des niveaux et du lapis, et montent l'enchantement d'un cran.
##
## Le joueur garde son objet en main pendant l'ecran : c'est la pile affichee
## en haut qui est amelioree, comme dans Minecraft.

var _rows: Array = []
var _title: Label
var _status: Label
var _level_label: Label


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	UiKit.fill_screen(backdrop)
	add_child(backdrop)

	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.BG_SOLID, 2,
		Color(0.45, 0.25, 0.65), 6))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	_title = UiKit.label("Table d'enchantement", 20, Color(0.85, 0.65, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	_level_label = UiKit.label("Niveau 0", 14, UiKit.TEXT_DIM)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_level_label)

	for key in Items.ENCHANTS:
		column.add_child(_offer_row(str(key)))

	_status = UiKit.label("Mettez l'objet a enchanter en main.", 13, UiKit.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	var close := UiKit.mc_button("Fermer")
	close.pressed.connect(close_self)
	column.add_child(close)


## Une ligne : nom, niveau actuel, cout et bouton.
func _offer_row(key: String) -> HBoxContainer:
	var def: Dictionary = Items.ENCHANTS[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.name = "row_" + key

	var name_label := UiKit.label(str(def["name"]), 16)
	name_label.custom_minimum_size = Vector2(120, 36)
	row.add_child(name_label)

	var value := UiKit.label("I", 16, Color(0.75, 0.60, 1.0))
	value.custom_minimum_size = Vector2(90, 36)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.name = "value"
	row.add_child(value)

	var cost := UiKit.label("", 13, UiKit.TEXT_DIM)
	cost.custom_minimum_size = Vector2(130, 36)
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.name = "cost"
	row.add_child(cost)

	var button := UiKit.mc_button("Enchanter", 14)
	button.custom_minimum_size = Vector2(120, 36)
	button.pressed.connect(func(): _apply(key))
	button.name = "button"
	row.add_child(button)

	_rows.append({"key": key, "row": row, "value": value, "cost": cost,
		"button": button})
	return row


## Applique un enchantement a l'objet en main. Renvoie true si c'est passe.
func _apply(key: String) -> bool:
	var player := Game.player
	if player == null:
		return false
	var stack: Dictionary = player.inventory.held()
	if stack.is_empty():
		_status.text = "Mains vides : rien a enchanter."
		_status.modulate = Color(0.95, 0.7, 0.7)
		return false
	var def: Dictionary = Items.ENCHANTS[key]
	var level := int(stack.get("ench", {}).get(key, 0))
	if level >= int(def["max"]):
		_status.text = "%s est deja au maximum." % def["name"]
		_status.modulate = Color(0.95, 0.7, 0.7)
		return false
	var cost_lapis := int(def["lapis"])
	var cost_levels := int(def["levels"])
	if player.inventory.count_of(Items.LAPIS) < cost_lapis:
		_status.text = "Il manque du lapis (%d requis)." % cost_lapis
		_status.modulate = Color(0.95, 0.7, 0.7)
		return false
	if player.xp_level < cost_levels:
		_status.text = "Niveau %d requis." % cost_levels
		_status.modulate = Color(0.95, 0.7, 0.7)
		return false

	player.inventory.take_of(Items.LAPIS, cost_lapis)
	player.xp_level -= cost_levels
	player.xp = 0.0
	stack["ench"] = Inventory.enchants_of(stack)
	stack["ench"][key] = level + 1
	player.inventory.slots[player.inventory.selected] = stack
	Sounds.play_ui("craft")
	_status.text = "%s %s !" % [def["name"], _roman(level + 1)]
	_status.modulate = Color(0.75, 1.0, 0.75)
	_refresh()
	return true


## Chiffre romain des niveaux d'enchantement (I a III).
static func _roman(level: int) -> String:
	match level:
		1: return "I"
		2: return "II"
		_: return "III"


func open() -> void:
	visible = true
	_refresh()


func close_self() -> void:
	Game.close_screens()


func _refresh() -> void:
	var player := Game.player
	if player == null:
		return
	var stack: Dictionary = player.inventory.held()
	_level_label.text = "Niveau %d  —  %s" % [player.xp_level,
		Items.name_of(int(stack.get("id", -1))) if not stack.is_empty() else "mains vides"]
	var enchants := Inventory.enchants_of(stack)
	for entry in _rows:
		var key: String = entry["key"]
		var def: Dictionary = Items.ENCHANTS[key]
		var level := int(enchants.get(key, 0))
		(entry["value"] as Label).text = _roman(level) if level > 0 else "—"
		(entry["cost"] as Label).text = "%d lapis • niv. %d" % [
			int(def["lapis"]), int(def["levels"])]
		var button: Button = entry["button"]
		button.disabled = level >= int(def["max"]) or stack.is_empty() \
			or player.inventory.count_of(Items.LAPIS) < int(def["lapis"]) \
			or player.xp_level < int(def["levels"])
