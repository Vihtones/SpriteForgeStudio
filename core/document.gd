extends RefCounted
## Editable document. Pixel buffers remain CPU-side; snapshots have a memory ceiling.
const DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const MAX_HISTORY_BYTES = 33554432
const MAX_SIDE = 512
const MAX_LAYER_MASK_PIXELS = 262144
const World = preload("res://core/world_data.gd")
const DEFAULT_ANCHORS = {"hand": [24, 18], "hand_l": [8, 18], "head": [16, 6], "neck": [16, 10], "chest": [16, 14], "shoulder_l": [11, 12], "elbow_l": [8, 16], "shoulder_r": [21, 12], "elbow_r": [24, 16], "pelvis": [16, 22], "hip_l": [13, 23], "foot_l": [12, 29], "hip_r": [19, 23], "feet": [16, 29], "foot_r": [20, 29], "shield_mount": [8, 17], "weapon_mount": [24, 17]}
const DEFAULT_SKELETON = [["pelvis", "chest"], ["chest", "neck"], ["neck", "head"], ["chest", "shoulder_l"], ["shoulder_l", "elbow_l"], ["elbow_l", "hand_l"], ["chest", "shoulder_r"], ["shoulder_r", "elbow_r"], ["elbow_r", "hand"], ["pelvis", "hip_l"], ["hip_l", "foot_l"], ["pelvis", "hip_r"], ["hip_r", "foot_r"]]
var width: int = 32
var height: int = 32
var frames: int = 4
var fps: int = 8
var direction: int = 0
var frame: int = 0
var active_layer: int = 0
var layers: Array = []
var palette: Array = ["#191b32", "#34496b", "#75b5ad", "#e9d8a6", "#e69c69", "#bd536b", "#6e4d87", "#f5eee4"]
var anchors: Dictionary = DEFAULT_ANCHORS.duplicate(true)
var selection: Rect2i = Rect2i()
var art: Dictionary = {"bible": "Silhuetas legíveis, luz superior esquerda, paleta restrita.", "locked": false, "references": [], "memory": [], "candidates": []}
var map_data: Dictionary = {"width": 24, "height": 16, "cells": [], "collision": [], "lights": []}
var undo_stack: Array = []
var redo_stack: Array = []
var dirty: bool = false
var revision: int = 0
var manifest: Dictionary = {"id": "", "name": "Sem título", "art_bible_version": 1, "godot": "4.7.2", "export_profile": "animated", "dependencies": [], "approvals": []}
var rig: Dictionary = {"family": "humanoid", "anchors": {}, "depth": {}, "rotations": {}, "skeleton": DEFAULT_SKELETON.duplicate(true)}
var animation: Dictionary = {"active": 0, "clips": [{"name": "walk", "frames": [0, 1, 2, 3], "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
var clipboard: Image
var pixel_budget_limit: int = 67108864

func _init() -> void:
	manifest.id = Crypto.new().generate_random_bytes(16).hex_encode()
	add_layer("Corpo")
	map_data.cells.resize(384)
	map_data.cells.fill(-1)
	map_data.collision.resize(384)
	map_data.collision.fill(false)
	World.normalize(map_data)
	dirty = false

func initialize_blank(canvas_width: int, canvas_height: int, frame_count: int, frame_rate: int) -> bool:
	if canvas_width < 8 or canvas_width > MAX_SIDE or canvas_height < 8 or canvas_height > MAX_SIDE or frame_count < 1 or frame_count > 32 or frame_rate < 1 or frame_rate > 60:
		return false
	var required_bytes: int = canvas_width * canvas_height * 4 * frame_count * 8
	if required_bytes > pixel_budget_limit: return false
	width = canvas_width
	height = canvas_height
	frames = frame_count
	fps = frame_rate
	direction = 0
	frame = 0
	selection = Rect2i()
	anchors = DEFAULT_ANCHORS.duplicate(true)
	for key in anchors:
		var point: Array = anchors[key]
		anchors[key] = [roundi(float(point[0]) * (width - 1) / 31.0), roundi(float(point[1]) * (height - 1) / 31.0)]
	layers.clear()
	if not add_layer("Corpo"): return false
	active_layer = 0
	animation = {"active": 0, "clips": [{"name": "walk", "frames": Array(range(frames)), "durations_ms": {}, "loop": true}], "events": {}, "hitboxes": {}}
	rig.anchors.clear()
	rig.depth.clear()
	rig.rotations.clear()
	dirty = true
	return validate().is_empty()

func blank() -> Image:
	return Image.create(width, height, false, Image.FORMAT_RGBA8)

func tile_images() -> Array:
	var result: Array = []
	if map_data.has("tileset_png"):
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(map_data.tileset_png)) == OK:
			for y in int(image.get_height() / 16):
				for x in int(image.get_width() / 16): result.append(image.get_region(Rect2i(x * 16, y * 16, 16, 16)))
	else:
		for d in 8:
			for f in frames: result.append(composite(d, f))
	return result

func add_layer(title: String, equipment: bool = false) -> bool:
	if layers.size() >= 16 or width * height * 4 * frames * 8 * (layers.size() + 1) > pixel_budget_limit: return false
	var cels: Array = []
	for d in 8:
		var row: Array = []
		for f in frames:
			row.append(blank())
		cels.append(row)
	layers.append({"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": title, "retarget_key": title.strip_edges().to_lower(), "visible": true, "locked": false, "opacity": 1.0, "equipment": equipment, "asymmetric": false, "families": [rig.family], "anchor": "hand", "pivot": "feet", "bone": [], "offset": [0, 0], "cels": cels})
	active_layer = layers.size() - 1
	return true

func current() -> Image:
	return layers[active_layer].cels[direction][frame]

func composite(d: int = -1, f: int = -1) -> Image:
	if d < 0: d = direction
	if f < 0: f = frame
	var result: Image = blank()
	var ordered: Array = []
	for index in layers.size(): ordered.append(index)
	var depth: Dictionary = rig.depth.get(cel_key(d, f), {})
	ordered.sort_custom(func(a, b):
		var ra: int = int(depth.get(layers[a].id, a))
		var rb: int = int(depth.get(layers[b].id, b))
		return ra < rb if ra != rb else a < b
	)
	for index in ordered:
		result.blend_rect(composite_layer(index, d, f), Rect2i(0, 0, width, height), Vector2i.ZERO)
	return result

func composite_layer(index: int, d: int = -1, f: int = -1, include_hidden: bool = false) -> Image:
	## Render one layer into a transparent canvas with the same transform rules as composite().
	var result: Image = blank()
	if index < 0 or index >= layers.size(): return result
	if d < 0: d = direction
	if f < 0: f = frame
	if d < 0 or d >= 8 or f < 0 or f >= frames: return result
	var layer: Dictionary = layers[index]
	if not include_hidden and (not layer.visible or (layer.equipment and not compatible(layer))): return result
	var source: Image = masked_layer_cel(index, d, f)
	var angle: float = float(rig.get("rotations", {}).get(cel_key(d, f), {}).get(layer.id, 0.0))
	if absf(angle) >= 0.01:
		var pivot_name: String = str(layer.get("pivot", layer.get("anchor", "feet")))
		var pivot: Array = anchor_at(pivot_name, d, f)
		source = rotate_layer(source, Vector2i(int(pivot[0]), int(pivot[1])), angle)
	if float(layer.opacity) < 1.0:
		source = source.duplicate()
		for y in height:
			for x in width:
				var color: Color = source.get_pixel(x, y)
				color.a *= float(layer.opacity)
				source.set_pixel(x, y, color)
	result.blend_rect(source, Rect2i(0, 0, width, height), layer_offset(index, d, f))
	return result

func masked_layer_cel(index: int, d: int, f: int) -> Image:
	var source: Image = layers[index].cels[d][f]
	var hidden: Array = layers[index].get("visibility_masks", {}).get(cel_key(d, f), [])
	if hidden.is_empty(): return source
	var masked := source.duplicate()
	for pixel_index in hidden: masked.set_pixel(int(pixel_index) % width, int(int(pixel_index) / width), Color.TRANSPARENT)
	return masked

func layer_mask_pixels() -> int:
	var count := 0
	for layer in layers:
		for hidden in layer.get("visibility_masks", {}).values(): count += hidden.size()
	return count

func mask_pixels_at_frame(target_frame: int) -> int:
	var count := 0
	for layer in layers:
		for d in 8: count += layer.get("visibility_masks", {}).get(cel_key(d, target_frame), []).size()
	return count

func edit_layer_mask(mode: String) -> bool:
	if mode not in ["hide", "reveal", "clear"] or art.get("locked", false) or layers[active_layer].locked: return false
	var layer: Dictionary = layers[active_layer]
	if mode != "clear" and (selection.size == Vector2i.ZERO or absf(layer_rotation(str(layer.id))) >= 0.01 or layer_offset() != Vector2i.ZERO): return false
	var masks: Dictionary = layer.get("visibility_masks", {})
	var previous: Array = masks.get(cel_key(), [])
	var hidden := {}
	if mode == "clear":
		for pixel_index in previous:
			if rig.get("protected_pixels", {}).get(cel_key(), []).has(int(pixel_index)): hidden[int(pixel_index)] = true
	if mode != "clear":
		for pixel_index in previous: hidden[int(pixel_index)] = true
		var region := selection.intersection(Rect2i(0, 0, width, height))
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				if rig.get("protected_pixels", {}).get(cel_key(), []).has(y * width + x): continue
				if mode == "hide": hidden[y * width + x] = true
				else: hidden.erase(y * width + x)
	var next: Array = hidden.keys()
	next.sort()
	var sorted_previous := previous.duplicate(); sorted_previous.sort()
	if next == sorted_previous or layer_mask_pixels() - previous.size() + next.size() > MAX_LAYER_MASK_PIXELS: return false
	checkpoint("Máscara de visibilidade da camada")
	if not layer.has("visibility_masks"): layer.visibility_masks = {}
	if next.is_empty(): layer.visibility_masks.erase(cel_key())
	else: layer.visibility_masks[cel_key()] = next
	art["pose_approvals"] = []
	manifest.approvals = []
	if str(art.get("status", "candidate")) != "rejected": art["status"] = "candidate"
	return true

func rotate_layer(source: Image, pivot: Vector2i, degrees: float) -> Image:
	if source.is_empty() or absf(degrees) < 0.01: return source
	var used := source.get_used_rect()
	if used.size == Vector2i.ZERO: return source
	var center := Vector2(pivot) + Vector2(0.5, 0.5)
	var radians := deg_to_rad(degrees)
	var corners := [Vector2(used.position), Vector2(used.end.x, used.position.y), Vector2(used.position.x, used.end.y), Vector2(used.end)]
	var min_x := source.get_width()
	var min_y := source.get_height()
	var max_x := 0
	var max_y := 0
	for corner in corners:
		var rotated: Vector2 = center + (corner - center).rotated(radians)
		min_x = mini(min_x, floori(rotated.x))
		min_y = mini(min_y, floori(rotated.y))
		max_x = maxi(max_x, ceili(rotated.x))
		max_y = maxi(max_y, ceili(rotated.y))
	min_x = clampi(min_x, 0, source.get_width())
	min_y = clampi(min_y, 0, source.get_height())
	max_x = clampi(max_x, 0, source.get_width())
	max_y = clampi(max_y, 0, source.get_height())
	var result := blank()
	for y in range(min_y, max_y):
		for x in range(min_x, max_x):
			var sample: Vector2 = center + (Vector2(x, y) + Vector2(0.5, 0.5) - center).rotated(-radians)
			var sx := floori(sample.x)
			var sy := floori(sample.y)
			if sx >= used.position.x and sy >= used.position.y and sx < used.end.x and sy < used.end.y:
				var color := source.get_pixel(sx, sy)
				if color.a > 0.0: result.set_pixel(x, y, color)
	return result

func layer_rotation(layer_id: String, d: int = -1, f: int = -1) -> float:
	return float(rig.get("rotations", {}).get(cel_key(d, f), {}).get(layer_id, 0.0))

func set_layer_rotation(layer_id: String, degrees: float, d: int = -1, f: int = -1, make_checkpoint: bool = true) -> bool:
	if not is_finite(degrees) or degrees < -180.0 or degrees > 180.0: return false
	var key := cel_key(d, f)
	if is_equal_approx(layer_rotation(layer_id, d, f), degrees): return false
	if make_checkpoint: checkpoint("Girar camada")
	if not rig.has("rotations"): rig.rotations = {}
	if not rig.rotations.has(key): rig.rotations[key] = {}
	if absf(degrees) < 0.01: rig.rotations[key].erase(layer_id)
	else: rig.rotations[key][layer_id] = degrees
	if rig.rotations[key].is_empty(): rig.rotations.erase(key)
	return true

func mark_rig_pose_key(layer_id: String, anchor_name: String, d: int = -1, f: int = -1) -> bool:
	var target_direction := direction if d < 0 else d
	var target_frame := frame if f < 0 else f
	if d < -1 or f < -1 or target_direction < 0 or target_direction >= 8 or target_frame < 0 or target_frame >= frames: return false
	var layer_index := -1
	for index in layers.size():
		if str(layers[index].id) == layer_id:
			layer_index = index
			break
	if layer_index < 0 or not anchors.has(anchor_name): return false
	var layer: Dictionary = layers[layer_index]
	var key := cel_key(d, f)
	var needs_rotation: bool = not rig.get("rotations", {}).get(key, {}).has(layer_id)
	var needs_offset: bool = layer.equipment and not rig.get("offsets", {}).get(key, {}).has(layer_id)
	var needs_anchor: bool = not rig.get("anchors", {}).get(key, {}).has(anchor_name)
	if not needs_rotation and not needs_offset and not needs_anchor: return false
	checkpoint("Marcar pose-chave do rig")
	if not rig.has("rotations"): rig.rotations = {}
	if not rig.rotations.has(key): rig.rotations[key] = {}
	rig.rotations[key][layer_id] = layer_rotation(layer_id, d, f)
	if layer.equipment:
		if not rig.has("offsets"): rig.offsets = {}
		if not rig.offsets.has(key): rig.offsets[key] = {}
		rig.offsets[key][layer_id] = rig.offsets.get(key, {}).get(layer_id, layer.offset.duplicate(true))
	if not rig.has("anchors"): rig.anchors = {}
	if not rig.anchors.has(key): rig.anchors[key] = {}
	var point: Array = anchor_at(anchor_name, d, f).duplicate(true)
	rig.anchors[key][anchor_name] = point
	return true

func set_layer_bone(layer_id: String, segment: Array) -> bool:
	if not segment.is_empty() and (segment.size() != 2 or not segment[0] is String or not segment[1] is String or segment[0] == segment[1]): return false
	if not segment.is_empty():
		if not anchors.has(segment[0]) or not anchors.has(segment[1]) or not rig.get("skeleton", []).has(segment): return false
	var layer_index := -1
	for index in layers.size():
		if str(layers[index].id) == layer_id:
			layer_index = index
			break
	if layer_index < 0: return false
	var layer: Dictionary = layers[layer_index]
	if layer.get("bone", []).duplicate(true) == segment and (segment.is_empty() or str(layer.get("pivot", "")) == str(segment[0])): return false
	checkpoint("Mapear camada ao osso")
	layer.bone = segment.duplicate(true)
	if not segment.is_empty(): layer.pivot = str(segment[0])
	return true

func snapshot() -> Dictionary:
	var copy: Array = []
	for layer in layers:
		var l: Dictionary = layer.duplicate(true)
		l.cels = []
		for row in layer.cels:
			var images: Array = []
			for img in row: images.append(img.duplicate())
			l.cels.append(images)
		copy.append(l)
	return {"layers": copy, "width": width, "height": height, "frames": frames, "fps": fps, "frame": frame, "direction": direction, "selection": selection, "active": active_layer, "anchors": anchors.duplicate(true), "map": map_data.duplicate(true), "art": art.duplicate(true), "palette": palette.duplicate(), "rig": rig.duplicate(true), "animation": animation.duplicate(true), "manifest": manifest.duplicate(true), "bytes": memory_bytes()}

func checkpoint(label: String = "Edição") -> void:
	var state := snapshot()
	state.label = label
	undo_stack.append(state)
	while undo_stack.size() > 1 and undo_stack.reduce(func(total, s): return total + s.bytes, 0) > MAX_HISTORY_BYTES:
		undo_stack.pop_front()
	redo_stack.clear()
	mark_changed()

func mark_changed() -> void:
	dirty = true
	revision += 1

func restore(s: Dictionary) -> void:
	width = int(s.get("width", width))
	height = int(s.get("height", height))
	layers = s.layers
	frames = s.frames
	fps = s.fps
	active_layer = s.active
	anchors = s.anchors
	map_data = s.map
	art = s.art
	palette = s.palette
	rig = s.rig
	animation = s.animation
	manifest = s.manifest
	frame = mini(int(s.get("frame", frame)), frames - 1)
	direction = int(s.get("direction", direction))
	selection = s.get("selection", Rect2i())
	mark_changed()

func undo() -> bool:
	if undo_stack.is_empty(): return false
	var state: Dictionary = undo_stack.pop_back()
	var present := snapshot()
	present.label = state.get("label", "Edição")
	redo_stack.append(present)
	restore(state)
	return true

func redo() -> bool:
	if redo_stack.is_empty(): return false
	var state: Dictionary = redo_stack.pop_back()
	var present := snapshot()
	present.label = state.get("label", "Edição")
	undo_stack.append(present)
	restore(state)
	return true

func allowed(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height and (selection.size == Vector2i.ZERO or selection.has_point(p)) and not rig.get("protected_pixels", {}).get(cel_key(), []).has(p.y * width + p.x)

func pixel(p: Vector2i, color: Color, mirror: bool = false, size: int = 1) -> void:
	if layers[active_layer].locked: return
	for dy in size:
		for dx in size:
			var radius := floori(size / 2.0)
			var q := p + Vector2i(dx - radius, dy - radius)
			if allowed(q): current().set_pixelv(q, color)
			var reflected := Vector2i(width - 1 - q.x, q.y)
			if mirror and not layers[active_layer].get("asymmetric", false) and allowed(reflected): current().set_pixelv(reflected, color)

func line(a: Vector2i, b: Vector2i, color: Color, mirror: bool = false, size: int = 1) -> void:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in steps + 1:
		var t: float = float(i) / maxi(1, steps)
		pixel(Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))), color, mirror, size)

func flood(start: Vector2i, color: Color) -> void:
	if not allowed(start) or layers[active_layer].locked: return
	var old: Color = current().get_pixelv(start)
	if old == color: return
	var pending: Array[Vector2i] = [start]
	while not pending.is_empty():
		var p: Vector2i = pending.pop_back()
		if not allowed(p) or current().get_pixelv(p) != old: continue
		current().set_pixelv(p, color)
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: pending.append(p + delta)

func insert_frame_after(source_frame: int, make_checkpoint: bool = true) -> int:
	## Inserts a duplicate of one frame across all directions/layers and remaps every
	## frame-indexed document track. Returns the new frame index, or -1 on refusal.
	if source_frame < 0 or source_frame >= frames or frames >= 32 or layers.is_empty(): return -1
	if width * height * 4 * (frames + 1) * 8 * layers.size() > pixel_budget_limit: return -1
	var added_masks := mask_pixels_at_frame(source_frame)
	if layer_mask_pixels() + added_masks > MAX_LAYER_MASK_PIXELS: return -1
	if make_checkpoint: checkpoint("Inserir frame")
	for layer in layers:
		for row in layer.cels: row.insert(source_frame + 1, row[source_frame].duplicate())
	frames += 1
	remap_frames(source_frame, true)
	frame = source_frame + 1
	return frame

func duplicate_frame() -> bool:
	return insert_frame_after(frame, true) >= 0

func delete_frame() -> void:
	if frames == 1: return
	checkpoint("Remover frame")
	for l in layers:
		for row in l.cels: row.remove_at(frame)
	remap_frames(frame, false)
	frames -= 1
	frame = mini(frame, frames - 1)
	if not map_data.has("tileset_png"):
		for buffer in World.tile_buffers(map_data):
			for i in buffer.size():
				if buffer[i] >= frames * 8: buffer[i] = -1

func extend_clip_with_holds(clip_name: String, extra_frames: int = 2) -> bool:
	## Adds visible timing poses by holding the clip's final source pose. This keeps
	## anatomy pixel-stable and makes no false claim of hand-drawn in-betweens.
	if extra_frames < 1 or extra_frames > 8 or frames + extra_frames > 32: return false
	var clip_index := -1
	for i in animation.clips.size():
		if str(animation.clips[i].name) == clip_name: clip_index = i; break
	if clip_index < 0: return false
	var target: Dictionary = animation.clips[clip_index]
	if target.frames.is_empty(): return false
	if width * height * 4 * (frames + extra_frames) * 8 * layers.size() > pixel_budget_limit: return false
	var source_pose_frame := int(target.frames[-1])
	if layer_mask_pixels() + mask_pixels_at_frame(source_pose_frame) * extra_frames > MAX_LAYER_MASK_PIXELS: return false
	var source_duration := float(target.durations_ms.get(str(source_pose_frame), 1000.0 / fps))
	var hold_duration := floorf(source_duration / float(extra_frames + 1))
	var source_residual := source_duration - hold_duration * extra_frames
	for i in extra_frames:
		animation.active = clip_index
		frame = int(target.frames[-1])
		if not duplicate_frame(): return false
		# duplicate_frame remaps frame references in every clip and includes the new
		# hold in the active clip; subsequent clips retain their original pose mapping.
		target = animation.clips[clip_index]
		var inserted := frame
		target.durations_ms[str(source_pose_frame)] = source_residual
		target.durations_ms[str(inserted)] = hold_duration
		animation.clips[clip_index] = target
	return true

func demo() -> void:
	var tiles := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			var shade: int = posmod(x * 31 + y * 17, 9)
			var c := Color("42546a") if x < 16 else Color("2b5147")
			if x < 16:
				if y % 8 == 0 or (x + (8 if y >= 8 else 0)) % 16 == 0: c = Color("25354b")
				elif shade == 0: c = Color("5a6d80")
			elif shade == 0: c = Color("426654")
			tiles.set_pixel(x, y, c)
	map_data.tileset_png = Marshalls.raw_to_base64(tiles.save_png_to_buffer())
	for d in 8:
		for f in frames:
			var img: Image = layers[0].cels[d][f]
			var bob: int = f % 2
			img.fill_rect(Rect2i(11, 6 + bob, 10, 9), Color(palette[3]))
			img.fill_rect(Rect2i(10, 15 + bob, 12, 10), Color(palette[2]))
			img.fill_rect(Rect2i(10, 25, 4, 5 - bob), Color(palette[1]))
			img.fill_rect(Rect2i(18, 25, 4, 5 - (1 - bob)), Color(palette[1]))
			img.fill_rect(Rect2i(8, 16 + bob, 2, 8), Color(palette[4]))
			img.fill_rect(Rect2i(22, 16 + bob, 2, 8), Color(palette[4]))
			img.fill_rect(Rect2i(11, 5 + bob, 10, 3), Color(palette[0]))
			if d not in [7, 0, 1]:
				img.set_pixel(13 if d < 4 else 18, 10 + bob, Color(palette[0]))
	for y in 16:
		for x in 24:
			if y == 0 or x == 0 or y == 15 or x == 23:
				map_data.cells[y * 24 + x] = 0
				map_data.collision[y * 24 + x] = true
			else: map_data.cells[y * 24 + x] = 1
	map_data.lights = [[5, 4], [18, 10]]

func validate() -> Array[String]:
	var issues: Array[String] = []
	if not art.get("source_assets", []) is Array: issues.append("Procedência de recursos inválida")
	else:
		for source in art.get("source_assets", []):
			if not source is Dictionary: issues.append("Registro de procedência inválido")
	var tile_count: int = frames * 8
	if map_data.has("tileset_png"):
		var tiles := Image.new()
		if tiles.load_png_from_buffer(Marshalls.base64_to_raw(map_data.tileset_png)) != OK or tiles.get_width() < 16 or tiles.get_height() < 16 or tiles.get_width() > 256 or tiles.get_height() > 256 or tiles.get_width() % 16 != 0 or tiles.get_height() % 16 != 0: issues.append("Tileset inválido")
		else: tile_count = int(tiles.get_width() / 16) * int(tiles.get_height() / 16)
	if not World.valid(map_data, tile_count) or memory_bytes() > pixel_budget_limit: issues.append("Mapa, salas, camadas, terreno, luzes ou orçamento inválidos")
	if not preload("res://core/contracts.gd").valid_extensions({"manifest": manifest, "rig": rig, "animation": animation, "anchors": anchors, "layers": layers, "frames": frames, "width": width, "height": height}): issues.append("Contratos de manifesto, rig ou animação inválidos")
	if layers.is_empty(): issues.append("Documento sem camadas")
	for l in layers:
		if l.equipment and l.visible and not compatible(l): issues.append("Equipamento incompatível com família/morfologia/pose: " + l.name)
		if l.cels.size() != 8: issues.append("Direções ausentes: " + str(l.name))
		for row in l.cels:
			if row.size() != frames: issues.append("Frames inconsistentes")
			for img in row:
				if img.get_size() != Vector2i(width, height): issues.append("Dimensão de cel inválida")
	for key in anchors:
		var a: Array = anchors[key]
		if a[0] < 0 or a[1] < 0 or a[0] >= width or a[1] >= height: issues.append("Âncora fora do quadro: " + key)
	return issues

func cel_key(d: int = -1, f: int = -1) -> String:
	return "%d:%d" % [direction if d < 0 else d, frame if f < 0 else f]

func anchor_at(name: String, d: int = -1, f: int = -1) -> Array:
	var per_cell: Dictionary = rig.anchors.get(cel_key(d, f), {})
	if per_cell.has(name): return per_cell[name]
	if anchors.has(name): return anchors[name]
	if name == "shield_mount": return [roundi(width * 0.25), roundi(height * 0.53)]
	if name == "weapon_mount": return [roundi(width * 0.75), roundi(height * 0.53)]
	return [0, 0]

func set_anchor(name: String, point: Vector2i) -> void:
	if not anchors.has(name) or point.x < 0 or point.y < 0 or point.x >= width or point.y >= height: return
	checkpoint("Mover âncora")
	var key := cel_key()
	if not rig.anchors.has(key): rig.anchors[key] = {}
	rig.anchors[key][name] = [point.x, point.y]

func add_anchor(name: String, point: Vector2i) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9_-]{0,23}$")
	if anchors.size() >= 32 or pattern.search(name) == null or anchors.has(name): return false
	if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height: return false
	checkpoint("Adicionar articulação")
	anchors[name] = [point.x, point.y]
	return true

func remove_anchor(name: String) -> bool:
	if not anchors.has(name) or DEFAULT_ANCHORS.has(name): return false
	for layer in layers:
		if layer.anchor == name: return false
	checkpoint("Remover articulação")
	anchors.erase(name)
	for values in rig.anchors.values(): values.erase(name)
	return true

func clip() -> Dictionary:
	return animation.clips[int(animation.active)]

func frame_seconds(f: int = -1, target_clip: Dictionary = {}) -> float:
	var c: Dictionary = clip() if target_clip.is_empty() else target_clip
	return float(c.durations_ms.get(str(frame if f < 0 else f), 1000.0 / fps)) / 1000.0

func add_clip(name: String, first: int, last_frame: int) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,40}$")
	if animation.clips.size() >= 32 or pattern.search(name) == null or first < 0 or last_frame < first or last_frame >= frames: return false
	for c in animation.clips:
		if c.name == name: return false
	checkpoint()
	animation.clips.append({"name": name, "frames": range(clampi(first, 0, frames - 1), clampi(last_frame, first, frames - 1) + 1), "durations_ms": {}, "loop": true})
	animation.active = animation.clips.size() - 1
	return true

func duplicate_clip() -> bool:
	if animation.clips.size() >= 32: return false
	var source: Dictionary = clip()
	var stem: String = str(source.name).left(34)
	var candidate := stem + "_copy"
	var suffix := 2
	while animation.clips.any(func(item): return item.name == candidate):
		candidate = stem.left(40 - str(suffix).length() - 1) + "_" + str(suffix)
		suffix += 1
	checkpoint("Duplicar clip")
	var duplicate: Dictionary = source.duplicate(true)
	duplicate.name = candidate
	animation.clips.insert(animation.active + 1, duplicate)
	animation.active += 1
	return true

func rename_clip(name: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]{1,40}$")
	if pattern.search(name) == null: return false
	for i in animation.clips.size():
		if i != animation.active and animation.clips[i].name == name: return false
	if clip().name == name: return false
	checkpoint("Renomear clip")
	clip().name = name
	return true

func delete_clip() -> bool:
	if animation.clips.size() <= 1: return false
	checkpoint("Remover clip")
	animation.clips.remove_at(animation.active)
	animation.active = mini(animation.active, animation.clips.size() - 1)
	frame = int(clip().frames[0])
	return true

func remap_frames(changed: int, insert: bool) -> void:
	if not map_data.has("tileset_png"):
		var previous: int = frames - 1 if insert else frames
		var next_count: int = previous + (1 if insert else -1)
		for buffer in World.tile_buffers(map_data):
			for i in buffer.size():
				var tile: int = int(buffer[i])
				if tile < 0: continue
				var f: int = tile % previous
				buffer[i] = -1 if not insert and f == changed else int(tile / previous) * next_count + f + ((1 if insert else -1) if f > changed else 0)
	for i in animation.clips.size():
		var c: Dictionary = animation.clips[i]
		var mapped: Array = []
		for f in c.frames:
			if insert:
				mapped.append(int(f) + (1 if f > changed else 0))
				if f == changed and i == animation.active: mapped.append(changed + 1)
			elif f != changed: mapped.append(int(f) - (1 if f > changed else 0))
		if mapped.is_empty(): mapped = [0]
		c.frames = mapped
		var durations := {}
		for key in c.durations_ms:
			var f := int(key)
			if not insert and f == changed: continue
			durations[str(f + ((1 if insert else -1) if f > changed else 0))] = c.durations_ms[key]
		c.durations_ms = durations
	var remap_targets: Array = [rig.anchors, rig.depth, rig.get("offsets", {}), rig.get("rotations", {}), rig.get("protected_pixels", {}), animation.events, animation.hitboxes]
	for layer in layers:
		remap_targets.append(layer.get("visibility_masks", {}))
		if layer.get("effect") is Dictionary:
			remap_targets.append(layer.effect.get("baseline", {}))
			var effect_frames: Array = []
			for f in layer.effect.get("frames", []):
				if not insert and int(f) == changed: continue
				effect_frames.append(int(f) + ((1 if insert else -1) if int(f) > changed else 0))
				if insert and int(f) == changed: effect_frames.append(changed + 1)
			if effect_frames.is_empty(): layer.erase("effect")
			else: layer.effect.frames = effect_frames
	for target in remap_targets:
		var mapped := {}
		for key in target:
			var parts: PackedStringArray = key.split(":")
			var f := int(parts[1])
			if not insert and f == changed: continue
			var next: int = f + ((1 if insert else -1) if f > changed else 0)
			mapped[parts[0] + ":" + str(next)] = target[key]
			if insert and f == changed: mapped[parts[0] + ":" + str(changed + 1)] = target[key].duplicate(true) if target[key] is Dictionary or target[key] is Array else target[key]
		target.clear()
		target.merge(mapped)

func selected_rect() -> Rect2i:
	return selection if selection.size != Vector2i.ZERO else Rect2i(0, 0, width, height)

func copy_pixels() -> void:
	clipboard = current().get_region(selected_rect())

func paste_pixels() -> bool:
	if clipboard == null or layers[active_layer].locked: return false
	checkpoint("Colar pixels")
	var target := selected_rect().position
	for y in clipboard.get_height():
		for x in clipboard.get_width():
			var p := target + Vector2i(x, y)
			if allowed(p): current().set_pixelv(p, clipboard.get_pixel(x, y))
	return true

func transform_pixels(operation: String, offset: Vector2i = Vector2i.ZERO) -> bool:
	if layers[active_layer].locked or operation not in ["flip_x", "flip_y", "rotate", "move", "clear"]: return false
	var rect := selected_rect()
	var source: Image = current().get_region(rect)
	if operation == "rotate" and rect.size.x != rect.size.y: return false
	for index in rig.get("protected_pixels", {}).get(cel_key(), []):
		var p := Vector2i(int(index) % width, int(int(index) / width))
		if rect.has_point(p) or Rect2i(rect.position + offset, rect.size).has_point(p): return false
	checkpoint({"flip_x": "Espelhar horizontal", "flip_y": "Espelhar vertical", "rotate": "Girar 90°", "move": "Mover seleção", "clear": "Limpar seleção"}[operation])
	current().fill_rect(rect, Color.TRANSPARENT)
	match operation:
		"flip_x": source.flip_x()
		"flip_y": source.flip_y()
		"rotate": source.rotate_90(CLOCKWISE)
		"clear": return true
	var destination := rect.position + offset
	# Move is allowed beyond the source selection, but never beyond the image.
	current().blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), destination)
	if operation == "move": selection = Rect2i(destination, rect.size).intersection(Rect2i(0, 0, width, height))
	return true

func protect_selection(clear: bool = false) -> void:
	checkpoint()
	if not rig.has("protected_pixels"): rig.protected_pixels = {}
	if clear:
		rig.protected_pixels.erase(cel_key())
		return
	var indices: Array = rig.protected_pixels.get(cel_key(), [])
	var rect := selected_rect()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i: int = y * width + x
			if not indices.has(i): indices.append(i)
	rig.protected_pixels[cel_key()] = indices

func compatible(layer: Dictionary) -> bool:
	if not layer.get("families", ["humanoid"]).has(rig.family): return false
	var required: Dictionary = layer.get("compatibility", {})
	for key in ["morphology", "pose", "version"]:
		if required.has(key) and required[key] != rig.get(key, ""): return false
	return true

func pixel_bytes() -> int:
	return width * height * 4 * frames * 8 * layers.size()

func memory_bytes() -> int:
	return pixel_bytes() + World.project_bytes(map_data) + layer_mask_pixels() * 16

func layer_offset(index: int = -1, d: int = -1, f: int = -1) -> Vector2i:
	var layer: Dictionary = layers[active_layer if index < 0 else index]
	if not layer.equipment: return Vector2i.ZERO
	var anchor: Array = anchor_at(layer.anchor, d, f)
	var local: Array = rig.get("offsets", {}).get(cel_key(d, f), {}).get(layer.id, layer.offset)
	return Vector2i(int(anchor[0]), int(anchor[1])) + Vector2i(int(local[0]), int(local[1]))

func bake_layer_pose(layer_id: String, d: int = -1, f: int = -1) -> bool:
	## Commits the current rigid transform into one cel while preserving its screen-space composite.
	var target_direction := direction if d < 0 else d
	var target_frame := frame if f < 0 else f
	if d < -1 or f < -1 or target_direction < 0 or target_direction >= 8 or target_frame < 0 or target_frame >= frames or art.get("locked", false): return false
	var layer_index := -1
	for index in layers.size():
		if str(layers[index].id) == layer_id: layer_index = index; break
	if layer_index < 0 or bool(layers[layer_index].locked): return false
	var layer: Dictionary = layers[layer_index]
	if not layer.visible or (layer.equipment and not compatible(layer)): return false
	var key := cel_key(target_direction, target_frame)
	var angle := layer_rotation(layer_id, target_direction, target_frame)
	var offset := layer_offset(layer_index, target_direction, target_frame)
	if absf(angle) < 0.01 and offset == Vector2i.ZERO: return false
	# Protection is cel-scoped rather than layer-scoped. Refuse to move any art when
	# protected coordinates exist because ownership cannot be preserved unambiguously.
	if not rig.get("protected_pixels", {}).get(key, []).is_empty(): return false
	if not layer.get("visibility_masks", {}).get(key, []).is_empty(): return false
	var source: Image = layer.cels[target_direction][target_frame]
	var pivot_name: String = str(layer.get("pivot", layer.get("anchor", "feet")))
	if not anchors.has(pivot_name): return false
	var pivot: Array = anchor_at(pivot_name, target_direction, target_frame)
	var transformed := rotate_layer(source, Vector2i(int(pivot[0]), int(pivot[1])), angle)
	var baked := blank()
	baked.blend_rect(transformed, Rect2i(0, 0, width, height), offset)
	var neutral_offset := [0, 0]
	if layer.equipment:
		var equipment_anchor: Array = anchor_at(str(layer.get("anchor", "hand")), target_direction, target_frame)
		neutral_offset = [-int(equipment_anchor[0]), -int(equipment_anchor[1])]
	checkpoint("Aplicar pose à camada")
	layer.cels[target_direction][target_frame] = baked
	if rig.has("rotations") and rig.rotations.has(key):
		rig.rotations[key].erase(layer_id)
		if rig.rotations[key].is_empty(): rig.rotations.erase(key)
	if layer.equipment:
		if not rig.has("offsets"): rig.offsets = {}
		if not rig.offsets.has(key): rig.offsets[key] = {}
		rig.offsets[key][layer_id] = neutral_offset
	mark_changed()
	return true

func detached_copy() -> RefCounted:
	var copy = get_script().new()
	copy.width = width
	copy.height = height
	copy.restore(snapshot())
	copy.revision = revision
	copy.dirty = dirty
	copy.undo_stack.clear()
	copy.redo_stack.clear()
	return copy
