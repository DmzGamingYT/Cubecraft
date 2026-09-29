class_name PostFx
extends CanvasLayer

## Post-traitement d'ecran, cyclable par une touche dediee (`F6`).
##
## Un seul passage plein ecran, **une seule** lecture de texture et une
## vingtaine d'operations arithmetiques : pas de flou, pas de plusieurs passes,
## pas de lecture de voisins. C'est ce qui le rend utilisable sur une machine
## modeste — l'effet coute un blit plein ecran, rien de plus.
##
## Le shader lit l'image deja rendue (`hint_screen_texture`) et n'ecrit qu'une
## couleur par pixel : saturation, contraste, lumiere, teinte chaude et
## vignette. Tout est reglable par uniformes, si bien que les presets ne
## recompilent rien — changer de mode ne fait que pousser des flottants.
##
## La couche est posee **au-dessus de la 3D et au-dessous du HUD** (niveau 5,
## le HUD est a 10) : l'interface garde ses couleurs exactes, et un texte
## d'inventaire n'est jamais assombri par la vignette.

## Niveau de la couche. Au-dessus du monde, sous le HUD.
const LAYER := 5

## Les modes, dans l'ordre du cycle. Le premier est le jeu tel quel : la touche
## fait donc toujours revenir a l'image d'origine sans quitter le jeu.
const PRESETS := [
	{
		"name": "Naturel",
		"enabled": false,
		"saturation": 1.0, "contrast": 1.0, "brightness": 1.0,
		"warmth": 0.0, "vignette": 0.0,
	},
	{
		"name": "Chaleureux",
		"enabled": true,
		"saturation": 1.16, "contrast": 1.08, "brightness": 1.02,
		"warmth": 0.05, "vignette": 0.34,
	},
	{
		"name": "Vif",
		"enabled": true,
		"saturation": 1.34, "contrast": 1.16, "brightness": 1.05,
		"warmth": 0.03, "vignette": 0.22,
	},
]

## Code du shader. Ecrit ici plutot que dans un `.gdshader` comme le reste du
## projet, qui ne pose aucun fichier d'asset : c'est le meme choix que l'atlas
## et les sons, tous generes par le code.
const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float brightness = 1.0;
uniform float warmth = 0.0;
uniform float vignette = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	// Contraste puis lumiere : l'ordre compte, un contraste applique apres la
	// lumiere assombrit les hautes lumieres au lieu de les etaler.
	c = (c - 0.5) * contrast + 0.5;
	c *= brightness;
	// Saturation, autour de la luminance percue (Rec. 709).
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	// Teinte : un peu plus de rouge et moins de bleu, comme une fin d'apres-midi.
	c *= vec3(1.0 + warmth, 1.0, 1.0 - warmth * 0.8);
	// Vignette : eloignement au carre du centre, donc douce pres du milieu et
	// seulement sensible dans les coins.
	vec2 d = SCREEN_UV - vec2(0.5);
	c *= clamp(1.0 - dot(d, d) * vignette * 3.0, 0.0, 1.0);
	COLOR = vec4(clamp(c, vec3(0.0), vec3(1.0)), 1.0);
}
"""

var index := 0

var _rect: ColorRect
var _material: ShaderMaterial
var _toast: Label
var _toast_time := 0.0
var _toast_rise := 0.0


func _ready() -> void:
	layer = LAYER
	# Le menu de pause gele l'arbre ; le post-traitement doit continuer de
	# suivre les changements de mode pendant la pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shader := Shader.new()
	shader.code = SHADER_CODE

	_material = ShaderMaterial.new()
	_material.shader = shader

	_rect = ColorRect.new()
	_rect.name = "Grade"
	_rect.material = _material
	# Le rect couvre l'ecran : le shader lit l'image courante et la reecrit.
	# `fill_screen` plutot que `set_anchors_preset` : le preset ne remet pas les
	# offsets a zero, et un rect de taille nulle ne montrerait rien du tout.
	UiKit.fill_screen(_rect)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)

	_toast = Label.new()
	_toast.name = "Toast"
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_color_override("font_color", Color(1, 1, 0.88))
	_toast.add_theme_color_override("font_shadow_color", Color(0.08, 0.08, 0.10))
	_toast.add_theme_constant_override("shadow_offset_x", 2)
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 12.0
	_toast.offset_bottom = 40.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)

	_apply()


## Passe au mode suivant et le nomme a l'ecran : sans ce message, la touche
## semblerait ne rien faire quand on revient de « Vif » a « Naturel » (l'ecran
## retrouve simplement son aspect d'origine, ce qui peut passer pour un bug).
func cycle() -> int:
	return step(1)


## Avance ou recule d'un mode. La pause s'en sert pour offrir les deux sens :
## une touche unique qui ne ferait qu'avancer obligerait a en faire le tour
## pour revenir en arriere.
func step(delta: int) -> int:
	index = posmod(index + delta, PRESETS.size())
	_apply()
	_show_toast()
	return index


## Force un mode par son numero, sans message. C'est le reglage de demarrage
## (`--shader=N`) qui s'en sert : afficher le bandeau au lancement n'aurait
## aucun sens.
func set_index(value: int) -> void:
	index = posmod(value, PRESETS.size())
	_apply()


## Nombre de modes disponibles, cycle compris.
static func count() -> int:
	return PRESETS.size()


func preset_name() -> String:
	return str(PRESETS[index]["name"])


func is_enabled() -> bool:
	return bool(PRESETS[index]["enabled"])


## Pousse les uniformes du mode courant. Aucune compilation : un preset n'est
## qu'un jeu de flottants.
func _apply() -> void:
	var preset: Dictionary = PRESETS[index]
	_material.set_shader_parameter("saturation", preset["saturation"])
	_material.set_shader_parameter("contrast", preset["contrast"])
	_material.set_shader_parameter("brightness", preset["brightness"])
	_material.set_shader_parameter("warmth", preset["warmth"])
	_material.set_shader_parameter("vignette", preset["vignette"])
	_rect.visible = bool(preset["enabled"])


func _show_toast() -> void:
	if _toast == null:
		return
	_toast.text = "Rendu : %s   (F6)" % preset_name()
	_toast_time = 1.6
	_toast_rise = 1.0
	_toast.visible = true
	_toast.modulate.a = 1.0


func _process(delta: float) -> void:
	if _toast_time <= 0.0:
		return
	_toast_time = maxf(0.0, _toast_time - delta)
	# Le message monte puis s'efface : il ne reste pas pose sur le jeu.
	_toast_rise = maxf(0.0, _toast_rise - delta)
	var t := _toast_time / 1.6
	_toast.modulate.a = clampf(t * 1.8, 0.0, 1.0)
	_toast.offset_top = 12.0 - (1.0 - _toast_rise) * 6.0
	_toast.offset_bottom = _toast.offset_top + 28.0
	if _toast_time <= 0.0:
		_toast.visible = false
