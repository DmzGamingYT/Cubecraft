class_name DebugOverlay
extends Control

## Overlay de diagnostic (F3) : images par seconde, position, chunk, biome,
## bloc vise et etat du streaming. Indispensable pour reglier la portee de rendu
## sur une machine donnee.

var _label: Label
var _visible := false
var _frame_accum := 0.0
var _fps := 0.0
var _target_name := "—"
var _target_pos := Vector3i.ZERO
var _has_target := false


func _ready() -> void:
	UiKit.anchor(self, Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = UiKit.label("", 13, Color(0.85, 1.0, 0.85))
	_label.position = Vector2(10, 8)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


func toggle() -> void:
	_visible = not _visible
	visible = _visible


func set_target(block_id: int, pos: Vector3i) -> void:
	_has_target = block_id != Blocks.AIR
	_target_name = Blocks.name_of(block_id) if _has_target else "—"
	_target_pos = pos


func _process(delta: float) -> void:
	_frame_accum += delta
	if _frame_accum >= 0.25:
		_fps = Engine.get_frames_per_second()
		_frame_accum = 0.0
	if not _visible or Game.player == null or Game.world == null:
		return

	var player := Game.player
	var pos := player.global_position
	var chunk := Vox.chunk_of(Vector3i(floori(pos.x), 0, floori(pos.z)))
	var facing := player.get_yaw()
	var biome := Biomes.name_of(Game.world.biome_at(floori(pos.x), floori(pos.z)))

	var lines := [
		"Cubecraft  —  %.0f FPS" % _fps,
		"XYZ  %.1f / %.1f / %.1f" % [pos.x, pos.y, pos.z],
		"Chunk  %d, %d   Biome  %s" % [chunk.x, chunk.y, biome],
		"Chunks  %d   Portee  %d" % [Game.world.chunks.size(), Game.world.render_distance],
		"Heure  %s   Vie  %.0f/20   Faim  %.0f/20" % [Game.clock_text(),
			player.health, player.food],
		"Orientation  %.0f°   %s" % [fmod(rad_to_deg(-facing), 360.0),
			"Vol" if player.flying else "Marche"],
		"Cible  %s  (%d, %d, %d)" % [_target_name, _target_pos.x, _target_pos.y, _target_pos.z],
		"Dessins  %d   Objets  %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)],
	]
	_label.text = "\n".join(lines)
