extends Node

## Autoload `Sounds`.
##
## Banque de bruitages fabriques au demarrage, et lecture spatialeement Mixing
## trois dimensions (un pas_ECOUTE_ du bon cote). Un petit nombre de
## polyphones evite de couper une marche quand on en enchaine une autre.

const VOICES := 8

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next := 0
var _rng := RandomNumberGenerator.new()

## Lecteur de musique du menu. Il est volontairement unique et separe des
## voix 3D : la musique ne doit jamais se melanger a un bruitage de pas, ni
## dependre de la position de la camera.
var _music: AudioStreamPlayer
var _music_stream: AudioStreamWAV
## Volume de la musique, en decibels sous le maximum. Assez bas pour que les
## bruitages du jeu restent toujours devant.
const MUSIC_DB := -9.0
## Decalage de volume pose par le reglage du joueur, en decibels. Il s'ajoute au
## volume de chaque son plutot que de le remplacer : le mixage interne du jeu
## (la musique sous les bruitages, la pluie sous les pas) reste donc valable a
## n'importe quel reglage, et le curseur du joueur ne fait que l'ensemble.
var _sfx_offset := 0.0
var _music_offset := 0.0
## Retard avant de lancer la musique apres l'affichage du menu : le fondu
## d'ouverture dure 0,55 s, demarrer la musique dessus couvrait l'entree.
const MUSIC_DELAY := 0.6

## Blocs regroupes par timbre : la matiere du son, pas son apparence.
const MATERIAL_OF := {
	Blocks.GRASS: "soft", Blocks.LEAVES: "soft", Blocks.SNOW: "soft", Blocks.TORCH: "soft",
	Blocks.STONE: "stone", Blocks.COBBLESTONE: "stone", Blocks.COAL_ORE: "stone",
	Blocks.IRON_ORE: "stone", Blocks.BEDROCK: "stone", Blocks.IRON_BLOCK: "stone",
	Blocks.CRAFTING_TABLE: "wood",
	Blocks.LOG: "wood", Blocks.PLANKS: "wood",
	Blocks.SAND: "grain", Blocks.GRAVEL: "grain", Blocks.DIRT: "grain",
	Blocks.WATER: "grain",
}


func _ready() -> void:
	_build_bank()
	for i in VOICES:
		var player := AudioStreamPlayer3D.new()
		player.unit_size = 6.0
		player.max_db = 0.0
		player.pitch_scale = 1.0
		add_child(player)
		_voices.append(player)
	_music = AudioStreamPlayer.new()
	_music.stream = _music_stream
	_music.volume_db = MUSIC_DB + _music_offset
	add_child(_music)


## Volume des bruitages et de l'interface, en lineaire 0..1. Pose a chaque
## changement de reglage ; n'affecte que les sons joues apres, ceux qui sont en
## cours gardent leur volume — les couper en plein milieu s'entendrait.
func set_sfx_scale(scale: float) -> void:
	_sfx_offset = Settings.to_db(scale)
	for voice in _voices:
		if voice.playing:
			voice.volume_db += _sfx_offset


## Volume de la musique, en lineaire 0..1. Applique immediatement : le joueur
## qui baisse la musique au menu doit l'entendre baisser sur la nappe en cours.
func set_music_scale(scale: float) -> void:
	_music_offset = Settings.to_db(scale)
	if _music != null:
		_music.volume_db = MUSIC_DB + _music_offset


## Lance la musique du menu. Sans effet si elle tourne deja : le bouton
## « Nouveau monde » ramene au menu plusieurs fois, et relancer la musique a
## chaque retour ferait repartir le flux de zero.
func start_music() -> void:
	if _music == null or not is_inside_tree() or _music.playing:
		return
	_music.play()


## Arrete la musique, avec un fondu court : couper une nappe de seize secondes
## en plein milieu s'entend comme une porte claquée.
func stop_music(fade: float = 0.4) -> void:
	if _music == null or not _music.playing:
		return
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -40.0, fade)
	tween.tween_callback(func():
		if _music != null:
			_music.stop()
			_music.volume_db = MUSIC_DB + _music_offset)


## Relance la musique avec son volume normal.
func resume_music() -> void:
	if _music == null:
		return
	_music.volume_db = MUSIC_DB + _music_offset
	start_music()


func _build_bank() -> void:
	var salt := 0
	for material in ["soft", "stone", "wood", "grain"]:
		var tones := SoundFactory.material_tones(material)
		var cutoff: float = tones[0]
		var decay: float = tones[1]
		var pitch: float = tones[2]
		salt += 1
		_bank["dig_" + material] = SoundFactory._to_stream(
			SoundFactory.burst(salt, decay * 1.6, cutoff, decay, pitch))
		_bank["break_" + material] = SoundFactory._to_stream(
			SoundFactory.burst(salt + 100, decay * 3.2, cutoff * 0.8, decay * 1.5, pitch))
		_bank["place_" + material] = SoundFactory._to_stream(
			SoundFactory.burst(salt + 200, decay * 1.2, cutoff * 1.2, decay * 0.6, pitch * 0.9))
		_bank["step_" + material] = SoundFactory._to_stream(
			SoundFactory.burst(salt + 300, decay * 0.9, cutoff * 0.7, decay * 0.45, pitch * 0.8))

	_bank["pickup"] = SoundFactory._to_stream(SoundFactory.blip(1, 520.0, 980.0, 0.09))
	_bank["craft"] = SoundFactory._to_stream(SoundFactory.blip(2, 420.0, 720.0, 0.16))
	_bank["splash"] = SoundFactory._to_stream(SoundFactory.burst(9, 0.35, 1800.0, 0.12, 1.2))
	# Aie bref et grave quand on est blesse.
	_bank["hurt"] = SoundFactory._to_stream(SoundFactory.burst(10, 0.22, 520.0, 0.18, 0.6))
	# Machonnement : deux bouchées descendantes.
	_bank["eat"] = SoundFactory._to_stream(SoundFactory.blip(11, 320.0, 140.0, 0.14))
	# Coup porte : impact mat et bref.
	_bank["hit"] = SoundFactory._to_stream(SoundFactory.burst(12, 0.16, 900.0, 0.30, 0.5))
	# Montée de niveau : arpege court qui monte.
	_bank["levelup"] = SoundFactory._to_stream(SoundFactory.blip(13, 440.0, 1320.0, 0.22))
	# Grognement de zombie : voix grave, pour le faire sentir la nuit.
	_bank["zombie"] = SoundFactory._to_stream(SoundFactory.blip(14, 150.0, 90.0, 0.55))

	# Sons d'interface du menu, plays a plat et non en 3D.
	_bank["ui_click"] = SoundFactory._to_stream(SoundFactory.ui_click())
	_bank["ui_hover"] = SoundFactory._to_stream(SoundFactory.ui_hover())
	_bank["ui_open"] = SoundFactory._to_stream(SoundFactory.ui_open())

	# La musique est un flux a part : il fait seize secondes, il tourne en
	# boucle, et il a son propre lecteur. Le mettre dans la banque le ferait
	# mixer avec les bruitages sur les mêmes voix, polyphones.
	_music_stream = SoundFactory._to_stream(SoundFactory.menu_music())
	_music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_stream.loop_begin = 0
	_music_stream.loop_end = SoundFactory.MUSIC_LENGTH * SoundFactory.SAMPLE_RATE - 1


static func material_of(block_id: int) -> String:
	return MATERIAL_OF.get(block_id, "soft")


## Joue un bruitage a une position du monde.
func play_at(name: String, world_pos: Vector3, volume_db: float = 0.0,
		pitch_jitter: float = 0.12) -> void:
	if not _bank.has(name) or not is_inside_tree():
		return
	var player := _voices[_next]
	_next = (_next + 1) % _voices.size()
	player.global_position = world_pos
	player.stream = _bank[name]
	player.volume_db = volume_db + _sfx_offset
	_rng.seed = int(hash("cubecraft:jitter:%d:%d" % [Time.get_ticks_msec(), _next]))
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Coupe toutes les voix en cours : appele avant de quitter, sinon une voix
## encore active laisse un playback orphelin dans le serveur audio.
func stop_all() -> void:
	for voice in _voices:
		if voice.playing:
			voice.stop()
	if _music != null and _music.playing:
		_music.stop()


## Joue au niveau du joueur (ramassage, fabrication, interface).
func play_ui(name: String, volume_db: float = -4.0) -> void:
	if not _bank.has(name) or not is_inside_tree():
		return
	var player := _voices[_next]
	_next = (_next + 1) % _voices.size()
	# L'autoload est un Node simple : on se cale sur la camera pour que le son
	# d'interface ne vienne pas de l'origine du monde.
	var listener := get_viewport().get_camera_3d()
	player.global_position = listener.global_position if listener != null else Vector3.ZERO
	player.stream = _bank[name]
	player.volume_db = volume_db + _sfx_offset
	player.pitch_scale = 1.0
	player.play()
