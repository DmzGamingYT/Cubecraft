class_name Vox
extends RefCounted

## Constantes globales du monde voxel.
##
## Indexation des donnees de chunk : idx = (z * 16 + x) * 96 + y.
## Le choix est dicte par le volume de padding du mailleur, qui partage ce
## layout : une colonne verticale (y variable a x,z fixes) doit etre CONTIGUE
## pour qu'on puisse la recopier d'un chunk a l'autre par memcpy, puis que le
## mailleur puisse picoter les voisins d'une face sans conversion.

const CHUNK_X := 16
const CHUNK_Z := 16
const CHUNK_Y := 96

const CHUNK_AREA := CHUNK_X * CHUNK_Z
const CHUNK_VOLUME := CHUNK_X * CHUNK_Y * CHUNK_Z

const SEA_LEVEL := 34
const BEDROCK_HEIGHT := 3

## Rendu d'un cube : 0.0 sombre ... 1.0 plein soleil (ordre : +X -X +Y -Y +Z -Z).
const FACE_SHADE := [0.74, 0.74, 1.0, 0.45, 0.62, 0.62]

## Densite des 4 niveaux d'occlusion ambiante : multiplicateur de lumiere.
const AO_LEVELS := [0.45, 0.62, 0.81, 1.0]


## Index d'un bloc dans un volume en colonnes (y rapide).
static func index(x: int, y: int, z: int) -> int:
	return (z * CHUNK_X + x) * CHUNK_Y + y


## Index du premier bloc d'une colonne verticale.
static func column_index(x: int, z: int) -> int:
	return (z * CHUNK_X + x) * CHUNK_Y


static func chunk_key(cx: int, cz: int) -> int:
	## Encode une coordonnee de chunk sur 32 bits (2 x 16 bits signes).
	return (cx & 0xFFFF) | ((cz & 0xFFFF) << 16)


static func key_to_cx(key: int) -> int:
	var cx := key & 0xFFFF
	return cx - 0x10000 if cx >= 0x8000 else cx


static func key_to_cz(key: int) -> int:
	var cz := (key >> 16) & 0xFFFF
	return cz - 0x10000 if cz >= 0x8000 else cz


static func in_chunk(x: int) -> bool:
	return x >= 0 and x < CHUNK_X


static func in_height(y: int) -> bool:
	return y >= 0 and y < CHUNK_Y


## Conversion monde (entiers) -> position du noeud Chunk correspondant.
static func chunk_of(block_pos: Vector3i) -> Vector2i:
	return Vector2i(floori(block_pos.x / float(CHUNK_X)), floori(block_pos.z / float(CHUNK_Z)))


## Coordonnee locale dans le chunk.
static func local_of(block_pos: Vector3i) -> Vector3i:
	return Vector3i(block_pos.x - floori(block_pos.x / float(CHUNK_X)) * CHUNK_X, block_pos.y,
			block_pos.z - floori(block_pos.z / float(CHUNK_Z)) * CHUNK_Z)
