extends Control
signal edited
signal message(text: String)
signal room_changed
const World = preload("res://core/world_data.gd")
var doc: RefCounted
var mode: String = "Tile"
var door_name: String = "Porta"
var brush: String = "Lápis"
var tile: int = 0
var terrain: int = -1
var light: Dictionary = {"color": "#ffcf8b", "energy": 1.0, "radius": 4.0, "shadows": false}
var playing: bool = false
var player := Vector2(160, 120)
var camera_focus := Vector2(160, 120)
var editor_zoom := 1.0
var anim_frame: int = 0
var facing: int = 0
var painting: bool = false
var panning: bool = false
var textures: Array = []
var character_textures: Array = []
var character_texture: ImageTexture
var clock = preload("res://core/playback.gd").new()
var preview_clip_name: String = ""
var preview_action_clip: String = ""
var preview_action_elapsed: float = 0.0
var preview_action_duration: float = 0.0
var preview_actor_height: float = 0.0
var cell: float = 28
var zoom: float = 1
var pan := Vector2.ZERO
var surface: Control
var start := Vector2i.ZERO
var last := Vector2i.ZERO
var hover := Vector2i(-1, -1)
var erasing: bool = false
var door_start := Vector2i(-1, -1)
var door_start_room_id := ""

func _ready() -> void:
	custom_minimum_size = Vector2(500, 360)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL; clip_contents = true
	surface = preload("res://ui/world_surface.gd").new(); add_child(surface)
	resized.connect(refresh_surface)
	refresh_surface()

func origin() -> Vector2:
	if playing: return size * 0.5 - (camera_focus / 24.0) * cell + pan
	return (size - Vector2(doc.map_data.width, doc.map_data.height) * cell) / 2 + pan

func set_preview(value: bool) -> void:
	if value and not playing:
		editor_zoom = zoom
		zoom = float(doc.map_data.get("camera_settings", {}).get("zoom", 2))
		camera_focus = player
		preview_action_clip = ""
		preview_actor_height = 0.0
		_select_preview_clip("idle_breathing")
	elif not value and playing:
		zoom = editor_zoom
		camera_focus = player
		preview_action_clip = ""
		preview_actor_height = 0.0
		preview_clip_name = ""
		clock.reset()
	playing = value
	refresh_surface()

func point(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - origin()) / cell).floor())

func refresh_surface() -> void:
	if doc == null or surface == null: return
	cell = maxf(0.5, minf(size.x / float(doc.map_data.width), size.y / float(doc.map_data.height)) * zoom)
	surface.map = doc.map_data; surface.textures = textures; surface.cell = cell; surface.origin = origin(); surface.collisions = not playing
	surface.queue_redraw(); queue_redraw()

func refresh() -> void:
	textures.clear(); character_textures.clear()
	for image in doc.tile_images(): textures.append(ImageTexture.create_from_image(image))
	for direction in 8:
		for frame in doc.frames: character_textures.append(ImageTexture.create_from_image(doc.composite(direction, frame)))
	anim_frame = clampi(anim_frame, 0, doc.frames - 1)
	character_texture = character_textures[facing * doc.frames + anim_frame]
	refresh_surface()

func cancel_gesture() -> void:
	painting = false; panning = false; hover = Vector2i(-1, -1)
	door_start = Vector2i(-1, -1)
	door_start_room_id = ""
	queue_redraw()

func invalidate() -> void:
	cancel_gesture(); zoom = 1; pan = Vector2.ZERO
	textures.clear(); character_textures.clear(); character_texture = null
	refresh_surface()

func fit_map() -> void:
	zoom = 1; pan = Vector2.ZERO; refresh_surface()

func reset_player() -> bool:
	for y in int(doc.map_data.height):
		for x in int(doc.map_data.width):
			var point := Vector2(x + 0.5, y + 0.5) * 24
			if not solid(point): player = point; camera_focus = point; queue_redraw(); return true
	return false

func _draw() -> void:
	if doc == null: return
	if playing and character_texture:
		var actor_rect := _actor_rect()
		draw_texture_rect(character_texture, actor_rect, false)
		var help := "PRÉVIA • WASD/setas mover • Espaço pular • J/clique atacar • E porta"
		draw_string(ThemeDB.fallback_font, Vector2(16, 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		var box := preview_hitbox_rect()
		if not box.size.is_zero_approx():
			draw_rect(box, Color(1.0, 0.24, 0.2, 0.24), true)
			draw_rect(box, Color(1.0, 0.32, 0.24, 0.95), false, 2)
		draw_string(ThemeDB.fallback_font, Vector2(16, 44), "Ação: " + preview_clip_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6ce83"))
		if doc.art.get("candidate_status", "") == "rejected":
			draw_string(ThemeDB.fallback_font, Vector2(16, 62), "ARTE REPROVADA • visual apenas para teste técnico", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ff766d"))
		for door in doc.map_data.get("doors", []):
			for endpoint in [door.a, door.b]:
				var center := (Vector2(endpoint[0], endpoint[1]) + Vector2(0.5, 0.5)) * 24
				if player.distance_to(center) <= 18:
					draw_string(ThemeDB.fallback_font, Vector2(16, 46), "E • " + str(door.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("a6f2e2"))
					break
		var current_room_id: String = doc.map_data.rooms[int(doc.map_data.active_room)].id
		for connection in doc.map_data.get("connections", []):
			for endpoint in [connection.a, connection.b]:
				if endpoint.room != current_room_id: continue
				var center := (Vector2(endpoint.point[0], endpoint.point[1]) + Vector2(0.5, 0.5)) * 24
				if player.distance_to(center) <= 18:
					draw_string(ThemeDB.fallback_font, Vector2(16, 66), "E • " + str(connection.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("f6ce83"))
					break
	elif door_start.x >= 0 and not playing and door_start_room_id == doc.map_data.rooms[int(doc.map_data.active_room)].id:
		var first := origin() + (Vector2(door_start) + Vector2(0.5, 0.5)) * cell
		var current := origin() + (Vector2(hover) + Vector2(0.5, 0.5)) * cell
		draw_line(first, current, Color("a6f2e2"), 3)
		draw_circle(first, maxf(4, cell * 0.22), Color("f6ce83"))
		draw_string(ThemeDB.fallback_font, Vector2(16, 24), "Escolha a segunda porta nesta ou em outra sala", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	elif painting and brush == "Retângulo":
		var rect := Rect2i(start.min(hover), (start - hover).abs() + Vector2i.ONE).intersection(Rect2i(0, 0, int(doc.map_data.width), int(doc.map_data.height)))
		draw_rect(Rect2(origin() + Vector2(rect.position) * cell, Vector2(rect.size) * cell), Color(1, 1, 1, 0.65), false, 2)
	elif World.inside(doc.map_data, hover):
		draw_rect(Rect2(origin() + Vector2(hover) * cell, Vector2.ONE * cell), Color.WHITE, false)

func _process(delta: float) -> void:
	if not playing or doc == null or not is_visible_in_tree(): return
	advance_preview(delta)

func advance_preview(delta: float) -> void:
	if not playing or doc == null: return
	var smoothing: float = float(doc.map_data.get("camera_settings", {}).get("smoothing", 0.0))
	camera_focus = player if smoothing <= 0 else camera_focus.lerp(player, 1.0 - exp(-smoothing * minf(delta, 0.2)))
	var axis := Vector2.ZERO
	if has_focus():
		axis.x = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		axis.y = float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	if axis != Vector2.ZERO and preview_action_clip.is_empty():
		var angle := int(round(axis.angle() / (PI / 4)))
		facing = [2, 3, 4, 5, 6, 7, 0, 1][posmod(angle, 8)]
		move_player(axis.normalized() * 110 * minf(delta, 0.2))
	if preview_action_clip.is_empty():
		_select_preview_clip("walk" if axis != Vector2.ZERO else "idle_breathing")
	else:
		preview_action_elapsed += clampf(delta, 0.0, 2.0)
		if preview_action_clip == "jump" and preview_action_duration > 0.0:
			var progress := clampf(preview_action_elapsed / preview_action_duration, 0.0, 1.0)
			preview_actor_height = sin(progress * PI) * cell * 0.7
	var clip_index := _preview_clip_index(preview_clip_name)
	var tick: Dictionary = clock.tick_clip(doc, clip_index, anim_frame, delta)
	anim_frame = int(tick.frame)
	if not preview_action_clip.is_empty() and tick.finished:
		preview_action_clip = ""
		preview_action_elapsed = 0.0
		preview_action_duration = 0.0
		preview_actor_height = 0.0
		preview_clip_name = ""
		clock.reset()
		_select_preview_clip("idle_breathing")
	if not character_textures.is_empty(): character_texture = character_textures[facing * doc.frames + anim_frame]
	refresh_surface()
	queue_redraw()

func _preview_clip_index(name: String) -> int:
	for index in doc.animation.clips.size():
		if str(doc.animation.clips[index].get("name", "")) == name:
			return index
	return -1

func _select_preview_clip(name: String) -> bool:
	var index := _preview_clip_index(name)
	if index < 0:
		index = clampi(int(doc.animation.get("active", 0)), 0, doc.animation.clips.size() - 1)
	if index < 0 or index >= doc.animation.clips.size(): return false
	var clip: Dictionary = doc.animation.clips[index]
	if clip.frames.is_empty(): return false
	if preview_clip_name != str(clip.name):
		preview_clip_name = str(clip.name)
		anim_frame = int(clip.frames[0])
		clock.reset()
		if not character_textures.is_empty():
			character_texture = character_textures[facing * doc.frames + anim_frame]
	return true

func start_preview_action(name: String) -> bool:
	if not playing or not preview_action_clip.is_empty(): return false
	var index := _preview_clip_index(name)
	if index < 0: return false
	var clip: Dictionary = doc.animation.clips[index]
	if bool(clip.get("loop", true)) or clip.frames.size() < 2: return false
	preview_action_clip = name
	preview_action_elapsed = 0.0
	preview_action_duration = 0.0
	for frame in clip.frames:
		preview_action_duration += doc.frame_seconds(int(frame), clip)
	preview_clip_name = ""
	_select_preview_clip(name)
	if preview_action_duration <= 0.0:
		preview_action_clip = ""
		return false
	queue_redraw()
	return true

func _actor_rect() -> Rect2:
	return Rect2(origin() + player / 24.0 * cell - Vector2(0.5, 0.85) * cell * 1.5 - Vector2(0, preview_actor_height), Vector2.ONE * cell * 1.5)

func preview_hitbox_rect() -> Rect2:
	if not playing or preview_action_clip != "attack": return Rect2()
	var hitbox: Variant = doc.animation.get("hitboxes", {}).get("%d:%d" % [facing, anim_frame], [])
	if not hitbox is Array or hitbox.size() != 4: return Rect2()
	var scale := _actor_rect().size.x / float(doc.width)
	return Rect2(_actor_rect().position + Vector2(float(hitbox[0]), float(hitbox[1])) * scale, Vector2(float(hitbox[2]), float(hitbox[3])) * scale)

func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_SPACE:
		if start_preview_action("jump"): get_viewport().set_input_as_handled()
		return
	if event.physical_keycode == KEY_J:
		if start_preview_action("attack"): get_viewport().set_input_as_handled()
		return
	if event.physical_keycode != KEY_E: return
	for door in doc.map_data.get("doors", []):
		for pair in [[door.a, door.b], [door.b, door.a]]:
			var from: Vector2 = (Vector2(pair[0][0], pair[0][1]) + Vector2(0.5, 0.5)) * 24
			if player.distance_to(from) > 18: continue
			player = (Vector2(pair[1][0], pair[1][1]) + Vector2(0.5, 0.5)) * 24
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	var active_room_id: String = doc.map_data.rooms[int(doc.map_data.active_room)].id
	for connection in doc.map_data.get("connections", []):
		for pair in [[connection.a, connection.b], [connection.b, connection.a]]:
			if pair[0].room != active_room_id: continue
			var from: Vector2 = (Vector2(pair[0].point[0], pair[0].point[1]) + Vector2(0.5, 0.5)) * 24
			if player.distance_to(from) > 18: continue
			var target_index := -1
			for i in doc.map_data.rooms.size():
				if doc.map_data.rooms[i].id == pair[1].room: target_index = i; break
			if target_index >= 0 and World.switch_room(doc.map_data, target_index):
				player = (Vector2(pair[1].point[0], pair[1].point[1]) + Vector2(0.5, 0.5)) * 24
				refresh(); room_changed.emit(); message.emit("Entrou em " + str(doc.map_data.rooms[target_index].name) + ".")
				queue_redraw(); get_viewport().set_input_as_handled(); return
	message.emit("Chegue perto de uma porta para usá-la.")
	get_viewport().set_input_as_handled()

func move_player(motion: Vector2) -> void:
	var steps := maxi(1, ceili(motion.length() / 4))
	for i in mini(steps, 64):
		var next := player + motion / steps
		if not solid(Vector2(next.x, player.y)): player.x = next.x
		if not solid(Vector2(player.x, next.y)): player.y = next.y

func solid(p: Vector2) -> bool:
	for offset in [Vector2(-5, -3), Vector2(5, -3), Vector2(-5, 3), Vector2(5, 3)]:
		var q := Vector2i(((p + offset) / 24).floor())
		if not World.inside(doc.map_data, q) or doc.map_data.collision[q.y * int(doc.map_data.width) + q.x]: return true
	return false

func paint(pos: Vector2, erase: bool) -> void:
	if World.paint(doc.map_data, point(pos), mode, terrain if mode == "Terreno" else tile, erase, light): edited.emit(); refresh_surface()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = event.pressed; return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var previous := cell
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.25, 16)
			var anchor: Vector2 = (event.position - origin()) / previous
			refresh_surface()
			pan += event.position - (origin() + anchor * cell)
			refresh_surface(); return
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return
		grab_focus()
		if playing:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed: start_preview_action("attack")
			return
		hover = point(event.position)
		if mode == "Porta":
			if event.button_index == MOUSE_BUTTON_RIGHT:
				door_start = Vector2i(-1, -1); door_start_room_id = ""; queue_redraw(); return
			if not World.inside(doc.map_data, hover): return
			var active_room_id: String = doc.map_data.rooms[int(doc.map_data.active_room)].id
			if doc.map_data.collision[hover.y * int(doc.map_data.width) + hover.x] or World.door_at(doc.map_data, hover) or World.connection_at(doc.map_data, active_room_id, hover):
				message.emit("Escolha uma célula livre e sem outra porta."); return
			if door_start.x < 0:
				door_start = hover; door_start_room_id = active_room_id; queue_redraw(); return
			doc.checkpoint("Conectar portas")
			var connected := World.add_door(doc.map_data, door_start, hover, door_name) if door_start_room_id == active_room_id else World.add_connection(doc.map_data, door_start_room_id, door_start, active_room_id, hover, door_name)
			if connected:
				door_start = Vector2i(-1, -1); door_start_room_id = ""; edited.emit(); message.emit("Portas conectadas entre salas. Na prévia, aproxime-se e pressione E.")
			else: message.emit("Não foi possível conectar essas células.")
			refresh_surface(); return
		if event.pressed:
			if not World.inside(doc.map_data, hover): return
			if mode in ["Tile", "Terreno"] and World.metadata(doc.map_data).locked: return
			if mode == "Terreno" and terrain < 0 and event.button_index == MOUSE_BUTTON_LEFT: return
			doc.checkpoint("Mapa: " + mode + " / " + brush)
			erasing = event.button_index == MOUSE_BUTTON_RIGHT; start = hover; last = hover; painting = true
			if brush == "Balde" and mode != "Luz":
				World.flood(doc.map_data, hover, mode, terrain if mode == "Terreno" else tile, erasing)
				painting = false; edited.emit(); refresh_surface()
			elif brush != "Retângulo" or mode == "Luz": paint(event.position, erasing)
		elif painting:
			if brush == "Retângulo" and mode != "Luz":
				var rect := Rect2i(start.min(hover), (start - hover).abs() + Vector2i.ONE).intersection(Rect2i(0, 0, int(doc.map_data.width), int(doc.map_data.height)))
				for y in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x): World.paint(doc.map_data, Vector2i(x, y), mode, terrain if mode == "Terreno" else tile, erasing, light)
				edited.emit(); refresh_surface()
			painting = false; queue_redraw()
	if event is InputEventMouseMotion:
		if panning: pan += event.relative; refresh_surface(); return
		hover = point(event.position)
		if painting and not playing and brush == "Lápis":
			var end := hover.clamp(Vector2i.ZERO, Vector2i(int(doc.map_data.width) - 1, int(doc.map_data.height) - 1))
			var steps := maxi(absi(end.x - last.x), absi(end.y - last.y))
			for i in steps + 1:
				var p := Vector2i(Vector2(last).lerp(Vector2(end), float(i) / maxi(1, steps)).round())
				World.paint(doc.map_data, p, mode, terrain if mode == "Terreno" else tile, erasing, light)
			last = end; edited.emit(); refresh_surface()
		queue_redraw()
