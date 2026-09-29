class_name CursorStack
extends Control

## Dessine la pile d'objets « en main » a la position de la souris, par-dessus
## toute l'interface. Tant qu'elle n'est pas posee, l'objet suit le curseur
## comme dans Minecraft.

func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Même netteté que les slots : icône 16px suivie au curseur.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	var stack := Game.cursor_stack
	if stack.is_empty() or not Game.is_screen_open():
		visible = false
		return
	visible = true
	queue_redraw()


func _draw() -> void:
	var stack := Game.cursor_stack
	if stack.is_empty():
		return
	var item_id := int(stack.get("id", -1))
	if item_id < 0:
		return
	var icon := Assets.icon_for(item_id)
	var size_px := 30.0
	var origin := get_viewport().get_mouse_position() - Vector2(size_px, size_px) * 0.5
	if icon != null:
		draw_texture_rect(icon, Rect2(origin, Vector2(size_px, size_px)), false)
	var count := int(stack.get("count", 1))
	if count > 1:
		var font := ThemeDB.fallback_font
		var text := str(count)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var pos := origin + Vector2(size_px - tw, size_px)
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0, 0, 0, 0.85))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
