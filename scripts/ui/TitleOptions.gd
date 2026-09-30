class_name TitleOptions
extends VBoxContainer

## Panneau « Reglages » du menu de lancement.
##
## Il ne connait pas le jeu : il lit et ecrit `Settings`, puis annonce chaque
## changement par `changed`. C'est `TitleScreen` — et non ce panneau — qui
## applique effectivement le volume au lecteur de sons et le champ de vision au
## joueur. Un panneau qui s'afficherait tout seul parlerait a des noeuds qui
## n'existent pas encore au moment ou il est construit.
##
## Chaque reglage est une ligne complete, pas une etiquette et un controle
## separes : a cette taille de carte, un intitule au-dessus de son controle
## repete six fois mangerait la moitie de la hauteur.
##
## Le panneau se construit sans arbre de scene (le test de fumee le compile), et
## lit ses valeurs au moment ou on l'affiche — un reglage change par le menu
## pause doit s'y retrouver tel quel.

## Un reglage a change. `key` est la cle de `Settings`, `value` sa nouvelle
## valeur, deja bornee.
signal changed(key: String, value: Variant)
## Le joueur a fini : retour au panneau principal.
signal back_requested

const ROW_WIDTH := 340.0

## Texte d'un reglage, dans l'ordre d'affichage. Un reglages par ligne, donc
## l'ordre du tableau EST l'ordre a l'ecran.
##
## La taille de l'interface ouvre la liste : c'est le seul reglage qui change la
## maniere dont on LIT tous les autres, et un joueur qui la cherche doit la
## trouver avant d'avoir a decroiser une colonne.
const ROWS := [
	{"key": "ui_scale", "title": "Taille de l'interface"},
	{"key": "music", "title": "Musique"},
	{"key": "sfx", "title": "Bruitages"},
	{"key": "fov", "title": "Champ de vision"},
	{"key": "sensitivity", "title": "Sensibilité"},
	{"key": "render_distance", "title": "Portée de rendu"},
	{"key": "shader", "title": "Rendu"},
]

var _rows: Dictionary = {}


func _init() -> void:
	# Separation resserree : huit lignes de 36 px dans une carte de 450 ne
	# laissent pas la place d'un espacement de 6 px entre chacune.
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	if _rows.is_empty():
		_build()


## Recharge l'affichage depuis `Settings`. Appele a chaque ouverture du panneau :
## un reglage change ailleurs (menu pause, ligne de commande) doit se voir ici.
func refresh() -> void:
	if _rows.is_empty():
		_build()
	for key in _rows:
		_write_row(key)


func _build() -> void:
	var title := UiKit.label("Réglages", 18, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	add_child(UiKit.divider(ROW_WIDTH))

	for spec in ROWS:
		_add_stepper(str(spec["key"]), str(spec["title"]))

	add_child(UiKit.divider(ROW_WIDTH))
	_add_toggle("invert_y", "Inverser l'axe vertical")

	var hint := UiKit.label(
		"La portée de rendu ne s'applique qu'à la prochaine partie",
		11, TitleScreen.HINT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

	var reset := UiKit.mc_button("Réinitialiser")
	reset.custom_minimum_size = Vector2((ROW_WIDTH - 8.0) * 0.5, 38.0)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_on_reset)

	var back := UiKit.mc_button("Retour")
	back.custom_minimum_size = Vector2((ROW_WIDTH - 8.0) * 0.5, 38.0)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): back_requested.emit())

	# Les deux boutons sur une meme ligne. Empiles, ils prenaient 42 px de plus —
	# exactement ce que demande la ligne de taille d'interface, dans une carte
	# dimensionnee au pixel pres. Retaillir un reglage existant pour en
	# ajouter un nouveau n'etait pas une option : la carte garde sa hauteur pour
	# que le menu ne saute pas d'un panneau a l'autre, et c'est sa taille qui
	# commande celle de tout l'ecran.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.add_child(reset)
	actions.add_child(back)
	add_child(actions)


func _add_stepper(key: String, title: String) -> void:
	var row := UiKit.mc_stepper(title, "", ROW_WIDTH)
	var minus: Button = row.get_node("Moins")
	var plus: Button = row.get_node("Plus")
	minus.pressed.connect(func(): _on_step(key, -1))
	plus.pressed.connect(func(): _on_step(key, 1))
	add_child(row)
	_rows[key] = row


func _add_toggle(key: String, title: String) -> void:
	var row := UiKit.mc_toggle(title, "", ROW_WIDTH)
	var button: Button = row.get_node("Bouton")
	button.pressed.connect(func(): _on_toggle(key))
	add_child(row)
	_rows[key] = row


func _on_step(key: String, direction: int) -> void:
	# La sensibilite se regle au cran, mais on ne veut pas un ecriture disque par
	# cran : dix crans en moins de deux secondes, c'est dix JSON ecrits pour rien.
	var save := key != "sensitivity"
	var new_value: Variant = _next_value(key, direction, save)
	if new_value == null:
		return
	_write_row(key)
	changed.emit(key, new_value)


## Valeur d'un reglage apres un cran.
##
## Le rendu est le seul reglage CYCLIQUE : il n'a pas de borne haute, il
## repasse par le mode naturel. Le nombre de modes appartient a `PostFx`, pas aux
## reglages — les borner ici afficherait « Naturel » six fois de suite avant que
## le curseur ne bute, ce qui serait exactement l'inverse d'un cycle.
func _next_value(key: String, direction: int, save: bool) -> Variant:
	if key == "shader":
		var count := PostFx.count()
		if count <= 0:
			return null
		return Settings.set_value(key,
			posmod(int(Settings.value(key)) + direction, count), save)
	return Settings.step(key, direction, save)


func _on_toggle(key: String) -> void:
	var new_value: Variant = Settings.set_value(key, not bool(Settings.value(key)))
	_write_row(key)
	changed.emit(key, new_value)


func _on_reset() -> void:
	Settings.reset()
	refresh()
	# Un seul signal, avec la valeur par defaut de chaque reglage : l'appelant
	# n'a pas a redemander la liste, et l'affichage est deja a jour.
	for spec in ROWS:
		changed.emit(str(spec["key"]), Settings.value(str(spec["key"])))
	changed.emit("invert_y", Settings.value("invert_y"))


## Ecrit la valeur d'une ligne. Le format est le point ou chaque reglage decide
## de se montrer : un volume en pourcentage, une distance en blocs, un nom de
## rendu, une sensibilite en multiple de celle de base.
##
## Les deux familles de lignes ne portent pas les memes enfants — l'un un
## libelle de valeur, l'autre un bouton — et chacune n'a que le sien. La garde
## teste donc la PRESENCE de l'un des deux, jamais l'un en particulier : ne
## tester que « Valeur » faisait ignorer en silence toutes les lignes a bouton,
## dont l'interrupteur restait vide.
func _write_row(key: String) -> void:
	var row: Control = _rows.get(key)
	if row == null:
		return
	var current: Variant = Settings.value(key)
	var has_value := row.has_node("Valeur")
	if not has_value and not row.has_node("Bouton"):
		return
	if has_value:
		_write_value(row.get_node("Valeur") as Label, key, current)
	var button := row.get_node_or_null("Bouton") as Button
	if button != null:
		button.text = "Oui" if bool(current) else "Non"


func _write_value(value_label: Label, key: String, current: Variant) -> void:
	if key == "music" or key == "sfx":
		value_label.text = "%d %%" % int(round(float(current) * 100.0))
	elif key == "ui_scale":
		# L'ecran peut interdire un palier : le « + » cesse alors de bouger et
		# rien ne l'expliquerait. Le suffixe le dit sur la ligne meme, ce qui
		# evite une ligne d'aide de plus dans une carte deja pleine.
		var cap := "" if _scale_fits(current) else " max"
		value_label.text = "%d%%%s" % [int(round(float(current) * 100.0)), cap]
	elif key == "fov":
		value_label.text = "%d°" % int(round(float(current)))
	elif key == "sensitivity":
		# En multiple de la base : « x1,5 » se comprend sans connaitre le chiffre
		# sous-jacent, que personne ne retient de toute facon.
		value_label.text = "x%.1f" % (float(current) / float(Settings.DEFAULTS["sensitivity"]))
	elif key == "render_distance":
		value_label.text = "%d chunks" % int(current)
	elif key == "shader":
		value_label.text = _shader_name(int(current))


## L'echelle demande tient-elle sur l'ecran du joueur ?
##
## Renvoie toujours vrai sans fenetre : le moteur y rapporte un ecran vide, que
## `fit_ui_scale` lit comme « aucune contrainte ». Le test et la capture d'ecran
## doivent donc afficher un pourcentage nu, et non un avertissement permanent qui
## n'expliquerait rien au joueur.
func _scale_fits(current: Variant) -> bool:
	return is_equal_approx(
		UiKit.fit_ui_scale(float(current), UiKit.screen_size(get_window())),
		float(current))


## Nom du mode de rendu. Le mode est un cyle : le reglage est borne par le
## nombre de presets reels, pas par une borne codee dans les reglages.
func _shader_name(index: int) -> String:
	var count := PostFx.count()
	if count <= 0:
		return "Naturel"
	return str(PostFx.PRESETS[posmod(index, count)]["name"])
