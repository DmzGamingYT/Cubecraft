class_name Crosshair
extends Control

## Reticule de visee : deux traits fins traces deux fois (ombre puis lumiere)
## pour rester lisible sur n'importe quel fond. Leger ecart du centre quand on
## mine, comme si la visee "serrait" le bloc.

const LENGTH := 9.0
const THICKNESS := 1.0
const GAP := 2.0

var progress := 0.0


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size * 0.5
	var gap := GAP + progress * 3.0
	var shadow := Color(0, 0, 0, 0.55)
	var light := Color(1, 1, 1, 0.9)
	var tint := light.lerp(Color(1.0, 0.72, 0.25, 0.95), progress)

	for pass_index in 2:
		var color := shadow if pass_index == 0 else tint
		var offset := Vector2.ONE if pass_index == 0 else Vector2.ZERO
		# L'ombre est decalee d'un pixel pour creer le contour.
		for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + axis * gap + offset, center + axis * (gap + LENGTH) + offset,
				color, THICKNESS)
