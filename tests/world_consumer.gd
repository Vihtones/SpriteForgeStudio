extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://map.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 6: await physics_frame
	var region: NavigationRegion2D = scene.get_node("Navigation")
	var deadline := Time.get_ticks_msec() + 3000
	while NavigationServer2D.map_get_iteration_id(region.get_navigation_map()) == 0 and Time.get_ticks_msec() < deadline: await physics_frame
	var iteration_id := NavigationServer2D.map_get_iteration_id(region.get_navigation_map())
	var route := NavigationServer2D.map_get_path(region.get_navigation_map(), Vector2(12, 12), Vector2(180, 108), true)
	var ground_cells: int = scene.get_node("Ground").get_used_cells().size()
	var overlay_cells: int = scene.get_node("Layer_1").get_used_cells().size()
	var collision := root.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(60, 60), Vector2(156, 60)))
	var doorways: Array = get_nodes_in_group("sfs_interactions")
	var actor := CharacterBody2D.new()
	actor.name = "TestPlayer"
	actor.collision_layer = 1
	var follow_camera := Camera2D.new()
	follow_camera.name = "SFSFollowCamera"
	follow_camera.set_script(load("res://examples/export/pixel_camera.gd"))
	follow_camera.set("snap_to_pixels", true)
	actor.add_child(follow_camera)
	var actor_shape := CollisionShape2D.new()
	var actor_rect := RectangleShape2D.new(); actor_rect.size = Vector2(8, 8); actor_shape.shape = actor_rect
	actor.add_child(actor_shape); scene.add_child(actor)
	var door_transition := false
	var cross_room_doors: Array = doorways.filter(func(area): return not str(area.get("target_scene")).is_empty())
	if not cross_room_doors.is_empty():
		var doorway: Area2D = cross_room_doors[0]
		actor.global_position = doorway.global_position
		for i in 3: await physics_frame
		var destination: Vector2 = doorway.target_position
		door_transition = doorway.interact(actor)
		for i in 8: await process_frame
		door_transition = door_transition and current_scene != scene and is_instance_valid(actor) and actor.get_parent() == current_scene and actor.global_position.is_equal_approx(destination)
	var camera_room := false
	if is_instance_valid(actor) and current_scene != null and current_scene.has_meta("sfs_bounds"):
		var bounds: Rect2 = current_scene.get_meta("sfs_bounds")
		var camera_settings: Dictionary = current_scene.get_meta("sfs_camera_settings")
		camera_room = follow_camera.limit_right == int(bounds.end.x) and follow_camera.zoom == Vector2.ONE * int(camera_settings.zoom)
	var ambient_room := false
	if current_scene != null and current_scene.has_node("AmbientLight"):
		ambient_room = current_scene.get_node("AmbientLight").color == Color(str(current_scene.get_meta("sfs_ambient_color")))
	var ok: bool = route.size() >= 2 and not collision.is_empty() and ground_cells == 48 and overlay_cells == 1 and door_transition and camera_room and ambient_room
	var report := FileAccess.open("res://consumer-report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"ok": ok, "path_points": route.size(), "physics_hit": not collision.is_empty(), "doorways": doorways.size(), "cross_room_doorways": cross_room_doors.size(), "door_transition": door_transition, "actor_preserved": is_instance_valid(actor) and actor.get_parent() == current_scene, "camera_room_settings_applied": camera_room, "camera_zoom": follow_camera.zoom, "ambient_room_settings_applied": ambient_room, "ambient_color": str(current_scene.get_meta("sfs_ambient_color")) if current_scene != null else "", "destination_scene": current_scene.scene_file_path if current_scene != null else "", "iteration": iteration_id})); report.close()
	quit(0 if ok else 1)
