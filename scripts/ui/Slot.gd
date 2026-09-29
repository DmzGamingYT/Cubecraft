class_name Slot
extends Control

## Un emplacement d'inventaire dessine a la main : fond, icone, nombre.
## Le composant ne connait pas la logique de depot, il emet juste le clic ;
## l'ecran proprietaire decide quoi en faire.

signal pressed(index: int, button: int, shift: bool)
signal hovered(index: int, entered: bool)

var stack: Dictionary = {}
var slot_index := -1
var highlighted := false
var badge := ""

var _hovered := false


func _ready() -> void:
	custom_minimum_size = Vector2(UiKit.SLOT_SIZE, UiKit.SLOT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Pixels nets : sans ça, l'icone 16px étirée en ~32px est lissée
	# (filtre linéaire hérité) et le bâton paraît "gras"/flou.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Un `BoxContainer` etire ses enfants sur son axe, et un `Control` nu est
	# en `SIZE_FILL` par defaut : dans la rangee de fabrication, l'emplacement
	# du resultat etait donc tire sur toute la hauteur de la grille, et l'icone
	# etiree avec lui. On se recentre et on garde le carre.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func set_stack(value: Dictionary) -> void:
	if value == stack:
		return
	stack = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		pressed.emit(slot_index, event.button_index, event.shift_pressed)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		hovered.emit(slot_index, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		hovered.emit(slot_index, false)
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var fill := UiKit.SLOT
	if highlighted:
		fill = UiKit.SLOT_SELECTED
	elif _hovered:
		fill = UiKit.SLOT_HOVER
	# Voile violet : un objet enchante se repere d'un coup d'oeil.
	if not Inventory.enchants_of(stack).is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.16, 0.55, 0.55))
	draw_rect(rect, fill)
	draw_rect(rect, UiKit.BORDER, false, 2.0)

	if badge != "":
		draw_string(ThemeDB.fallback_font, Vector2(5, size.y - 6), badge,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.TEXT_DIM)

	if stack.is_empty():
		return

	var item_id := int(stack.get("id", -1))
	if item_id < 0:
		return
	var icon := Assets.icon_for(item_id)
	if icon == null:
		return
	# Marge interne : l'icone ne touche jamais le cadre.
	var pad := 5.0
	var icon_rect := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	draw_texture_rect(icon, icon_rect, false)

	var count := int(stack.get("count", 1))
	if count > 1:
		var text := str(count)
		var font := ThemeDB.fallback_font
		# `draw_string` avec `width = -1` ignore l'alignement : le texte part
		# vers la droite depuis `pos` et sort du slot (chiffre coupé sur la
		# capture). On mesure et on dessine en LEFT recalé.
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var pos := Vector2(size.x - 6.0 - tw, size.y - 6.0)
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0, 0, 0, 0.85))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
