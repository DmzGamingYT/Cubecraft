class_name ChatUI
extends Control

## Chat en jeu : journal qui s'efface et ligne de saisie.
##
## Le reseau existait deja (`Net.send_chat`, `Net.chat_received`, filtrage et
## relais par l'hote) mais aucun ecran ne consommait le signal : le transport
## fonctionnait, personne n'était là pour lire. Ce composant est ce maillon
## manquant, et rien d'autre — il ne filtre pas, ne retransmet pas, ne decide
## de l'ordre des messages. Ces regles restent dans `Net`, qui est le seul a
## savoir qui fait autorite.
##
## Ce n'est **pas** un `Game.Screen` : un ecran de ce genre libere la souris et
## vole le deplacement, alors que le chat doit laisser la souris capturee pour
## qu'on puisse continuer a regarder autour de soi en tapant. D'ou un `Control` a part,
## monte dans le HUD, qui ne fait que poser `can_move = false` le temps que la
## ligne soit ouverte.
##
## Le journal garde peu de lignes et les efface d'elles-memes : une conversation
## a quatre joueurs ne doit pas pousser le reticule hors de l'ecran.

## Lignes conservees au maximum. Au-dela, les plus anciennes sont retirees.
const MAX_LINES := 8
## Duree d'affichage pleine d'une ligne, en secondes.
const LIFETIME := 12.0
## A partir de quand la ligne commence a s'effader.
const FADE_AFTER := 7.0
## Longueur maximale d'un message envoye, en caracteres. Le meme plafond est
## applique cote reseau : celui-ci ne protege que le lien, celui-la l'ecran.
const MAX_LEN := 120

## Ligne d'historique. `age` sert au fondu, `author` et `line` a l'affichage.
var _entries: Array[Dictionary] = []
var _log: VBoxContainer
var _input: LineEdit
var _open := false


func _ready() -> void:
	# Le fond est transparent et le composant ne mange pas la souris : elle doit
	# rester capturee pour que le joueur puisse regarder autour de lui en écrivant.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.chat_received.connect(_on_message)
	# L'hote a refuse une edition : on le dit plutot que de laisser disparaitre
	# le bloc sous les yeux du joueur sans explication.
	Net.block_reverted.connect(func(_pos): add_line("",
		"Edition refusee par l'hote — bloc remis en place.", true))
	visible = true


func _build() -> void:
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	# En bas a gauche, au-dessus de la barre rapide. La marge evite que la
	# derniere ligne touche les coeurs et les emplacements.
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.anchor_top = 0.0
	_log.offset_left = 10.0
	_log.offset_top = -132.0
	_log.offset_bottom = -86.0
	_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_log)

	_input = LineEdit.new()
	_input.visible = false
	_input.max_length = MAX_LEN
	_input.add_theme_font_size_override("font_size", 15)
	_input.add_theme_stylebox_override("normal", UiKit.slot_style(UiKit.BG_SOLID))
	_input.add_theme_stylebox_override("focus", UiKit.slot_style(UiKit.BG_SOLID))
	_input.add_theme_color_override("font_color", UiKit.TEXT)
	_input.add_theme_color_override("caret_color", UiKit.TEXT)
	_input.placeholder_text = "Message…"
	_input.text_submitted.connect(_on_submitted)
	# Meme ligne que le journal, une rangee plus bas : la ligne saisie apparait
	# la ou le texte sera lu ensuite.
	_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_input.anchor_top = 0.0
	_input.offset_left = 10.0
	_input.offset_top = -82.0
	_input.offset_right = 430.0
	_input.offset_bottom = -56.0
	_input.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_input)


## Vrai tant que la ligne de saisie est ouverte : le HUD s'en sert pour ne pas
## transformer la touche Echap en pause, et le joueur pour rester immobile.
func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_input.visible = true
	_input.text = ""
	_input.grab_focus()
	if Game.player != null:
		Game.player.can_move = false
	# La souris reste capturee : c'est ce qui permet de regarder autour de soi
	# en ecrivant, et c'est la difference avec un ecran d'inventaire.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Ferme sans envoyer. Rendu au jeu : la ligne disparait, le joueur remarche.
func close() -> void:
	if not _open:
		return
	_open = false
	_input.visible = false
	_input.release_focus()
	if Game.player != null:
		Game.player.can_move = true
	Game._apply_mouse_captured()


## Envoie la ligne courante, puis rend la main. Un message vide ne part pas.
func _on_submitted(text: String) -> void:
	var clean := text.strip_edges()
	if not clean.is_empty():
		if Net.is_online():
			Net.send_chat(clean)
		else:
			# En solo, `Net.send_chat` ne fait rien du tout : le taper serait
			# silencieusement perdu. On le dit plutot que de laisser croire que
			# le message est parti.
			add_line("", "Le chat n'existe qu'en multijoueur.", true)
	close()


## Reception d'un message, quel que soit son auteur. `peer_id` n'est pas utilise
## ici : `Net` a deja resolu le pseudo, et c'est lui qui garantit qu'un joueur
## ne peut pas se faire passer pour un autre en envoyant un message.
func _on_message(_peer_id: int, author: String, line: String) -> void:
	add_line(author, line, false)


## Ajoute une ligne au journal. `system` = gris et sans auteur : ce n'est pas
## quelqu'un qui parle, c'est le jeu.
func add_line(author: String, text: String, system: bool) -> void:
	var label: Label
	if system:
		label = UiKit.label(text, 14, UiKit.TEXT_DIM)
	else:
		# Le pseudo se distingue par sa couleur et le message reste lisible :
		# dans un historique qui s'efface, c'est la seule maniere de retrouver
		# qui a dit quoi.
		label = UiKit.label("%s : %s" % [author, text], 14, UiKit.TEXT)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 0)
	_log.add_child(label)
	_entries.append({"label": label, "age": 0.0, "base": label.modulate.a})

	# Une ligne de plus que la capacity : on retire les plus anciennes, par la
	# tete de la liste, ce qui evite d'avoir a chercher la plus vieille.
	while _entries.size() > MAX_LINES:
		var old: Dictionary = _entries.pop_front()
		var node: Label = old["label"]
		if is_instance_valid(node):
			node.queue_free()


## Le fondu est porte par `modulate` de chaque etiquette. Une ligne qui part
## doit disparaitre completement, sinon elle s'accumule en semaphore.
func _process(delta: float) -> void:
	for entry in _entries:
		entry["age"] = float(entry["age"]) + delta
	var i := 0
	while i < _entries.size():
		var entry: Dictionary = _entries[i]
		var label: Label = entry["label"]
		var age := float(entry["age"])
		if age > LIFETIME:
			if is_instance_valid(label):
				label.queue_free()
			_entries.remove_at(i)
			continue
		elif age > FADE_AFTER:
			# Fondu quadratique : il s'etire sur les dernieres secondes au lieu
			# de s'ecrouler d'un coup quand le seuil est franchi.
			var t := 1.0 - (age - FADE_AFTER) / (LIFETIME - FADE_AFTER)
			label.modulate.a = t * t
		i += 1
