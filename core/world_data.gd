extends RefCounted
## Bounded, deterministic tile editing independent of UI and SceneTree.
const MAX_SIDE = 128
const MAX_LAYERS = 8
const NEIGHBORS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Clockwise from north; bit i of a blob mask refers to NEIGHBORS_8[i].
const NEIGHBORS_8 = [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1), Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]
const TERRAIN_MODES = {"edge16": 16, "blob47": 47}
const TERRAIN_OUTSIDE = ["different", "same"]
## The 47 reduced 8-neighbor masks in ascending order; tiles[i] of a blob47 terrain draws BLOB47_MASKS[i].
const BLOB47_MASKS = [0, 1, 4, 5, 7, 16, 17, 20, 21, 23, 28, 29, 31, 64, 65, 68, 69, 71, 80, 81, 84, 85, 87, 92, 93, 95, 112, 113, 116, 117, 119, 124, 125, 127, 193, 197, 199, 209, 213, 215, 221, 223, 241, 245, 247, 253, 255]

static func filled(count: int, value: Variant) -> Array:
	var result: Array = []; result.resize(count); result.fill(value); return result

static func normalize(map: Dictionary) -> void:
	map.width = int(map.width); map.height = int(map.height)
	map.active_layer = int(map.get("active_layer", 0))
	if not map.has("base"): map.base = {"id": "ground", "name": "Solo", "visible": true, "locked": false, "opacity": 1.0, "terrain": filled(map.cells.size(), -1)}
	if not map.has("layers"): map.layers = []
	if not map.has("terrain_sets"): map.terrain_sets = []
	if not map.has("light_settings"): map.light_settings = {}
	if not map.has("ambient_color"): map.ambient_color = "#ffffff"
	if not map.has("doors"): map.doors = []
	if not map.has("connections"): map.connections = []
	if not map.has("camera_settings"): map.camera_settings = {"zoom": 2, "smoothing": 5.0, "pixel_snap": true}
	if not map.get("ambient_color") is String or not Color.html_is_valid(map.ambient_color): map.ambient_color = "#ffffff"
	map.active_layer = clampi(int(map.get("active_layer", 0)), 0, map.layers.size())
	for buffer in tile_buffers(map):
		for i in buffer.size(): buffer[i] = int(buffer[i])
	for layer in layers(map):
		for i in layer.terrain.size(): layer.terrain[i] = int(layer.terrain[i])
	for i in map.lights.size(): map.lights[i] = [int(map.lights[i][0]), int(map.lights[i][1])]
	_normalize_camera(map)
	for door in map.doors:
		door.a = [int(door.a[0]), int(door.a[1])]
		door.b = [int(door.b[0]), int(door.b[1])]
	ensure_rooms(map)
	map.active_room = int(map.get("active_room", 0))
	for room in map.rooms:
		if room is Dictionary and room.get("data") is Dictionary: _normalize_room_data(room.data)
	for connection in map.connections:
		for endpoint in [connection.a, connection.b]: endpoint.point = [int(endpoint.point[0]), int(endpoint.point[1])]

static func _normalize_room_data(map: Dictionary) -> void:
	map.width = int(map.width); map.height = int(map.height)
	map.active_layer = int(map.get("active_layer", 0))
	for buffer in tile_buffers(map):
		for i in buffer.size(): buffer[i] = int(buffer[i])
	for layer in layers(map):
		for i in layer.terrain.size(): layer.terrain[i] = int(layer.terrain[i])
	for i in map.lights.size(): map.lights[i] = [int(map.lights[i][0]), int(map.lights[i][1])]
	if not map.has("camera_settings"): map.camera_settings = {"zoom": 2, "smoothing": 5.0, "pixel_snap": true}
	if not map.get("ambient_color") is String or not Color.html_is_valid(map.ambient_color): map.ambient_color = "#ffffff"
	_normalize_camera(map)
	for door in map.get("doors", []):
		door.a = [int(door.a[0]), int(door.a[1])]
		door.b = [int(door.b[0]), int(door.b[1])]

static func _normalize_camera(map: Dictionary) -> void:
	var settings: Variant = map.get("camera_settings", {})
	if not settings is Dictionary: settings = {}
	map.camera_settings = {
		"zoom": clampi(int(settings.get("zoom", 2)), 1, 6),
		"smoothing": clampf(float(settings.get("smoothing", 5.0)), 0.0, 20.0),
		"pixel_snap": bool(settings.get("pixel_snap", true))
	}

static func _room_snapshot(map: Dictionary) -> Dictionary:
	var data := map.duplicate(true)
	data.erase("rooms")
	data.erase("active_room")
	data.erase("connections")
	return data

static func ensure_rooms(map: Dictionary) -> void:
	if map.get("rooms", null) is Array and not map.rooms.is_empty(): return
	map.rooms = [{"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": "Exterior", "data": _room_snapshot(map)}]
	map.active_room = 0
	if not map.has("connections"): map.connections = []

static func sync_active_room(map: Dictionary) -> void:
	ensure_rooms(map)
	var index := clampi(int(map.get("active_room", 0)), 0, map.rooms.size() - 1)
	map.rooms[index].data = _room_snapshot(map)
	map.active_room = index

static func prune_connections(map: Dictionary) -> void:
	if not map.get("connections", null) is Array: map.connections = []; return
	var used := {}
	map.connections = map.connections.filter(func(connection):
		for endpoint in [connection.a, connection.b]:
			var record: Dictionary = map.rooms.filter(func(r): return r.id == endpoint.room)[0] if map.rooms.any(func(r): return r.id == endpoint.room) else {}
			if record.is_empty(): return false
			var p := Vector2i(int(endpoint.point[0]), int(endpoint.point[1]))
			if not inside(record.data, p) or record.data.collision[p.y * int(record.data.width) + p.x] or door_at(record.data, p): return false
			var key: String = str(endpoint.room) + ":" + str(p.x) + ":" + str(p.y)
			if used.has(key): return false
			used[key] = true
		return true
	)

static func project_bytes(map: Dictionary) -> int:
	if not map.get("rooms", null) is Array or map.rooms.is_empty(): return _single_bytes(map)
	var total := 0
	for room in map.rooms:
		if room is Dictionary and room.get("data") is Dictionary: total += _single_bytes(room.data)
	return total

static func _single_bytes(map: Dictionary) -> int:
	var cells: int = int(map.get("width", 0)) * int(map.get("height", 0))
	var buffers: int = 1 + (layers(map).size() * 16)
	for terrain in map.get("terrain_sets", []):
		if terrain is Dictionary and terrain.get("tiles") is Array: buffers += terrain.tiles.size()
	return cells * buffers + str(map.get("tileset_png", "")).to_utf8_buffer().size()

static func create_room(map: Dictionary, name: String = "") -> bool:
	ensure_rooms(map)
	if map.rooms.size() >= 32 or project_bytes(map) + _single_bytes(map) > 67108864: return false
	sync_active_room(map)
	var room := _room_snapshot(map)
	room.cells.fill(-1)
	room.collision.fill(false)
	for layer in layers(room):
		layer.cells.fill(-1)
		layer.terrain.fill(-1)
	room.doors = []
	room.lights = []
	room.light_settings = {}
	var room_name := name.strip_edges().left(80)
	if room_name.is_empty(): room_name = "Sala " + str(map.rooms.size() + 1)
	map.rooms.append({"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": room_name, "data": room})
	return switch_room(map, map.rooms.size() - 1)

## Creates a deterministic village block using explicit user-owned tile roles.
## Structure and vegetation tiles are layout placeholders, not finished art.
static func generate_village(map: Dictionary, seed: int, tile_count: int, roles: Dictionary = {}) -> bool:
	if tile_count < 3 or int(map.width) < 16 or int(map.height) < 12: return false
	var ground_tile := int(roles.get("ground", 0))
	var path_tile := int(roles.get("path", 1))
	var plaza_tile := int(roles.get("plaza", 2))
	var structure_tile := int(roles.get("structure", 3 if tile_count > 3 else -1))
	var vegetation_tile := int(roles.get("vegetation", 4 if tile_count > 4 else -1))
	if ground_tile < 0 or ground_tile >= tile_count or path_tile < 0 or path_tile >= tile_count or plaza_tile < 0 or plaza_tile >= tile_count: return false
	if structure_tile < -1 or structure_tile >= tile_count or vegetation_tile < -1 or vegetation_tile >= tile_count: return false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var width := int(map.width)
	var height := int(map.height)
	map.cells.fill(ground_tile)
	map.collision.fill(false)
	for layer in map.layers:
		layer.cells.fill(-1)
		layer.terrain.fill(-1)
	map.base.terrain.fill(-1)
	map.doors.clear()
	map.lights.clear()
	map.light_settings.clear()
	# Two broad streets form a legible cross with a plaza at the center.
	var cx := width / 2
	var cy := height / 2
	for y in height:
		for x in width:
			var idx := y * width + x
			if abs(x - cx) <= 1 or abs(y - cy) <= 1: map.cells[idx] = path_tile
			if abs(x - cx) <= 2 and abs(y - cy) <= 2: map.cells[idx] = plaza_tile
	# Seeded pocket parks are placed beside the road while keeping a clear route.
	var park_count: int = clampi((width * height) / 180, 1, 8)
	for i in park_count:
		var px := rng.randi_range(3, width - 4)
		var py := rng.randi_range(3, height - 4)
		if abs(px - cx) <= 3 or abs(py - cy) <= 3: continue
		var park_tile := vegetation_tile if vegetation_tile >= 0 else plaza_tile
		for oy in range(-1, 2):
			for ox in range(-1, 2): map.cells[(py + oy) * width + px + ox] = park_tile
	# Building footprints get a selected placeholder tile and collision.
	var placed := 0
	var attempts: int = width * height / 5
	for attempt in attempts:
		if placed >= mini(12, max(1, width * height / 140)): break
		var bx := rng.randi_range(2, width - 5)
		var by := rng.randi_range(2, height - 5)
		var bw := rng.randi_range(2, 3)
		var bh := rng.randi_range(2, 3)
		var near_vertical: bool = abs(bx - cx) < abs(by - cy)
		if (near_vertical and abs(bx - cx) < 4) or (not near_vertical and abs(by - cy) < 4): continue
		var clear := true
		for oy in range(bh):
			for ox in range(bw):
				var idx := (by + oy) * width + bx + ox
				if map.cells[idx] != ground_tile or map.collision[idx]: clear = false
		if not clear: continue
		for oy in range(bh):
			for ox in range(bw):
				var idx := (by + oy) * width + bx + ox
				map.collision[idx] = true
				if structure_tile >= 0: map.cells[idx] = structure_tile
		var door_x: int = bx + bw / 2
		var door_y: int = by + bh / 2
		var entrance := Vector2i(door_x, by + bh - 1) if near_vertical else Vector2i(bx + bw - 1, door_y)
		map.collision[entrance.y * width + entrance.x] = false
		map.cells[entrance.y * width + entrance.x] = path_tile
		placed += 1
	sync_active_room(map)
	return true

static func switch_room(map: Dictionary, index: int) -> bool:
	ensure_rooms(map)
	if index < 0 or index >= map.rooms.size() or index == int(map.active_room): return false
	sync_active_room(map)
	var registry: Array = map.rooms
	var next_data: Dictionary = registry[index].data.duplicate(true)
	for key in map.keys():
		if key not in ["rooms", "active_room", "connections"]: map.erase(key)
	for key in next_data: map[key] = next_data[key]
	map.rooms = registry
	map.active_room = index
	return true

static func rename_room(map: Dictionary, index: int, name: String) -> bool:
	ensure_rooms(map)
	var title := name.strip_edges().left(80)
	if index < 0 or index >= map.rooms.size() or title.is_empty(): return false
	map.rooms[index].name = title
	return true

static func remove_room(map: Dictionary, index: int) -> bool:
	ensure_rooms(map)
	if map.rooms.size() <= 1 or index < 0 or index >= map.rooms.size(): return false
	var removed_id: String = map.rooms[index].id
	var active := int(map.active_room)
	if index == active:
		var replacement := index - 1 if index > 0 else 1
		map.rooms.remove_at(index)
		map.active_room = replacement - 1 if replacement > index else replacement
		var next_data: Dictionary = map.rooms[int(map.active_room)].data.duplicate(true)
		for key in map.keys():
			if key not in ["rooms", "active_room", "connections"]: map.erase(key)
		for key in next_data: map[key] = next_data[key]
	else:
		map.rooms.remove_at(index)
		if index < active: map.active_room -= 1
	map.connections = map.get("connections", []).filter(func(c): return c.a.room != removed_id and c.b.room != removed_id)
	sync_active_room(map)
	return true

static func metadata(map: Dictionary, index: int = -1) -> Dictionary:
	if index < 0: index = int(map.get("active_layer", 0))
	return map.base if index == 0 else map.layers[index - 1]

static func cells(map: Dictionary, index: int = -1) -> Array:
	if index < 0: index = int(map.get("active_layer", 0))
	return map.cells if index == 0 else map.layers[index - 1].cells

static func layers(map: Dictionary) -> Array:
	var base: Dictionary = map.base.duplicate(false); base.cells = map.cells
	return [base] + map.layers

static func tile_buffers(map: Dictionary) -> Array:
	var result: Array = [map.cells]
	for layer in map.get("layers", []): result.append(layer.cells)
	for terrain in map.get("terrain_sets", []): result.append(terrain.tiles)
	return result

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func valid(map: Dictionary, tile_count: int) -> bool:
	if not _valid_single(map, tile_count): return false
	if not map.has("rooms"): return true
	if not map.rooms is Array or map.rooms.is_empty() or map.rooms.size() > 32 or not integer(map.get("active_room", 0)): return false
	if int(map.active_room) < 0 or int(map.active_room) >= map.rooms.size(): return false
	var ids := {}
	for room in map.rooms:
		if not room is Dictionary or not room.get("id") is String or room.id.is_empty() or ids.has(room.id): return false
		if not room.get("name") is String or room.name.strip_edges().is_empty() or room.name.length() > 80: return false
		if not room.get("data") is Dictionary or not _valid_single(room.data, tile_count): return false
		ids[room.id] = true
	var connections: Variant = map.get("connections", [])
	if not connections is Array or connections.size() > 64: return false
	var connection_ids := {}
	var endpoints := {}
	for connection in connections:
		if not connection is Dictionary or not connection.get("id") is String or connection.id.is_empty() or connection_ids.has(connection.id): return false
		if not connection.get("name") is String or connection.name.strip_edges().is_empty() or connection.name.length() > 80: return false
		if not connection.get("a") is Dictionary or not connection.get("b") is Dictionary: return false
		if connection.a == connection.b: return false
		for endpoint in [connection.a, connection.b]:
			if not endpoint.get("room") is String or not ids.has(endpoint.room) or not endpoint.get("point") is Array or endpoint.point.size() != 2: return false
			if not integer(endpoint.point[0]) or not integer(endpoint.point[1]): return false
			var target_room: Dictionary = map.rooms.filter(func(r): return r.id == endpoint.room)[0]
			var room_data: Dictionary = target_room.data
			var p := Vector2i(int(endpoint.point[0]), int(endpoint.point[1]))
			if not inside(room_data, p) or room_data.collision[p.y * int(room_data.width) + p.x] or door_at(room_data, p): return false
			var key: String = str(endpoint.room) + ":" + str(p.x) + ":" + str(p.y)
			if endpoints.has(key): return false
			endpoints[key] = true
		connection_ids[connection.id] = true
	return true

static func _valid_single(map: Dictionary, tile_count: int) -> bool:
	if not integer(map.get("width")) or not integer(map.get("height")): return false
	if map.width < 1 or map.height < 1 or map.width > MAX_SIDE or map.height > MAX_SIDE: return false
	var count := int(map.width) * int(map.height)
	if not map.get("cells") is Array or map.cells.size() != count or not map.get("collision") is Array or map.collision.size() != count: return false
	var ambient: Variant = map.get("ambient_color", "#ffffff")
	if not ambient is String or not Color.html_is_valid(ambient): return false
	for value in map.collision: if not value is bool: return false
	if not map.get("lights") is Array or map.lights.size() > 32: return false
	var positions := {}
	for light in map.lights:
		if not light is Array or light.size() != 2 or not integer(light[0]) or not integer(light[1]): return false
		if light[0] < 0 or light[1] < 0 or light[0] >= map.width or light[1] >= map.height or positions.has(str(light)): return false
		positions[str(light)] = true
	var doors: Variant = map.get("doors", [])
	if not doors is Array or doors.size() > 32: return false
	var door_ids := {}
	var door_points := {}
	for door in doors:
		if not door is Dictionary or not door.get("id") is String or door.id.is_empty() or door_ids.has(door.id): return false
		if not door.get("name") is String or door.name.is_empty() or door.name.length() > 80: return false
		if not door.get("a") is Array or not door.get("b") is Array or door.a.size() != 2 or door.b.size() != 2: return false
		var endpoints: Array = [door.a, door.b]
		if door.a == door.b: return false
		for point in endpoints:
			if not integer(point[0]) or not integer(point[1]) or point[0] < 0 or point[1] < 0 or point[0] >= map.width or point[1] >= map.height: return false
			var point_key := "%d:%d" % [int(point[0]), int(point[1])]
			if door_points.has(point_key) or map.collision[int(point[1]) * int(map.width) + int(point[0])]: return false
			door_points[point_key] = true
		door_ids[door.id] = true
	var extra = map.get("layers", [])
	var terrains = map.get("terrain_sets", [])
	if not extra is Array or extra.size() >= MAX_LAYERS or not terrains is Array or terrains.size() > 16: return false
	var ids := {}
	var records: Array = extra.duplicate(false)
	if map.has("base"): records.push_front(map.base)
	for record in records:
		if not record is Dictionary or not record.get("id") is String or not record.get("name") is String or record.name.length() > 80 or ids.has(record.id): return false
		ids[record.id] = true
		if not record.get("visible") is bool or not record.get("locked") is bool: return false
		var opacity = record.get("opacity")
		if not (opacity is int or opacity is float) or not is_finite(float(opacity)) or opacity < 0 or opacity > 1: return false
		if not record.get("terrain") is Array or record.terrain.size() != count: return false
		for value in record.terrain: if not integer(value) or value < -1 or value >= terrains.size(): return false
	for record in extra:
		if not record.get("cells") is Array or record.cells.size() != count: return false
	for terrain in terrains:
		if not terrain is Dictionary or not terrain.get("name") is String or terrain.name.length() > 80 or not terrain.get("tiles") is Array: return false
		var mode = terrain.get("mode", "edge16")
		if not mode is String or not TERRAIN_MODES.has(mode) or terrain.tiles.size() != TERRAIN_MODES[mode]: return false
		var outside = terrain.get("outside", "different")
		if not outside is String or not TERRAIN_OUTSIDE.has(outside): return false
	for buffer in tile_buffers(map):
		for value in buffer: if not integer(value) or value < -1 or value >= tile_count: return false
	if map.has("active_layer") and (not integer(map.active_layer) or map.active_layer < 0 or map.active_layer > extra.size()): return false
	var settings = map.get("light_settings", {})
	if not settings is Dictionary or settings.size() > 32: return false
	for key in settings:
		if not key is String: return false
		var split: PackedStringArray = key.split(":")
		if split.size() != 2 or not split[0].is_valid_int() or not split[1].is_valid_int(): return false
		if not map.lights.has([int(split[0]), int(split[1])]) and not map.lights.any(func(p): return p[0] == int(split[0]) and p[1] == int(split[1])): return false
		var light = settings[key]
		if not light is Dictionary or not light.get("color") is String or not Color.html_is_valid(light.color) or not light.get("shadows") is bool: return false
		for field in ["radius", "energy"]:
			if not (light.get(field) is float or light.get(field) is int) or not is_finite(float(light[field])): return false
		if light.radius < 0.5 or light.radius > 16 or light.energy < 0 or light.energy > 8: return false
	var camera: Variant = map.get("camera_settings", {"zoom": 2, "smoothing": 5.0, "pixel_snap": true})
	if not camera is Dictionary or camera.size() != 3 or not camera.has_all(["zoom", "smoothing", "pixel_snap"]): return false
	if not integer(camera.zoom) or camera.zoom < 1 or camera.zoom > 6: return false
	if not (camera.smoothing is int or camera.smoothing is float) or not is_finite(float(camera.smoothing)) or camera.smoothing < 0 or camera.smoothing > 20: return false
	if not camera.pixel_snap is bool: return false
	return true

static func add_layer(map: Dictionary, name: String) -> bool:
	if map.layers.size() + 1 >= MAX_LAYERS: return false
	map.layers.append({"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": name.left(80), "visible": true, "locked": false, "opacity": 1.0, "cells": filled(map.cells.size(), -1), "terrain": filled(map.cells.size(), -1)})
	map.active_layer = map.layers.size()
	return true

static func remove_layer(map: Dictionary) -> bool:
	if map.active_layer == 0: return false
	map.layers.remove_at(map.active_layer - 1); map.active_layer = mini(map.active_layer, map.layers.size()); return true

static func resize(map: Dictionary, width: int, height: int) -> bool:
	if width < 1 or height < 1 or width > MAX_SIDE or height > MAX_SIDE: return false
	var buffers: Array = [map.cells, map.collision, map.base.terrain]
	for layer in map.layers: buffers.append(layer.cells); buffers.append(layer.terrain)
	for i in buffers.size():
		var previous: Array = buffers[i].duplicate()
		buffers[i].resize(width * height); buffers[i].fill(false if i == 1 else -1)
		for y in mini(height, int(map.height)):
			for x in mini(width, int(map.width)): buffers[i][y * width + x] = previous[y * int(map.width) + x]
	map.width = width; map.height = height
	map.doors = map.doors.filter(func(door):
		for point in [door.a, door.b]:
			if point[0] < 0 or point[1] < 0 or point[0] >= width or point[1] >= height: return false
			if map.collision[int(point[1]) * width + int(point[0])]: return false
		return true
	)
	map.lights = map.lights.filter(func(p): return p[0] < width and p[1] < height)
	for key in map.light_settings.keys():
		var p: PackedStringArray = key.split(":")
		if int(p[0]) >= width or int(p[1]) >= height: map.light_settings.erase(key)
	for layer in range(map.layers.size() + 1):
		for y in height:
			for x in width: update_terrain(map, layer, Vector2i(x, y))
	sync_active_room(map)
	prune_connections(map)
	return true

static func inside(map: Dictionary, p: Vector2i) -> bool:
	return Rect2i(0, 0, int(map.width), int(map.height)).has_point(p)

static func update_terrain(map: Dictionary, layer_index: int, p: Vector2i) -> void:
	if not inside(map, p): return
	var terrain: Array = metadata(map, layer_index).terrain
	var idx := p.y * int(map.width) + p.x
	var kind := int(terrain[idx])
	if kind < 0: return
	var definition: Dictionary = map.terrain_sets[kind]
	var outside_matches: bool = definition.get("outside", "different") == "same"
	var blob: bool = definition.get("mode", "edge16") == "blob47"
	var directions: Array = NEIGHBORS_8 if blob else NEIGHBORS
	var mask: int = 0
	for i in directions.size():
		var q: Vector2i = p + directions[i]
		var matches: bool = outside_matches
		if inside(map, q): matches = terrain[q.y * int(map.width) + q.x] == kind
		if matches: mask |= 1 << i
	cells(map, layer_index)[idx] = definition.tiles[BLOB47_MASKS.find(blob47_reduce(mask)) if blob else mask]

## Drops corner bits whose two adjacent sides are not both set, leaving one of the 47 BLOB47_MASKS.
static func blob47_reduce(mask: int) -> int:
	var result: int = mask & 0b01010101
	for corner in [1, 3, 5, 7]:
		var sides: int = (1 << (corner - 1)) | (1 << ((corner + 1) % 8))
		if (mask & (1 << corner)) != 0 and (mask & sides) == sides: result |= 1 << corner
	return result

static func paint(map: Dictionary, p: Vector2i, mode: String, value: int, erase: bool, light: Dictionary = {}) -> bool:
	if not inside(map, p): return false
	var layer := metadata(map)
	if mode in ["Tile", "Terreno"] and layer.locked: return false
	var index := p.y * int(map.width) + p.x
	match mode:
		"Tile", "Terreno":
			if mode == "Terreno" and not erase and (value < 0 or value >= map.terrain_sets.size()): return false
			layer.terrain[index] = value if mode == "Terreno" and not erase else -1
			cells(map)[index] = -1 if erase else value
			update_terrain(map, int(map.active_layer), p)
			for delta in NEIGHBORS_8: update_terrain(map, int(map.active_layer), p + delta)
		"Colisão":
			if not erase and (door_at(map, p) or connection_at(map, str(map.rooms[int(map.active_room)].id), p)): return false
			map.collision[index] = not erase
		"Luz":
			var coord := [p.x, p.y]
			var key := "%d:%d" % [p.x, p.y]
			if erase:
				map.lights = map.lights.filter(func(other): return other[0] != p.x or other[1] != p.y)
				map.light_settings.erase(key)
			else:
				if not map.lights.has(coord):
					if map.lights.size() >= 32: return false
					map.lights.append(coord)
				map.light_settings[key] = light.duplicate(true) if not light.is_empty() else {"color": "#ffcf8b", "energy": 1.0, "radius": 4.0, "shadows": false}
		_: return false
	return true

static func door_at(map: Dictionary, point: Vector2i) -> bool:
	for door in map.get("doors", []):
		if (int(door.a[0]) == point.x and int(door.a[1]) == point.y) or (int(door.b[0]) == point.x and int(door.b[1]) == point.y): return true
	return false

static func connection_at(map: Dictionary, room_id: String, point: Vector2i) -> bool:
	for connection in map.get("connections", []):
		for endpoint in [connection.a, connection.b]:
			if endpoint.room == room_id and int(endpoint.point[0]) == point.x and int(endpoint.point[1]) == point.y: return true
	return false

static func add_connection(map: Dictionary, room_a: String, a: Vector2i, room_b: String, b: Vector2i, name: String = "") -> bool:
	ensure_rooms(map)
	sync_active_room(map)
	if room_a == room_b or map.connections.size() >= 64: return false
	var record_a: Dictionary = map.rooms.filter(func(r): return r.id == room_a)[0] if map.rooms.any(func(r): return r.id == room_a) else {}
	var record_b: Dictionary = map.rooms.filter(func(r): return r.id == room_b)[0] if map.rooms.any(func(r): return r.id == room_b) else {}
	if record_a.is_empty() or record_b.is_empty() or not inside(record_a.data, a) or not inside(record_b.data, b): return false
	if record_a.data.collision[a.y * int(record_a.data.width) + a.x] or record_b.data.collision[b.y * int(record_b.data.width) + b.x]: return false
	if door_at(record_a.data, a) or door_at(record_b.data, b) or connection_at(map, room_a, a) or connection_at(map, room_b, b): return false
	var title := name.strip_edges().left(80)
	if title.is_empty(): title = "Conexão " + str(map.connections.size() + 1)
	map.connections.append({"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": title, "a": {"room": room_a, "point": [a.x, a.y]}, "b": {"room": room_b, "point": [b.x, b.y]}})
	return true

static func remove_connection(map: Dictionary, index: int) -> bool:
	if index < 0 or index >= map.get("connections", []).size(): return false
	map.connections.remove_at(index)
	return true

static func add_door(map: Dictionary, a: Vector2i, b: Vector2i, name: String = "") -> bool:
	if not inside(map, a) or not inside(map, b) or a == b or map.get("doors", []).size() >= 32: return false
	if door_at(map, a) or door_at(map, b) or map.collision[a.y * int(map.width) + a.x] or map.collision[b.y * int(map.width) + b.x]: return false
	var title := name.strip_edges().left(80)
	if title.is_empty(): title = "Porta " + str(map.doors.size() + 1)
	map.doors.append({"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": title, "a": [a.x, a.y], "b": [b.x, b.y]})
	return true

static func remove_door(map: Dictionary, index: int) -> bool:
	if index < 0 or index >= map.get("doors", []).size(): return false
	map.doors.remove_at(index)
	return true

static func flood(map: Dictionary, p: Vector2i, mode: String, value: int, erase: bool) -> bool:
	if not inside(map, p) or mode == "Luz": return false
	if mode in ["Tile", "Terreno"] and metadata(map).locked: return false
	var buffer: Array = map.collision if mode == "Colisão" else (metadata(map).terrain if mode == "Terreno" else cells(map))
	var original = buffer[p.y * int(map.width) + p.x]
	var stack: Array[Vector2i] = [p]
	var visited := {}
	var points: Array[Vector2i] = []
	while not stack.is_empty():
		var q := stack.pop_back() as Vector2i
		if not inside(map, q) or visited.has(q): continue
		visited[q] = true
		if buffer[q.y * int(map.width) + q.x] != original: continue
		points.append(q)
		for delta in NEIGHBORS: stack.append(q + delta)
	for q in points: paint(map, q, mode, value, erase)
	return not points.is_empty()
