extends SceneTree
## Runs inside a clean Godot project that only contains a Sprite Forge export.
var checks: Array = []

func _initialize() -> void: call_deferred("run")

func check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})

func run() -> void:
	var frames := ResourceLoader.load("res://animations.tres", "SpriteFrames", ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	check("animations.tres loads as SpriteFrames with clips", frames != null and frames.get_animation_names().size() > 0)
	var character_scene := load("res://character.tscn") as PackedScene
	var character: Node = character_scene.instantiate() if character_scene != null else null
	check("character.tscn instantiates", character != null)
	var sprite := character.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D if character != null else null
	var playback := false
	if sprite != null and sprite.sprite_frames != null:
		root.add_child(character)
		var clip := StringName()
		for animation in sprite.sprite_frames.get_animation_names():
			if sprite.sprite_frames.get_frame_count(animation) > 1: clip = animation; break
		if clip != StringName():
			sprite.play(clip)
			var deadline := Time.get_ticks_msec() + 3000
			while sprite.frame == 0 and Time.get_ticks_msec() < deadline: await process_frame
			playback = sprite.is_playing() and sprite.frame > 0
	check("character animation plays and advances frames", playback)
	var tileset := ResourceLoader.load("res://tileset.tres", "TileSet", ResourceLoader.CACHE_MODE_IGNORE) as TileSet
	check("tileset.tres loads with at least one source", tileset != null and tileset.get_source_count() > 0)
	var rooms_file := FileAccess.get_file_as_string("res://rooms.json")
	var rooms_manifest: Variant = JSON.parse_string(rooms_file) if not rooms_file.is_empty() else null
	var room_scenes: Array = []
	if rooms_manifest is Dictionary and rooms_manifest.get("rooms") is Array:
		for room in rooms_manifest.rooms: room_scenes.append(str(room.get("scene", "")))
	check("rooms.json lists every exported room", room_scenes.size() >= 1)
	var all_rooms_load := not room_scenes.is_empty()
	for scene_path in room_scenes:
		var packed := load("res://" + scene_path) as PackedScene
		var instance: Node = packed.instantiate() if packed != null else null
		all_rooms_load = all_rooms_load and instance != null and instance.get_node_or_null("Ground") is TileMapLayer
		if instance != null: instance.free()
	check("every room scene loads with a ground layer", all_rooms_load)
	var map_scene := load("res://map.tscn") as PackedScene
	var map: Node = map_scene.instantiate() if map_scene != null else null
	check("map.tscn instantiates", map != null)
	var route_points := 0
	var collision_bodies := 0
	var doorways := 0
	if map != null:
		root.add_child(map)
		current_scene = map
		for i in 6: await physics_frame
		var region := map.get_node_or_null("Navigation") as NavigationRegion2D
		if region != null:
			var nav_map := region.get_navigation_map()
			var deadline := Time.get_ticks_msec() + 3000
			while NavigationServer2D.map_get_iteration_id(nav_map) == 0 and Time.get_ticks_msec() < deadline: await physics_frame
			var vertices := region.navigation_polygon.get_vertices() if region.navigation_polygon != null else PackedVector2Array()
			var bounds := Rect2(vertices[0], Vector2.ZERO) if not vertices.is_empty() else Rect2()
			for point in vertices: bounds = bounds.expand(point)
			# The region reaches the server a few syncs after the first iteration, so wait until it answers queries.
			var sync_deadline := Time.get_ticks_msec() + 3000
			while NavigationServer2D.map_get_closest_point(nav_map, region.to_global(bounds.get_center())) == Vector2.ZERO and Time.get_ticks_msec() < sync_deadline: await physics_frame
			var start := NavigationServer2D.map_get_closest_point(nav_map, region.to_global(bounds.position))
			var finish := NavigationServer2D.map_get_closest_point(nav_map, region.to_global(bounds.end))
			route_points = NavigationServer2D.map_get_path(nav_map, start, finish, true).size()
		collision_bodies = map.find_children("*", "StaticBody2D", true, false).size()
		doorways = get_nodes_in_group("sfs_interactions").size()
	check("navigation region produces a route", route_points >= 2)
	check("collision tiles become physics bodies", collision_bodies > 0)
	check("doorway runtime scripts load in the room", doorways > 0)
	var ok := checks.all(func(entry): return entry.passed)
	var report := FileAccess.open("res://report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"ok": ok, "checks": checks, "route_points": route_points, "collision_bodies": collision_bodies, "doorways": doorways}, "\t"))
	report.close()
	quit(0 if ok else 1)
