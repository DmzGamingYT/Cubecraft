class_name Settings
extends RefCounted

## Reglages persistants du joueur : volumes, portee, champ de vision, sensibilite,
## post-traitement, echelle d'interface.
##
## Tout est statique, sans autoload : le menu des reglages, le joueur et le
## generateur de sons ont besoin des MEMES valeurs, et le test de fumee instancie
## des ecrans hors du jeu ou aucun autoload n'existe. Une classe statique est le
## seul endroit ou ces trois mondeurs se rejoignent sans dependre du_scene tree.
##
## Le fichier n'est lu qu'au premier acces puis garde en memoire : le menu des
## reglages s'ouvre des dizaines de fois par session, et relire le disque a chaque
## lecture serait du travail pour rien.
##
## Toute valeur est bornee a la lecture ET a l'ecriture. C'est la seule partie du
## code qui lit un fichier ecrit par quelqu'un d'autre : un JSON tronque, une
## version ancienne du jeu, ou une portee a 900 ne doivent pas pouvoir rendre le
## jeu injouable au demarrage.

const PATH := "user://cubecraft_settings.json"
const FORMAT_VERSION := 1

## Valeurs par defaut. C'est la seule source de verite : un reglage absent du
## fichier prend sa valeur ici, jamais une valeur codee dans le menu.
const DEFAULTS := {
	"music": 0.65,
	"sfx": 0.90,
	"ui_scale": 1.0,
	"render_distance": 5,
	"fov": 75.0,
	"sensitivity": 0.0022,
	"invert_y": false,
	"shader": 0,
}

## Bornes par reglage : [minimum, maximum]. Filet de securite, pas la verite du
## jeu : `shader` y est borne large, parce que le nombre REEL de modes de rendu
## appartient a `PostFx` et bouge quand on en ajoute un. C'est le menu qui
## boucle sur le vrai compte.
const LIMITS := {
	"music": [0.0, 1.0],
	"sfx": [0.0, 1.0],
	"ui_scale": [0.75, 2.0],
	"render_distance": [2, 14],
	"fov": [55.0, 100.0],
	"sensitivity": [0.0004, 0.0080],
	"shader": [0, 8],
}

## Pas d'un cran de reglage. Un volume de 1 a 100 crans est inmanoeuvrable au
## stick ; un champ de vision a 0,5 degre ne se sent pas. Le pas est donc choisi
## par reglage, et non deduit des bornes.
const STEPS := {
	"music": 0.05,
	"sfx": 0.05,
	"ui_scale": 0.25,
	"render_distance": 1.0,
	"fov": 1.0,
	"sensitivity": 0.0002,
	"shader": 1.0,
}

static var _cache: Dictionary = {}
static var _loaded := false


## Charge le fichier une seule fois. L'appel est idempotent : le menu peut le
## redemander sans relire le disque.
## Cette methode s'appelait `load`, comme la fonction globale de GDScript. Le
## parseur resolvait tous les appels vers la globale, qui exige un chemin :
## `Settings` ne compilait donc plus, et avec lui l'autoload `Sounds` — c'est-a-dire
## tout le son du jeu. Le nom est desormais explicite.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("Reglages illisibles : %s" % error_string(FileAccess.get_open_error()))
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("Reglages corrompus : repart des valeurs par defaut.")
		return
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("Reglages d'une version differente : repart des defauts.")
		return
	# Seules les cles connues sont reprises : un fichier charge de cles en trop
	# ne doit pas se retrouver dans le cache et ressortir a l'ecriture.
	for key in DEFAULTS:
		if data.has(key):
			_cache[key] = bounded(key, data[key])


## Ecrit le fichier. Renvoie false si l'ecriture echoue sans interrompre la
## partie : un disque plein doit seulement empecher de garder le reglage.
static func write() -> bool:
	var data: Dictionary = {"version": FORMAT_VERSION}
	for key in _cache:
		data[key] = _cache[key]
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Reglages non enregistres : %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


## Un reglage, borne. La cle est inconnue du jeu : on rend la defaut plutot que
## de planter, un menu qui evolue ne doit pas casser les enregistrements vieux.
static func value(key: String, fallback: Variant = null) -> Variant:
	ensure_loaded()
	if not _cache.has(key):
		return DEFAULTS.get(key, fallback)
	return _cache[key]


## Change un reglage et enregistre. La valeur est bornee avant d'etre stockee :
## le fichier ne contient donc jamais une valeur hors bornes, meme si le menu a
## un bug. `save` vaut false pour un reglage ajuste en boucle — la sensibilite
## par exemple — ou l'on ne veut pas ecrire le disque a chaque cran.
static func set_value(key: String, new_value: Variant, save: bool = true) -> Variant:
	ensure_loaded()
	if not DEFAULTS.has(key):
		return null
	# `Variant` explicite : `bounded` rend une valeur de type libre par nature
	# (un bool, un int ou un flottant selon le reglage), et le `:=` ferait de
	# l'avertissement « type infere sur un Variant » une erreur — le projet
	# traite les avertissements comme des erreurs.
	var limited: Variant = bounded(key, new_value)
	_cache[key] = limited
	if save:
		write()
	return limited


## Change un reglage d'un cran, vers le haut ou vers le bas. Le pas du reglage
## est applique ici plutot que dans le menu : « + » doit signifier la meme chose
## partout, et le menu n'a pas a connaitre l'echelle de la sensibilite.
##
## `save` a la meme raison que dans `set_value` : une reglure qu'on ajuste en
## boucle n'a pas besoin d'une ecriture disque par cran.
static func step(key: String, direction: int, save: bool = true) -> Variant:
	var current: Variant = value(key)
	if not (current is int or current is float):
		return set_value(key, not bool(current), save)
	var increment: float = float(STEPS.get(key, 1.0))
	var next := float(current) + float(direction) * increment
	# Le type suit celui du defaut : un reglage entier ne doit pas devenir
	# flottant sous pretexte qu'on l'a ajuste d'un pas. `bounded` borne ensuite
	# a la plage — un cran de trop s'arrete donc sur la limite, sans debordement.
	return set_value(key, int(round(next)) if DEFAULTS[key] is int else next, save)


## Ramene tous les reglages a leurs valeurs par defaut et les ecrit.
static func reset() -> void:
	_loaded = true
	_cache = DEFAULTS.duplicate(true)
	write()


static func has(key: String) -> bool:
	return DEFAULTS.has(key)


static func keys() -> Array:
	return DEFAULTS.keys()


## Bornage a la lecture comme a l'ecriture. Le type suit celui du defaut : un
## reglage entier refuse un flottant, un reglage booleen refuse 7.
##
## Une chaine n'est acceptee que si elle est reellement un nombre. `float("abc")`
## ne leve pas d'erreur en GDScript, il vaut 0 — sans cette verification, un
## fichier de reglages abime (`"fov": "beaucoup"`) ne tomberait pas sur la valeur
## par defaut mais sur le minimum de la plage, et le joueur decouvrirait son
## champ de vision change au lancement.
static func bounded(key: String, raw: Variant) -> Variant:
	var fallback: Variant = DEFAULTS.get(key)
	if not DEFAULTS.has(key):
		return raw
	if fallback is bool:
		return bool(raw)
	var numeric := raw is int or raw is float
	if raw is String:
		# `is_valid_float` refuse « 1,5 » (virgule) comme « abc », et accepte
		# les espaces : c'est exactement ce qu'on veut d'un fichier ecrit a la
		# main ou par un autre outil.
		numeric = (raw as String).strip_edges().is_valid_float()
	if not numeric:
		return fallback
	if fallback is int:
		return clampi(int(raw), int(LIMITS[key][0]), int(LIMITS[key][1]))
	if fallback is float:
		return clampf(float(raw), float(LIMITS[key][0]), float(LIMITS[key][1]))
	return raw


## Volume lineaire (0..1) vers decibels, l'unite que les lecteurs audio
## attendent. Zero est traite a part : `linear_to_db(0)` vaut -inf, qu'un volume
## de son n'aime pas — on coupe donc vraiment le son.
static func to_db(scale: float) -> float:
	if scale <= 0.001:
		return -60.0
	return linear_to_db(clampf(scale, 0.0, 1.0))
