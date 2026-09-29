class_name TitleWorlds
extends VBoxContainer

## Panneau « Mes mondes » du menu de lancement.
##
## Il remplace l'ancien bouton unique « Charger la partie », qui ne pouvait
## dire ni *quel* monde on reprend, ni en creer un deuxieme sans effacer le
## premier. Le jeu garde six emplacements ; ce panneau en montre les six, vides
## compris, parce qu'un emplacement vide est justement celui sur lequel on cree.
##
## Il ne touche pas au disque : il lit `SaveSystem.list_slots()` et annonce les
## intentions par signaux. C'est `TitleScreen` qui appelle `Game` — effacer une
## sauvegarde depuis un panneau d'interface serait le seul endroit du jeu ou
## supprimer un fichier n'aurait pas a passer par lui.
##
## Supprimer demande deux fois. Une seule fois, un clic glisse sur un bouton mal
## vise suffit a perdre des heures de jeu ; le second appui se fait sur un bouton
## qui a change de couleur ET de texte, donc sur une decision vue et non devinee.

## Reprendre l'emplacement `slot`.
signal load_slot(slot: int)
## Creer une partie et la enregistrer dans l'emplacement `slot`.
signal create_slot(slot: int)
## Effacer definitivement l'emplacement `slot`.
signal delete_slot(slot: int)
## Le joueur a fini.
signal back_requested

const ROW_WIDTH := 398.0
const ROW_HEIGHT := 56.0
## Hauteur visible de la liste : quatre lignes entieres, separations comprises.
## Un nombre de lignes et non une hauteur libre — une ligne coupee en son
## milieu se lit comme une carte mal disposee, alors qu'elle dit seulement que
## la liste defile.
const LIST_HEIGHT := ROW_HEIGHT * 4.0 + 4.0 * 3.0

var _list: VBoxContainer
var _rows: Dictionary = {}
## Emplacement dont la suppression attend un second appui. Un seul a la fois :
## deux confirmations ouvertes obligeraient a se souvenir de laquelle on etait
## en train de faire.
var _pending_delete := 0


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	if _list == null:
		_build()


## Recharge la liste depuis le disque et redessine chaque ligne. Appele a chaque
## ouverture : une partie peut avoir ete sauvegardee depuis l'ecran de pause
## juste avant de revenir au titre, et la ligne doit le dire.
func refresh() -> void:
	if _list == null:
		_build()
	_pending_delete = 0
	# La liste revient en haut a chaque ouverture. Sans ce reset, elle souvrait
	# ou le joueur l'avait laissee — et `follow_focus` entrainait ensuite la
	# carte vers le bas, parce que le focus du bouton « Retour » suivait la
	# defilement : le monde 1, celui qu'on cherche, etait hors de l'ecran.
	_scroll_to_top()
	var entries := SaveSystem.list_slots()
	for entry in entries:
		_write_row(int(entry["slot"]), entry)


func _scroll_to_top() -> void:
	var scroll := _list.get_parent() as ScrollContainer
	if scroll == null:
		return
	scroll.set_deferred("vertical_scroll", 0.0)


func _build() -> void:
	var title := UiKit.label("Mes mondes", 18, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# Les six lignes font bien plus que la carte : la liste defile plutot que de
	# tronquer, et la molette comme le stick droit la font fonctionner.
	var scroll := ScrollContainer.new()
	scroll.name = "Liste"
	scroll.custom_minimum_size = Vector2(ROW_WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "Emplacements"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	for slot in range(1, SaveSystem.SLOT_COUNT + 1):
		_add_row(slot)

	var back := UiKit.mc_button("Retour")
	back.custom_minimum_size = Vector2(ROW_WIDTH, 40.0)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)


func _add_row(slot: int) -> void:
	var card := PanelContainer.new()
	card.name = "Emplacement%d" % slot
	card.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	card.add_theme_stylebox_override("panel", UiKit.card(
		Color(0.06, 0.07, 0.09, 0.72), Color(1.0, 1.0, 1.0, 0.12), 6))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# Le numero a gauche, dans une colonne fixe : il dit « ou » dans la liste
	# sans cycle, et il garde la meme place quel que soit le nom du monde.
	var badge := UiKit.label(str(slot), 20, UiKit.TEXT_DIM)
	badge.name = "Numero"
	badge.custom_minimum_size = Vector2(24.0, 0.0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)

	var texts := VBoxContainer.new()
	texts.name = "Textes"
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Largeur nulle imposee : sans elle, un `Label` annonce la largeur de son
	# TEXTE comme taille minimale, et la colonne s'elargissait du plus long nom
	# de monde trouve — la carte deborderait alors de la largeur du bouton.
	texts.custom_minimum_size = Vector2(0.0, 0.0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)

	var name_label := UiKit.label("", 14, UiKit.TEXT)
	name_label.name = "Nom"
	name_label.custom_minimum_size = Vector2(0.0, 18.0)
	# Une seule ligne : un nom de monde qui deborderait sur trois pousserait la
	# ligne hors de la carte et desalignerait toute la liste. Le libelle est
	# volontairement court pour que cela n'arrive jamais.
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	texts.add_child(name_label)

	var detail := UiKit.label("", 11, UiKit.TEXT_DIM)
	detail.name = "Detail"
	detail.custom_minimum_size = Vector2(0.0, 14.0)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.clip_text = true
	texts.add_child(detail)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 4)
	row.add_child(actions)

	_list.add_child(card)
	_rows[slot] = {"card": card, "nom": name_label, "detail": detail,
		"actions": actions, "texts": texts}


## Redessine une ligne d'apres son en-tete. Les deux boutons sont recrees a chaque
## fois : un emplacement peut passer de vide a occupe sans que la ligne change
## de forme, et un bouton « Charger » pose sur un emplacement vide serait le
## silence le plus trompeur du menu.
func _write_row(slot: int, entry: Dictionary) -> void:
	var row: Dictionary = _rows.get(slot)
	if row.is_empty():
		return
	var actions: HBoxContainer = row["actions"]
	for child in actions.get_children():
		child.queue_free()

	var nom: Label = row["nom"]
	var detail: Label = row["detail"]
	nom.text = SaveSystem.slot_label(entry)
	detail.text = SaveSystem.slot_detail(entry)

	if not bool(entry.get("exists", false)):
		nom.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		# Un emplacement vide ne montre qu'un bouton : « Créer » n'a pas besoin
		# d'une ligne entiere, et un second bouton « Effacer » y serait absurde.
		var create := UiKit.mc_button("Créer")
		create.custom_minimum_size = Vector2(96.0, 38.0)
		create.pressed.connect(func(): create_slot.emit(slot))
		actions.add_child(create)
		return

	nom.add_theme_color_override("font_color", UiKit.TEXT)
	# Boutons volontairement courts. « Charger » et non « Reprendre » : six
	# caracteres de moins, soit 30 px rendus a la colonne de texte — assez pour
	# que la graine et la date tiennent sur une ligne au lieu d'etre coupees.
	var load_button := UiKit.mc_primary_button("Charger")
	load_button.custom_minimum_size = Vector2(88.0, 38.0)
	load_button.pressed.connect(func(): load_slot.emit(slot))
	actions.add_child(load_button)

	var erase := UiKit.mc_danger_button("Effacer")
	erase.name = "Effacer"
	erase.custom_minimum_size = Vector2(76.0, 38.0)
	erase.pressed.connect(func(): _on_delete_pressed(slot))
	actions.add_child(erase)


## Premier appui : le bouton se transforme en « Confirmer ? » et passe au rouge.
## Second appui sur ce meme bouton : la suppression part. Revenir au panneau
## principal annule l'attente — le joueur qui change d'avis ne doit pas avoir a
## aller chercher un bouton « Annuler ».
func _on_delete_pressed(slot: int) -> void:
	if _pending_delete == slot:
		_pending_delete = 0
		delete_slot.emit(slot)
		return
	_pending_delete = slot
	var row: Dictionary = _rows.get(slot)
	if row.is_empty():
		return
	var actions: HBoxContainer = row["actions"]
	var previous := actions.get_node_or_null("Effacer")
	if previous == null:
		return
	# Le bouton est REFAIT par la fabrique plutot que retague a la main : sa
	# plaque vient de `mc_danger_button`, et la refaire ici en dupliquerait les
	# quatre etats.
	var armed := UiKit.mc_danger_button("Confirmer ?", 16, true)
	armed.name = "Effacer"
	armed.custom_minimum_size = previous.custom_minimum_size
	armed.pressed.connect(func(): _on_delete_pressed(slot))
	actions.remove_child(previous)
	previous.queue_free()
	actions.add_child(armed)
	# Le nouveau bouton est le dernier enfant : on lui donne le focus pour que la
	# confirmation puisse se faire au stick, sans viser.
	armed.call_deferred("grab_focus")


## Une suppression est-elle en attente de second appui ? L'ecran titre s'en sert
## pour que Echap annule l'attente avant de fermer le panneau.
func has_pending_delete() -> bool:
	return _pending_delete != 0


## Annule une suppression en attente, si le joueur a change d'avis ou d'ecran.
## La ligne est redessinee depuis le disque : c'est le seul moyen de retrouver un
## bouton « Effacer » intact, puisque `mc_danger_button` l'a remplace.
func cancel_pending() -> void:
	if _pending_delete == 0:
		return
	_pending_delete = 0
	for entry in SaveSystem.list_slots():
		_write_row(int(entry["slot"]), entry)
