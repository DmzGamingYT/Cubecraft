class_name Biomes
extends RefCounted

## Biomes du monde. Les teintes sont appliquees aux sommets via le materiau
## (vertex_color_use_as_albedo), ce qui recolore herbe et feuillage en un seul
## passage, sans multiplier les textures.

enum {
	PLAINS,
	FOREST,
	DESERT,
	SNOWY,
	MOUNTAIN,
	COUNT,
}

static var defs: Dictionary = {
	PLAINS: {
		"name": "Plaine", "tree_density": 0.05, "spruce": false,
		"grass": Color(0.58, 0.86, 0.40), "foliage": Color(0.36, 0.78, 0.30),
	},
	FOREST: {
		"name": "Foret", "tree_density": 0.34, "spruce": false,
		"grass": Color(0.44, 0.82, 0.34), "foliage": Color(0.26, 0.70, 0.24),
	},
	DESERT: {
		"name": "Desert", "tree_density": 0.0, "spruce": false,
		"grass": Color(0.78, 0.86, 0.44), "foliage": Color(0.55, 0.76, 0.36),
	},
	SNOWY: {
		"name": "Toundra", "tree_density": 0.16, "spruce": true,
		"grass": Color(0.58, 0.78, 0.70), "foliage": Color(0.32, 0.58, 0.42),
	},
	MOUNTAIN: {
		"name": "Montagne", "tree_density": 0.03, "spruce": true,
		"grass": Color(0.50, 0.80, 0.42), "foliage": Color(0.30, 0.66, 0.32),
	},
}


static func name_of(biome: int) -> String:
	return defs.get(biome, defs[PLAINS])["name"]


static func grass_tint(biome: int) -> Color:
	return defs.get(biome, defs[PLAINS])["grass"]


static func foliage_tint(biome: int) -> Color:
	return defs.get(biome, defs[PLAINS])["foliage"]


static func tree_density(biome: int) -> float:
	return defs.get(biome, defs[PLAINS])["tree_density"]


## Biome froid : la pluie y tombe en neige.
static func is_cold(biome: int) -> bool:
	return biome == SNOWY


static func is_spruce(biome: int) -> bool:
	return defs.get(biome, defs[PLAINS])["spruce"]
