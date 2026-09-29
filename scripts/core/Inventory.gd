class_name Inventory
extends RefCounted

## Inventaire du joueur : 9 emplacements de barre rapide + 27 de rangement.
##
## Un emplacement vide vaut `{}` ; sinon `{"id": int, "count": int}`. Les
## emplacements 0 a HOTBAR_SIZE-1 sont directement selectionnables par les
## touches 1-9 et par la molette.

const HOTBAR_SIZE := 9
const SIZE := 36

var slots: Array = []
var selected := 0


func _init() -> void:
	reset()


func reset() -> void:
	slots.clear()
	for i in SIZE:
		slots.append({})


func held() -> Dictionary:
	return slots[selected]


func held_id() -> int:
	return held().get("id", -1)


func is_empty_at(index: int) -> bool:
	return slots[index].is_empty()


func count_of(item_id: int) -> int:
	var total := 0
	for slot in slots:
		if slot.get("id", -1) == item_id:
			total += int(slot["count"])
	return total


## Ajoute des objets et renvoie la quantite qui n'a PAS tenu.
## Remplit d'abord les piles existantes, puis les emplacements libres.
func add(item_id: int, count: int) -> int:
	if item_id < 0 or count <= 0:
		return 0
	var limit := Items.max_stack(item_id)

	# 1. Completer les piles deja commencees, de la barre vers le rangement.
	for pass_hotbar in 2:
		for i in SIZE:
			if count <= 0:
				return 0
			var index := i if pass_hotbar == 0 else i + HOTBAR_SIZE
			if index >= SIZE:
				continue
			var slot: Dictionary = slots[index]
			if slot.get("id", -1) != item_id:
				continue
			var room: int = limit - int(slot["count"])
			if room <= 0:
				continue
			var moved := mini(room, count)
			slot["count"] = int(slot["count"]) + moved
			count -= moved

	# 2. Occuper les emplacements vides, barre d'abord.
	for pass_hotbar in 2:
		for i in SIZE:
			if count <= 0:
				return 0
			var index := i if pass_hotbar == 0 else i + HOTBAR_SIZE
			if index >= SIZE or not slots[index].is_empty():
				continue
			var moved := mini(limit, count)
			slots[index] = {"id": item_id, "count": moved}
			count -= moved

	return count


## Retire `count` exemplaires de `item_id` de tout l'inventaire.
## Renvoie la quantite reellement retiree (enchantement, lapis, niveau).
func take_of(item_id: int, count: int) -> int:
	var taken := 0
	for i in SIZE:
		if taken >= count:
			break
		var slot: Dictionary = slots[i]
		if int(slot.get("id", -1)) != item_id:
			continue
		var moved := mini(int(slot["count"]), count - taken)
		slot["count"] = int(slot["count"]) - moved
		taken += moved
		if int(slot["count"]) <= 0:
			slots[i] = {}
	return taken


## Retire `count` exemplaires de l'objet selectionne. Renvoie la quantite retiree.
func take_from_selected(count: int) -> int:
	var slot: Dictionary = slots[selected]
	if slot.is_empty():
		return 0
	var taken := mini(count, int(slot["count"]))
	slot["count"] = int(slot["count"]) - taken
	if int(slot["count"]) <= 0:
		slots[selected] = {}
	return taken


func consume_selected(count: int) -> void:
	take_from_selected(count)


## Retire un objet d'un emplacement donne (utilise par l'interface).
func take_at(index: int, count: int) -> int:
	var slot: Dictionary = slots[index]
	if slot.is_empty():
		return 0
	var taken := mini(count, int(slot["count"]))
	slot["count"] = int(slot["count"]) - taken
	if int(slot["count"]) <= 0:
		slots[index] = {}
	return taken


## Retire une quantite de l'objet tenu (casse de bloc, fabrication).
func consume_held(item_id: int, count: int) -> bool:
	if count <= 0:
		return true
	if held_id() != item_id:
		return false
	take_from_selected(count)
	return true


func to_array() -> Array:
	var out: Array = []
	for slot in slots:
		if slot.is_empty():
			out.append([0, 0])
		else:
			# Troisieme case : les enchantements, pour qu'ils survivent au
			# rechargement. Un objet non enchante reste sur deux cases.
			out.append([int(slot["id"]), int(slot["count"]), slot.get("ench", {})])
	return out


func from_array(data: Array) -> void:
	reset()
	for i in mini(data.size(), SIZE):
		var pair: Array = data[i]
		if pair.size() >= 2 and int(pair[0]) > 0 and int(pair[1]) > 0:
			slots[i] = {"id": int(pair[0]), "count": int(pair[1])}
			if pair.size() >= 3 and pair[2] is Dictionary and not (pair[2] as Dictionary).is_empty():
				slots[i]["ench"] = (pair[2] as Dictionary).duplicate()


## Enchantements d'une pile (dictionnaire vide si aucun).
static func enchants_of(stack: Dictionary) -> Dictionary:
	return stack.get("ench", {}) if stack is Dictionary else {}
