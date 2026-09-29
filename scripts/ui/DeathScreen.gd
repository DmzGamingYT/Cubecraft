class_name DeathScreen
extends Control

## Ecran de mort facon Minecraft : fond rouge sombre, cause du deces,
## "Reapparaitre" ou "Retour au titre". Visible quand le joueur est mort.

signal respawn_requested
signal title_requested

const CAUSES := {
	"chute": "Vous avez fait une chute mortelle.",
	"noyade": "Vous vous êtes noyé.",
	"faim": "Vous êtes mort de faim.",
	"brulure": "Vous avez brûlé dans la lave, ou contre un cactus.",
}

var _subtitle: Label


func _ready() -> void:
	UiKit.fill_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.35, 0.02, 0.02, 0.75)
	UiKit.fill_screen(backdrop)
	add_child(backdrop)

	var center := CenterContainer.new()
	UiKit.fill_screen(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.panel(UiKit.BG_SOLID, 2,
		Color(0.55, 0.12, 0.12), 6))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := UiKit.label("Vous êtes mort !", 24, Color(0.95, 0.35, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_subtitle = UiKit.label("", 15, UiKit.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle)

	var respawn := UiKit.mc_button("Réapparaître")
	respawn.pressed.connect(func(): respawn_requested.emit())
	column.add_child(respawn)

	var home := UiKit.mc_button("Retour au titre")
	home.pressed.connect(func(): title_requested.emit())
	column.add_child(home)


## Affiche l'ecran avec la cause du deces.
func open(cause: String) -> void:
	_subtitle.text = str(CAUSES.get(cause, ""))
	visible = true


func close() -> void:
	visible = false
