extends Node

## Autoload `InputSetup`.
##
## Enregistre les touches au demarrage plutot que dans project.godot : le
## mapping reste lisible, versionnable et facile a retoucher. Les
## `physical_keycode` identifient une touche par sa POSITION sur le clavier et
## non par son etiquette : sur un AZERTY, {Z} et {W} declenchent "avancer".

## Touches physiques : AZERTY en priorite, QWERTY en secours.
const KEYS := {
	"move_forward": [KEY_W, KEY_Z, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_Q, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL],
	"fly": [KEY_F],
	"drop": [KEY_G],
	"inventory": [KEY_E],
	# Chat : T, et la barre oblique comme dans Minecraft. Les deux ouvrent la
	# meme ligne de saisie.
	"chat": [KEY_T, KEY_SLASH],
	"debug": [KEY_F3],
	"debug_menu": [KEY_F4],
	"save": [KEY_F5],
	# Rendu : F6 fait le tour des modes de post-traitement (voir `PostFx`).
	"shader_toggle": [KEY_F6],
	"pause": [KEY_ESCAPE],
	"hotbar_1": [KEY_1],
	"hotbar_2": [KEY_2],
	"hotbar_3": [KEY_3],
	"hotbar_4": [KEY_4],
	"hotbar_5": [KEY_5],
	"hotbar_6": [KEY_6],
	"hotbar_7": [KEY_7],
	"hotbar_8": [KEY_8],
	"hotbar_9": [KEY_9],
}

## Combos de touches : une touche **modifiee**. Le registre ne permet pas
## d'ecrire « Ctrl + Alt + D », et c'est precisement ce qui distingue un
## raccourci d'atelier d'une touche de jeu : F4 tombe sous les doigts en
## plein combat, le trio Ctrl+Alt+D demande de vouloir ouvrir l'outil.
const CHORDS := {
	"debug_menu": [{ "key": KEY_D, "ctrl": true, "alt": true }],
}

const MOUSE := {
	"break": [MOUSE_BUTTON_LEFT],
	"attack": [MOUSE_BUTTON_LEFT],
	"place": [MOUSE_BUTTON_RIGHT],
	"pick": [MOUSE_BUTTON_MIDDLE],
	"hotbar_next": [MOUSE_BUTTON_WHEEL_DOWN],
	"hotbar_prev": [MOUSE_BUTTON_WHEEL_UP],
}

## Boutons de manette. Le pave gauche pilote la deplacement et la camera ; le
## pave droit reprend les gestes de la souris — miner, poser, prendre — pour que
## les deux mains restent sur les sticks, qui sont les seuls controles qu'on
## regarde vraiment.
##
## Les declencheurs analogiques (gachettes) sont poses comme des axes : c'est la
## seule facon d'en tirer une graduation, et c'est ce qui permet de viser sans
## entrainer l'axe. Ils ne sont volontairement pas dans ce tableau — voir
## JOY_AXES.
const JOY_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"drop": [JOY_BUTTON_B],
	"inventory": [JOY_BUTTON_X],
	"fly": [JOY_BUTTON_Y],
	"sprint": [JOY_BUTTON_RIGHT_STICK],
	"crouch": [JOY_BUTTON_LEFT_STICK],
	"pause": [JOY_BUTTON_START],
	"chat": [JOY_BUTTON_BACK],
	"attack": [JOY_BUTTON_RIGHT_SHOULDER],
	"break": [JOY_BUTTON_RIGHT_SHOULDER],
	"place": [JOY_BUTTON_LEFT_SHOULDER],
	"debug_menu": [JOY_BUTTON_MISC1],
}

## Axes de manette : [axe, signe]. Le signe indique la direction positive, pour
## que « avancer » soit l'axe Y pousse vers l'arriere : le pousse-souris etant
## tourne vers le joueur, son avant est le -Y.
##
## Un axe unique produit deux demi-touches, l'une tiree vers 0, l'autre vers -1 :
## c'est le format de `InputMap`, pas une astuce du jeu.
const JOY_AXES := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [[JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
	# Gachettes : elles ne sont pressees qu'au bout du course.
	"pick": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"hotbar_next": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"hotbar_prev": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
}

## Zone morte des sticks, en fraction de course. Sous 0,2 un stick au repos fait
## encore derives le joueur dans une direction ; au-dessus, il faut trop de
## poussee pour marcher droit.
const STICK_DEADZONE := 0.22


func _enter_tree() -> void:
	register()


## (Re)declare toutes les actions. Appele aussi apres un changement de reglages.
static func register() -> void:
	for action in KEYS:
		_add_keys(action, KEYS[action])
	for action in CHORDS:
		for chord in CHORDS[action]:
			_add_chord(action, chord)
	for action in MOUSE:
		_add_mouse(action, MOUSE[action])
	for action in JOY_BUTTONS:
		_add_joy_button(action, JOY_BUTTONS[action])
	for action in JOY_AXES:
		_add_joy_axis(action, JOY_AXES[action])


static func _add_keys(action: StringName, codes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code in codes:
		var event := InputEventKey.new()
		event.physical_keycode = code
		InputMap.action_add_event(action, event)


static func _add_chord(action: StringName, chord: Dictionary) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = int(chord.get("key", 0))
	event.ctrl_pressed = bool(chord.get("ctrl", false))
	event.alt_pressed = bool(chord.get("alt", false))
	event.shift_pressed = bool(chord.get("shift", false))
	InputMap.action_add_event(action, event)


static func _add_mouse(action: StringName, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for button in buttons:
		var event := InputEventMouseButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)


static func _add_joy_button(action: StringName, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for button in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)


## Un axe donne deux touches opposees : la demi-course vers le signe demande, et
## l'autre vers le signe inverse. Sans les deux, pousser le stick a fond declenche
## l'action a l'envers de ce qu'on attend.
static func _add_joy_axis(action: StringName, entries: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# Les sticks ont une zone morte, les gachettes non : une gachette au repos
	# n'est pas a moitie poussee.
	if not (entries[0][0] == JOY_AXIS_TRIGGER_LEFT or entries[0][0] == JOY_AXIS_TRIGGER_RIGHT):
		InputMap.action_set_deadzone(action, STICK_DEADZONE)
	for entry in entries:
		var axis: int = int(entry[0])
		var direction: float = float(entry[1])
		var pressed := InputEventJoypadMotion.new()
		pressed.axis = axis
		pressed.axis_value = direction
		InputMap.action_add_event(action, pressed)
		var released := InputEventJoypadMotion.new()
		released.axis = axis
		released.axis_value = 0.0
		InputMap.action_add_event(action, released)
