extends SceneTree

const MotionPanel = preload("res://ui/three_d_motion_panel.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel = MotionPanel.new()
	root.add_child(panel)
	await process_frame
	await process_frame
	panel.set_proportions({"torso_height": 1.06, "shoulder_width": 1.08, "arm_length": 1.05, "leg_length": 1.04})
	var hero_pose := {"torso": deg_to_rad(-4.0), "left_arm": deg_to_rad(-18.0), "right_arm": deg_to_rad(24.0), "left_elbow": deg_to_rad(18.0), "right_elbow": deg_to_rad(24.0), "left_leg": deg_to_rad(12.0), "right_leg": deg_to_rad(-14.0), "left_knee": deg_to_rad(8.0), "right_knee": deg_to_rad(12.0)}
	var colors: Array = ["#191b32", "#34496b", "#75b5ad", "#e9d8a6", "#e69c69", "#f5eee4"]
	var capture: Dictionary = await panel.capture_sequence([0], Vector2i(64, 64), colors, [hero_pose])
	if not capture.get("ok", false):
		printerr("360 demo capture failed: ", capture.get("message", "unknown error"))
		quit(1)
		return
	var cell_size := 128
	var gutter := 8
	var contact_sheet := Image.create(cell_size * 4 + gutter * 5, cell_size * 2 + gutter * 3, false, Image.FORMAT_RGBA8)
	contact_sheet.fill(Color("10131b"))
	for direction in 8:
		var source: Image = capture.images[direction][0]
		var enlarged := source.duplicate()
		enlarged.resize(cell_size, cell_size, Image.INTERPOLATE_NEAREST)
		var slot := Vector2i(gutter + (direction % 4) * (cell_size + gutter), gutter + int(direction / 4) * (cell_size + gutter))
		contact_sheet.blend_rect(enlarged, Rect2i(Vector2i.ZERO, enlarged.get_size()), slot)
	var target_path := ProjectSettings.globalize_path("res://examples/3d_motion_360_turntable.png")
	var error := contact_sheet.save_png(target_path)
	print("360 turntable output: ", target_path, " — 8 views, 64x64 source frames, 2x nearest-neighbor display scale, error ", error)
	panel.queue_free()
	quit(0 if error == OK else 1)
