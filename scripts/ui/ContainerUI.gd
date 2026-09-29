class_name ContainerUI
extends Control

## Ecran de conteneur : inventaire du joueur et grille de fabrication.
##
## Le meme composant sert pour l'inventaire (grille 2x2) et pour l'etabli
## (grille 3x3) : seule la taille de grille change. La pile tenue par le
## curseur vit dans `Game.cursor_stack`, ce qui lui permet de suivre la souris
## meme a travers les changements d'ecran.

const SHIFT_REFRESH_LIMIT := 64

var grid_size := 2
var grid: Array = []
var screen_title := "Inventaire"

var _slot_nodes: Array[Slot] = []
var _grid_nodes: Array[Slot] = []
var _result_node: Slot
var _result: Dictionary = {}
var _built := false


func _init(p_size: int = 2, p_title: String = "Inventaire") -> void:
	grid_size = p_size
	screen_title = p_title


func _ready() -> void:
	grid.clear()
	for i in grid_size * grid_size:
		grid.append({})
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_recompute()
	_refresh()
	visible = false


func _build() -> void:
	if _built:
		return
	_built = true

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	UiKit.fill_screen(backdrop)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# `CenterContainer` plutôt que des ancres à 0.5 : voir le commentaire du
	# meme nom dans PauseMenu — les offsets herites decalent le panneau.
	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel())
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := UiKit.label(screen_title, 18, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# --- Zone de fabrication
	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 16)
	craft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(craft_row)

	var grid_box := UiKit.grid(grid_size, grid_size)
	craft_row.add_child(grid_box)
	for i in grid_size * grid_size:
		var node := _make_slot(i)
		_grid_nodes.append(node)
		grid_box.add_child(node)
		node.pressed.connect(_on_grid_pressed)

	craft_row.add_child(UiKit.label("→", 22, UiKit.TEXT_DIM))

	_result_node = _make_slot(-1)
	craft_row.add_child(_result_node)
	_result_node.pressed.connect(_on_result_pressed)

	column.add_child(HSeparator.new())
	column.add_child(UiKit.label("Inventaire", 14, UiKit.TEXT_DIM))

	var main_box := UiKit.grid(9, 3)
	column.add_child(main_box)
	for i in 27:
		var node := _make_slot(Inventory.HOTBAR_SIZE + i)
		_slot_nodes.append(node)
		main_box.add_child(node)
		node.pressed.connect(_on_inventory_pressed)

	column.add_child(HSeparator.new())

	var hotbar_box := UiKit.grid(9, 1)
	column.add_child(hotbar_box)
	for i in Inventory.HOTBAR_SIZE:
		var node := _make_slot(i)
		_slot_nodes.append(node)
		hotbar_box.add_child(node)
		node.pressed.connect(_on_inventory_pressed)


func _make_slot(index: int) -> Slot:
	var node := Slot.new()
	node.focus_mode = Control.FOCUS_NONE
	node.slot_index = index
	return node


# -------------------------------------------------------------- interactions

func _on_grid_pressed(index: int, button: int, shift: bool) -> void:
	if shift and button == MOUSE_BUTTON_LEFT:
		_send_grid_to_inventory(index)
	else:
		_click_stack(grid, index, button)
	_recompute()
	_refresh()


func _on_inventory_pressed(index: int, button: int, shift: bool) -> void:
	var slots: Array = Game.player.inventory.slots
	if shift and button == MOUSE_BUTTON_LEFT:
		_quick_move(slots, index)
	else:
		_click_stack(slots, index, button)
	_recompute()
	_refresh()


func _on_result_pressed(_index: int, button: int, _shift: bool) -> void:
	_take_result(button == MOUSE_BUTTON_RIGHT)
	_recompute()
	_refresh()


## Clic sur un emplacement : prendre la pile, la deposer, echanger ou fusionner.
func _click_stack(model: Array, index: int, button: int) -> void:
	var cursor := Game.cursor_stack
	var slot: Dictionary = model[index]

	if button == MOUSE_BUTTON_LEFT:
		if cursor.is_empty():
			if slot.is_empty():
				return
			Game.cursor_stack = slot.duplicate(true)
			model[index] = {}
			return
		if slot.is_empty():
			model[index] = cursor.duplicate(true)
			Game.cursor_stack = {}
			return
		if int(slot["id"]) == int(cursor["id"]):
			var room := Items.max_stack(int(cursor["id"])) - int(slot["count"])
			if room > 0:
				var moved := mini(room, int(cursor["count"]))
				slot["count"] = int(slot["count"]) + moved
				cursor["count"] = int(cursor["count"]) - moved
				if int(cursor["count"]) <= 0:
					Game.cursor_stack = {}
		else:
			model[index] = cursor.duplicate(true)
			Game.cursor_stack = slot.duplicate(true)
		return

	# Clic droit : on prend la moitie de la pile, on pose une seule unite.
	if cursor.is_empty():
		if slot.is_empty():
			return
		var half := int(ceil(float(slot["count"]) * 0.5))
		Game.cursor_stack = {"id": int(slot["id"]), "count": half}
		slot["count"] = int(slot["count"]) - half
		if int(slot["count"]) <= 0:
			model[index] = {}
		return

	var item_id := int(cursor["id"])
	if slot.is_empty():
		cursor["count"] = int(cursor["count"]) - 1
		model[index] = {"id": item_id, "count": 1}
	elif int(slot["id"]) == item_id and int(slot["count"]) < Items.max_stack(item_id):
		slot["count"] = int(slot["count"]) + 1
		cursor["count"] = int(cursor["count"]) - 1
	if int(Game.cursor_stack.get("count", 0)) <= 0:
		Game.cursor_stack = {}


## Maj+clic : deplacement rapide entre inventaire et barre rapide.
func _quick_move(slots: Array, index: int) -> void:
	var slot: Dictionary = slots[index]
	if slot.is_empty():
		return
	var item_id := int(slot["id"])
	var limit := Items.max_stack(item_id)
	var from := Inventory.HOTBAR_SIZE if index < Inventory.HOTBAR_SIZE else 0
	var to := slots.size() if index < Inventory.HOTBAR_SIZE else Inventory.HOTBAR_SIZE

	for i in range(from, to):
		var other: Dictionary = slots[i]
		if not other.is_empty() and int(other["id"]) != item_id:
			continue
		if other.is_empty():
			slots[i] = slot.duplicate(true)
			slots[index] = {}
			return
		if int(other["count"]) < limit:
			var moved := mini(limit - int(other["count"]), int(slot["count"]))
			other["count"] = int(other["count"]) + moved
			slot["count"] = int(slot["count"]) - moved
			if int(slot["count"]) <= 0:
				slots[index] = {}
			return


## Maj+clic sur la grille : le contenu part dans le rangement.
func _send_grid_to_inventory(index: int) -> void:
	var cell: Dictionary = grid[index]
	if cell.is_empty():
		return
	var left := Game.player.inventory.add(int(cell["id"]), int(cell["count"]))
	grid[index] = {"id": int(cell["id"]), "count": left} if left > 0 else {}


## Clic sur le resultat : recupere un lot, ou fabrique en boucle (clic droit).
func _take_result(all: bool = false) -> void:
	if _result.is_empty():
		return
	var item_id := int(_result["id"])
	var amount := int(_result["count"])

	if not all:
		var cursor := Game.cursor_stack
		if cursor.is_empty():
			if Game.player.inventory.add(item_id, amount) > 0:
				return  # rangement plein
		else:
			if int(cursor["id"]) != item_id:
				return
			if int(cursor["count"]) + amount > Items.max_stack(item_id):
				return
			cursor["count"] = int(cursor["count"]) + amount
		_consume_ingredients()
		Sounds.play_ui("craft", -8.0)
		return

	# Fabrication en serie : on s'arrete des que le rangement est plein ou que
	# les ingredients manquent.
	for _i in SHIFT_REFRESH_LIMIT:
		if _result.is_empty():
			break
		if Game.player.inventory.add(item_id, int(_result["count"])) > 0:
			break
		_consume_ingredients()
		_recompute()
	_refresh()
	Sounds.play_ui("craft", -8.0)


func _consume_ingredients() -> void:
	for i in grid.size():
		var cell: Dictionary = grid[i]
		if cell.is_empty():
			continue
		cell["count"] = int(cell["count"]) - 1
		if int(cell["count"]) <= 0:
			grid[i] = {}


func _recompute() -> void:
	var ids: Array = []
	for cell in grid:
		ids.append(int(cell.get("id", Recipes.EMPTY)))
	_result = Recipes.match(ids, grid_size)


func _refresh() -> void:
	if Game.player == null:
		return
	for i in _grid_nodes.size():
		_grid_nodes[i].set_stack(grid[i])
	if _result_node != null:
		_result_node.set_stack(_result)
	var slots: Array = Game.player.inventory.slots
	for node in _slot_nodes:
		var index: int = node.slot_index
		node.set_stack(slots[index] if index < slots.size() else {})


## Rend au joueur ce qui restait dans la grille quand l'ecran se ferme.
func give_back() -> void:
	for i in grid.size():
		var cell: Dictionary = grid[i]
		if cell.is_empty():
			continue
		if Game.player.inventory.add(int(cell["id"]), int(cell["count"])) > 0:
			ItemEntity.spawn(Game.world, Game.player.global_position + Vector3(0, 1, 0),
				int(cell["id"]), int(cell["count"]))
		grid[i] = {}


func _process(_delta: float) -> void:
	# L'inventaire peut changer pendant que l'ecran est ouvert (ramassage d'un
	# objet tombe a cote) : on resynchronise sans reconstruire l'interface.
	if visible and Game.player != null:
		_refresh()
