class_name HeartsBar
extends Control

## Jauges de survie au-dessus de la barre rapide, dessinees en code : 10
## coeurs a gauche (2 PV chacun), 10 pilons a droite, bulles d'air au-dessus
## des pilons quand la tete est sous l'eau. Style pixel, fond sombre si vide.

const ICON := 9.0
const STEP := 11.0


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if Game.player == null:
		return
	var player := Game.player
	var view := get_viewport_rect().size
	var cx := view.x * 0.5
	# La barre fait 9 * 42 + 8 * 4 = 410 px, centree : les jauges s'alignent
	# sur ses bords, comme dans Minecraft.
	var left := cx - 205.0
	var top := view.y - 84.0
	for i in 10:
		var hp := player.health - float(i * 2)
		_draw_heart(Vector2(left + float(i) * STEP, top), hp)
		var fp := player.food - float(i * 2)
		_draw_drumstick(Vector2(cx + 205.0 - float(i + 1) * STEP, top), fp)
	if player.air < Player.MAX_AIR or player._head_in_water:
		for i in 10:
			var ap := player.air - float(i * 2)
			_draw_bubble(Vector2(cx + 205.0 - float(i + 1) * STEP, top - 12.0), ap)
	_draw_xp(cx, top)


## Barre verte d'experience et niveau, au-dessus de la barre rapide.
func _draw_xp(cx: float, top: float) -> void:
	var player := Game.player
	var bar := Rect2(cx - 195.0, top - 13.0, 390.0, 5.0)
	draw_rect(bar, Color(0.06, 0.06, 0.07, 0.85))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * player.xp_progress(), bar.size.y)),
		Color(0.45, 0.85, 0.25))
	draw_rect(bar, Color(0.05, 0.05, 0.05, 0.9), false, 1.0)
	if player.xp_level > 0:
		# Le chiffre de niveau, entoure comme dans Minecraft.
		var text := str(player.xp_level)
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var at := Vector2(cx - width * 0.5, top - 16.0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4,
			Color(0.05, 0.05, 0.05, 0.95))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(0.50, 1.0, 0.30))


## Coeur 9x9 : deux ronds + triangle, rouge plein, moitié ou vide sombre.
func _draw_heart(at: Vector2, hp: float) -> void:
	var dark := Color(0.23, 0.10, 0.10)
	_draw_heart_shape(at, dark)
	if hp >= 2.0:
		_draw_heart_shape(at, Color(0.85, 0.12, 0.12))
	elif hp >= 1.0:
		draw_circle(at + Vector2(2.6, 2.8), 2.6, Color(0.85, 0.12, 0.12))
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.6, 4.0), at + Vector2(4.5, 4.0),
			at + Vector2(4.5, 9.0)]), Color(0.85, 0.12, 0.12))


func _draw_heart_shape(at: Vector2, color: Color) -> void:
	draw_circle(at + Vector2(2.6, 2.8), 2.6, color)
	draw_circle(at + Vector2(6.4, 2.8), 2.6, color)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.6, 4.0), at + Vector2(8.4, 4.0),
		at + Vector2(4.5, 9.0)]), color)


## Pilon : rond marron + reflet, sombre si vide.
func _draw_drumstick(at: Vector2, fp: float) -> void:
	var c := Vector2(at.x + 4.5, at.y + 4.5)
	if fp >= 2.0:
		draw_circle(c, 4.0, Color(0.62, 0.40, 0.20))
		draw_circle(c + Vector2(-1.2, -1.2), 1.4, Color(0.85, 0.62, 0.38))
	elif fp >= 1.0:
		draw_circle(c, 4.0, Color(0.25, 0.17, 0.10))
		draw_arc(c, 4.0, PI * 0.5, PI * 1.5, 8, Color(0.62, 0.40, 0.20), 8.0)
	else:
		draw_circle(c, 4.0, Color(0.25, 0.17, 0.10))


## Bulle d'air : cercle bleu clair, contour seul si vide.
func _draw_bubble(at: Vector2, ap: float) -> void:
	var c := Vector2(at.x + 4.5, at.y + 4.5)
	if ap > 0.0:
		draw_circle(c, 3.6, Color(0.55, 0.80, 0.95, 0.9))
	else:
		draw_arc(c, 3.6, 0.0, TAU, 12, Color(0.35, 0.45, 0.55, 0.7), 1.5)
