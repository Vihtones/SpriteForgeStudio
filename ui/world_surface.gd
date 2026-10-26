extends Control
## Static map draw list. Actor animation does not rebuild map geometry.
var map: Dictionary = {}
var textures: Array = []
var cell: float = 24
var origin := Vector2.ZERO
var collisions: bool = true
const World = preload("res://core/world_data.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var ambient: Color = Color(str(map.get("ambient_color", "#ffffff"))) if not map.is_empty() else Color.WHITE
	draw_rect(Rect2(Vector2.ZERO, size), Color("101c24").lerp(ambient, 0.08))
	if map.is_empty(): return
	var bounds := Rect2i(0, 0, int(map.width), int(map.height))
	var visible := Rect2i(Vector2i((-origin / cell).floor()), Vector2i((size / cell).ceil()) + Vector2i(2, 2)).intersection(bounds)
	for y in range(visible.position.y, visible.end.y):
		for x in range(visible.position.x, visible.end.x):
			draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell), Color("1e3a39") if (x + y) % 2 == 0 else Color("213f3c"))
	for layer in World.layers(map):
		if not layer.visible or layer.opacity <= 0: continue
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var index := int(layer.cells[y * int(map.width) + x])
				if index >= 0 and index < textures.size(): draw_texture_rect(textures[index], Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell), false, Color(ambient.r, ambient.g, ambient.b, float(layer.opacity)))
	if collisions:
		for y in range(visible.position.y, visible.end.y):
			for x in range(visible.position.x, visible.end.x):
				var rect := Rect2(origin + Vector2(x, y) * cell, Vector2.ONE * cell)
				if cell >= 10: draw_rect(rect, Color(0, 0, 0, 0.2), false)
				if map.collision[y * int(map.width) + x]: draw_rect(rect.grow(-minf(3, cell / 6)), Color(1, 0.35, 0.35, 0.4))
	for light in map.lights:
		var center := origin + (Vector2(light[0], light[1]) + Vector2.ONE * 0.5) * cell
		var settings: Dictionary = map.light_settings.get("%d:%d" % [int(light[0]), int(light[1])], {"color": "#ffcf8b", "radius": 4, "energy": 1})
		var color := Color(settings.color)
		for ring in range(6, 0, -1):
			color.a = clampf(float(settings.energy) * 0.04, 0.02, 0.2)
			draw_circle(center, cell * float(settings.radius) * ring / 6, color)
	for door_index in map.get("doors", []).size():
		var door: Dictionary = map.doors[door_index]
		for endpoint in [door.a, door.b]:
			var rect := Rect2(origin + Vector2(endpoint[0], endpoint[1]) * cell, Vector2.ONE * cell).grow(-maxf(2.0, cell * 0.2))
			draw_rect(rect, Color("6be0ce"), false, maxf(1.0, cell * 0.07))
			draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), Color("f6ce83"), maxf(2.0, cell * 0.09))
			if cell >= 14: draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 13), str(door_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var active_room_id := str(map.rooms[int(map.active_room)].id) if map.get("rooms", []).size() > int(map.get("active_room", 0)) else ""
	for connection_index in map.get("connections", []).size():
		var connection: Dictionary = map.connections[connection_index]
		for endpoint in [connection.a, connection.b]:
			if endpoint.room != active_room_id: continue
			var p: Array = endpoint.point
			var rect := Rect2(origin + Vector2(p[0], p[1]) * cell, Vector2.ONE * cell).grow(-maxf(2.0, cell * 0.2))
			draw_rect(rect, Color("f6ce83"), false, maxf(1.0, cell * 0.08))
			draw_line(rect.position, rect.end, Color("f6ce83"), maxf(1.0, cell * 0.06))
			if cell >= 14: draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 13), "↔" + str(connection_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
