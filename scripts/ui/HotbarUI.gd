class_name HotbarUI
extends Control

## Barre rapide : les neuf emplacements selectionnables, avec le nom du bloc
## tenu qui apparait brièvement au-dessus.

const NAME_DURATION := 1.8

var _slots: Array[Slot] = []
var _name_label: Label
var _name_timer := 0.0
var _last_selected := -1


func _ready() -> void:
	UiKit.anchor(self, Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 78)
	# Les ancres basses placent le bord HAUT du control en bas d'ecran : sans
	# offset negatif, la barre pousse entierement hors de la fenetre et
	# disparait, enfants compris.
	offset_top = -custom_minimum_size.y

	_name_label = UiKit.label("", 17, Color(1, 1, 1, 0.95))
	UiKit.anchor(_name_label, Control.PRESET_CENTER_BOTTOM)
	_name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_name_label.offset_bottom = -70
	_name_label.offset_top = -96
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	var row := UiKit.grid(Inventory.HOTBAR_SIZE, 1)
	UiKit.anchor(row, Control.PRESET_CENTER_BOTTOM)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -14
	row.offset_top = -14 - UiKit.SLOT_SIZE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	for i in Inventory.HOTBAR_SIZE:
		var node := Slot.new()
		node.slot_index = i
		node.focus_mode = Control.FOCUS_NONE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slots.append(node)
		row.add_child(node)


func _process(delta: float) -> void:
	var inventory := Game.player.inventory if Game.player != null else null
	if inventory == null:
		return
	for i in _slots.size():
		_slots[i].set_stack(inventory.slots[i])
		_slots[i].highlighted = i == inventory.selected

	if inventory.selected != _last_selected:
		_last_selected = inventory.selected
		var item_id := inventory.held_id()
		if item_id > 0:
			_name_label.text = Items.name_of(item_id)
			_name_timer = NAME_DURATION

	if _name_timer > 0.0:
		_name_timer -= delta
		_name_label.modulate.a = clampf(_name_timer / 0.5, 0.0, 1.0)
	else:
		_name_label.text = ""
