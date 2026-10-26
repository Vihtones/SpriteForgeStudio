extends SceneTree
const Doc = preload("res://core/document.gd")
const World = preload("res://core/world_data.gd")
const Store = preload("res://core/storage.gd")
const Worker = preload("res://core/batch_worker.gd")
var folder: String = "res://test_results/world_" + str(Time.get_ticks_usec())
var checks: Array = []
var failed: int = 0

func expect(ok: bool, title: String) -> void:
	checks.append({"name": title, "passed": ok})
	if ok: print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var doc := Doc.new()
	var map: Dictionary = doc.map_data
	expect(World.valid(map, 32), "new map satisfies bounded layer contract")
	expect(map.camera_settings == {"zoom": 2, "smoothing": 5.0, "pixel_snap": true}, "new rooms receive bounded pixel camera defaults")
	expect(map.ambient_color == "#ffffff", "new rooms receive neutral ambient lighting")
	var invalid_camera: Dictionary = map.duplicate(true); invalid_camera.camera_settings.zoom = 0
	expect(not World.valid(invalid_camera, 32), "map contract rejects invalid pixel camera zoom")
	var invalid_ambient: Dictionary = map.duplicate(true); invalid_ambient.ambient_color = "not-a-color"
	expect(not World.valid(invalid_ambient, 32), "map contract rejects malformed ambient color")
	var village_a: Dictionary = map.duplicate(true)
	var village_b_doc := Doc.new()
	var village_b: Dictionary = village_b_doc.map_data
	expect(World.generate_village(village_a, 7351, 32) and World.generate_village(village_b, 7351, 32), "seeded village generator accepts compatible maps")
	expect(village_a.cells == village_b.cells and village_a.collision == village_b.collision, "village generation is deterministic for the same seed")
	var village_navigation: Dictionary = preload("res://core/navigation.gd").new().analyze(village_a)
	expect(World.valid(village_a, 32) and village_navigation.connected, "generated village stays valid and keeps walkable streets connected")
	var visible_structures := false
	for index in village_a.cells.size():
		if village_a.cells[index] == 3 and village_a.collision[index]: visible_structures = true
	expect(visible_structures, "generated building footprints use a visible structure tile as well as collision")
	var custom_roles := {"ground": 5, "path": 6, "plaza": 7, "structure": 8, "vegetation": 9}
	var role_map_a := Doc.new().map_data
	var role_map_b := Doc.new().map_data
	expect(World.generate_village(role_map_a, 7351, 16, custom_roles) and World.generate_village(role_map_b, 7351, 16, custom_roles), "layout accepts explicit roles mapped to a different tileset ordering")
	expect(role_map_a.cells == role_map_b.cells and role_map_a.collision == role_map_b.collision and role_map_a.cells.has(8) and role_map_a.cells.has(9), "custom role mapping remains deterministic and draws buildings and vegetation")
	var role_doc := Doc.new()
	role_doc.map_data = role_map_a.duplicate(true)
	var role_storage := Store.new()
	var role_save_path := folder.path_join("role-layout.sfs.json")
	var role_save_ok: bool = role_storage.save_document(role_doc, role_save_path) == OK
	var role_loaded = role_storage.load_document(role_save_path)
	expect(role_save_ok and role_loaded != null and role_loaded.map_data.cells == role_map_a.cells and role_loaded.map_data.collision == role_map_a.collision, "custom layout roles and collision survive SFS save/load")
	var role_export_path := folder.path_join("role-layout-export")
	var role_export_result: Error = role_storage.export_all(role_loaded, role_export_path) if role_loaded != null else ERR_INVALID_DATA
	var role_export_ok: bool = role_export_result == OK
	var role_export_metadata: Dictionary = Store.read_json(role_export_path.path_join("metadata.json")) if role_export_ok else {}
	var exported_map: Dictionary = role_export_metadata.get("map", {})
	var normalized_export_tiles: Array = exported_map.get("cells", []).map(func(value): return int(value))
	expect(role_export_ok and normalized_export_tiles == role_map_a.cells and exported_map.get("collision", []) == role_map_a.collision, "custom layout remains intact in the Godot export manifest")
	var invalid_roles_map := Doc.new().map_data
	var invalid_roles_before: Array = invalid_roles_map.cells.duplicate()
	expect(not World.generate_village(invalid_roles_map, 1, 16, {"ground": 16}) and invalid_roles_map.cells == invalid_roles_before, "invalid tile role is rejected without mutating the room")
	World.paint(map, Vector2i(2, 3), "Tile", 3, false)
	World.paint(map, Vector2i(2, 3), "Colisão", 0, false)
	World.paint(map, Vector2i(20, 10), "Luz", 0, false)
	World.add_layer(map, "Roof")
	World.paint(map, Vector2i(2, 3), "Tile", 7, false)
	expect(map.cells[74] == 3 and map.layers[0].cells[74] == 7, "base and overlay paint independently")
	doc.checkpoint("Map resize")
	World.resize(map, 8, 6)
	expect(map.cells.size() == 48 and map.cells[26] == 3 and map.layers[0].cells[26] == 7 and map.collision[26], "resize preserves coordinates across all buffers")
	expect(map.lights.is_empty() and map.light_settings.is_empty(), "crop removes out-of-bounds lights and properties")
	doc.undo(); map = doc.map_data
	expect(map.width == 24 and map.lights.size() == 1 and map.layers[0].cells[74] == 7, "undo restores resized layers and clipped light")
	doc.redo(); map = doc.map_data
	expect(map.width == 8 and map.height == 6, "redo restores map dimensions")
	World.resize(map, 12, 9)
	expect(map.cells[38] == 3 and map.cells[107] == -1 and not map.collision[107], "map expansion preserves contents and fills new cells")
	World.metadata(map).locked = true
	expect(not World.paint(map, Vector2i(0, 0), "Tile", 1, false) and not World.flood(map, Vector2i(0, 0), "Tile", 1, false), "locked layer refuses brush and fill")
	expect(World.paint(map, Vector2i(0, 0), "Colisão", 0, false), "global collision remains independent of tile layer locks")
	World.metadata(map).locked = false
	World.flood(map, Vector2i(0, 0), "Tile", 5, false)
	expect(World.cells(map)[0] == 5 and World.cells(map)[38] == 7, "bucket fills connected region without crossing existing tile")
	map.terrain_sets.append({"name": "Grass", "tiles": range(16)})
	World.paint(map, Vector2i(3, 3), "Terreno", 0, false)
	World.paint(map, Vector2i(4, 3), "Terreno", 0, false)
	expect(World.cells(map)[39] == 2 and World.cells(map)[40] == 8, "terrain applies east/west neighbor masks")
	World.paint(map, Vector2i(3, 2), "Terreno", 0, false)
	expect(World.cells(map)[39] == 3 and World.cells(map)[27] == 4, "terrain recomputes neighboring north/south masks")
	World.paint(map, Vector2i(4, 3), "Terreno", 0, true)
	expect(World.cells(map)[39] == 1 and World.cells(map)[40] == -1, "terrain erase updates surrounding variants")
	World.paint(map, Vector2i(3, 2), "Tile", 9, false)
	expect(World.metadata(map).terrain[27] == -1 and World.cells(map)[39] == 0, "manual tile clears terrain membership and adjacent mask")
	World.resize(map, 4, 4)
	expect(World.cells(map)[15] == 0 and World.valid(map, 32), "crop recalculates terrain edges and keeps valid contract")
	var export_map := Doc.new()
	World.resize(export_map.map_data, 8, 8)
	var export_tiles := Image.create(256, 48, false, Image.FORMAT_RGBA8)
	export_tiles.fill(Color("39784c")); export_map.map_data.tileset_png = Marshalls.raw_to_base64(export_tiles.save_png_to_buffer())
	export_map.map_data.terrain_sets.append({"name": "Lago", "mode": "blob47", "tiles": range(47)})
	for y in range(3, 6):
		for x in range(3, 6): World.paint(export_map.map_data, Vector2i(x, y), "Terreno", 0, false)
	var export_folder := folder.path_join("blob-export")
	DirAccess.make_dir_recursive_absolute(export_folder)
	expect(Store.new()._export_map_scene(export_map, export_folder) == OK, "blob47 terrain exports a map scene")
	var export_set: TileSet = ResourceLoader.load(export_folder.path_join("tileset.tres"), "TileSet", ResourceLoader.CACHE_MODE_IGNORE)
	var export_source := export_set.get_source(0) as TileSetAtlasSource
	var center_data := export_source.get_tile_data(Vector2i(14, 2), 0)
	var all_neighbors := [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]
	expect(export_set.get_terrain_sets_count() == 1 and export_set.get_terrain_set_mode(0) == TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES, "blob47 terrain exports a corner-and-side TileSet terrain set")
	var all_bits_set := true
	for bit in all_neighbors: all_bits_set = all_bits_set and center_data.get_terrain_peering_bit(bit) == 0
	expect(center_data.terrain_set == 0 and all_bits_set, "interior blob47 tile carries all eight neighbor bits in the TileSet")
	var empty_data := export_source.get_tile_data(Vector2i(0, 0), 0)
	expect(empty_data.terrain_set == 0 and empty_data.get_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE) == -1, "isolated blob47 tile carries no neighbor bits")
	var reduced := {}
	for mask in 256: reduced[World.blob47_reduce(mask)] = true
	var reduced_masks: Array = reduced.keys(); reduced_masks.sort()
	expect(reduced_masks == World.BLOB47_MASKS, "blob47 reduction maps all 256 neighbor masks onto the 47 canonical masks")
	expect(World.blob47_reduce(0b00000010) == 0 and World.blob47_reduce(0b00000111) == 7, "blob47 corners count only when both adjacent sides match")
	var blob_doc := Doc.new()
	var blob_map: Dictionary = blob_doc.map_data
	World.resize(blob_map, 8, 8)
	blob_map.terrain_sets.append({"name": "Lake", "mode": "blob47", "tiles": range(47)})
	var blob := func(mask: int) -> int: return World.BLOB47_MASKS.find(mask)
	World.paint(blob_map, Vector2i(3, 3), "Terreno", 0, false)
	expect(World.cells(blob_map)[27] == blob.call(0), "blob47 isolated cell uses the empty mask tile")
	World.paint(blob_map, Vector2i(4, 4), "Terreno", 0, false)
	expect(World.cells(blob_map)[27] == blob.call(0) and World.cells(blob_map)[36] == blob.call(0), "blob47 diagonal-only neighbor does not join cells")
	for y in range(2, 5):
		for x in range(2, 5): World.paint(blob_map, Vector2i(x, y), "Terreno", 0, false)
	expect(World.cells(blob_map)[27] == blob.call(255), "blob47 interior cell uses the full mask tile")
	expect(World.cells(blob_map)[18] == blob.call(0b00011100) and World.cells(blob_map)[19] == blob.call(0b01111100), "blob47 outer corner and edge include matching diagonals")
	World.paint(blob_map, Vector2i(3, 3), "Terreno", 0, true)
	expect(World.cells(blob_map)[19] == blob.call(0b01000100), "blob47 hole drops inner corners from the edge above it")
	expect(World.cells(blob_map)[18] == blob.call(0b00010100), "blob47 erase updates diagonal neighbors")
	expect(World.valid(blob_map, 47), "blob47 terrain keeps the map contract valid")
	blob_map.terrain_sets.append({"name": "Sea", "mode": "blob47", "outside": "same", "tiles": range(47)})
	World.paint(blob_map, Vector2i(0, 7), "Terreno", 1, false)
	expect(World.cells(blob_map)[56] == blob.call(0b01110000), "outside=same treats the map border as matching terrain")
	World.paint(blob_map, Vector2i(0, 7), "Terreno", 1, true)
	var blob_invalid: Dictionary = blob_map.duplicate(true); blob_invalid.terrain_sets[0].tiles = range(16)
	expect(not World.valid(blob_invalid, 47), "blob47 terrain requires 47 tiles")
	blob_invalid = blob_map.duplicate(true); blob_invalid.terrain_sets[0].mode = "edge16"
	expect(not World.valid(blob_invalid, 47), "edge16 terrain still requires 16 tiles")
	blob_invalid = blob_map.duplicate(true); blob_invalid.terrain_sets[0].mode = "wang"
	expect(not World.valid(blob_invalid, 47), "unknown terrain mode is rejected")
	blob_invalid = blob_map.duplicate(true); blob_invalid.terrain_sets[1].outside = "wrap"
	expect(not World.valid(blob_invalid, 47), "unknown terrain border rule is rejected")
	var guide := World.blob47_guide()
	expect(guide.get_size() == Vector2i(256, 48) and guide.get_pixel(7, 3) == Color8(192, 192, 192) and guide.get_pixel(231, 35) == Color8(32, 32, 32), "artist guide draws one 3x3 neighborhood per blob47 tile in reading order")
	guide.save_png(ProjectSettings.globalize_path(folder.path_join("blob47-guide.png")))
	var guide_large := guide.duplicate(); guide_large.resize(1024, 192, Image.INTERPOLATE_NEAREST); guide_large.save_png(ProjectSettings.globalize_path(folder.path_join("blob47-guide-4x.png")))
	var invalid: Dictionary = map.duplicate(true); invalid.width = 4.5
	expect(not World.valid(invalid, 32), "fractional dimensions are rejected")
	invalid = map.duplicate(true); invalid.cells[0] = 1.25
	expect(not World.valid(invalid, 32), "fractional tile IDs are rejected")
	invalid = map.duplicate(true); invalid.layers[0].id = invalid.base.id
	expect(not World.valid(invalid, 32), "duplicate map layer IDs are rejected")
	invalid = map.duplicate(true); invalid.lights = [[99, 0]]
	expect(not World.valid(invalid, 32), "out-of-bounds light is rejected")
	var door_map := Doc.new().map_data
	World.resize(door_map, 3, 1)
	door_map.collision[1] = true
	var door_navigation := preload("res://core/navigation.gd").new()
	expect(not door_navigation.analyze(door_map).connected and World.add_door(door_map, Vector2i(0, 0), Vector2i(2, 0), "Interior"), "paired door connection joins a disconnected interior navigation region")
	expect(door_navigation.analyze(door_map).connected and not World.paint(door_map, Vector2i(0, 0), "Colisão", 0, false), "door links update navigation connectivity and preserve a passable threshold")
	expect(not World.add_door(door_map, Vector2i(0, 0), Vector2i(1, 0)) and World.valid(door_map, 32), "door contract rejects reused and colliding endpoints")
	var cropped_door := Doc.new()
	World.add_door(cropped_door.map_data, Vector2i(2, 2), Vector2i(20, 10))
	World.resize(cropped_door.map_data, 8, 6)
	expect(cropped_door.map_data.doors.is_empty(), "map crop removes connections whose destination is outside bounds")
	while World.add_layer(map, "Extra"): pass
	expect(map.layers.size() == 7 and not World.add_layer(map, "Too much"), "layer limit admits eight including base")
	map.active_layer = 0
	expect(not World.remove_layer(map), "base layer cannot be removed")
	var remap := Doc.new()
	World.add_layer(remap.map_data, "Overlay")
	World.cells(remap.map_data)[0] = 15
	remap.map_data.terrain_sets = [{"name": "Pattern", "tiles": range(16)}]
	remap.frame = 1; remap.duplicate_frame()
	expect(World.cells(remap.map_data)[0] == 19 and remap.map_data.terrain_sets[0].tiles[15] == 19, "frame insertion remaps overlay and terrain tile references")
	remap.delete_frame()
	expect(World.cells(remap.map_data)[0] == 15 and remap.map_data.terrain_sets[0].tiles[15] == 15, "frame deletion reverses map tile remapping")
	var store := Store.new()
	var legacy := store.encode(Doc.new())
	legacy.schema = 2
	for key in ["base", "layers", "active_layer", "terrain_sets", "light_settings", "camera_settings"]: legacy.map.erase(key)
	store.atomic_json(folder.path_join("legacy.sfs.json"), legacy)
	var loaded = store.load_document(folder.path_join("legacy.sfs.json"))
	expect(loaded != null and loaded.map_data.base.name == "Solo" and World.valid(loaded.map_data, 32), "legacy schema-2 map upgrades without losing base cells")
	var scene_doc := Doc.new()
	World.resize(scene_doc.map_data, 8, 6)
	scene_doc.map_data.ambient_color = "#59617a"
	var tiles := Image.create(256, 16, false, Image.FORMAT_RGBA8)
	tiles.fill(Color("39784c")); scene_doc.map_data.tileset_png = Marshalls.raw_to_base64(tiles.save_png_to_buffer())
	scene_doc.map_data.cells.fill(0)
	World.add_layer(scene_doc.map_data, "Decor")
	World.paint(scene_doc.map_data, Vector2i(3, 3), "Tile", 1, false)
	World.metadata(scene_doc.map_data).opacity = 0.5
	World.metadata(scene_doc.map_data).visible = false
	World.paint(scene_doc.map_data, Vector2i(4, 2), "Colisão", 0, false)
	World.paint(scene_doc.map_data, Vector2i(2, 2), "Luz", 0, false, {"color": "#7799ff", "energy": 1.5, "radius": 3.0, "shadows": true})
	expect(World.add_door(scene_doc.map_data, Vector2i(1, 1), Vector2i(6, 4), "Praça ↔ Casa"), "paired door can connect village exterior and interior points")
	expect(World.create_room(scene_doc.map_data, "Casa"), "world project creates an independent interior room")
	World.paint(scene_doc.map_data, Vector2i(2, 2), "Tile", 4, false)
	World.paint(scene_doc.map_data, Vector2i(0, 0), "Colisão", 0, false)
	expect(scene_doc.map_data.cells[18] == -1 and scene_doc.map_data.rooms.size() == 2, "new room starts with independent empty cells")
	expect(World.switch_room(scene_doc.map_data, 0) and scene_doc.map_data.doors.size() == 1 and scene_doc.map_data.cells[18] == 0, "switching rooms restores exterior tiles and door data")
	var switched_back := World.switch_room(scene_doc.map_data, 1)
	expect(switched_back and World.cells(scene_doc.map_data)[18] == 4 and scene_doc.map_data.collision[0], "switching back restores the edited interior")
	World.rename_room(scene_doc.map_data, 1, "Casa da Praça")
	scene_doc.map_data.ambient_color = "#292f45"
	World.switch_room(scene_doc.map_data, 0)
	var exterior_id: String = scene_doc.map_data.rooms[0].id
	var interior_id_for_link: String = scene_doc.map_data.rooms[1].id
	expect(World.add_connection(scene_doc.map_data, exterior_id, Vector2i(2, 1), interior_id_for_link, Vector2i(3, 2), "Entrada da casa"), "named portal links two distinct rooms")
	expect(World.connection_at(scene_doc.map_data, exterior_id, Vector2i(2, 1)) and not World.paint(scene_doc.map_data, Vector2i(2, 1), "Colisão", 0, false), "cross-room portal thresholds stay clear of collision")
	var project_nav := preload("res://core/navigation.gd").new().analyze_project(scene_doc.map_data)
	expect(project_nav.rooms == 2 and project_nav.connected, "project-wide navigation traverses portals between rooms")
	var cropped_link := Doc.new()
	World.create_room(cropped_link.map_data, "Interior")
	var cropped_a: String = cropped_link.map_data.rooms[0].id
	var cropped_b: String = cropped_link.map_data.rooms[1].id
	World.add_connection(cropped_link.map_data, cropped_a, Vector2i(20, 10), cropped_b, Vector2i(20, 10))
	World.switch_room(cropped_link.map_data, 0); World.resize(cropped_link.map_data, 4, 4)
	expect(cropped_link.map_data.connections.is_empty(), "resizing a linked room removes invalid cross-room portals")
	var deleted_link := Doc.new()
	World.create_room(deleted_link.map_data, "Interior")
	World.add_connection(deleted_link.map_data, deleted_link.map_data.rooms[0].id, Vector2i(1, 1), deleted_link.map_data.rooms[1].id, Vector2i(2, 2))
	expect(World.remove_room(deleted_link.map_data, 1) and deleted_link.map_data.connections.is_empty(), "removing a room also removes its portal links")
	var path := folder.path_join("map.sfs.json")
	scene_doc.map_data.rooms[1].data.camera_settings = {"zoom": 4, "smoothing": 0.0, "pixel_snap": false}
	expect(store.save_document(scene_doc, path) == OK, "dynamic map saves")
	expect(Store.read_json(path).schema == 3, "expanded world format is independently versioned as schema 3")
	loaded = store.load_document(path)
	expect(loaded != null and loaded.map_data == scene_doc.map_data, "map layers, ambient light settings and dimensions roundtrip exactly")
	var nav := preload("res://core/navigation.gd").new()
	expect(nav.analyze(scene_doc.map_data).walkable == 47 and nav.analyze(scene_doc.map_data).connected, "navigation uses actual map dimensions and obstacles")
	expect(store.export_all(scene_doc, folder.path_join("export")) == OK, "multi-layer map exports native Godot resources")
	var rooms_index: Dictionary = Store.read_json(folder.path_join("export/rooms.json"))
	var interior_id: String = str(scene_doc.map_data.rooms[1].id)
	expect(rooms_index.rooms.size() == 2 and rooms_index.rooms[1].name == "Casa da Praça" and FileAccess.file_exists(folder.path_join("export/rooms/%s/map.tscn" % interior_id)), "export writes a scene and index for every room")
	expect(rooms_index.navigation.connected and rooms_index.connections.size() == 1, "room index carries project-wide portal topology and connected navigation")
	expect(FileAccess.file_exists(folder.path_join("export/examples/export/doorway.gd")) and FileAccess.file_exists(folder.path_join("export/examples/export/room_transition.gd")) and FileAccess.file_exists(folder.path_join("export/examples/export/pixel_camera.gd")), "export includes doorway and pixel camera runtime scripts")
	expect(FileAccess.get_file_as_string("res://examples/export/doorway.gd") == FileAccess.get_file_as_string("res://examples/export/doorway.gd.txt") and FileAccess.get_file_as_string("res://examples/export/room_transition.gd") == FileAccess.get_file_as_string("res://examples/export/room_transition.gd.txt") and FileAccess.get_file_as_string("res://examples/export/pixel_camera.gd") == FileAccess.get_file_as_string("res://examples/export/pixel_camera.gd.txt"), "raw export script templates stay synchronized with runtime scripts")
	var interior_scene: Node = load(folder.path_join("export/rooms/%s/map.tscn" % interior_id)).instantiate()
	expect(interior_scene.get_meta("sfs_room_id") == interior_id and interior_scene.get_node("Ground").get_used_cells().is_empty() and interior_scene.get_node("AmbientLight").color == Color("#292f45"), "exported interior scene loads its isolated contents and ambient lighting")
	interior_scene.free()
	var scene: Node = load(folder.path_join("export/map.tscn")).instantiate()
	expect(scene.get_node("AmbientLight") is CanvasModulate and scene.get_node("AmbientLight").color == Color("#59617a") and scene.get_meta("sfs_ambient_color") == "#59617a", "exported map applies scene-wide ambient light at runtime")
	var overlay: TileMapLayer = scene.get_node("Layer_1")
	expect(scene.get_node("Ground").get_used_cells().size() == 48 and overlay.get_used_cells().size() == 1 and not overlay.visible and is_equal_approx(overlay.modulate.a, 0.5), "export preserves layer cells, visibility and opacity")
	var occluders: int = 0
	var settings_ok := false
	for child in scene.get_children():
		if child is StaticBody2D:
			for nested in child.get_children(): if nested is LightOccluder2D: occluders += 1
		if child is PointLight2D: settings_ok = child.shadow_enabled and is_equal_approx(child.energy, 1.5) and is_equal_approx(child.texture_scale, 3.0 * 24 / 64)
	expect(occluders == 1 and settings_ok, "export contains real light shadows and collision occluder")
	var door_areas: Array = scene.find_children("*", "Area2D", true, false)
	expect(door_areas.size() == 3 and door_areas.any(func(area): return area.get("target_scene") == "res://rooms/%s/map.tscn" % interior_id_for_link), "export creates local doors and a cross-scene transition area")
	expect(scene.get_node("Navigation").navigation_polygon.get_polygon_count() == 47, "exported navigation omits exactly blocked cells")
	scene.free()
	await consumer_check(folder.path_join("export"), "direct-consumer")
	var batch_output := folder.path_join("batch-export")
	var batch_result := Worker.execute({"id": "world-multiroom", "input": path, "output": ProjectSettings.globalize_path(batch_output), "kind": "export", "progress": folder.path_join("batch-progress.json"), "cancel": folder.path_join("batch-cancel")})
	var batch_rooms: Dictionary = Store.read_json(batch_output.path_join("rooms.json")) if FileAccess.file_exists(batch_output.path_join("rooms.json")) else {}
	expect(batch_result.status == "done" and batch_rooms.get("rooms", []).size() == 2 and FileAccess.file_exists(batch_output.path_join("rooms/%s/map.tscn" % interior_id)) and FileAccess.file_exists(batch_output.path_join("examples/export/doorway.gd")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(batch_output.path_join(".sfs-stage-world-multiroom"))), "lote publica salas, conexões e scripts no pacote final e remove o staging")
	await consumer_check(batch_output, "batch-consumer")
	var nested_script_path := batch_output.path_join("examples/export/doorway.gd")
	var corrupt_nested_script := FileAccess.open(nested_script_path, FileAccess.WRITE); corrupt_nested_script.store_string("corrupted"); corrupt_nested_script.close()
	expect(Worker.execute({"id": "world-multiroom", "input": path, "output": ProjectSettings.globalize_path(batch_output), "kind": "export", "progress": folder.path_join("batch-progress.json"), "cancel": folder.path_join("batch-cancel")}).status == "done" and FileAccess.get_file_as_string(nested_script_path) == FileAccess.get_file_as_string("res://examples/export/doorway.gd"), "cache repara script auxiliar alterado dentro do pacote de salas")
	var one_room := scene_doc.detached_copy()
	expect(World.remove_room(one_room.map_data, 1), "fixture can remove a room before testing stale export cleanup")
	var one_room_path := folder.path_join("one-room.sfs.json")
	store.save_document(one_room, one_room_path)
	var one_room_result := Worker.execute({"id": "world-multiroom", "input": one_room_path, "output": ProjectSettings.globalize_path(batch_output), "kind": "export", "progress": folder.path_join("batch-progress.json"), "cancel": folder.path_join("batch-cancel")})
	var one_room_manifest: Dictionary = Store.read_json(batch_output.path_join("batch_manifest.json"))
	expect(one_room_result.status == "done" and one_room_manifest.get("checksums", {}).keys().all(func(name): return str(name) != "rooms/%s/map.tscn" % interior_id) and not FileAccess.file_exists(batch_output.path_join("rooms/%s/map.tscn" % interior_id)), "reexport removes obsolete room files previously owned by the manifest")
	var blocked_output := folder.path_join("blocked-publish")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_output.path_join("character.tscn")))
	var blocked_result := Worker.execute({"id": "world-rollback", "input": path, "output": ProjectSettings.globalize_path(blocked_output), "kind": "export", "progress": folder.path_join("blocked-progress.json"), "cancel": folder.path_join("blocked-cancel")})
	expect(blocked_result.status == "failed" and not FileAccess.file_exists(blocked_output.path_join("CREDITS.txt")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(blocked_output.path_join(".sfs-stage-world-rollback"))) and not FileAccess.file_exists(blocked_output.path_join("batch_manifest.json")), "publication conflict rolls back earlier files and cleans staging without writing success marker")
	var result := Worker.execute({"id": "world-test", "input": path, "output": folder.path_join("production"), "kind": "production", "parameters": {}, "progress": folder.path_join("progress.json"), "cancel": folder.path_join("cancel")})
	expect(result.status == "done", "automatic production accepts visible map-only project")
	var report = Store.read_json(folder.path_join("production/production-report.json"))
	expect(report is Dictionary and report.map.layers == 2 and report.map.navigation.walkable == 47, "automatic report includes map topology")
	await ui_checks()
	store.atomic_json("res://test_results/world-report.json", {"passed": checks.size() - failed, "failed": failed, "checks": checks})
	print("WORLD RESULT ", checks.size() - failed, " passed / ", failed, " failed")
	quit(1 if failed else 0)

func consumer_check(export_folder: String, consumer_name: String) -> void:
	var destination := folder.path_join(consumer_name)
	DirAccess.make_dir_recursive_absolute(destination)
	for filename in ["map.tscn", "tileset.tres"]: DirAccess.copy_absolute(export_folder.path_join(filename), destination.path_join(filename))
	_copy_tree(export_folder.path_join("rooms"), destination.path_join("rooms"))
	_copy_tree(export_folder.path_join("examples"), destination.path_join("examples"))
	DirAccess.copy_absolute("res://tests/world_consumer.gd", destination.path_join("validate.gd"))
	var project := FileAccess.open(destination.path_join("project.godot"), FileAccess.WRITE)
	project.store_string("config_version=5\n[application]\nconfig/name=\"SFSWorldConsumer\"\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n"); project.close()
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path(destination), "--script", "res://validate.gd", "--log-file", ProjectSettings.globalize_path(destination.path_join("run.log"))])
	var deadline := Time.get_ticks_msec() + 15000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline: await process_frame
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	var report = Store.read_json(destination.path_join("consumer-report.json"))
	expect(report is Dictionary and report.get("ok", false), "clean Godot consumer executes navigation, physics and both tile layers")
	if report is Dictionary: Store.new().atomic_json("res://test_results/world-consumer-report.json", report)

func _copy_tree(source: String, destination: String) -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	var directory := DirAccess.open(source)
	if directory == null: return
	for filename in directory.get_files(): DirAccess.copy_absolute(source.path_join(filename), destination.path_join(filename))
	for child in directory.get_directories(): _copy_tree(source.path_join(child), destination.path_join(child))

func ui_checks() -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = folder.path_join("ui_workspace")
	root.add_child(ui); ui.queue.jobs.clear(); ui.queue.checkpoint_path = folder.path_join("ui_queue.json")
	ui.tabs.current_tab = 1
	await process_frame
	ui.world_command({"kind": "add_layer"})
	expect(ui.doc.map_data.active_layer == 1 and ui.world_controls.listing.item_count == 2, "layer UI changes model and refreshes inspector")
	ui.world_command({"kind": "resize", "width": 32, "height": 20})
	expect(ui.doc.map_data.width == 32 and ui.doc.map_data.height == 20, "map UI applies expanded dimensions")
	ui.world.brush = "Retângulo"; ui.world.mode = "Tile"; ui.world.tile = 1
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = ui.world.origin() + Vector2(2.5, 2.5) * ui.world.cell
	ui.world._gui_input(press)
	press.pressed = false; press.position = ui.world.origin() + Vector2(4.5, 3.5) * ui.world.cell
	ui.world._gui_input(press)
	expect(World.cells(ui.doc.map_data)[2 * 32 + 2] == 1 and World.cells(ui.doc.map_data)[3 * 32 + 4] == 1, "rectangle gesture fills selected map region")
	ui.world.mode = "Porta"
	ui.world_command({"kind": "door_name", "value": "Casa da Praça"})
	press.pressed = true; press.position = ui.world.origin() + Vector2(8.5, 8.5) * ui.world.cell; ui.world._gui_input(press)
	press.pressed = true; press.position = ui.world.origin() + Vector2(10.5, 8.5) * ui.world.cell; ui.world._gui_input(press)
	expect(ui.doc.map_data.doors.size() == 1 and ui.doc.map_data.doors[0].name == "Casa da Praça" and ui.doc.undo(), "door-pair tool creates a named entrance and supports Undo")
	expect(ui.doc.map_data.doors.is_empty(), "undo removes the paired doorway metadata")
	ui.world.mode = "Tile"
	press.pressed = true; ui.world._gui_input(press)
	ui.undo()
	expect(not ui.world.painting and World.cells(ui.doc.map_data)[2 * 32 + 2] == 1, "undo cancels pending map gesture before restoring state")
	var original_rooms: int = ui.doc.map_data.rooms.size()
	ui.world_command({"kind": "add_room"})
	expect(ui.doc.map_data.rooms.size() == original_rooms + 1 and ui.doc.map_data.active_room == 1, "world panel creates and activates a new room")
	ui.world_command({"kind": "rename_room", "value": "Interior de teste"})
	ui.world_command({"kind": "select_room", "index": 0})
	expect(ui.doc.map_data.active_room == 0 and ui.doc.map_data.rooms[1].name == "Interior de teste", "room rename and room switching update the editor state")
	ui.doc.undo()
	expect(ui.doc.map_data.rooms.size() == original_rooms + 1, "room switch can be undone without deleting the new room")
	ui.undo()
	expect(World.cells(ui.doc.map_data)[2 * 32 + 2] == -1, "map paint undo restores independent layer cells")
	ui.world.brush = "Lápis"; press.pressed = true; ui.world._gui_input(press)
	ui.tabs.current_tab = 0
	expect(not ui.world.painting, "leaving map tab cancels active stroke")
	World.resize(ui.doc.map_data, 6, 4); ui.doc.map_data.collision.fill(false)
	for y in 4: ui.doc.map_data.collision[y * 6 + 3] = true
	ui.world.player = Vector2(36, 36); ui.world.move_player(Vector2(300, 0))
	expect(ui.world.player.x < 72 and not ui.world.solid(ui.world.player), "playable preview cannot tunnel through one-cell wall")
	expect(World.add_door(ui.doc.map_data, Vector2i(1, 1), Vector2i(4, 2)), "playable preview accepts an in-map doorway connection")
	ui.world.playing = true; ui.world.player = Vector2(36, 36)
	var use_door := InputEventKey.new(); use_door.pressed = true; use_door.physical_keycode = KEY_E
	ui.world._unhandled_key_input(use_door)
	expect(ui.world.player.is_equal_approx(Vector2(108, 60)), "E interaction teleports the player between paired map doorways")
	ui.world.playing = false
	var ui_rooms: Array = ui.doc.map_data.rooms
	var ui_to: String = ui_rooms[1].id
	ui.world_command({"kind": "select_room", "index": 0})
	ui.world.mode = "Porta"; ui.world.door_name = "Escada"
	press.pressed = true; press.position = ui.world.origin() + Vector2(1.5, 1.5) * ui.world.cell; ui.world._gui_input(press)
	ui.world_command({"kind": "select_room", "index": 1})
	press.pressed = true; press.position = ui.world.origin() + Vector2(2.5, 2.5) * ui.world.cell; ui.world._gui_input(press)
	expect(ui.doc.map_data.connections.size() == 1 and ui.doc.map_data.connections[0].name == "Escada", "door tool pairs endpoints across selected rooms")
	ui.world.playing = true
	ui.world_command({"kind": "select_room", "index": 0})
	ui.world.player = Vector2(36, 36)
	ui.world._unhandled_key_input(use_door)
	expect(ui.doc.map_data.rooms[int(ui.doc.map_data.active_room)].id == ui_to and ui.world.player.is_equal_approx(Vector2(60, 60)), "E preview crosses rooms while preserving the actor position")
	World.resize(ui.doc.map_data, 24, 16); ui.world.refresh(); ui.world.fit_map()
	var test_tile_image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	ui.world.textures = [ImageTexture.create_from_image(test_tile_image), ImageTexture.create_from_image(test_tile_image), ImageTexture.create_from_image(test_tile_image), ImageTexture.create_from_image(test_tile_image), ImageTexture.create_from_image(test_tile_image)]
	ui.refresh_world_controls()
	var chosen_roles := {"ground": 4, "path": 3, "plaza": 2, "structure": 1, "vegetation": 0}
	for role in chosen_roles:
		var picker: OptionButton = ui.world_controls.village_roles[role]
		picker.select(picker.get_item_index(chosen_roles[role]))
	var before_village: Array = ui.doc.map_data.cells.duplicate()
	var generate_button: Button
	for node in ui.world_controls.find_children("*", "Button", true, false):
		if node is Button and node.text == "Gerar layout": generate_button = node
	if generate_button != null: generate_button.emit_signal("pressed")
	expect(ui.doc.map_data.cells.has(2) and ui.doc.map_data.cells.has(1) and ui.doc.map_data.collision.any(func(value): return value) and ui.world_controls._read_village_roles() == chosen_roles, "village UI passes custom tile roles and creates visible structures with collision")
	ui.undo()
	expect(ui.doc.map_data.cells == before_village, "Undo restores the map before assisted village generation")
	ui.world_command({"kind": "camera_settings", "settings": {"zoom": 3, "smoothing": 0.0, "pixel_snap": false}})
	expect(ui.doc.map_data.camera_settings.zoom == 3 and World.valid(ui.doc.map_data, ui.doc.tile_images().size()), "camera inspector applies valid room settings")
	ui.undo()
	expect(ui.doc.map_data.camera_settings.zoom == 2 and ui.doc.map_data.camera_settings.pixel_snap, "Undo restores previous room camera settings")
	ui.world.set_preview(false)
	ui.world.set_preview(true)
	expect(ui.world.zoom == 2 and ui.world.origin().is_equal_approx(ui.world.size * 0.5 - ui.world.camera_focus / 24.0 * ui.world.cell + ui.world.pan), "playable preview follows the configured pixel camera")
	ui.world.set_preview(false)
	ui.world_command({"kind": "ambient_color", "value": "#43526a"})
	expect(ui.doc.map_data.ambient_color == "#43526a" and World.valid(ui.doc.map_data, ui.doc.tile_images().size()), "ambient light inspector applies valid room tone")
	ui.undo()
	expect(ui.doc.map_data.ambient_color == "#ffffff", "Undo restores the previous ambient room color")
	var five_tiles: Array = ui.world.textures
	ui.world.textures = []
	for i in 48: ui.world.textures.append(ImageTexture.create_from_image(test_tile_image))
	var terrains_before: int = ui.doc.map_data.terrain_sets.size()
	ui.world_command({"kind": "add_terrain", "name": "Lago", "start": 2, "mode": "blob47", "outside": "same"})
	expect(ui.doc.map_data.terrain_sets.size() == terrains_before, "panel refuses a blob47 terrain without 47 consecutive tiles")
	ui.world_command({"kind": "add_terrain", "name": "Grama", "start": 0, "mode": "edge16", "outside": "same"})
	var grass: Dictionary = ui.doc.map_data.terrain_sets[ui.doc.map_data.terrain_sets.size() - 1]
	expect(grass.name == "Grama" and grass.outside == "same" and not grass.has("mode") and grass.tiles.size() == 16, "panel edge16 terrain keeps the legacy shape and border rule")
	ui.undo()
	ui.world.textures = five_tiles
	var proof_path := ProjectSettings.globalize_path("res://examples/animation_proof/sentinela.sfs.json")
	var proof_doc = Store.new().load_document(proof_path)
	ui.world.doc = proof_doc
	ui.world.refresh()
	ui.world.set_preview(true)
	expect(ui.world.preview_clip_name == "idle_breathing", "playable world preview starts with breathing idle")
	var idle_frame: int = ui.world.anim_frame
	ui.world.advance_preview(0.21)
	expect(ui.world.preview_clip_name == "idle_breathing" and ui.world.anim_frame != idle_frame, "playable world preview advances breathing frames without movement")
	var source_frame: int = proof_doc.frame
	var source_clip: int = int(proof_doc.animation.active)
	var jump_first_frame: int = int(proof_doc.animation.clips[1].frames[0])
	var jump_started: bool = ui.world.start_preview_action("jump")
	var jump_texture: Image = ui.world.character_texture.get_image() if ui.world.character_texture != null else Image.new()
	expect(jump_started and ui.world.preview_action_clip == "jump" and ui.world.anim_frame == jump_first_frame and jump_texture.get_data() == proof_doc.composite(ui.world.facing, jump_first_frame).get_data(), "jump switches to its own first cel immediately without retaining idle pixels")
	ui.world.advance_preview(0.15)
	expect(ui.world.preview_actor_height > 0 and ui.world.anim_frame in proof_doc.animation.clips[1].frames, "jump animates and raises the actor during its arc")
	ui.world.advance_preview(1.0)
	var jump_return_texture: Image = ui.world.character_texture.get_image() if ui.world.character_texture != null else Image.new()
	var idle_first_frame: int = int(proof_doc.animation.clips[0].frames[0])
	expect(ui.world.preview_action_clip.is_empty() and ui.world.preview_clip_name == "idle_breathing" and ui.world.anim_frame == idle_first_frame and jump_return_texture.get_data() == proof_doc.composite(ui.world.facing, idle_first_frame).get_data() and is_zero_approx(ui.world.preview_actor_height), "jump returns to the first idle cel immediately with no one-frame action residue")
	var attack_key := InputEventKey.new(); attack_key.pressed = true; attack_key.physical_keycode = KEY_J
	ui.world._unhandled_key_input(attack_key)
	var attack_first_frame: int = int(proof_doc.animation.clips[2].frames[0])
	var attack_start_texture: Image = ui.world.character_texture.get_image() if ui.world.character_texture != null else Image.new()
	expect(ui.world.preview_action_clip == "attack" and ui.world.anim_frame == attack_first_frame and attack_start_texture.get_data() == proof_doc.composite(ui.world.facing, attack_first_frame).get_data(), "attack switches to its own first cel immediately without retaining idle pixels")
	ui.world.advance_preview(0.45)
	expect(ui.world.preview_action_clip == "attack" and ui.world.anim_frame == 13 and ui.world.preview_hitbox_rect().size.x > 0, "J plays attack and shows the active directional hitbox")
	expect(not ui.world.start_preview_action("jump"), "preview does not overlap two one-shot actions")
	ui.world.advance_preview(2.0)
	var attack_return_texture: Image = ui.world.character_texture.get_image() if ui.world.character_texture != null else Image.new()
	expect(ui.world.preview_action_clip.is_empty() and ui.world.preview_clip_name == "idle_breathing" and ui.world.anim_frame == idle_first_frame and attack_return_texture.get_data() == proof_doc.composite(ui.world.facing, idle_first_frame).get_data(), "attack returns to the first idle cel immediately with no one-frame action residue")
	var jump_key := InputEventKey.new(); jump_key.pressed = true; jump_key.physical_keycode = KEY_SPACE
	ui.world._unhandled_key_input(jump_key)
	expect(ui.world.preview_action_clip == "jump", "Space triggers jump in the playable preview")
	expect(proof_doc.frame == source_frame and int(proof_doc.animation.active) == source_clip, "playable actions do not edit the source timeline or clip selection")
	ui.free()
