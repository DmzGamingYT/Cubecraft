class_name HUD
extends CanvasLayer

## Assemblage de toute l'interface 2D.
##
## Le HUD est en PROCESS_MODE_ALWAYS pour rester vivant pendant la pause, et il
## capte les raccourcis qui doivent rester actifs meme quand un ecran est
## ouvert.

var crosshair: Crosshair
var hotbar: HotbarUI
var hearts: HeartsBar
var debug: DebugOverlay
var inventory_screen: ContainerUI
var crafting_screen: ContainerUI
var pause_menu: PauseMenu
var death_screen: DeathScreen
var enchant_screen: EnchantScreen
var chat: ChatUI

var _cursor_layer: Control
var _was_dead := false


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	crosshair = Crosshair.new()
	add_child(crosshair)

	hotbar = HotbarUI.new()
	add_child(hotbar)

	hearts = HeartsBar.new()
	add_child(hearts)

	debug = DebugOverlay.new()
	add_child(debug)

	inventory_screen = ContainerUI.new(2, "Inventaire")
	add_child(inventory_screen)

	crafting_screen = ContainerUI.new(3, "Établi")
	add_child(crafting_screen)

	pause_menu = PauseMenu.new()
	pause_menu.resume_requested.connect(func(): Game.toggle_pause())
	add_child(pause_menu)

	death_screen = DeathScreen.new()
	death_screen.respawn_requested.connect(_on_respawn)
	add_child(death_screen)

	enchant_screen = EnchantScreen.new()
	add_child(enchant_screen)

	# Le chat est monte avant le curseur : c'est la pile en main qui doit rester
	# au-dessus de tout, y compris de la ligne de saisie.
	chat = ChatUI.new()
	add_child(chat)

	# Le dernier enfant est dessine par-dessus tout : c'est la pile en main.
	_cursor_layer = CursorStack.new()
	add_child(_cursor_layer)


func show_screen(which: int) -> void:
	inventory_screen.visible = which == Game.Screen.INVENTORY
	crafting_screen.visible = which == Game.Screen.CRAFTING
	enchant_screen.visible = which == Game.Screen.ENCHANTING
	if which == Game.Screen.ENCHANTING:
		enchant_screen.open()
	if not inventory_screen.visible:
		inventory_screen.give_back()
	if not crafting_screen.visible:
		crafting_screen.give_back()
	var dead := Game.player != null and Game.player.dead
	crosshair.visible = which == Game.Screen.NONE and not dead
	hotbar.visible = which == Game.Screen.NONE and not dead
	hearts.visible = which == Game.Screen.NONE and not dead
	pause_menu.visible = get_tree().paused


func _on_respawn() -> void:
	if Game.player != null:
		Game.player.respawn()


func _process(_delta: float) -> void:
	pause_menu.visible = get_tree().paused
	if Game.player == null:
		return
	var dead := Game.player.dead
	if dead and not _was_dead:
		death_screen.open(Game.player.death_cause)
	elif not dead:
		death_screen.close()
	_was_dead = dead
	var open := Game.screen == Game.Screen.NONE and not dead
	crosshair.visible = open
	hotbar.visible = open
	hearts.visible = open
	debug.set_target(Game.player.target_id, Game.player.target_pos)
	if not crosshair.visible:
		return
	crosshair.progress = Game.player.mining_ratio
	crosshair.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# La ligne de chat ouverte capte tout : Echap la ferme au lieu de mettre le
	# monde en pause, et aucune touche de jeu ne passe a travers.
	if chat.is_open():
		if event.is_action_pressed("pause") or event.is_action_pressed("chat"):
			chat.close()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("chat"):
		if not get_tree().paused and Game.player != null and not Game.player.dead:
			chat.open()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		if Game.is_screen_open() and not get_tree().paused:
			Game.close_screens()
		else:
			Game.toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug"):
		debug.toggle()
		get_viewport().set_input_as_handled()
		return

	if Game.player == null:
		return

	for i in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Game.player.inventory.selected = i
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("hotbar_next"):
		Game.player.inventory.selected = (Game.player.inventory.selected + 1) % Inventory.HOTBAR_SIZE
	elif event.is_action_pressed("hotbar_prev"):
		Game.player.inventory.selected = (Game.player.inventory.selected \
				+ Inventory.HOTBAR_SIZE - 1) % Inventory.HOTBAR_SIZE
	else:
		return
	get_viewport().set_input_as_handled()
