class_name PlayerBody
extends Node3D

## Corps du personnage, construit en boites texturisees : la meme silhouette
## sert a l'apercu du menu titre, au joueur regarde par les autres en
## multijoueur, et a la troisieme personne.
##
## Les proportions sont celles de Minecraft, exprimees en blocs : la tete fait
## 0,5 bloc de large, le buste 0,25 de profondeur, les membres 4 pixels de
## large. Un bloc du monde fait 1,0, donc le personnage mesure 1,8 bloc de haut,
## exactement la hauteur de la hitbox du joueur.
##
## Chaque membre est un `Node3D` pivotant place a son epaule ou a sa hanche, et
## la boite est un enfant decale vers le bas : pivoter le membre fait tourner
## l'articulation, pas le centre de la boite. C'est ce qui permet de balancer
## les bras en marchant sans que l'epaule se detache du buste.
##
## La boite n'est pas une `BoxMesh` : celle-ci n'accepte pas les UV. On construit
## l'`ArrayMesh` a la main pour plaquer le rectangle de la face correcte de la
## skin, et les triangles sont ecrits dans le sens trigonometrique vu de
## l'exterieur, comme le veut l'indexation du monde.

## Conversion d'un pixel de skin en bloc du monde. Le personnage fait 32 pixels
## de haut dans la skin (12 de jambe, 12 de buste, 8 de tete) et doit mesurer
## 1,8 bloc en jeu, exactement la hauteur de la hitbox du joueur : d'ou
## 1,8 / 32. Se tromper de facteur ici ne casse aucune erreur visible, mais
## decale la tete a cote du buste au lieu de la poser dessus.
const PX := 0.05625

const HEAD_SIZE := Vector3(8.0, 8.0, 8.0) * PX
const BODY_SIZE := Vector3(8.0, 12.0, 4.0) * PX
const LIMB_SIZE := Vector3(4.0, 12.0, 4.0) * PX

## Position de chaque membre, en blocs, mesuree depuis le sol. Les hanches sont
## a 0,675 (12 pixels), le buste de 0,675 a 1,35, et la tete culmine a 1,80.
const LEG_Y := 0.0
const BODY_Y := 1.0125
const HEAD_Y := 1.575
const ARM_Y := 1.35

## Decalage lateral d'un membre : le buste fait 0,225 de demi-largeur, le bras
## 0,1125 de demi-largeur, et ils doivent se toucher.
const ARM_X := 0.3375
const LEG_X := 0.1125

## Amplitude du balancement, en radians. Un bras qui descend a 45 degres sous
## l'horizontale &#8212; 1,57 &#8212; donnerait une marche de marionnette.
const SWING := 0.9
const SWING_FAST := 1.35

## Vitesse a laquelle les membres rejoignent la position de repos. Une valeur
## faible donne des membres qui traînent, comme dans Minecraft.
const SMOOTH := 12.0

var skin_index := 0

var head: Node3D
var body: Node3D
var arm_left: Node3D
var arm_right: Node3D
var leg_left: Node3D
var leg_right: Node3D

var _material: StandardMaterial3D
var _phase := 0.0
var _swing_amount := 0.0
var _lean := 0.0
var _idle_time := 0.0
var _arms_raised := false


func _ready() -> void:
	build()


## Construit la hierarchie et le materiau. Appele par `_ready`, et
## directement par les scripts de diagnostic qui instancient le personnage hors
## de l'arbre de la scene.
func build() -> void:
	if head != null:
		return
	_material = SkinFactory.skin_material(skin_index)
	_build()


## Change la tenue en place, en reutilisant la hierarchie : les membres gardes
## leur position d'animation, ce qui evite un clignotement au changement de skin.
func set_skin(index: int) -> void:
	skin_index = index
	_material = SkinFactory.skin_material(skin_index)
	for member in _members():
		var mesh: MeshInstance3D = member.get_node_or_null("Boite")
		if mesh != null:
			mesh.material_override = _material


## Une animation au repos, en boucle : le personnage avance et recule sur une
## ligne. C'est la pose de l'apercu du menu, ou l'on n'a pas de vitesse reelle.
## `speed` est en blocs par seconde, `0` pour un repos avec seulement la
## respiration.
func animate(delta: float, speed: float, grounded: bool = true) -> void:
	_idle_time += delta
	# La frequence du balancement suit la vitesse : au repos on ne marche pas,
	# on respire seulement.
	_swing_amount = move_toward(_swing_amount,
		clampf(speed / 4.6, 0.0, 1.6), delta * 5.0)
	_phase += delta * (4.0 + speed * 1.8) * _swing_amount

	# Respiration : le buste se soulève de quelques millimetres et le personnage
	# se balance tres legerement. C'est ce qui empeche un menu de paraitre fige.
	var breath := sin(_idle_time * 1.5)
	body.position.y = BODY_Y + breath * 0.012
	head.position.y = HEAD_Y + breath * 0.018
	# Inclinaison vers l'avant proportionnelle a la vitesse : le personnage
	# se penche quand il court et se redresse quand il s'arrete. La respiration
	# s'y ajoute, mais attenuee au repos pour qu'un perso immobile ne se balance
	# pas dans le vide.
	_lean = move_toward(_lean, clampf(speed * 0.02, 0.0, 0.14), delta * 4.0)
	rotation.x = _lean + breath * 0.02 * (0.25 + _swing_amount * 0.75)

	# Balancement des membres en opposition de phase : bras et jambes contraires,
	# c'est ce qui rend la marche lisible meme sur une silhouette de 4 pixels.
	var amount := _swing_amount
	if not grounded:
		amount *= 0.2
	var swing := sin(_phase) * SWING * minf(amount, 1.0)
	var swing_fast := sin(_phase) * SWING_FAST * minf(amount, 1.6)
	arm_right.rotation.x = swing
	arm_left.rotation.x = -swing
	leg_right.rotation.x = -swing_fast
	leg_left.rotation.x = swing_fast

	# En l'air, les bras se replient legerement vers l'arriere, comme si le
	# personnage cherchait son equilibre.
	if not grounded:
		arm_right.rotation.x = -0.35
		arm_left.rotation.x = -0.35

	# Un bras leve (minage, pose de bloc) : l'animation de marche doit ceder la
	# main, et les deux bras remontent ensemble comme dans Minecraft.
	if _arms_raised:
		arm_right.rotation.x = lerpf(arm_right.rotation.x, -2.3, delta * 10.0)
		arm_left.rotation.x = lerpf(arm_left.rotation.x, -2.3, delta * 10.0)


## Intensite du balancement, de 0 au repos a 1,6 en course. L'apercu du menu
## s'en sert pour faire respirer son ombre au meme rythme que le corps.
func swing_ratio() -> float:
	return _swing_amount


## Tete qui tourne vers un point : l'avatar regarde celui qui parle.
func look_at_point(target: Vector3, delta: float) -> void:
	var to := target - global_position
	if to.length() < 0.01:
		return
	var yaw := atan2(-to.x, -to.z) - rotation.y
	head.rotation.y = lerp_angle(head.rotation.y, wrapf(yaw, -PI, PI), delta * 6.0)
	head.rotation.x = lerpf(head.rotation.x,
		clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.5, 0.5), delta * 6.0)


## Levaille les bras, pour miner ou poser un bloc. L'animation de marche est
## alors mise de cote jusqu'au retour au repos.
func raise_arm(raised: bool) -> void:
	_arms_raised = raised


func _members() -> Array[Node3D]:
	return [head, body, arm_left, arm_right, leg_left, leg_right]


func _build() -> void:
	head = _pivot("Tete", Vector3(0, HEAD_Y, 0), "tete", HEAD_SIZE)
	body = _pivot("Corps", Vector3(0, BODY_Y, 0), "corps", BODY_SIZE)
	# Les bras et les jambes sont deux pivots distincts, places a l'epaule et a
	# la hanche, et la boite pend sous le pivot.
	arm_left = _pivot("BrasG", Vector3(ARM_X, ARM_Y, 0), "bras_gauche", LIMB_SIZE)
	arm_right = _pivot("BrasD", Vector3(-ARM_X, ARM_Y, 0), "bras_droite", LIMB_SIZE)
	leg_left = _pivot("JambeG", Vector3(LEG_X, LEG_Y + LIMB_SIZE.y, 0),
		"jambe_gauche", LIMB_SIZE)
	leg_right = _pivot("JambeD", Vector3(-LEG_X, LEG_Y + LIMB_SIZE.y, 0),
		"jambe_droite", LIMB_SIZE)
	# L'ordre compte pour la transparence de la tete dans un autre materiau,
	# et surtout pour que les enfants soient detruits dans le bon ordre.
	for member in [head, body, arm_left, arm_right, leg_left, leg_right]:
		add_child(member)


## Un membre articule : un `Node3D` place a l'articulation, avec la boite
## decalee vers le bas de la moitie de sa hauteur.
func _pivot(node_name: String, at: Vector3, member: String, size: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = at
	# Le buste et la tete sont centres sur leur pivot ; les membres pendent
	# dessous, l'epaule ou la hanche en haut.
	if member == "corps" or member == "tete":
		pivot.position = at
		var mesh := _box(node_name, member, size, Vector3.ZERO)
		pivot.add_child(mesh)
	else:
		var mesh := _box(node_name, member, size, Vector3(0, -size.y * 0.5, 0))
		pivot.add_child(mesh)
	return pivot


## La boite texturisee d'un membre, les six faces de la skin.
func _box(node_name: String, member: String, size: Vector3, offset: Vector3) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var	arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# Le tableau d'attributs est volontairement non type : `add_surface_from_arrays`
	# attend des Variant, et un `Array[Variant]` refuse de contenir un
	# PackedFloat32Array.
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array()

	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	for face in SkinFactory.FACES:
		var rect := SkinFactory.uv_normalized(member, face)
		if rect.size.x <= 0.0:
			continue
		var quad := _face_quad(face, size, offset)
		var base := vertices.size()
		# Quatre sommets, dans le sens trigonometrique vu de l'exterieur : c'est
		# la condition pour que Godot affiche la face, et le test de fumee la
		# verifie sur le maillage du monde.
		for corner in quad:
			vertices.push_back(corner)
		for _i in 4:
			normals.push_back(_face_normal(face))		# Les UV sont ajoutees sommet par sommet : `_face_uv` renvoie les quatre
		# coins, il faut les inserer dans le meme ordre que les positions.
		var face_uvs := _face_uv(rect, face)
		for i in 4:
			uvs.push_back(face_uvs[i])
		indices.push_back(base)
		indices.push_back(base + 1)
		indices.push_back(base + 2)
		indices.push_back(base)
		indices.push_back(base + 2)
		indices.push_back(base + 3)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var instance := MeshInstance3D.new()
	instance.name = "Boite"
	instance.mesh = mesh
	instance.material_override = _material
	return instance


## Les quatre sommets d'une face, dans le sens trigonometrique vu de
## l'exterieur. `haut` et `bas` sont ecrits a part : leur ordre depend de la
## normale, et c'est l'erreur classique qui rend une boite invisible.
static func _face_quad(face: String, size: Vector3, offset: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var o := offset
	match face:
		"avant":
			return PackedVector3Array([
				Vector3(-h.x, -h.y, h.z) + o, Vector3(h.x, -h.y, h.z) + o,
				Vector3(h.x, h.y, h.z) + o, Vector3(-h.x, h.y, h.z) + o])
		"arriere":
			return PackedVector3Array([
				Vector3(h.x, -h.y, -h.z) + o, Vector3(-h.x, -h.y, -h.z) + o,
				Vector3(-h.x, h.y, -h.z) + o, Vector3(h.x, h.y, -h.z) + o])
		"droite":
			return PackedVector3Array([
				Vector3(h.x, -h.y, h.z) + o, Vector3(h.x, -h.y, -h.z) + o,
				Vector3(h.x, h.y, -h.z) + o, Vector3(h.x, h.y, h.z) + o])
		"gauche":
			return PackedVector3Array([
				Vector3(-h.x, -h.y, -h.z) + o, Vector3(-h.x, -h.y, h.z) + o,
				Vector3(-h.x, h.y, h.z) + o, Vector3(-h.x, h.y, -h.z) + o])
		"haut":
			return PackedVector3Array([
				Vector3(-h.x, h.y, -h.z) + o, Vector3(h.x, h.y, -h.z) + o,
				Vector3(h.x, h.y, h.z) + o, Vector3(-h.x, h.y, h.z) + o])
		_:
			return PackedVector3Array([
				Vector3(-h.x, -h.y, h.z) + o, Vector3(h.x, -h.y, h.z) + o,
				Vector3(h.x, -h.y, -h.z) + o, Vector3(-h.x, -h.y, -h.z) + o])


static func _face_normal(face: String) -> Vector3:
	match face:
		"avant":
			return Vector3(0, 0, 1)
		"arriere":
			return Vector3(0, 0, -1)
		"droite":
			return Vector3(1, 0, 0)
		"gauche":
			return Vector3(-1, 0, 0)
		"haut":
			return Vector3(0, 1, 0)
		_:
			return Vector3(0, -1, 0)


## Les quatre UV d'une face, calculees a partir de la position du sommet plutot
## qu'ecrites coin par coin.
##
## Une seule regle regit toutes les faces, et c'est celle du format officiel :
## **regardee de l'exterieur, U doit progresser vers la droite du spectateur**.
## Ecrire les UV face par face a la main fait presque toujours introduire un
## miroir sur les faces de cote ou de dos — invisible tant que la peinture est
## symetrique, patent des qu'une vraie skin importee porte un logo dans le dos.
## U et V sont donc deduits de deux axes, un par direction.
static func _face_uv(rect: Rect2, face: String) -> PackedVector2Array:
	var u0 := rect.position.x
	var v0 := rect.position.y
	var u1 := u0 + rect.size.x
	var v1 := v0 + rect.size.y
	var axes := _face_axes(face)
	var u_axis: Vector3 = axes[0]
	var v_axis: Vector3 = axes[1]
	var out := PackedVector2Array()
	for corner in _face_corners(face, Vector3.ONE):
		# Le sommet le plus loin dans le sens de l'axe prend la valeur haute du
		# rectangle ; l'autre, la valeur basse.
		var u := u1 if corner.dot(u_axis) > 0.0 else u0
		var v := v1 if corner.dot(v_axis) > 0.0 else v0
		out.push_back(Vector2(u, v))
	return out


## Axes d'une face : la direction 3D dans laquelle U doit croitre, et celle dans
## laquelle V doit croitre. V pointe vers le bas de l'image, donc vers le bas du
## membre pour les faces verticales.
##
## Pour le dessus et le dessous, on garde U aligne sur X comme la face avant,
## et V aligne sur Z avec le bord arriere du membre en haut du rectangle : c'est
## la convention du format officiel, et elle fait que le dessus d'une tete se
## lit dans le meme sens que son front.
static func _face_axes(face: String) -> Array:
	match face:
		"avant":
			return [Vector3(1, 0, 0), Vector3(0, -1, 0)]
		"arriere":
			return [Vector3(-1, 0, 0), Vector3(0, -1, 0)]
		"droite":
			return [Vector3(0, 0, -1), Vector3(0, -1, 0)]
		"gauche":
			return [Vector3(0, 0, 1), Vector3(0, -1, 0)]
		"haut":
			return [Vector3(1, 0, 0), Vector3(0, 0, 1)]
		_:
			return [Vector3(1, 0, 0), Vector3(0, 0, 1)]


## Les quatre coins d'une face, a taille unitaire, dans le meme ordre que
## `_face_quad`. Ils ne servent qu'a l'orientation ; la vraie taille est
## reconstituee plus haut par la projection sur les axes.
static func _face_corners(face: String, h: Vector3) -> PackedVector3Array:
	return _face_quad(face, h * 2.0, Vector3.ZERO)
