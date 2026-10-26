extends SceneTree

const MotionPanel = preload("res://ui/three_d_motion_panel.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel = MotionPanel.new()
	root.add_child(panel)
	await process_frame
	await process_frame
	panel.orbit_control.value = 137.0
	panel._toggle_walk()
	var keyed_pose := {"torso": deg_to_rad(5.0), "left_arm": deg_to_rad(-25.0), "right_arm": deg_to_rad(25.0), "left_leg": deg_to_rad(18.0), "right_leg": deg_to_rad(-18.0)}
	var result: Dictionary = await panel.capture_sequence([0], Vector2i(32, 32), ["#191b32", "#34496b", "#75b5ad", "#e9d8a6", "#e69c69", "#f5eee4"], [keyed_pose])
	var valid: bool = bool(result.get("ok", false)) and result.get("images", []).size() == 8
	var anchors_valid: bool = result.get("attachment_anchor_positions", []).size() == 8 and result.get("equipment_attachments", {}).has("shield") and result.get("equipment_attachments", {}).has("sword")
	anchors_valid = anchors_valid and panel.equipment_mounts.shield.position.is_equal_approx(Vector3(0.0, -0.22, 0.0))
	anchors_valid = anchors_valid and panel.mannequin.find_child("ShieldRivet", true, false) == null
	var rig_markers: Array[Node] = panel.mannequin.find_children("*Marker", "MeshInstance3D", true, false)
	anchors_valid = anchors_valid and rig_markers.is_empty()
	var view_hashes: Dictionary = {}
	if valid:
		for direction_frames in result.images:
			valid = valid and direction_frames.size() == 1
			for cel in direction_frames:
				valid = valid and cel is Image and cel.get_size() == Vector2i(32, 32) and not cel.is_empty() and cel.get_used_rect().size != Vector2i.ZERO
				view_hashes[cel.get_data().hex_encode()] = true
		if valid: result.images[0][0].save_png("res://test_results/three-d-motion-preview.png")
	valid = valid and view_hashes.size() >= 4
	if anchors_valid:
		for direction_anchors in result.attachment_anchor_positions:
			anchors_valid = anchors_valid and direction_anchors.size() == 1 and direction_anchors[0].has("shield") and direction_anchors[0].has("sword")
			for equipment_name in ["shield", "sword"]:
				var point: Array = direction_anchors[0].get(equipment_name, [])
				anchors_valid = anchors_valid and point.size() == 2 and point[0] >= 0 and point[0] < 32 and point[1] >= 0 and point[1] < 32
	valid = valid and anchors_valid
	valid = valid and panel.live_walk and is_equal_approx(panel.mannequin.rotation.y, deg_to_rad(137.0))
	print("3D viewport capture: ", "PASS" if valid else "FAIL ", result.get("message", ""))
	var report := {"passed": 1 if valid else 0, "failed": 0 if valid else 1, "message": result.get("message", ""), "walk_restored": panel.live_walk, "orbit_degrees": rad_to_deg(panel.mannequin.rotation.y), "distinct_views": view_hashes.size()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_results"))
	var file := FileAccess.open("res://test_results/three-d-motion-viewport-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	panel.queue_free()
	quit(0 if valid else 1)
