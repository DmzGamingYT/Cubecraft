class_name Settings
extends RefCounted

## Reglages persistants du joueur : volumes, portee, champ de vision, sensibilite,
## post-traitement.
##
## Un seul fichier JSON, lu au premier acces puis garde en memoire : le menu des
## reglages s'ouvre des dizaines de fois par session, et relire le disque a chaque
## lecture serait du travail pour rien.
##
## Toute valeur est bornee a la lecture ET a l'ecriture. C'est la seule partie du
## code qui lit un fichier ecrit par quelqu'un d'autre : un JSON tronque, une
## version ancienne du jeu, ou une valeur a 900 pour la portee ne doivent pas
## pouvoir rendre le jeu injouable au demarrage.

const PATH := "user://cubecraft_settings.json"
const FORMAT_VERSION := 1

## Valeurs par defaut. C'est la seule source de verite : un reglage absent du
## fichier prend sa valeur ici, jamais une valeur codee dans le menu.
const DEFAULTS := {
	"music": 0.65,
	"sfx": 0.90,
	"render_distance": 5,
	"fov": 75.0,
	"sensitivity": 0.0022,
	"invert_y": false,
	"shader": 0,
}

## Bornes par reglage : [minimum, maximum]. Le pas d'ajustement est pose par le
## menu lui-meme, pas ici.
const LIMITS := {
	"music": [0.0, 1.0],
	"sfx": [0.0, 1.0],
	"render_distance": [2, 14],
	"fov": [55.0, 100.0],
	"sensitivity": [0.0004, 0.0080],
	"shader": [0, 8],
}

## Reglages affiches sous forme de pourcentage ou de texte, avec leur pas. Le
## menu boucle sur cette table : ajouter un reglage ici suffit a ce qu'il
## apparaisse, sans toucher au panneau.
const SCALARS := ["music", "sfx", "fov", "sensitivity"]

var _cache: Dictionary = {}
var _loaded := false


func _init() -> void:
	ensure_loaded()


## Charge le fichier une seule fois. L'appel est idempotent : le menu peut le
## redemander sans relire le disque.
##
## Cette methode s'appelait `load`, comme la fonction globale de GDScript.
## Le parseur resolvait tous les appels vers la globale, qui exige un chemin :
## `Settings` ne compilait donc plus, et avec lui l'autoload `Sounds` — c'est-a-dire
## tout le son du jeu. Le nom est desormais explicite, et l'ancien reste
## disponible pour qui le cherchait.
func ensure_loaded() -> void:
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
			_cache[key] = _bounded(key, data[key])


## Ecrit le fichier. Renvoie false si l'ecriture echoue, sans interrompre la
## partie : un disque plein ne doit pas empecher de jouer, seulement de ne pas
## garder le reglage.
func write() -> bool:
	var data := {"version": FORMAT_VERSION}
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
func value(key: String, fallback: Variant = null) -> Variant:
	ensure_loaded()
	if not _cache.has(key):
		return DEFAULTS.get(key, fallback)
	return _cache[key]


## Change un reglage et enregistre. La valeur est bornee avant d'etre stockee :
## le fichier ne contient donc jamais une valeur hors bornes, meme si le menu a
## un bug.
func set_value(key: String, new_value: Variant) -> Variant:
	ensure_loaded()
	if not DEFAULTS.has(key):
		return null
	# `Variant` explicite : `_bounded` rend une valeur de type libre par nature
	# (un bool, un int ou un flottant selon le reglage), et le `:=` ferait
	# de l'avertissement « type infere sur un Variant » une erreur — le projet
	# traite les avertissements comme des erreurs.
	var bounded: Variant = _bounded(key, new_value)
	_cache[key] = bounded
	write()
	return bounded


## Ramene tous les reglages a leurs valeurs par defaut et les ecrit.
func reset() -> void:
	_loaded = true
	_cache = DEFAULTS.duplicate(true)
	write()


func has(key: String) -> bool:
	ensure_loaded()
	return DEFAULTS.has(key)


func keys() -> Array:
	return DEFAULTS.keys()


## Bornage a la lecture comme a l'ecriture. Le type suit celui du defaut : un
## reglage entier refuse un flottant, un reglage booleen refuse 7.
func _bounded(key: String, raw: Variant) -> Variant:
	var fallback: Variant = DEFAULTS.get(key)
	if fallback is bool:
		return bool(raw)
	if fallback is int:
		if not (raw is int or raw is float or raw is String):
			return fallback
		return _clamp_int(key, int(raw))
	if fallback is float:
		if not (raw is int or raw is float or raw is String):
			return fallback
		return clampf(float(raw), float(LIMITS[key][0]), float(LIMITS[key][1]))
	return raw


func _clamp_int(key: String, raw: int) -> int:
	return clampi(raw, int(LIMITS[key][0]), int(LIMITS[key][1]))


## Volume lineaire (0..1) vers decibels, l'unite que les lecteurs audio
## attendent. Zero est traite a part : `linear_to_db(0)` vaut -inf, qu'un volume
## de son n'aime pas — on coupe donc vraiment le son.
static func to_db(scale: float) -> float:
	if scale <= 0.001:
		return -60.0
	return linear_to_db(clampf(scale, 0.0, 1.0))
