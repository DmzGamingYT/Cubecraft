extends SceneTree

## Verification du cycle de vie des taches de fond du monde.
##
## Ce test existe parce que la boucle de vidage de `_exit_tree` a deja voulu etre
## « nettoyee » : elle ressemble a de la politesse — deux secondes d'attente que
## rien ne lit — et la retirer a fait pendre le moteur a la sortie du test de
## fumee. Le role exact du moteur n'est pas evident, mais le fait, lui, est
## mesure : sans la boucle, `SmokeTest` termine ses verifications puis ne rend
## jamais la main, bloque sur une variable de condition du `WorkerThreadPool`
## pendant la fermeture. Avec elle, il sort proprement.
##
## Le test fixe donc le comportement observable : un monde detruit avec des
## taches en vol les laisse **finir** avant de mourir, et ses files de travail
## reviennent vides. C'est ce qui empeche un worker de tourner sur un monde
## detruit.
##
## L'observation passe par une reference aux dictionnaires eux-memes, pris
## avant la destruction : un `Dictionary` est un objet reference, la copie
## locale survit au monde, et la boucle de vidage y ecrit toujours. Relire le
## monde apres coup ne donnerait rien — il est detruit, et ses champs avec lui.
##
## `_exit_tree` est appele **directement**, et non par `free`. Avec la boucle,
## les deux font la meme chose ; sans elle, `free` pend le moteur sur une
## variable de condition du `WorkerThreadPool` et le test ne rend jamais la
## main — une regression detectee par un blocage n'en est pas une, en CI. Le
## monde n'est libere qu'apres, une fois les files vides.

var _fails := 0
var _frames := 0

## Les deux files qu'une destruction doit vider.
const QUEUES := ["_queued_gen", "_queued_mesh"]


func _process(_delta: float) -> bool:
	_frames += 1
	# Une image de chauffe : les noeuds doivent etre dans l'arbre avant qu'on
	# leur demande de travailler.
	if _frames < 2:
		return false
	_queues_exist()
	_drains_on_destruction()
	if _fails == 0:
		print("\nOK : les taches de fond finissent avant que le monde meure.")
	else:
		print("\n%d VERIFICATION(S) EN ECHEC." % _fails)
	quit(1 if _fails > 0 else 0)
	return true


## Les files attendues existent bien, avec le bon type : une file d'etat de
## tache remplacee par autre chose viderait le monde de travers.
func _queues_exist() -> void:
	var world := World.new()
	for queue in QUEUES:
		var value: Variant = world.get(queue)
		if not (value is Dictionary):
			_fail("%s n'est pas un dictionnaire (%s)" % [queue, type_string(typeof(value))])
		else:
			_ok("%s est bien un dictionnaire de taches en vol" % queue)
	world.free()


## Un monde avec des taches en vol, detruit sans preparation : les files
## doivent revenir vides, ce qui prouve que les taches ont ete laissees
## finir plutot que coupees.
func _drains_on_destruction() -> void:
	var world := World.new()
	root.add_child(world)
	world.setup(4242, 3)
	world.render_distance = 3
	# Le centre reste le sentinelle tant que `update` n'a pas ete appele, et
	# `_schedule` balayerait alors un disque a deux milliards de blocs de
	# distance. On le place donc la ou un joueur le serait.
	world._center = Vector2i(0, 0)
	world._schedule_dirty = true
	world._schedule()

	var inflight: int = world._inflight()
	if inflight <= 0:
		_fail("aucune tache n'a ete soumise : la destruction ne prouve rien")
		world.free()
		return
	_ok("%d tache(s) en vol au moment de la destruction" % inflight)

	# References prises avant : ce sont les dictionnaires que la boucle de
	# vidage vient vider.
	var held: Dictionary = {}
	for queue in QUEUES:
		held[queue] = world.get(queue)
		_ok("%s contient %d entree(s) avant la destruction"
			% [queue, (held[queue] as Dictionary).size()])

	# La boucle de vidage, appelee telle que l'appelera `free`.
	world._exit_tree()

	for queue in QUEUES:
		var left: int = (held[queue] as Dictionary).size()
		if left == 0:
			_ok("%s vidée : les taches ont ete laissees finir" % queue)
		else:
			_fail("%s conserve %d entree(s) apres la destruction : le monde partira avant la fin des taches"
				% [queue, left])

	# Les files sont vides : la liberation ne peut plus pendre, et c'est le
	# monde lui qu'on rend.
	root.remove_child(world)
	world.free()


func _fail(what: String) -> void:
	_fails += 1
	print("  ECHEC : %s" % what)


func _ok(what: String) -> void:
	print("  ok     %s" % what)
