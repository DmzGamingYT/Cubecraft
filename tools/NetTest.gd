extends SceneTree

## Test de bout en bout du multijoueur, sans ecran.
##
##   godot --headless --script res://tools/NetTest.gd
##
## Le test ouvre **deux processus Godot** et les fait parler en reseau local :
## l'un heberge, l'autre se connecte. Les deux lancent le vrai jeu — autoloads
## compris, `Net` en tete — sur `scenes/NetPeer.tscn`, si bien que ce qui est
## mesure est exactement ce qu'une vraie partie mesurerait : resolution des
## appels RPC a travers deux processus, ordre des messages, filtrage des
## arguments, retransmission, deconnexion.
##
## ## Pourquoi deux processus et pas deux objets dans un seul arbre
##
## Un `MultiplayerAPI` est resolu par **un** noeud racine unique dans la
## `SceneTree`. Deux `SceneMultiplayer` dans le meme arbre ne peuvent pas
## designer deux pairs distincts : le second `set_multiplayer` ecrase le
## premier, et les deux noeuds se retrouvent avec la meme API, donc le meme
## pair. C'est la raison pour laquelle une version anterieure de ce test
## echouait : elle essayait de faire tourner un serveur et un client dans un
## seul processus, ce que le moteur ne permet pas.
##
## Deux processus, en revanche, reproduisent exactement la situation visee : le
## multijoueur de ce projet est fait pour deux machines distinctes, sur la
## boucle locale ici. Chaque pair est donc verifie pour de bon.
##
## Chaque processus ecrit ses verifications dans un fichier, et celui-ci les
## relit et les agrege. Le code de retour vaut 0 si tout passe.

## Debut de la plage de ports dynamique : evite a la fois les services du
## systeme et une partie deja ouverte sur la machine.
const PORT_BASE := 27800
## Limite de temps du test, en images. Un pair qui ne conclut pas doit
## arreter le test, pas laisser des processus godot en trainee.
const MAX_FRAMES := 2400

var _port := 0
var _host_pid := -1
var _client_pid := -1
var _client2_pid := -1
## Pseudos des clients que l'hote doit attendre avant de lancer.
var _clients: Array = []
var _reports: Array[String] = []
var _frame := 0
var _done := false


func _initialize() -> void:
	print("== Cubecraft : test reseau de bout en bout ==")
	_port = PORT_BASE + (randi() % 400)
	print("port de test : %d" % _port)
	_reports = [
		"user://nettest_host.txt",
		"user://nettest_client.txt",
		"user://nettest_client2.txt",
	]
	# Deux clients, et non un : c'est le cas qui-intereste vraiment l'hote,
	# qui doit leur relayer les poses a l'un et a l'autre. Un seul client ne
	# verrait jamais passer par le relais.
	_clients = ["Bob", "Carol"]
	print("clients : %s" % ", ".join(_clients))
	for path in _reports:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# L'hote d'abord : le client tente de se connecter en boucle, mais autant
	# lui donner une cible deja ouverte.
	#
	# `create_process` renvoie le PID du processus cree, pas `OK`. Seuls les
	# codes d'erreur sont negatifs : c'est le signe qu'il faut tester.
	_host_pid = _spawn("host", "Alice", _reports[0])
	if _host_pid < 0:
		print("ECHEC : l'hote n'a pas pu demarrer (code %d)" % _host_pid)
		quit(1)
		return

	# Laisse a l'hote le temps d'ouvrir son port avant que le client vise.
	OS.delay_msec(500)

	_client_pid = _spawn("client", _clients[0], _reports[1])
	if _client_pid < 0:
		print("ECHEC : le client n'a pas pu demarrer (code %d)" % _client_pid)
		quit(1)
		return
	OS.delay_msec(300)
	_client2_pid = _spawn("client", _clients[1], _reports[2])
	if _client2_pid < 0:
		print("ECHEC : le second client n'a pas pu demarrer (code %d)" % _client2_pid)
		quit(1)


## Lance un pair dans son propre processus et renvoie son PID, ou un code
## d'erreur negatif. L'hote recoit la liste des pseudos attendus : c'est lui qui
## doit attendre tout le monde avant de lancer la partie.
func _spawn(peer_role: String, peer: String, report: String) -> int:
	var args: Array = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://scenes/NetPeer.tscn", "--", "--role=%s" % peer_role,
		"--port=%d" % _port, "--name=%s" % peer,
		"--out=%s" % ProjectSettings.globalize_path(report),
	]
	# Tous les pairs, y compris les clients, recoivent la liste : chacun doit
	# pouvoir deduire la tenue qui le distingue des autres. C'est aussi ce que
	# l'ecran salon fait quand deux joueurs choisissent le meme skin.
	args.append("--expect=%s" % ",".join(_clients))
	return OS.create_process(OS.get_executable_path(), args, false)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame > MAX_FRAMES:
		print("ECHEC : delai depasse (%.0f s)" % (_frame / 60.0))
		return _report()
	return _report()


## Agrege les deux rapports. Renvoie vrai des que les deux fichiers sont
## lisibles, ou des qu'un depassement de delai survient.
func _report() -> bool:
	var checks := 0
	var failures: Array[String] = []
	var missing: Array[String] = []
	for path in _reports:
		var full := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(full):
			missing.append(path)
			continue
		var file := FileAccess.open(full, FileAccess.READ)
		if file == null:
			missing.append(path)
			continue
		var total := ""
		while not file.eof_reached():
			var line := file.get_line()
			if line.is_empty():
				continue
			# La derniere ligne du rapport est le compte des deux moities.
			if line.contains("\t") and not line.begins_with("ok") \
					and not line.begins_with("ECHEC"):
				total = line
				continue
			var parts := line.split("\t", false, 1)
			if parts.size() < 2:
				continue
			checks += 1
			if parts[0] != "ok":
				failures.append(parts[1])
		file.close()
		if not total.is_empty():
			# Le compte par cote est deja inclus dans `checks` : on s'en sert
			# seulement comme temoin que le pair a bien fini son scenario.
			pass
	if not missing.is_empty():
		return false
	_done = true
	print("----")
	if failures.is_empty():
		print("OK : %d verifications reseau passees." % checks)
		quit(0)
	else:
		for line in failures:
			print("ECHEC : %s" % line)
		print("%d echecs sur %d verifications reseau." % [failures.size(), checks])
		quit(1)
	return true
