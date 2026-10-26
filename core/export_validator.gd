extends RefCounted

const Storage = preload("res://core/storage.gd")
const World = preload("res://core/world_data.gd")

static func validate_package(folder: String) -> Dictionary:
	var checks: Array[Dictionary] = []
	var errors: Array[String] = []
	var metadata: Variant = Storage.read_json(folder.path_join("metadata.json"))
	var rooms_manifest: Variant = Storage.read_json(folder.path_join("rooms.json"))
	if not metadata is Dictionary:
		_record(checks, false, "metadata", "metadata.json is missing or invalid")
		return _report(checks)
	if not rooms_manifest is Dictionary:
		_record(checks, false, "rooms_manifest", "rooms.json is missing or invalid")
		return _report(checks)
	if not metadata.get("directions", null) is Array or not metadata.get("frames", null) is Array or not metadata.get("map", null) is Dictionary:
		_record(checks, false, "metadata_schema", "metadata is missing directions, frames, or world data")
		return _report(checks)
	if metadata.directions.is_empty() or metadata.frames.is_empty() or int(metadata.get("width", 0)) <= 0 or int(metadata.get("height", 0)) <= 0:
		_record(checks, false, "metadata_schema", "metadata dimensions and directional frame table must be non-empty")
		return _report(checks)
	if not rooms_manifest.get("rooms", null) is Array:
		_record(checks, false, "rooms_manifest", "rooms.json has no room list")
		return _report(checks)

	var image := Image.new()
	var image_error := image.load(folder.path_join(str(metadata.get("image", "spritesheet.png"))))
	var expected_width := int(metadata.get("width", 0)) * int(metadata.get("frames", []).size() / maxi(1, metadata.get("directions", []).size()))
	var expected_height: int = int(metadata.get("height", 0)) * metadata.get("directions", []).size()
	_record(checks, image_error == OK and image.get_width() == expected_width and image.get_height() == expected_height, "spritesheet", "spritesheet dimensions match exported frame and direction metadata")
	if image_error != OK or image.get_width() != expected_width or image.get_height() != expected_height:
		errors.append("Spritesheet failed its dimensions check.")

	var animations := ResourceLoader.load(folder.path_join("animations.tres"), "SpriteFrames", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	var clips: Array = metadata.get("animation", {}).get("clips", [])
	var animations_valid := animations != null and not clips.is_empty()
	if animations_valid:
		for clip in clips:
			if not clip is Dictionary or str(clip.get("name", "")).is_empty():
				animations_valid = false
				break
			for direction in metadata.get("directions", []):
				if not animations.has_animation(str(clip.name) + "_" + str(direction)):
					animations_valid = false
					break
			if not animations_valid: break
	_record(checks, animations_valid, "animation_resource", "every clip and direction exists in the exported SpriteFrames resource")
	if not animations_valid: errors.append("SpriteFrames is missing a declared clip or direction.")

	var character := ResourceLoader.load(folder.path_join("character.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var character_valid := character != null
	if character_valid:
		var actor := character.instantiate()
		var sprite := actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		var camera := actor.get_node_or_null("SFSFollowCamera") as Camera2D
		var scene_frames := sprite.sprite_frames if sprite != null else null
		var first_animation := ""
		if not clips.is_empty() and clips[0] is Dictionary:
			first_animation = str(clips[0].get("name", "")) + "_" + str(metadata.directions[0])
		character_valid = scene_frames != null and scene_frames.has_animation(first_animation) and camera != null
		actor.free()
	_record(checks, character_valid, "character_scene", "character scene references the exported animation resource and pixel camera")
	if not character_valid: errors.append("Character scene is incomplete or cannot be instantiated.")

	var map_data: Dictionary = metadata.map
	var map_rooms: Array = map_data.get("rooms", [])
	var rooms: Array = rooms_manifest.get("rooms", [])
	var rooms_valid := not rooms.is_empty() and rooms.size() == map_rooms.size() and rooms.size() <= 32
	if not rooms_valid:
		_record(checks, false, "world_rooms", "room manifest count must match project data and stay within the 32-room limit")
		errors.append("World room manifest is empty, oversized, or inconsistent with metadata.")
		return _report(checks, {"rooms": [], "errors": errors})
	var loaded_rooms: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for entry in rooms:
		if not entry is Dictionary:
			rooms_valid = false
			continue
		var room_id := str(entry.get("id", ""))
		var relative_scene := str(entry.get("scene", ""))
		if room_id.is_empty() or seen_ids.has(room_id) or not _safe_relative_path(relative_scene):
			rooms_valid = false
			continue
		seen_ids[room_id] = true
		var room_path := folder.path_join(relative_scene)
		var packed_room := ResourceLoader.load(room_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed_room == null:
			rooms_valid = false
			continue
		var room_node := packed_room.instantiate()
		var ground := room_node.get_node_or_null("Ground") as TileMapLayer
		var navigation := room_node.get_node_or_null("Navigation") as NavigationRegion2D
		var ambient := room_node.get_node_or_null("AmbientLight") as CanvasModulate
		var bounds: Variant = room_node.get_meta("sfs_bounds", null)
		var matching_record: Dictionary = {}
		for record in map_rooms:
			if record is Dictionary and str(record.get("id", "")) == room_id:
				matching_record = record
				break
		var room_data_variant: Variant = matching_record.get("data", {})
		var room_data: Dictionary = room_data_variant if room_data_variant is Dictionary else {}
		if room_data.is_empty() or not room_data.get("base", null) is Dictionary or not room_data.get("layers", null) is Array or not room_data.get("cells", null) is Array:
			rooms_valid = false
			loaded_rooms.append({"id": room_id, "scene": relative_scene, "ok": false, "error": "room data is incomplete"})
			room_node.free()
			continue
		var room_width := int(room_data.get("width", 0))
		var room_height := int(room_data.get("height", 0))
		var collision_data: Variant = room_data.get("collision", null)
		var collision_data_valid: bool = collision_data is Array and room_width > 0 and room_height > 0 and collision_data.size() == room_width * room_height
		var expected_collision_centers: Dictionary = {}
		if collision_data_valid:
			for index in collision_data.size():
				if collision_data[index] is bool and collision_data[index]:
					expected_collision_centers[Vector2i((index % room_width) * 24 + 12, int(index / room_width) * 24 + 12)] = true
		var light_settings: Variant = room_data.get("light_settings", {})
		var light_data: Variant = room_data.get("lights", null)
		var light_geometry_valid := light_data is Array and light_settings is Dictionary
		var expected_lights: Dictionary = {}
		if light_geometry_valid:
			for point in light_data:
				if not point is Array or point.size() != 2:
					light_geometry_valid = false
					continue
				var light_key := "%d:%d" % [int(point[0]), int(point[1])]
				var expected_center := Vector2i(int(point[0]) * 24 + 12, int(point[1]) * 24 + 12)
				expected_lights[expected_center] = light_settings.get(light_key, {"color": "#ffcf8b", "energy": 1.0, "radius": 4.0, "shadows": false})
		var collision_bodies := 0
		var light_nodes := 0
		var occluders := 0
		var doorways := 0
		var tile_layers := 0
		var collision_geometry_valid := true
		for child in room_node.get_children():
			if child is TileMapLayer:
				tile_layers += 1
				if child.tile_set == null or child.tile_set.get_source_count() == 0: collision_geometry_valid = false
			if child is StaticBody2D:
				collision_bodies += 1
				var center := Vector2i(roundi(child.position.x), roundi(child.position.y))
				if not expected_collision_centers.has(center): collision_geometry_valid = false
				expected_collision_centers.erase(center)
				var collision_shape: CollisionShape2D
				for body_child in child.get_children():
					if body_child is CollisionShape2D:
						collision_shape = body_child
						break
				if collision_shape == null or not collision_shape.shape is RectangleShape2D:
					collision_geometry_valid = false
				elif not (collision_shape.shape as RectangleShape2D).size.is_equal_approx(Vector2(24, 24)):
					collision_geometry_valid = false
			if child is PointLight2D:
				light_nodes += 1
				var actual_light_center := Vector2i(roundi(child.position.x), roundi(child.position.y))
				if not expected_lights.has(actual_light_center):
					light_geometry_valid = false
				else:
					var settings: Dictionary = expected_lights[actual_light_center]
					var expected_scale := float(settings.get("radius", 4.0)) * 24.0 / 64.0
					light_geometry_valid = light_geometry_valid and child.texture != null and child.color == Color(str(settings.get("color", "#ffcf8b")))
					light_geometry_valid = light_geometry_valid and is_equal_approx(child.energy, float(settings.get("energy", 1.0))) and is_equal_approx(child.texture_scale, expected_scale)
					light_geometry_valid = light_geometry_valid and child.shadow_enabled == bool(settings.get("shadows", false))
					expected_lights.erase(actual_light_center)
			if child is Area2D and child.is_in_group("sfs_interactions"): doorways += 1
			if child is StaticBody2D:
				for body_child in child.get_children():
					if body_child is LightOccluder2D: occluders += 1
		var identity_ok: bool = str(room_node.get_meta("sfs_room_id", "")) == room_id
		var world_nodes_ok: bool = ground != null and ground.tile_set != null and ground.tile_set.get_source_count() > 0 and navigation != null and ambient != null and bounds is Rect2 and bounds.size.x > 0 and bounds.size.y > 0
		var expected_tile_layers: int = World.layers(room_data).size()
		var tile_layers_ok: bool = tile_layers == expected_tile_layers
		var collision_ok: bool = collision_data_valid and collision_bodies == collision_data.count(true) and expected_collision_centers.is_empty() and collision_geometry_valid
		var lights_ok: bool = light_data is Array and light_nodes == light_data.size() and expected_lights.is_empty() and light_geometry_valid
		var has_shadows: bool = light_settings is Dictionary and light_settings.values().any(func(light): return light is Dictionary and bool(light.get("shadows", false)))
		var shadows_ok: bool = not has_shadows or occluders >= collision_bodies
		var expected_doors: int = room_data.get("doors", []).size() * 2
		for connection in map_data.get("connections", []):
			if connection is Dictionary:
				if str(connection.get("a", {}).get("room", "")) == room_id: expected_doors += 1
				if str(connection.get("b", {}).get("room", "")) == room_id: expected_doors += 1
		var doorways_ok: bool = doorways == expected_doors
		var room_valid: bool = identity_ok and world_nodes_ok and tile_layers_ok and collision_ok and lights_ok and shadows_ok and doorways_ok
		loaded_rooms.append({"id": room_id, "scene": relative_scene, "ok": room_valid, "checks": {"identity": identity_ok, "world_nodes": world_nodes_ok, "tile_layers": tile_layers_ok, "collision_geometry": collision_ok, "collision_data_valid": collision_data_valid, "collision_count_matches": collision_data_valid and collision_bodies == collision_data.count(true), "collision_centers_match": expected_collision_centers.is_empty(), "collision_shapes_valid": collision_geometry_valid, "expected_collision_cells": collision_data.count(true) if collision_data_valid else -1, "remaining_expected_centers": expected_collision_centers.size(), "lights": lights_ok, "shadow_occluders": shadows_ok, "doorways": doorways_ok}, "tile_layers": tile_layers, "expected_tile_layers": expected_tile_layers, "collision_cells": collision_bodies, "lights_count": light_nodes, "doorways_count": doorways})
		room_node.free()
		if not room_valid: rooms_valid = false
	_record(checks, rooms_valid, "world_rooms", "all room scenes load with matching tile resources, navigation, lighting, collisions, and doorways")
	if not rooms_valid: errors.append("One or more world room scenes do not match their data or are missing resources.")

	var tile_resource := ResourceLoader.load(folder.path_join("tileset.tres"), "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	var tile_resource_valid := tile_resource != null and tile_resource.get_source_count() > 0
	_record(checks, tile_resource_valid, "tileset_resource", "standalone exported TileSet resource loads and contains a source")
	if not tile_resource_valid: errors.append("The standalone TileSet resource is invalid.")

	return _report(checks, {"rooms": loaded_rooms, "errors": errors})

static func validate_png_sequence(folder: String, verify_hashes: bool = true) -> bool:
	var data: Variant = Storage.read_json(folder.path_join("sequence.json"))
	if not data is Dictionary or data.get("schema") != 1: return false
	for key in ["width", "height", "frame_count", "fps"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)): return false
	if data.fps < 1 or data.fps > 60: return false
	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var count := int(data.get("frame_count", 0))
	var width := int(data.get("width", 0))
	var height := int(data.get("height", 0))
	if count < 1 or count > 32 or width < 8 or width > 512 or height < 8 or height > 512 or data.get("directions") != directions: return false
	if not data.get("frames") is Array or data.frames.size() != count * 8 or not data.get("clips") is Array or data.clips.is_empty() or data.clips.size() > 32: return false
	var seen := {}
	for row in data.frames:
		if not row is Dictionary or not row.get("direction") in directions: return false
		if not (row.get("frame") is int or row.get("frame") is float): return false
		if not is_finite(float(row.frame)): return false
		var frame := int(row.get("frame", -1))
		var expected := "frames/%s/frame_%04d.png" % [row.direction, frame]
		if float(row.get("frame", -1)) != frame or frame < 0 or frame >= count or str(row.get("file", "")) != expected or seen.has(expected): return false
		seen[expected] = true
		var path := folder.path_join(expected)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return false
		var bounded := file.get_length() <= 4 * 1024 * 1024
		file.close()
		if not bounded or str(row.get("sha256", "")).length() != 64 or (verify_hashes and FileAccess.get_sha256(path) != row.sha256): return false
		var image := Image.new()
		if image.load(path) != OK or image.get_size() != Vector2i(width, height): return false
		if not row.get("pivot") is Array or row.pivot.size() != 2 or not row.get("anchors") is Dictionary or not row.get("events") is Array or not row.get("hitboxes") is Array: return false
	var names := {}
	for clip in data.clips:
		if not clip is Dictionary or not clip.get("name") is String or clip.name.is_empty() or names.has(clip.name) or not clip.get("loop") is bool or not clip.get("frames") is Array or clip.frames.is_empty() or clip.frames.size() > 32: return false
		names[clip.name] = true
		for row in clip.frames:
			if not row is Dictionary: return false
			if not (row.get("frame") is int or row.get("frame") is float) or not (row.get("duration_ms") is int or row.get("duration_ms") is float): return false
			if not is_finite(float(row.frame)): return false
			var frame := int(row.get("frame", -1))
			var duration := float(row.get("duration_ms", 0))
			if float(row.get("frame", -1)) != frame or frame < 0 or frame >= count or not is_finite(duration) or duration <= 0 or duration > 10000: return false
	return true

static func validate_profile(folder: String, profile: String) -> Dictionary:
	if profile == "playable": return validate_package(folder)
	var checks: Array[Dictionary] = []
	var errors: Array[String] = []
	var profile_data: Variant = Storage.read_json(folder.path_join("export-profile.json"))
	var profile_ok: bool = profile in ["sprite", "animated", "modular", "map", "sequence"] and profile_data is Dictionary and str(profile_data.get("profile", "")) == profile
	_record(checks, profile_ok, "profile_manifest", "export profile manifest matches the selected profile")
	if not profile_ok:
		errors.append("Export profile manifest is missing, invalid, or mismatched.")
		return _report(checks, {"errors": errors})
	var credits_ok := FileAccess.file_exists(folder.path_join("CREDITS.txt"))
	_record(checks, credits_ok, "credits", "provenance credits file exists")
	if not credits_ok: errors.append("CREDITS.txt is missing.")
	match profile:
		"sequence":
			var valid := validate_png_sequence(folder)
			_record(checks, valid, "png_sequence", "all directional PNGs match their hashes, dimensions and clip frame references")
			if not valid: errors.append("PNG sequence or its timing manifest is invalid.")
		"sprite":
			var metadata: Variant = Storage.read_json(folder.path_join("metadata.json"))
			var image := Image.new()
			var load_error := image.load(folder.path_join("spritesheet.png"))
			var dimensions_ok: bool = metadata is Dictionary and load_error == OK and image.get_width() == int(metadata.get("width", 0)) * int(metadata.get("frames", []).size() / maxi(1, metadata.get("directions", []).size())) and image.get_height() == int(metadata.get("height", 0)) * metadata.get("directions", []).size()
			_record(checks, dimensions_ok, "sprite_atlas", "isolated sprite export contains a correctly sized directional atlas")
			if not dimensions_ok: errors.append("Isolated sprite atlas dimensions do not match its metadata.")
			var frame := Image.new()
			var frame_error := frame.load(folder.path_join("frame.png"))
			var frame_ok: bool = metadata is Dictionary and frame_error == OK and frame.get_width() == int(metadata.get("width", 0)) and frame.get_height() == int(metadata.get("height", 0))
			_record(checks, frame_ok, "sprite_frame", "isolated PNG frame matches the declared canvas")
			if not frame_ok: errors.append("Isolated PNG frame is invalid.")
		"animated":
			var metadata: Variant = Storage.read_json(folder.path_join("metadata.json"))
			var animations := ResourceLoader.load(folder.path_join("animations.tres"), "SpriteFrames", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
			var scene := ResourceLoader.load(folder.path_join("character.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var animation_ok: bool = metadata is Dictionary and animations != null and scene != null
			if animation_ok:
				for clip in metadata.get("animation", {}).get("clips", []):
					for direction in metadata.get("directions", []):
						if not animations.has_animation(str(clip.get("name", "")) + "_" + str(direction)): animation_ok = false
			_record(checks, animation_ok, "animated_character", "animated profile has all clip-direction tracks and a loadable character scene")
			if not animation_ok: errors.append("Animated character export is missing clips, directions, or its scene.")
		"modular":
			var modular: Variant = Storage.read_json(folder.path_join("modular.json"))
			var scene := ResourceLoader.load(folder.path_join("modular_character.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var modular_ok: bool = modular is Dictionary and modular.get("layers", null) is Array and scene != null
			var sprite_count_ok := false
			var animation_coverage_ok := false
			var layer_images_ok := false
			var layer_image_count := 0
			var layer_image_diagnostics: Array[String] = []
			if modular_ok:
				var root := scene.instantiate()
				var sprites: Array = root.find_children("*", "Sprite2D", true, false)
				var player := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
				sprite_count_ok = sprites.size() == modular.layers.size()
				animation_coverage_ok = player != null
				if player != null:
					for clip in modular.get("clips", []):
						for direction in modular.get("directions", []):
							if not player.has_animation(str(clip.get("name", "")) + "_" + str(direction)): animation_coverage_ok = false
				layer_images_ok = true
				for layer in modular.layers:
					var texture_path := str(layer.get("texture", ""))
					if not _safe_relative_file_path(texture_path): layer_images_ok = false; layer_image_diagnostics.append("unsafe path=" + texture_path); continue
					var layer_image := Image.new()
					var layer_file_path := folder.path_join(texture_path)
					var layer_error := layer_image.load(layer_file_path)
					var expected_layer_size := Vector2i(int(modular.get("canvas", [0, 0])[0]) * int(layer.get("frame_count", 0)), int(modular.get("canvas", [0, 0])[1]) * modular.get("directions", []).size())
					if layer_error != OK or layer_image.get_size() != expected_layer_size: layer_images_ok = false; layer_image_diagnostics.append("%s err=%s size=%s expected=%s" % [layer_file_path, error_string(layer_error), str(layer_image.get_size()), str(expected_layer_size)])
					else: layer_image_count += 1
				root.free()
				modular_ok = sprite_count_ok and animation_coverage_ok and layer_images_ok
			_record(checks, modular_ok, "modular_character", "modular scene loads with one animated layer per source layer and complete clip-direction coverage")
			checks[-1]["subchecks"] = {"sprites_match_layers": sprite_count_ok, "animation_coverage": animation_coverage_ok, "layer_images_valid": layer_images_ok, "layer_images": layer_image_count, "layer_diagnostics": layer_image_diagnostics}
			if not modular_ok: errors.append("Modular character scene or one of its layer atlases is invalid.")
		"map":
			var manifest: Variant = Storage.read_json(folder.path_join("rooms.json"))
			var map_ok: bool = manifest is Dictionary and manifest.get("rooms", null) is Array and not manifest.rooms.is_empty() and manifest.rooms.size() <= 32
			var room_count := 0
			if map_ok:
				for room in manifest.rooms:
					if not room is Dictionary or not _safe_relative_path(str(room.get("scene", ""))): map_ok = false; continue
					var scene := ResourceLoader.load(folder.path_join(str(room.scene)), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
					if scene == null: map_ok = false; continue
					var root := scene.instantiate()
					map_ok = map_ok and root.get_node_or_null("Ground") is TileMapLayer and root.get_node_or_null("Navigation") is NavigationRegion2D and root.get_node_or_null("AmbientLight") is CanvasModulate and str(root.get_meta("sfs_room_id", "")) == str(room.get("id", ""))
					root.free()
					room_count += 1
			var tileset := ResourceLoader.load(folder.path_join("tileset.tres"), "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
			map_ok = map_ok and tileset != null and tileset.get_source_count() > 0 and manifest.get("active_room", "") != ""
			_record(checks, map_ok, "world_rooms", "map-only profile contains loadable room scenes and a standalone TileSet")
			if not map_ok: errors.append("Map export profile contains invalid room or TileSet resources.")
			else: profile_data["validated_room_count"] = room_count
	var report := _report(checks, {"errors": errors, "profile": profile})
	return report

static func _safe_relative_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.begins_with("/") or normalized.contains(":"): return false
	for part in normalized.split("/"):
		if part in ["", ".", ".."]: return false
	return normalized.ends_with(".tscn")

static func _safe_relative_file_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if normalized.is_empty() or normalized.begins_with("/") or normalized.contains(":"): return false
	for part in normalized.split("/"):
		if part in ["", ".", ".."]: return false
	return true

static func _record(checks: Array[Dictionary], passed: bool, name: String, details: String) -> void:
	checks.append({"name": name, "passed": passed, "details": details})

static func _report(checks: Array[Dictionary], extra: Dictionary = {}) -> Dictionary:
	var passed := 0
	for check in checks:
		if bool(check.get("passed", false)): passed += 1
	var report := {"schema": 1, "ok": passed == checks.size() and not checks.is_empty(), "passed": passed, "failed": checks.size() - passed, "checks": checks}
	for key in extra: report[key] = extra[key]
	return report
