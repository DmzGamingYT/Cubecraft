class_name Checklist
extends RefCounted

## Moteur de verification partage entre le test automatique (`--uitest`) et le
## menu de debug en jeu.
##
## Ces verifications vivaient dans `Main._run_ui_test`, donc elles n'etaient
## atteignables qu'au demarrage, avec un argument de ligne de commande, et
## leur resultat partait dans la console : invisible pour un joueur qui joue.
## Les reconstruire ici permet de les lancer **depuis le jeu**, devant la
## partie en cours, et d'en lire le resultat a l'ecran.
##
## Le principe reste celui d'un test : une liste de verifications nommees, un
## compteur, et un rapport. Rien n'est coupe au premier echec — un menu qui
## s'arreterait au premier probleme ne servirait a rien pour le debug, qui veut
## voir tous les symptoms d'un coup.

## Une verification : un nom lisible et un resultat.
##
## `ok` est vrai, faux, ou `null` pour « pas encore lancee ». L'etat
## intermediaire compte : une verification longue ne doit pas avoir l'air
## d'echouer avant meme d'avoir commence.
var entries: Array[Dictionary] = []
## Resultat de la derniere execution : `{total, failed, seconds}`.
var summary: Dictionary = {}
var _running := false


## Enregistre une verification et renvoie son identifiant, qui sert ensuite a
## la mettre a jour depuis le corps du test.
func add(name: String) -> int:
	entries.append({"name": name, "ok": null, "detail": ""})
	return entries.size() - 1


## Met a jour le resultat d'une verification.
func set_result(index: int, ok: bool, detail := "") -> void:
	if index < 0 or index >= entries.size():
		return
	entries[index]["ok"] = ok
	entries[index]["detail"] = detail


## La verification passe-t-elle ? Une verification jamais lancee ne compte pas
## comme un echec : elle n'a pas encore eu l'occasion d'echouer.
func is_ok(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	return entries[index]["ok"] != false


func count() -> int:
	return entries.size()


func failed_count() -> int:
	var n := 0
	for entry in entries:
		if entry["ok"] == false:
			n += 1
	return n


func done_count() -> int:
	var n := 0
	for entry in entries:
		if entry["ok"] != null:
			n += 1
	return n


func is_running() -> bool:
	return _running


func failed_names() -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if entry["ok"] == false:
			out.append(str(entry["name"]))
	return out


func name_of(index: int) -> String:
	if index < 0 or index >= entries.size():
		return ""
	return str(entries[index]["name"])


func detail_of(index: int) -> String:
	if index < 0 or index >= entries.size():
		return ""
	return str(entries[index]["detail"])


## Ouvre une execution : tout repart a « pas encore lancee », pour qu'une
## seconde execution ne melange pas ses resultats a ceux de la premiere.
func begin() -> void:
	for entry in entries:
		entry["ok"] = null
		entry["detail"] = ""
	summary = {}
	_running = true


## Cloture : le rapport que le menu affiche et que le test imprime.
func end(seconds := 0.0) -> void:
	_running = false
	summary = {
		"total": entries.size(),
		"done": done_count(),
		"failed": failed_count(),
		"seconds": seconds,
	}


## Rapport en une ligne, lisible dans une console comme dans un label.
func report_line() -> String:
	if summary.is_empty():
		return "%d verifications en attente" % entries.size()
	var failed := int(summary.get("failed", 0))
	var total := int(summary.get("total", 0))
	if failed == 0:
		return "OK : %d verifications passees en %.1f s" % [
			total, float(summary.get("seconds", 0.0))]
	return "ECHEC : %d/%d verifications" % [failed, total]
