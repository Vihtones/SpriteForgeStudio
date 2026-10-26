extends SceneTree
const MainScene = preload("res://main.tscn")
var passed := 0
var failed := 0

func expect(value: bool, message: String) -> void:
	if value: passed += 1; print("PASS ", message)
	else: failed += 1; printerr("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var studio: Control = MainScene.instantiate()
	studio.workspace_root = "user://pixel-shapes-ui-tests"
	root.add_child(studio)
	await process_frame
	var doc = studio.doc
	var canvas = studio.canvas
	var tools: Array = studio.DRAWING_TOOLS
	expect(tools.has("Retângulo preenchido") and tools.has("Elipse") and tools.has("Elipse preenchida"), "toolbar disponibiliza formas geométricas vazadas e preenchidas")
	for layer in doc.layers:
		for direction in 8:
			for frame in doc.frames: layer.cels[direction][frame].fill(Color.TRANSPARENT)
	doc.art.locked = false
	doc.selection = Rect2i()
	doc.direction = 0; doc.frame = 0; doc.active_layer = 0
	canvas.color = Color("f05b68")
	var empty: PackedByteArray = doc.current().get_data()
	studio.select_drawing_tool(tools.find("Elipse"))
	_drag(canvas, Vector2i(8, 8), Vector2i(14, 12))
	expect(doc.current().get_pixel(11, 10).a == 0.0 and doc.current().get_pixel(8, 10) == canvas.color, "elipse vazada pinta o contorno e preserva o centro")
	expect(doc.undo() and doc.current().get_data() == empty, "uma operação Undo reverte a elipse inteira")
	studio.select_drawing_tool(tools.find("Elipse preenchida"))
	_drag(canvas, Vector2i(8, 8), Vector2i(14, 12))
	expect(doc.current().get_pixel(11, 10) == canvas.color and doc.current().get_pixel(8, 10) == canvas.color, "elipse preenchida rasteriza contorno e interior")
	var report := FileAccess.open("res://test_results/pixel-shapes-ui-report.json", FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t")); report.close()
	print("Pixel shapes UI: %d passed, %d failed" % [passed, failed])
	studio.queue_free()
	quit(1 if failed else 0)

func _drag(canvas: Control, from: Vector2i, to: Vector2i) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = canvas.origin() + (Vector2(from) + Vector2.ONE * 0.5) * canvas.zoom
	canvas._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	release.position = canvas.origin() + (Vector2(to) + Vector2.ONE * 0.5) * canvas.zoom
	canvas._gui_input(release)
