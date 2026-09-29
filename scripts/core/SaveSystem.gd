class_name SaveSystem
extends RefCounted

## Lecture/ecriture des sauvegardes du jeu, une par emplacement.
##
## Le fichier de chaque emplacement est un JSON lisible par un humain : le monde
## y est decrit sous forme de germe, de position du joueur, d'inventaire, puis
## des seuls chunks modifies, compresses en zstd puis encodes en base64. La terre
## procedurale n'occupe donc aucune place : 24 ko de blocs tres compressibles par
## chunk.
##
## Lister les emplacements ne doit pas les relire tous : un monde joue quelques
## heures pese plusieurs megaoctets de base64, et les parser pour n'en garder que
## le nom ferait saccader le menu a chaque ouverture. Un index separe garde donc
## l'en-tete de chaque emplacement ; il n'est qu'un cache, et un emplacement dont
## l'index est incomplet est lu depuis son fichier puis remis a jour.

const SAVE_PATH := "user://cubecraft_save.json"
const SLOT_DIR := "user://saves"
const INDEX_PATH := "user://saves/index.json"
const FORMAT_VERSION := 1

## Nombre d'emplacements proposes au joueur. Six : assez pour garder plusieurs
## mondes sans multiplier les pages d'une liste qui tient dans la carte.
const SLOT_COUNT := 6

## Champs d'en-tete recopies dans l'index. Tout le reste du fichier (chunks,
## inventaire) ne sert qu'a la reprise de partie.
const HEADER_KEYS := ["name", "seed", "time", "saved_at"]


## L'emplacement demande existe-t-il ?
static func exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Premier emplacement libre, ou le dernier si tout est plein. « Jouer » ecrivant
## dans le premier libre, deux parties rapides successives ne s'ecrasent pas.
## Le dernier n'est pas le premier : ecraser une partie choisie plutot qu'une
## autre vaut mieux que d'ecraser silencieusement l'emplacement 1.
static func first_free_slot() -> int:
	for slot in range(1, SLOT_COUNT + 1):
		if not exists(slot):
			return slot
	return SLOT_COUNT


## Emplacement enregistre le plus recemment, ou 0 s'il n'y en a aucun. C'est ce
## que reprennent `--load` et le signal historique `load_requested` : sans
## emplacements, « charger » ne pouvait vouloir dire que le fichier unique.
static func most_recent_slot() -> int:
	var best := 0
	var best_time := -1
	for entry in list_slots():
		if not bool(entry.get("exists", false)):
			continue
		var when := int(entry.get("saved_at", 0))
		if when > best_time:
			best_time = when
			best = int(entry.get("slot", 0))
	return best


## Y a-t-il une sauvegarde dans un emplacement quelconque ?
static func exists_any() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if exists(slot):
			return true
	return false


## Chemin d'un emplacement. Le dossier est cree a la volee : un `user://` neuf
## n'a pas de sous-dossier, et le premier enregistrement ne doit pas echouer
## pour une raison de chemin.
static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SLOT_DIR, slot]


static func write(data: Dictionary, slot: int = 1) -> bool:
	_ensure_dir()
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_write_index(slot, data)
	return true


static func read(slot: int = 1) -> Dictionary:
	if not exists(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		push_error("Lecture de sauvegarde impossible : %s" % error_string(FileAccess.get_open_error()))
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Sauvegarde corrompue : JSON illisible.")
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("Sauvegarde d'une version differente, ignoree.")
		return {}
	return data


static func erase(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	var index := _read_index()
	if index.erase(str(slot)):
		_write_index_all(index)


## En-tete de tous les emplacements, du 1 au SLOT_COUNT, dans l'ordre. Chaque
## entree porte toujours `slot` et `exists` : le menu dessine une ligne par
## emplacement, vide compris, pour que « creer un monde » ait sa place.
static func list_slots() -> Array[Dictionary]:
	var index := _read_index()
	var out: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(_entry(slot, index))
	return out


## Nom affiche d'un emplacement : celui choisi par le joueur, sinon un libelle
## construit a partir du JOUR de sauvegarde, comme un dossier range
## automatiquement.
##
## La date est coupee entre le libelle et la ligne de detail — le jour d'un cote,
## l'heure de l'autre. La premiere version répétait la date entiere sur les deux
## lignes : le texte debordait sur trois lignes et la ligne du monde prenait deux
## fois plus de place que les autres, dont il sortait de la carte.
static func slot_label(entry: Dictionary) -> String:
	var name := str(entry.get("name", ""))
	if not name.is_empty():
		return name
	if not bool(entry.get("exists", false)):
		return "Emplacement %d" % int(entry.get("slot", 1))
	return "Monde du %s" % _format_day(int(entry.get("saved_at", 0)))


## Ligne de resume sous le nom : la graine — qui est la seule chose qui identifie
## un monde sans le charger — puis l'heure de la derniere sauvegarde.
static func slot_detail(entry: Dictionary) -> String:
	if not bool(entry.get("exists", false)):
		return "Vide — cliquer pour creer un monde"
	var parts: Array[String] = ["Graine %d" % int(entry.get("seed", 0))]
	var hour := _format_hour(int(entry.get("saved_at", 0)))
	if not hour.is_empty():
		parts.append(hour)
	return "   •   ".join(parts)


## Jour de sauvegarde, en francais. Chaine vide sur une date absente ou aberrante
## plutot qu'un nombre brut : elle serait affichee telle quelle.
static func _format_day(unix_time: int) -> String:
	var stamp := _stamp(unix_time)
	if stamp.is_empty():
		return ""
	return "%02d/%02d/%04d" % [stamp.day, stamp.month, stamp.year]


static func _format_hour(unix_time: int) -> String:
	var stamp := _stamp(unix_time)
	if stamp.is_empty():
		return ""
	return "%02dh%02d" % [stamp.hour, stamp.minute]


static func _stamp(unix_time: int) -> Dictionary:
	if unix_time <= 0:
		return {}
	return Time.get_datetime_dict_from_unix_time(unix_time)


# -------------------------------------------------------------------- index

## En-tete d'un emplacement, depuis l'index si elle y est, sinon depuis le
## fichier — auquel cas l'index est rattrape au passage.
static func _entry(slot: int, index: Dictionary) -> Dictionary:
	var entry: Dictionary = {"slot": slot, "exists": exists(slot)}
	if not entry["exists"]:
		return entry
	var cached: Variant = index.get(str(slot))
	if cached is Dictionary and (cached as Dictionary).has("saved_at"):
		entry["name"] = str(cached.get("name", ""))
		entry["seed"] = int(cached.get("seed", 0))
		entry["time"] = float(cached.get("time", 0.0))
		entry["saved_at"] = int(cached.get("saved_at", 0))
		return entry
	var data := read(slot)
	if data.is_empty():
		return entry
	_write_index(slot, data)
	entry["name"] = str(data.get("name", ""))
	entry["seed"] = int(data.get("seed", 0))
	entry["time"] = float(data.get("time", 0.0))
	entry["saved_at"] = int(data.get("saved_at", 0))
	return entry


static func _read_index() -> Dictionary:
	if not FileAccess.file_exists(INDEX_PATH):
		return {}
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return parsed


## Ecrit l'en-tete d'un emplacement dans l'index, en y lisant et en reecrivant
## tout : le fichier fait quelques centaines d'octets au plus.
static func _write_index(slot: int, data: Dictionary) -> void:
	var index := _read_index()
	var header: Dictionary = {}
	for key in HEADER_KEYS:
		header[key] = data.get(key, "")
	header["seed"] = int(data.get("seed", 0))
	header["time"] = float(data.get("time", 0.0))
	header["saved_at"] = int(data.get("saved_at", 0))
	index[str(slot)] = header
	_write_index_all(index)


static func _write_index_all(index: Dictionary) -> void:
	_ensure_dir()
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		# L'index n'est qu'un cache : son echec n'a pas lieu d'interrompre une
		# sauvegarde reussie, et il se reconstruira a la lecture.
		push_warning("Index de sauvegarde non ecrit : %s"
			% error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(index, "\t"))
	file.close()


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SLOT_DIR):
		DirAccess.make_dir_recursive_absolute(SLOT_DIR)


# ------------------------------------------------------------ compatibilite

## La premiere version du jeu n'avait qu'un seul fichier, a la racine de `user://`.
## Il est repris comme emplacement 1 au premier lancement de la version actuelle,
## puis deplace : le joueur ne perd pas sa partie, et l'ancien chemin ne traine
## pas dans `user://` a cote des emplacements.
static func migrate_legacy() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	if exists(1):
		# L'emplacement 1 existe deja : le fichier ancien est une copie oubliee.
		# On ne l'efface pas — c'est peut-etre la seule copie d'une vraie partie.
		return
	_ensure_dir()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(slot_path(1))) != OK:
		push_warning("Ancienne sauvegarde laissee en place : copie manuelle necessaire.")


# ------------------------------------------------------------- codec chunks

## Compresse un chunk modifie en chaine base64.
static func encode_chunk(blocks: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(blocks.compress(FileAccess.COMPRESSION_ZSTD))


## inverse de `encode_chunk`. `max_size` est la taille attendue une fois
## decompressee : la signature de `decompress` l'exige en premier argument.
static func decode_chunk(text: String, max_size: int = Vox.CHUNK_VOLUME) -> PackedByteArray:
	var raw := Marshalls.base64_to_raw(text)
	if raw.is_empty():
		return raw
	return raw.decompress(max_size, FileAccess.COMPRESSION_ZSTD)
