class_name Weather
extends Node3D

## Meteo : ciel clair, pluie ou neige, avec l'intensite qui monte et descend
## toute seule. Les gouttes sont un `GPUParticles3D` depetu du joueur ; le ciel
## s'assombrit, la brume monte et un bruit de pluie accompagne le tout.
##
## Le mode peut etre force (menu pause) : c'est ce que font les tests.

enum Mode { AUTO, CLEAR, RAIN, SNOW }

const MODES := {
	Mode.AUTO: "Automatique",
	Mode.CLEAR: "Dégagé",
	Mode.RAIN: "Pluie",
	Mode.SNOW: "Neige",
}

const MIN_TINT := 0.30      # noirissement maximal du ciel
const RAIN_PARTICLE := 1600
const SNOW_PARTICLE := 900

var mode: int = Mode.AUTO
var current: int = Mode.CLEAR
var strength := 0.0
var target_strength := 0.0

var _rain: GPUParticles3D
var _rain_process: ParticleProcessMaterial
var _drop: BoxMesh
var _next_change := 45.0
var _rng := RandomNumberGenerator.new()
var _env: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _rain_audio: AudioStreamPlayer3D = null
## Mise a l'ecran : une fois la sortie demandee, la boucle ne redemarre plus.
var _audio_stopped := false
var _clear_top := Color.WHITE
var _clear_horizon := Color.WHITE
var _overcast_top := Color.WHITE
var _overcast_horizon := Color.WHITE


func _ready() -> void:
	_rng.seed = 90210
	# Le `GPUParticles3D` n'est PAS cree ici : il n'apparait qu'a la premiere
	# precipitation, et disparait quand elle cesse. Un `GPUParticles3D` compile
	# son shader de simulation dans le serveur de rendu, et ce shader n'est
	# jamais rendu a l'arret du jeu : Godot signale alors « ParticlesShaderRD
	# never freed » et une allocation `MaterialStorage::Shader` orpheline.
	# Par temps clair il n'y a donc rien a faire liberer.
	_rain_audio = AudioStreamPlayer3D.new()
	_rain_audio.stream = _rain_loop()
	_rain_audio.volume_db = -60.0
	_rain_audio.unit_size = 40.0
	add_child(_rain_audio)


## Cree le noeud de particules, a la volee, quand il precipite pour de vrai.
func _make_particles() -> void:
	if _rain != null:
		return
	_rain = GPUParticles3D.new()
	_rain.name = "Precipitations"
	_rain.lifetime = 1.0
	_rain.local_coords = false
	# Forme, vitesse et gravite vivent dans le materiau de processus, pas
	# sur le noeud de particules lui-meme.
	_rain_process = ParticleProcessMaterial.new()
	_rain_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 14 blocs de rayon : de quoi remplir le champ de vision jusqu'a la
	# portee de rendu, sans noyer la scene sous les gouttes.
	_rain_process.emission_box_extents = Vector3(14, 1, 14)
	_rain_process.direction = Vector3.DOWN
	_rain_process.spread = 2.0
	_rain_process.gravity = Vector3(0, -18, 0)
	_rain.process_material = _rain_process
	# Godot 4.7 expose le maillage de la particule par `draw_pass_1` (et non
	# `mesh`) : c'est un Mesh, son materiau se regle dessus.
	_drop = _drop_mesh()
	_rain.draw_pass_1 = _drop
	add_child(_rain)
	_rain.emitting = false


## Detruit le noeud de particules. Appele pendant que le jeu tourne encore :
## c'est le seul moment ou le serveur de rendu rend reellement le shader.
func _drop_particles() -> void:
	if _rain == null:
		return
	_rain.emitting = false
	_rain.queue_free()
	_rain = null
	_rain_process = null
	_drop = null


func _exit_tree() -> void:
	# Le `AudioStreamPlayer3D` d'un noeud supprime peut laisser une piste
	# Playback orpheline dans le serveur audio : on l'arrete franchement, puis
	# on lache le flux, sinon Godot signale deux objets fuis a la sortie.
	if _rain_audio != null:
		_rain_audio.stop()
		_rain_audio.stream = null


## Petite boite : une goutte allongee, un cube pour un flocon. Le materiau
## est porte par le maillage lui-meme : `draw_pass_1` attend une Mesh, pas un
## materiau.
func _drop_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 1.0, 0.14)
	mesh.material = _drop_material(Color(0.70, 0.80, 0.95, 0.75))
	return mesh


func _drop_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Bruit de pluie synthetise : un souffle filtre en boucle.
func _rain_loop() -> AudioStream:
	var stream := SoundFactory._to_stream(
		SoundFactory.burst(31, 1.0, 5200.0, 0.02, 0.5))
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = 44100
	return stream


## Branche l'environnement du jeu pour assombrir le ciel avec la pluie.
## `sky_material` recoit les couleurs d'origine, refaites a chaque image.
func bind(environment: Environment, sky_material: ProceduralSkyMaterial = null) -> void:
	_env = environment
	_sky_material = sky_material
	if sky_material != null:
		_clear_top = sky_material.sky_top_color
		_clear_horizon = sky_material.sky_horizon_color
		_overcast_top = _clear_top.lerp(Color(0.38, 0.40, 0.44), 0.75)
		_overcast_horizon = _clear_horizon.lerp(Color(0.52, 0.55, 0.60), 0.75)


func _process(delta: float) -> void:
	if Game.player == null:
		return
	# La particule suit le joueur : sinon la pluie tombe dans le vide. Elle
	# n'est pourtant pas 16 blocs au-dessus de sa tete : a cette hauteur, et avec
	# une boite de 32 blocs de cote, toutes les gouttes sont dans le ciel et le
	# joueur n'en voyait qu'en levant les yeux. Le centre d'emission est a
	# hauteur de regard, et la boite assez large pour remplir le champ.
	if _rain != null:
		_rain.global_position = Game.player.global_position + Vector3(0, 5.0, 0)

	_next_change -= delta
	if mode == Mode.AUTO and _next_change <= 0.0:
		_next_change = randf_range(60.0, 150.0)
		# Aleatoire, mais pas de pluie pendant la nuit : la nuit on y voit
		# seulement les eclaircies de soleil.
		if Game.day_time > 0.3 and Game.day_time < 0.85 and _rng.randf() < 0.5:
			current = Mode.SNOW if _is_cold() else Mode.RAIN
		else:
			current = Mode.CLEAR
	target_strength = 0.0 if current == Mode.CLEAR else 1.0

	strength = move_toward(strength, target_strength, delta * 0.25)
	_apply()


## Coupe la boucle de pluie. A appeler avant de quitter : le serveur audio ne
## relache un playback arrete qu'au cycle de melangeage suivant, et Godot
## signale sinon deux objets fuis a la fermeture.
func stop_audio() -> void:
	_audio_stopped = true
	if _rain_audio != null and _rain_audio.playing:
		_rain_audio.stop()


func _is_cold() -> bool:
	return Game.player != null and Biomes.is_cold(
		Game.world.biome_at(floori(Game.player.global_position.x),
			floori(Game.player.global_position.z)))


## Effets visibles : particules, noir du ciel, brume, bruit.
func _apply() -> void:
	var snow := current == Mode.SNOW
	# Hysteresis : on cree le noeud des que ca precipite, mais on ne le detruit
	# que si la pluie s'arrete franchement. Sans cela, une intensite qui oscille
	# autour du seuil reconstruirait le noeud a chaque image.
	if strength > 0.05:
		_make_particles()
	elif strength <= 0.02:
		_drop_particles()

	if _rain != null:
		_rain.emitting = strength > 0.05
		_rain.amount = SNOW_PARTICLE if snow else RAIN_PARTICLE
		_rain_process.initial_velocity_min = 3.0 if snow else 16.0
		_rain_process.initial_velocity_max = 5.0 if snow else 20.0
		_rain_process.gravity = Vector3(0, -2.0, 0) if snow else Vector3(0, -18, 0)
		# Un flocon flotte : la neige derive au lieu de tomber droit.
		_rain_process.turbulence_enabled = snow
		if snow:
			_rain_process.turbulence_noise_strength = 1.4
			_rain_process.turbulence_noise_scale = 2.0
		# Un flocon est un cube blanc, une goutte une allonge bleu pale.
		if _drop != null:
			_drop.size = Vector3(0.18, 0.18, 0.18) if snow else Vector3(0.14, 1.0, 0.14)
			_drop.material = _drop_material(
				Color(1, 1, 1, 0.9) if snow else Color(0.70, 0.80, 0.95, 0.75))

	if _rain_audio != null:
		# Le flux ne tourne que s'il y a quelque chose a entendre : un
		# playback en boucle jamais arrete reste dans le melangeur du serveur
		# audio, et Godot le signale comme objet fui a la fermeture.
		if snow or strength <= 0.05:
			_rain_audio.volume_db = -60.0
			if _rain_audio.playing:
				_rain_audio.stop()
		else:
			_rain_audio.volume_db = lerpf(-40.0, -12.0, strength)
			if not _audio_stopped and not _rain_audio.playing:
				_rain_audio.play()

	# Le facteur est publie pour Main, qui recompose l'eclairage du jour a
	# chaque image : ici on ne touche qu'a ce qui n'est pas deja pose.
	Game.weather_dim = 1.0 - strength * Weather.MIN_TINT
	if _env != null:
		# Godot 4.7 n'a pas de `sky_modulate` : le ciel s'assombrit par
		# l'energie du fond et par les couleurs du materiau de ciel.
		_env.background_energy_multiplier = Game.weather_dim
		_env.fog_density = lerpf(0.0028, 0.0065, strength)
	if _sky_material != null:
		_sky_material.sky_top_color = _clear_top.lerp(_overcast_top, strength)
		_sky_material.sky_horizon_color = _clear_horizon.lerp(_overcast_horizon, strength)


## Force un mode (menu pause, tests). AUTO rend la main au hasard.
func set_mode(value: int) -> void:
	mode = value
	_next_change = randf_range(60.0, 150.0)
	match mode:
		Mode.CLEAR:
			current = Mode.CLEAR
		Mode.RAIN:
			current = Mode.RAIN
		Mode.SNOW:
			current = Mode.SNOW
		_:
			current = Mode.CLEAR


func mode_name() -> String:
	return str(MODES[mode])


func mode_index() -> int:
	return mode
