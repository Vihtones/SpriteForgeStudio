extends RefCounted
const Doc = preload("res://core/document.gd")
const SCHEMA = 4
const Contracts = preload("res://core/contracts.gd")
const DoorwayScript = preload("res://examples/export/doorway.gd")
const MAX_FILE_BYTES = 67108864
const World = preload("res://core/world_data.gd")
var error: String = ""

static func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > MAX_FILE_BYTES: return null
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	return parser.data if parser.parse(content) == OK else null

func encode(doc: RefCounted) -> Dictionary:
	World.sync_active_room(doc.map_data)
	var data := {"schema": SCHEMA if doc.layer_mask_pixels() > 0 else 3, "width": doc.width, "height": doc.height, "frames": doc.frames, "fps": doc.fps, "direction": doc.direction, "frame": doc.frame, "active_layer": doc.active_layer, "palette": doc.palette, "anchors": doc.anchors, "art": doc.art, "map": doc.map_data, "layers": []}
	data.manifest = doc.manifest.duplicate(true)
	data.rig = doc.rig.duplicate(true)
	data.animation = doc.animation.duplicate(true)
	data.revision = doc.revision
	for layer in doc.layers:
		var l: Dictionary = layer.duplicate()
		l.cels = []
		for row in layer.cels:
			var encoded: Array = []
			for img in row: encoded.append(Marshalls.raw_to_base64(img.save_png_to_buffer()))
			l.cels.append(encoded)
		data.layers.append(l)
	return data

func atomic_json(path: String, data: Dictionary) -> Error:
	var serialized := JSON.stringify(data)
	if serialized.to_utf8_buffer().size() > MAX_FILE_BYTES: return ERR_OUT_OF_MEMORY
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(serialized)
	file.flush()
	file.close()
	# Windows rename cannot replace an existing file. Keep a backup until replacement succeeds.
	var backup := path + ".bak"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
		var moved := DirAccess.rename_absolute(path, backup)
		if moved != OK: return moved
	var result := DirAccess.rename_absolute(tmp, path)
	if result != OK and FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, path)
	return result

func save_document(doc: RefCounted, path: String) -> Error:
	var result := atomic_json(path, encode(doc))
	if result == OK: doc.dirty = false
	return result

func load_document(path: String) -> RefCounted:
	error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "Não foi possível abrir o projeto."
		return null
	if file.get_length() > MAX_FILE_BYTES:
		error = "Arquivo excede 64 MiB."
		return null
	var parser := JSON.new()
	var content := file.get_as_text()
	file.close()
	if parser.parse(content) != OK: error = "JSON inválido ou incompleto."; return null
	var data = parser.data
	if not data is Dictionary or (data.get("schema") != 1 and data.get("schema") != 2 and data.get("schema") != 3 and data.get("schema") != SCHEMA):
		error = "Formato ou versão inválida."
		return null
	if not _valid(data):
		error = "Estrutura inválida ou limites excedidos."
		return null
	var doc = Doc.new()
	if data.schema == 1: data = migrate_v1(data, doc.manifest)
	if not Contracts.valid_extensions(data):
		error = "Contratos de animação, rig ou manifesto inválidos."
		return null
	doc.manifest = data.manifest
	doc.rig = data.rig
	doc.animation = data.animation
	doc.animation.active = int(doc.animation.active)
	for clip in doc.animation.clips:
		for i in clip.frames.size(): clip.frames[i] = int(clip.frames[i])
	for indices in doc.rig.get("protected_pixels", {}).values():
		for i in indices.size(): indices[i] = int(indices[i])
	for points in doc.rig.get("anchors", {}).values():
		for name in points:
			points[name] = [int(points[name][0]), int(points[name][1])]
	for offsets in doc.rig.get("offsets", {}).values():
		for layer_id in offsets:
			offsets[layer_id] = [int(offsets[layer_id][0]), int(offsets[layer_id][1])]
	doc.revision = int(data.get("revision", 0))
	doc.width = int(data.width)
	doc.height = int(data.height)
	doc.frames = int(data.frames)
	doc.fps = clampi(int(data.get("fps", 8)), 1, 60)
	doc.direction = clampi(int(data.get("direction", 0)), 0, 7)
	doc.frame = clampi(int(data.get("frame", 0)), 0, doc.frames - 1)
	doc.active_layer = clampi(int(data.get("active_layer", 0)), 0, data.layers.size() - 1)
	doc.palette = data.palette
	doc.anchors = data.anchors
	for key in doc.anchors:
		doc.anchors[key] = [int(doc.anchors[key][0]), int(doc.anchors[key][1])]
	for name in Doc.DEFAULT_ANCHORS:
		if not doc.anchors.has(name) and doc.anchors.size() < 32:
			var point: Array = Doc.DEFAULT_ANCHORS[name]
			doc.anchors[name] = [mini(int(point[0]), doc.width - 1), mini(int(point[1]), doc.height - 1)]
	if not doc.rig.has("skeleton"):
		doc.rig.skeleton = Doc.DEFAULT_SKELETON.duplicate(true)
	if not doc.rig.has("rotations"): doc.rig.rotations = {}
	doc.art = data.art
	doc.map_data = data.map
	World.normalize(doc.map_data)
	doc.layers.clear()
	for l in data.layers:
		var layer: Dictionary = l.duplicate(true)
		for indices in layer.get("visibility_masks", {}).values():
			for index in indices.size(): indices[index] = int(indices[index])
		if not layer.has("id"): layer.id = Crypto.new().generate_random_bytes(8).hex_encode()
		if not layer.has("asymmetric"): layer.asymmetric = false
		layer.pivot = layer.get("pivot", layer.get("anchor", "feet"))
		if not doc.anchors.has(layer.pivot): layer.pivot = "feet"
		layer.cels = []
		for row in l.cels:
			var decoded: Array = []
			for png in row:
				var img := Image.new()
				if not png.begins_with("iVBORw0KGgo"):
					error = "Assinatura PNG inválida."
					return null
				if img.load_png_from_buffer(Marshalls.base64_to_raw(png)) != OK or img.get_size() != Vector2i(doc.width, doc.height):
					error = "Cel PNG inválida."
					return null
				img.convert(Image.FORMAT_RGBA8)
				decoded.append(img)
			layer.cels.append(decoded)
		doc.layers.append(layer)
	return doc

func migrate_v1(data: Dictionary, defaults: Dictionary) -> Dictionary:
	data.schema = 2
	data.manifest = defaults.duplicate(true)
	data.rig = {"family": "humanoid", "anchors": {}, "depth": {}}
	data.animation = {"active": 0, "clips": [{"name": "walk", "frames": range(int(data.frames)), "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	data.direction = (int(data.get("direction", 0)) + 4) % 8
	for layer in data.layers:
		var old: Array = layer.cels
		layer.cels = [old[4], old[5], old[6], old[7], old[0], old[1], old[2], old[3]]
		layer.families = ["humanoid"]
	if not data.map.has("tileset_png"):
		for i in data.map.cells.size():
			var tile: int = int(data.map.cells[i])
			if tile >= 0: data.map.cells[i] = ((int(tile / int(data.frames)) + 4) % 8) * int(data.frames) + tile % int(data.frames)
	return data

func _valid(d: Dictionary) -> bool:
	for key in ["width", "height", "frames", "layers", "palette", "anchors", "art", "map"]:
		if not d.has(key): return false
	if not d.width is float and not d.width is int: return false
	if not d.height is float and not d.height is int: return false
	if not d.frames is float and not d.frames is int: return false
	if d.width < 1 or d.width > Doc.MAX_SIDE or d.height < 1 or d.height > Doc.MAX_SIDE or d.frames < 1 or d.frames > 32: return false
	if not d.layers is Array or d.layers.is_empty() or d.layers.size() > 16: return false
	if d.width * d.height * d.frames * 8 * d.layers.size() * 4 > 67108864: return false
	if not d.palette is Array or d.palette.is_empty() or d.palette.size() > 256: return false
	for color in d.palette:
		if not color is String or not Color.html_is_valid(color): return false
	if not d.anchors is Dictionary or d.anchors.size() > 32: return false
	for a in d.anchors.values():
		if not a is Array or a.size() != 2: return false
		for value in a:
			if not value is float and not value is int: return false
	if not d.art is Dictionary: return false
	for key in ["bible", "locked", "references", "memory", "candidates"]:
		if not d.art.has(key): return false
	if not d.art.bible is String or not d.art.locked is bool: return false
	for key in ["references", "memory", "candidates"]:
		if not d.art[key] is Array: return false
	if d.art.references.size() > 64 or d.art.candidates.size() > 4096 or d.art.memory.size() > 4096: return false
	for reference in d.art.references:
		if not reference is Dictionary: return false
		for key in ["name", "path", "sha256", "provenance", "thumbnail"]:
			if not reference.get(key) is String: return false
	for key in ["candidates", "memory"]:
		for candidate in d.art[key]:
			if not candidate is Dictionary or not candidate.get("palette") is Array: return false
			for color in candidate.palette:
				if not color is String or not Color.html_is_valid(color): return false
			for field in ["id", "status", "test", "description"]:
				if not candidate.get(field) is String: return false
	for key in ["fps", "direction", "frame", "active_layer"]:
		if d.has(key) and not d[key] is float and not d[key] is int: return false
	if not d.map is Dictionary: return false
	if d.schema >= 3 and not d.map.has_all(["base", "layers", "active_layer", "terrain_sets", "light_settings"]): return false
	var tile_count: int = int(d.frames) * 8
	if d.map.has("tileset_png"):
		if not d.map.tileset_png is String or not d.map.tileset_png.begins_with("iVBORw0KGgo") or d.map.tileset_png.length() > 4000000: return false
		var tiles := Image.new()
		if tiles.load_png_from_buffer(Marshalls.base64_to_raw(d.map.tileset_png)) != OK: return false
		if tiles.get_width() > 256 or tiles.get_height() > 256 or tiles.get_width() % 16 != 0 or tiles.get_height() % 16 != 0: return false
		tile_count = int(tiles.get_width() / 16) * int(tiles.get_height() / 16)
	if not World.valid(d.map, tile_count): return false
	for l in d.layers:
		if not l is Dictionary: return false
		for key in ["name", "visible", "locked", "opacity", "equipment", "anchor", "offset", "cels"]:
			if not l.has(key): return false
		if not l.name is String or not l.anchor is String: return false
		if not l.visible is bool or not l.locked is bool or not l.equipment is bool: return false
		if not l.opacity is float and not l.opacity is int: return false
		if l.opacity < 0 or l.opacity > 1: return false
		if not l.offset is Array or l.offset.size() != 2: return false
		for v in l.offset:
			if not v is float and not v is int: return false
		if not l.cels is Array or l.cels.size() != 8: return false
		for row in l.cels:
			if not row is Array or row.size() != d.frames: return false
			for png in row:
				if not png is String or png.length() > 4000000: return false
	return true

const EXPORT_PROFILES := ["sprite", "animated", "modular", "playable", "map", "sequence"]

func export_all(doc: RefCounted, folder: String, profile: String = "playable") -> Error:
	if doc == null or not doc.validate().is_empty() or profile not in EXPORT_PROFILES: return ERR_INVALID_DATA
	# Keep embedded room data aligned with the active-room scene in every profile.
	World.sync_active_room(doc.map_data)
	var result := DirAccess.make_dir_recursive_absolute(folder)
	if result != OK: return result
	if profile == "sequence":
		result = _export_png_sequence(doc, folder)
	elif profile == "map":
		result = export_map(doc, folder)
		if result != OK: return result
		result = _write_credits(doc, folder)
	else:
		result = _export_character_package(doc, folder, profile)
		if result != OK: return result
		if profile == "playable": result = export_map(doc, folder)
	if result != OK: return result
	var profile_file := {"schema": 1, "profile": profile, "application_version": str(ProjectSettings.get_setting("application/config/version", "")), "direction_order": Doc.DIRECTIONS.duplicate(), "frame_count": doc.frames, "layer_count": doc.layers.size(), "room_count": doc.map_data.get("rooms", []).size() if profile in ["map", "playable"] else 0}
	return atomic_json(folder.path_join("export-profile.json"), profile_file)

func _export_png_sequence(doc: RefCounted, folder: String) -> Error:
	var manifest := {"schema": 1, "width": doc.width, "height": doc.height, "fps": doc.fps, "frame_count": doc.frames, "directions": Doc.DIRECTIONS.duplicate(), "frames": [], "clips": [], "project_id": str(doc.manifest.id), "source_revision": doc.revision, "source_assets": doc.art.get("source_assets", []).duplicate(true)}
	manifest["family"] = str(doc.rig.family)
	manifest["palette"] = doc.palette.duplicate()
	manifest["skeleton"] = doc.rig.get("skeleton", []).duplicate(true)
	for direction in 8:
		var relative_folder: String = "frames/" + str(Doc.DIRECTIONS[direction])
		var result := DirAccess.make_dir_recursive_absolute(folder.path_join(relative_folder))
		if result != OK: return result
		for frame in doc.frames:
			var relative_path: String = relative_folder.path_join("frame_%04d.png" % frame)
			var full_path: String = folder.path_join(relative_path)
			result = doc.composite(direction, frame).save_png(full_path)
			if result != OK: return result
			var anchors := {}
			for anchor in doc.anchors: anchors[anchor] = doc.anchor_at(anchor, direction, frame).duplicate()
			manifest.frames.append({"direction": Doc.DIRECTIONS[direction], "frame": frame, "file": relative_path, "sha256": FileAccess.get_sha256(full_path), "pivot": doc.anchor_at("feet", direction, frame).duplicate(), "anchors": anchors, "events": doc.animation.events.get(doc.cel_key(direction, frame), []).duplicate(true), "hitboxes": doc.animation.hitboxes.get(doc.cel_key(direction, frame), []).duplicate(true)})
	for clip in doc.animation.clips:
		var frames: Array = []
		for frame in clip.frames: frames.append({"frame": int(frame), "duration_ms": doc.frame_seconds(int(frame), clip) * 1000.0})
		manifest.clips.append({"name": str(clip.name), "loop": bool(clip.loop), "frames": frames})
	var result := atomic_json(folder.path_join("sequence.json"), manifest)
	if result != OK: return result
	return _write_credits(doc, folder)

func _export_character_package(doc: RefCounted, folder: String, profile: String) -> Error:
	var include_animation: bool = profile != "sprite"
	var include_character: bool = profile in ["animated", "playable"]
	var include_modular: bool = profile == "modular"
	var sheet := Image.create(doc.width * doc.frames, doc.height * 8, false, Image.FORMAT_RGBA8)
	var frame_textures: Dictionary = {}
	var metadata := {"schema": 3, "image": "spritesheet.png", "width": doc.width, "height": doc.height, "fps": doc.fps, "directions": Doc.DIRECTIONS, "anchors": doc.anchors, "rig": doc.rig, "animation": doc.animation, "manifest": doc.manifest, "frames": [], "map": doc.map_data}
	metadata["source_assets"] = doc.art.get("source_assets", []).duplicate(true)
	metadata["direction_coverage"] = doc.art.get("direction_coverage", Doc.DIRECTIONS).duplicate()
	metadata["three_d_motion"] = {
		"rig": doc.art.get("three_d_motion_rig", {}).duplicate(true),
		"captures": doc.art.get("three_d_motion_captures", []).duplicate(true),
	}
	var exported_model: Dictionary = metadata.three_d_motion.rig.get("model_asset", {})
	exported_model.erase("glb_base64")
	for socket in exported_model.get("equipment_sockets", {}).values():
		if socket is Dictionary and socket.get("asset") is Dictionary: socket.asset.erase("glb_base64")
	var result := _write_credits(doc, folder)
	if result != OK: return result
	for d in 8:
		for f in doc.frames:
			var frame_image: Image = doc.composite(d, f)
			sheet.blit_rect(frame_image, Rect2i(0, 0, doc.width, doc.height), Vector2i(f * doc.width, d * doc.height))
			# Runtime frames own their pixels. Filtering can never sample a neighboring action.
			frame_textures["%d:%d" % [d, f]] = ImageTexture.create_from_image(frame_image)
			metadata.frames.append({"direction": Doc.DIRECTIONS[d], "frame": f, "x": f * doc.width, "y": d * doc.height, "w": doc.width, "h": doc.height, "duration_ms": 1000.0 / doc.fps})
	result = sheet.save_png(folder.path_join("spritesheet.png"))
	if result != OK: return result
	result = doc.composite().save_png(folder.path_join("frame.png"))
	if result != OK: return result
	result = atomic_json(folder.path_join("metadata.json"), metadata)
	if result != OK: return result
	var animations: SpriteFrames
	if include_animation:
		animations = SpriteFrames.new()
		animations.remove_animation("default")
		for clip in doc.animation.clips:
			for d in 8:
				var anim: String = clip.name + "_" + Doc.DIRECTIONS[d]
				animations.add_animation(anim)
				animations.set_animation_speed(anim, 1.0)
				animations.set_animation_loop(anim, clip.loop)
				for f in clip.frames:
					animations.add_frame(anim, frame_textures["%d:%d" % [d, f]], doc.frame_seconds(int(f), clip))
		result = ResourceSaver.save(animations, folder.path_join("animations.tres"))
		if result != OK: return result
	if include_character:
		var root := Node2D.new()
		root.name = "SpriteForgeCharacter"
		var sprite := AnimatedSprite2D.new()
		sprite.name = "AnimatedSprite2D"
		sprite.sprite_frames = animations
		sprite.animation = doc.clip().name + "_" + Doc.DIRECTIONS[doc.direction]
		root.set_meta("sfs_events", doc.animation.events)
		root.set_meta("sfs_hitboxes", doc.animation.hitboxes)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		root.add_child(sprite)
		sprite.owner = root
		if profile == "playable":
			var camera_settings: Dictionary = doc.map_data.get("camera_settings", {"zoom": 2, "smoothing": 5.0, "pixel_snap": true})
			var camera := Camera2D.new()
			camera.name = "SFSFollowCamera"
			camera.enabled = true
			camera.zoom = Vector2.ONE * int(camera_settings.zoom)
			camera.position_smoothing_speed = float(camera_settings.smoothing)
			camera.position_smoothing_enabled = float(camera_settings.smoothing) > 0 and not bool(camera_settings.pixel_snap)
			camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
			camera.set_script(load("res://examples/export/pixel_camera.gd"))
			camera.set("snap_to_pixels", bool(camera_settings.pixel_snap))
			camera.limit_left = 0
			camera.limit_top = 0
			camera.limit_right = int(doc.map_data.width) * 24
			camera.limit_bottom = int(doc.map_data.height) * 24
			root.add_child(camera)
			camera.owner = root
		var scene := PackedScene.new()
		result = scene.pack(root)
		if result == OK: result = ResourceSaver.save(scene, folder.path_join("character.tscn"))
		root.free()
		if result != OK: return result
	if include_modular:
		result = _export_modular_character(doc, folder)
		if result != OK: return result
	return OK

func _write_credits(doc: RefCounted, folder: String) -> Error:
	var credits := "Sprite Forge Studio — procedência dos recursos importados\n\n"
	for source in doc.art.get("source_assets", []):
		credits += "%s\nAutor: %s\nFonte: %s\nLicença: %s\nSHA-256: %s\n%s\n\n" % [str(source.get("name", "")), str(source.get("author", "")), str(source.get("source", "")), str(source.get("license", "não informada")), str(source.get("sha256", "")), str(source.get("license_notice", ""))]
	var sockets: Dictionary = doc.art.get("three_d_motion_rig", {}).get("model_asset", {}).get("equipment_sockets", {})
	for equipment in sockets:
		var asset: Variant = sockets[equipment].get("asset", {})
		if not asset is Dictionary or asset.is_empty(): continue
		credits += "Equipamento GLB (%s): %s\nOrigem declarada: %s\nLicença declarada: %s\nSHA-256: %s\nRevisão humana pendente; a declaração não comprova os direitos.\n\n" % [equipment, str(asset.get("filename", "")), str(asset.get("source", "Não informada")), str(asset.get("license", "Não informada")), str(asset.get("sha256", ""))]
	var credits_file := FileAccess.open(folder.path_join("CREDITS.txt"), FileAccess.WRITE)
	if credits_file == null: return FileAccess.get_open_error()
	credits_file.store_string(credits)
	credits_file.close()
	return OK

func _export_modular_character(doc: RefCounted, folder: String) -> Error:
	var estimated_bytes: int = doc.width * doc.height * doc.frames * 8 * doc.layers.size() * 4
	if estimated_bytes > 67108864: return ERR_OUT_OF_MEMORY
	var layers_folder := folder.path_join("layers")
	var result := DirAccess.make_dir_recursive_absolute(layers_folder)
	if result != OK: return result
	var root := Node2D.new()
	root.name = "SpriteForgeModularCharacter"
	root.set_meta("sfs_events", doc.animation.events)
	root.set_meta("sfs_hitboxes", doc.animation.hitboxes)
	root.set_meta("sfs_direction_order", Doc.DIRECTIONS.duplicate())
	var animation_library := AnimationLibrary.new()
	var layer_manifest: Array[Dictionary] = []
	var sprite_nodes: Array[Sprite2D] = []
	for layer_index in doc.layers.size():
		var layer: Dictionary = doc.layers[layer_index]
		var atlas := Image.create(doc.width * doc.frames, doc.height * 8, false, Image.FORMAT_RGBA8)
		var layer_record := {"index": layer_index, "id": str(layer.id), "name": str(layer.name), "equipment": bool(layer.equipment), "anchor": str(layer.get("anchor", "")), "retarget_key": str(layer.get("retarget_key", "")), "visible": bool(layer.visible), "opacity": float(layer.opacity), "texture": "layers/%02d.png" % layer_index, "direction_order": Doc.DIRECTIONS.duplicate(), "frame_count": doc.frames}
		for direction in 8:
			for frame_index in doc.frames:
				var cel: Image = doc.composite_layer(layer_index, direction, frame_index, true)
				atlas.blit_rect(cel, Rect2i(0, 0, doc.width, doc.height), Vector2i(frame_index * doc.width, direction * doc.height))
		var texture_path := folder.path_join(str(layer_record.texture))
		result = atlas.save_png(texture_path)
		if result != OK: root.free(); return result
		var sprite := Sprite2D.new()
		sprite.name = "Layer_%02d" % layer_index
		sprite.texture = ImageTexture.create_from_image(atlas)
		sprite.hframes = doc.frames
		sprite.vframes = 8
		sprite.frame = doc.direction * doc.frames + doc.frame
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = bool(layer.visible) and (not bool(layer.equipment) or doc.compatible(layer))
		# Opacity is already baked into composite_layer() pixels; applying it again here would square the alpha.
		sprite.modulate.a = 1.0
		sprite.z_index = layer_index
		sprite.set_meta("sfs_layer_id", str(layer.id))
		sprite.set_meta("sfs_layer_name", str(layer.name))
		sprite.set_meta("sfs_equipment", bool(layer.equipment))
		sprite.set_meta("sfs_anchor", str(layer.get("anchor", "")))
		sprite.set_meta("sfs_opacity", float(layer.opacity))
		root.add_child(sprite)
		sprite.owner = root
		sprite_nodes.append(sprite)
		layer_manifest.append(layer_record)
	for clip in doc.animation.clips:
		for direction in 8:
			var animation_name: String = str(clip.name) + "_" + Doc.DIRECTIONS[direction]
			var animation := Animation.new()
			animation.resource_name = animation_name
			animation.loop_mode = Animation.LOOP_LINEAR if bool(clip.loop) else Animation.LOOP_NONE
			var elapsed := 0.0
			var frame_track_ids: Array[int] = []
			var depth_track_ids: Array[int] = []
			for sprite in sprite_nodes:
				var frame_track := animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(frame_track, NodePath(str(sprite.name) + ":frame"))
				animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
				frame_track_ids.append(frame_track)
				var depth_track := animation.add_track(Animation.TYPE_VALUE)
				animation.track_set_path(depth_track, NodePath(str(sprite.name) + ":z_index"))
				animation.value_track_set_update_mode(depth_track, Animation.UPDATE_DISCRETE)
				depth_track_ids.append(depth_track)
			for frame_value in clip.frames:
				var frame_index := int(frame_value)
				var cell_key: String = doc.cel_key(direction, frame_index)
				var depth: Dictionary = doc.rig.get("depth", {}).get(cell_key, {})
				for layer_index in sprite_nodes.size():
					animation.track_insert_key(frame_track_ids[layer_index], elapsed, direction * doc.frames + frame_index)
					animation.track_insert_key(depth_track_ids[layer_index], elapsed, int(depth.get(str(doc.layers[layer_index].id), layer_index)))
				elapsed += doc.frame_seconds(frame_index, clip)
			animation.length = maxf(0.001, elapsed)
			if animation_library.add_animation(animation_name, animation) != OK: root.free(); return ERR_INVALID_DATA
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", animation_library)
	player.autoplay = str(doc.clip().name) + "_" + Doc.DIRECTIONS[doc.direction]
	root.add_child(player)
	player.owner = root
	var packed := PackedScene.new()
	result = packed.pack(root)
	if result == OK: result = ResourceSaver.save(packed, folder.path_join("modular_character.tscn"))
	root.free()
	if result != OK: return result
	return atomic_json(folder.path_join("modular.json"), {"schema": 1, "canvas": [doc.width, doc.height], "directions": Doc.DIRECTIONS, "clips": doc.animation.clips, "events": doc.animation.events, "hitboxes": doc.animation.hitboxes, "layers": layer_manifest, "transforms_baked_per_cel": true, "depth_animated_per_cel": true})

func export_map(doc: RefCounted, folder: String) -> Error:
	World.sync_active_room(doc.map_data)
	var manifest_rooms: Array = []
	for i in doc.map_data.rooms.size():
		var room: Dictionary = doc.map_data.rooms[i]
		var room_doc = Doc.new()
		room_doc.map_data = room.data.duplicate(true)
		room_doc.map_data.rooms = doc.map_data.rooms
		room_doc.map_data.active_room = i
		room_doc.map_data.connections = doc.map_data.connections.duplicate(true)
		var room_folder := folder if i == int(doc.map_data.active_room) else folder.path_join("rooms").path_join(str(room.id))
		var result := DirAccess.make_dir_recursive_absolute(room_folder)
		if result != OK: return result
		result = _export_map_scene(room_doc, room_folder, str(room.id), str(room.name))
		if result != OK: return result
		manifest_rooms.append({"id": room.id, "name": room.name, "scene": "map.tscn" if i == int(doc.map_data.active_room) else "rooms/%s/map.tscn" % room.id})
	var scripts_folder := folder.path_join("examples/export")
	var script_result := DirAccess.make_dir_recursive_absolute(scripts_folder)
	if script_result != OK: return script_result
	for script_name in ["doorway.gd", "room_transition.gd", "pixel_camera.gd"]:
		var template_path: String = "res://examples/export/" + script_name + ".txt"
		var source := FileAccess.open(template_path, FileAccess.READ)
		if source == null: printerr("Script template unavailable: ", template_path, " (", error_string(FileAccess.get_open_error()), ")"); return FileAccess.get_open_error()
		var bytes := source.get_buffer(source.get_length())
		source.close()
		var destination := FileAccess.open(scripts_folder.path_join(script_name), FileAccess.WRITE)
		if destination == null: printerr("Script output unavailable: ", scripts_folder.path_join(script_name), " (", error_string(FileAccess.get_open_error()), ")"); return FileAccess.get_open_error()
		destination.store_buffer(bytes)
		destination.close()
	var navigation: Dictionary = preload("res://core/navigation.gd").new().analyze_project(doc.map_data)
	return atomic_json(folder.path_join("rooms.json"), {"schema": 1, "active_room": doc.map_data.rooms[int(doc.map_data.active_room)].id, "rooms": manifest_rooms, "connections": doc.map_data.connections, "navigation": navigation})

func _export_map_scene(doc: RefCounted, folder: String, room_id: String = "", room_name: String = "") -> Error:
	var root := Node2D.new()
	root.name = "Room_" + room_id if not room_id.is_empty() else "SpriteForgeMap"
	root.set_meta("sfs_room_id", room_id)
	root.set_meta("sfs_room_name", room_name)
	root.set_meta("sfs_camera_settings", doc.map_data.get("camera_settings", {"zoom": 2, "smoothing": 5.0, "pixel_snap": true}))
	root.set_meta("sfs_ambient_color", str(doc.map_data.get("ambient_color", "#ffffff")))
	var images: Array = doc.tile_images()
	var atlas := Image.create(24 * 16, 24 * ceili(images.size() / 16.0), false, Image.FORMAT_RGBA8)
	for i in images.size():
		var tile: Image = images[i].duplicate()
		tile.resize(24, 24, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(tile, Rect2i(0, 0, 24, 24), Vector2i(i % 16, int(i / 16)) * 24)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(24, 24)
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = Vector2i(24, 24)
	for i in images.size(): source.create_tile(Vector2i(i % 16, int(i / 16)))
	tile_set.add_source(source, 0)
	_add_terrain_sets(tile_set, source, doc.map_data, images.size())
	var ambient := CanvasModulate.new()
	ambient.name = "AmbientLight"
	ambient.color = Color(str(doc.map_data.get("ambient_color", "#ffffff")))
	root.add_child(ambient)
	ambient.owner = root
	root.set_meta("sfs_bounds", Rect2(0, 0, int(doc.map_data.width) * 24, int(doc.map_data.height) * 24))
	var layer_index: int = 0
	for data in World.layers(doc.map_data):
		var tile_layer := TileMapLayer.new()
		tile_layer.name = "Ground" if layer_index == 0 else "Layer_" + str(layer_index)
		tile_layer.tile_set = tile_set
		tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tile_layer.visible = data.visible
		tile_layer.modulate.a = float(data.opacity)
		tile_layer.z_index = layer_index
		tile_layer.set_meta("sfs_layer_id", data.id)
		tile_layer.set_meta("sfs_layer_name", data.name)
		root.add_child(tile_layer)
		tile_layer.owner = root
		for y in int(doc.map_data.height):
			for x in int(doc.map_data.width):
				var tile := int(data.cells[y * int(doc.map_data.width) + x])
				if tile >= 0 and tile < images.size(): tile_layer.set_cell(Vector2i(x, y), 0, Vector2i(tile % 16, int(tile / 16)))
		layer_index += 1
	var nav := NavigationRegion2D.new()
	nav.name = "Navigation"
	nav.navigation_polygon = preload("res://core/navigation.gd").new().polygon(doc.map_data)
	root.add_child(nav)
	nav.owner = root
	var shadows: bool = doc.map_data.light_settings.values().any(func(light): return light.shadows)
	for y in int(doc.map_data.height):
		for x in int(doc.map_data.width):
			var index: int = y * int(doc.map_data.width) + x
			if doc.map_data.collision[index]:
				var body := StaticBody2D.new()
				body.position = Vector2(x * 24 + 12, y * 24 + 12)
				root.add_child(body)
				body.owner = root
				var shape := CollisionShape2D.new()
				var rectangle := RectangleShape2D.new()
				rectangle.size = Vector2(24, 24)
				shape.shape = rectangle
				body.add_child(shape)
				shape.owner = root
				if shadows:
					var occluder := LightOccluder2D.new()
					var polygon := OccluderPolygon2D.new()
					polygon.polygon = PackedVector2Array([Vector2(-12, -12), Vector2(12, -12), Vector2(12, 12), Vector2(-12, 12)])
					occluder.occluder = polygon
					body.add_child(occluder); occluder.owner = root
	for door in doc.map_data.get("doors", []):
		var a := Vector2(int(door.a[0]) * 24 + 12, int(door.a[1]) * 24 + 12)
		var b := Vector2(int(door.b[0]) * 24 + 12, int(door.b[1]) * 24 + 12)
		_add_door_area(root, str(door.id) + "_A", str(door.name), a, b)
		_add_door_area(root, str(door.id) + "_B", str(door.name), b, a)
	for connection in doc.map_data.get("connections", []):
		for pair in [[connection.a, connection.b], [connection.b, connection.a]]:
			if pair[0].room != room_id: continue
			var from := Vector2(int(pair[0].point[0]) * 24 + 12, int(pair[0].point[1]) * 24 + 12)
			var to := Vector2(int(pair[1].point[0]) * 24 + 12, int(pair[1].point[1]) * 24 + 12)
			var target_path := "res://map.tscn" if pair[1].room == doc.map_data.rooms[int(doc.map_data.active_room)].id else "res://rooms/%s/map.tscn" % pair[1].room
			_add_door_area(root, str(connection.id) + "_" + pair[0].room, str(connection.name), from, to, target_path)
	var light_image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var intensity: float = maxf(0, 1.0 - Vector2(x - 64, y - 64).length() / 64.0)
			light_image.set_pixel(x, y, Color(intensity, intensity, intensity, 1))
	for point in doc.map_data.lights:
		var settings: Dictionary = doc.map_data.light_settings.get("%d:%d" % [int(point[0]), int(point[1])], {"color": "#ffcf8b", "energy": 1, "radius": 4, "shadows": false})
		var light := PointLight2D.new()
		light.texture = ImageTexture.create_from_image(light_image)
		light.color = Color(settings.color)
		light.energy = float(settings.energy)
		light.texture_scale = float(settings.radius) * 24 / 64
		light.shadow_enabled = settings.shadows
		light.position = Vector2(point[0] * 24 + 12, point[1] * 24 + 12)
		root.add_child(light)
		light.owner = root
	var scene := PackedScene.new()
	var result := ResourceSaver.save(tile_set, folder.path_join("tileset.tres"))
	if result != OK: root.free(); return result
	result = scene.pack(root)
	if result == OK: result = ResourceSaver.save(scene, folder.path_join("map.tscn"))
	root.free()
	return result

func _add_terrain_sets(tile_set: TileSet, source: TileSetAtlasSource, map: Dictionary, tile_count: int) -> void:
	var claimed := {}
	var neighbors := [TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER]
	for set_index in map.terrain_sets.size():
		var definition: Dictionary = map.terrain_sets[set_index]
		var blob: bool = definition.get("mode", "edge16") == "blob47"
		tile_set.add_terrain_set()
		tile_set.set_terrain_set_mode(set_index, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES if blob else TileSet.TERRAIN_MODE_MATCH_SIDES)
		tile_set.add_terrain(set_index)
		tile_set.set_terrain_name(set_index, 0, str(definition.name))
		tile_set.set_terrain_color(set_index, 0, Color.from_hsv(float(set_index) / 16.0, 0.6, 0.9))
		for position in definition.tiles.size():
			var tile := int(definition.tiles[position])
			if tile < 0 or tile >= tile_count: continue
			if claimed.has(tile): printerr("Terrain tile shared by two terrains skipped in TileSet: ", tile); continue
			claimed[tile] = true
			var mask: int = World.BLOB47_MASKS[position] if blob else position
			var data := source.get_tile_data(Vector2i(tile % 16, int(tile / 16)), 0)
			data.terrain_set = set_index
			data.terrain = 0
			for bit in (8 if blob else 4):
				if mask & (1 << bit): data.set_terrain_peering_bit(neighbors[bit if blob else bit * 2], 0)

func _add_door_area(root: Node2D, node_name: String, title: String, position: Vector2, destination: Vector2, target_scene: String = "") -> void:
	var area := Area2D.new()
	area.name = "Doorway_" + node_name
	area.position = position
	area.collision_layer = 0
	area.collision_mask = 1
	area.add_to_group("sfs_interactions", true)
	area.set_script(DoorwayScript)
	area.set("target_position", destination)
	area.set("target_scene", target_scene)
	area.set("prompt_text", title)
	area.set_meta("sfs_interaction_id", node_name)
	area.set_meta("sfs_interaction_name", title)
	root.add_child(area)
	area.owner = root
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 20)
	shape.shape = rectangle
	area.add_child(shape)
	shape.owner = root
