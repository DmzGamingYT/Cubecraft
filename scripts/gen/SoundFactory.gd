class_name SoundFactory
extends RefCounted

## Fabrique les bruitages du jeu par synthese, sans aucun fichier audio.
##
## Chaque son est du bruit blanc filtre par un passe-bas d'ordre 1, multiplie
## par une enveloppe percussive. La couleur du bruit (coupe-basse, vitesse de
## decay) suffit a distinguer un pas dans l'herbe d'un pas sur la pierre.

const SAMPLE_RATE := 22050


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## Un tir de bruit filtre : `cutoff` en Hz, `decay` en secondes.
static func burst(salt: int, duration: float, cutoff: float, decay: float,
		pitch: float = 1.0) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("cubecraft:sfx:%d" % salt))
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)

	# Passe-bas d'ordre 1 : plus la constante de temps est courte, plus le son
	# est clair ; la frequence de coupure pilote cette constante.
	var a: float = 1.0 - exp(-2.0 * PI * cutoff / SAMPLE_RATE)
	var low := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var envelope: float = exp(-t / maxf(decay, 0.001))
		# Leger flottement de hauteur pour que deux sons ne soient jamais
		# exactement identiques.
		phase += 2.0 * PI * pitch * (1.0 + 0.04 * sin(t * 37.0)) / SAMPLE_RATE
		var white := rng.randf_range(-1.0, 1.0)
		low += a * (white - low)
		var body := sin(phase) * 0.25
		samples[i] = (low + body) * envelope
	return samples


## Bip melodique court (ramassage, fabrication).
static func blip(salt: int, start_hz: float, end_hz: float, duration: float) -> PackedFloat32Array:
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	var freq := start_hz
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var progress := float(i) / float(maxi(count - 1, 1))
		freq = lerpf(start_hz, end_hz, progress)
		phase += 2.0 * PI * freq / SAMPLE_RATE
		var envelope: float = minf(1.0, progress * 6.0) * (1.0 - progress)
		samples[i] = sin(phase) * envelope * 0.55
	return samples


static func material_tones(material: String) -> Array:
## [cutoff Hz, decay s, pitch]
	match material:
		"stone":
			return [1400.0, 0.09, 1.0]
		"wood":
			return [900.0, 0.11, 0.85]
		"grain":
			return [2600.0, 0.07, 1.1]
		_:
			return [700.0, 0.13, 0.7]


# ------------------------------------------------------------------- musique

## La musique du menu, synthetisee comme le reste : quatre mesures lentes, un
## nappe de cordes, une basse et un arpege. La boucle fait 16 secondes a 60
## pulsations par minute — volontairement lente, et divisible par quatre pour
## que chaque mesure tombe exactement sur une seconde de sample.
const MUSIC_BARS := 4
const MUSIC_BEAT := 1.0
const MUSIC_BAR := MUSIC_BEAT * 4.0
const MUSIC_LENGTH := MUSIC_BARS * MUSIC_BAR

## Progression : do - la - fa - sol. Les quatre accords les plus stables en mode
## majeur, et les plus invariants, ce qui fait qu'un ecouteur ne s'en lasse pas.
const MUSIC_CHORDS := [
	[130.81, 164.81, 196.00],  # do
	[110.00, 130.81, 164.81],  # la
	[87.31, 110.00, 130.81],   # fa
	[98.00, 123.47, 146.83],   # sol
]

## Un fluxMusical construit note par note, puis echantillonne. On ecrit les
## notes dans un tampon plutot que de melanger les voix en direct : c'est plus
## simple a raisonner, et le cout est le meme pour seize secondes.
static func menu_music() -> PackedFloat32Array:
	var total := int(MUSIC_LENGTH * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(total)
	# Un bruit de fond tres faible, detune de l'aigu : sans lui la nappe est
	# relativement limpide, un son synthetique d'une pureté suspecte.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("cubecraft:music"))

	for bar in MUSIC_BARS:
		var chord: Array = MUSIC_CHORDS[bar]
		var bar_start := int(float(bar) * MUSIC_BAR * SAMPLE_RATE)
		# Nappe : les trois notes du ton, tenues sur toute la mesure avec une
		# attaque longue et une release courte pour ne pas deborder sur la
		# mesure suivante.
		for i in chord.size():
			_add_pad(samples, bar_start, MUSIC_BAR - 0.35,
				float(chord[i]) * 2.0, 0.10 - float(i) * 0.012)
		# Basse : la fundamentalle sur le premier temps, redonnee a mi-mesure.
		_add_pluck(samples, bar_start, 1.6, float(chord[0]) * 0.5, 0.22)
		_add_pluck(samples, bar_start + int(MUSIC_BEAT * 2.0 * SAMPLE_RATE),
			1.6, float(chord[0]) * 0.5, 0.16)
		# Arpege : huit notes par mesure, en remontant puis redescendant le
		# ton, avec une note d'attente sur le premier temps.
		var pattern := [0, 1, 2, 1, 0, 1, 2, 1]
		for step in pattern.size():
			var at := bar_start + int(float(step) * MUSIC_BEAT * 0.5 * SAMPLE_RATE)
			var degree: int = pattern[step]
			# La quinte de l'accord est jouee une octave plus haut pour
			# qu'au tours d'aigu le mouvement reste audible.
			var octave := 2.0 if degree == 2 else 1.0
			_add_pluck(samples, at, 0.9, float(chord[degree]) * octave,
				0.075 - 0.004 * float(step % 3))

	# Le fondu des extremites : une boucle audio qui commence et finit sur un
	# silence franc produit un claquement a chaque tour. On ride donc les
	# premieres et dernieres 40 millisecondes.
	_fade_edges(samples, int(0.04 * SAMPLE_RATE))
	# Normalisation : la somme de quatre voix peut depasser +/-1, et un echantillon
	# ecrase en saturation distord le timbre bien plus qu'un gain applique.
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	if peak > 0.0:
		var gain := 0.72 / peak
		for i in samples.size():
			samples[i] *= gain
	return samples


## Une nappe tenue : attaque et release en cosinus, deux harmoniques legerement
## detunees pour donner de l'epaisseur, et un tremblement lent de hauteur.
static func _add_pad(buffer: PackedFloat32Array, at: int, duration: float,
		freq: float, gain: float) -> void:
	var count := int(duration * SAMPLE_RATE)
	var release := int(0.6 * SAMPLE_RATE)
	for i in count:
		var index := at + i
		if index < 0 or index >= buffer.size():
			continue
		var t := float(i) / SAMPLE_RATE
		# Enveloppe : montee sur 25 % de la note, palier, puis retombée douce.
		var progress := float(i) / float(count)
		var env := progress / 0.25 if progress < 0.25 else 1.0
		if count - i < release:
			env *= float(count - i) / float(release)
		env = clampf(env, 0.0, 1.0)
		# sin² : une ataque et une chute sans derivative brutale, ce qui evite
		# le claquement d'un rectangulaire.
		env *= env
		# Deux sinus legirement detunes : l'ecart de 0,6 % bat contre la
		# hauteur exacte et creent le battement caracteristique d'un orchestre.
		var f1 := freq * (1.0 + 0.003 * sin(t * 0.9))
		var value := sin(TAU * f1 * t) * 0.6 + sin(TAU * f1 * 2.0 * t) * 0.18
		value += sin(TAU * f1 * 1.006 * t) * 0.4
		buffer[index] += value * env * gain


## Une note frappee : attaque quasi instantanee, decroissance exponentielle.
## Leger fondu de 5 millisecondes pour qu'elle ne clique pas sur le timbre.
static func _add_pluck(buffer: PackedFloat32Array, at: int, duration: float,
		freq: float, gain: float) -> void:
	var count := int(duration * SAMPLE_RATE)
	var attack := int(0.005 * SAMPLE_RATE)
	for i in count:
		var index := at + i
		if index < 0 or index >= buffer.size():
			continue
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t / maxf(duration * 0.32, 0.001))
		if i < attack:
			env *= float(i) / float(maxi(attack, 1))
		# Trois harmoniques : une fondamentale pure sonnerait comme un
		# testeur, la troisieme donne au bouton la couleur d'un instrument.
		var value := sin(TAU * freq * t) * 0.7
		value += sin(TAU * freq * 2.0 * t) * 0.16
		value += sin(TAU * freq * 3.0 * t) * 0.07
		buffer[index] += value * env * gain


## Fondu sur les extremites d'un tampon, pour une boucle sans clic.
static func _fade_edges(samples: PackedFloat32Array, count: int) -> void:
	for i in mini(count, samples.size() / 2):
		var gain := 0.5 - 0.5 * cos(PI * float(i) / float(count))
		samples[i] *= gain
		var end := samples.size() - 1 - i
		if end >= 0:
			samples[end] *= gain


## Un clic d'interface, plus sourd qu'un bip : un bouton Minecraft est un bruit
## mat, pas une note.
static func ui_click() -> PackedFloat32Array:
	return burst(21, 0.07, 1100.0, 0.020, 1.15)


## Un survol : encore plus bref et plus grave que le clic, pour qu'il ne gêne
## pas la lecture quand la souris bouge vite.
static func ui_hover() -> PackedFloat32Array:
	return burst(22, 0.045, 700.0, 0.016, 0.9)


## Un son de navigation, plus long et plus clair que le clic : on l'entend une
## seule fois quand un panneau s'ouvre, il peut donc occuper plus de place.
static func ui_open() -> PackedFloat32Array:
	return blip(23, 380.0, 760.0, 0.18)
