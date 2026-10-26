extends SceneTree
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const Memory = preload("res://core/art_memory.gd")
const Gateway = preload("res://core/ai_gateway.gd")
const Queue = preload("res://core/batch_queue.gd")
const Precision = preload("res://core/precision.gd")
const References = preload("res://core/reference_library.gd")
const Quality = preload("res://core/quality_library.gd")
const Plan = preload("res://core/production_plan.gd")
const Navigation = preload("res://core/navigation.gd")
const SpriteSheetImporter = preload("res://core/spritesheet_importer.gd")
var passed: int = 0
var failed: int = 0
var checks: Array = []
var output: String = ProjectSettings.globalize_path("res://test_results")

func wait_job(queue: Node, index: int) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while queue.jobs[index].status in ["pending", "preparing", "running", "validating"] and Time.get_ticks_msec() < deadline:
		await process_frame

func expect(condition: bool, title: String) -> void:
	checks.append({"name": title, "passed": condition})
	if condition:
		passed += 1
		print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var d = Doc.new()
	expect(d.validate().is_empty(), "new document valid")
	expect(d.layers[0].cels.size() == 8 and d.frames == 4, "8 directions × 4 frames")
	var blank_document = Doc.new()
	var blank_initialized: bool = blank_document.initialize_blank(48, 64, 6, 12)
	var blank_cels_clear := blank_initialized
	if blank_initialized:
		for direction_index in 8:
			for frame_index in blank_document.frames:
				if blank_document.layers[0].cels[direction_index][frame_index].get_used_rect().size != Vector2i.ZERO: blank_cels_clear = false
	expect(blank_initialized and blank_cels_clear and blank_document.width == 48 and blank_document.height == 64 and blank_document.frames == 6 and blank_document.fps == 12 and blank_document.animation.clips[0].frames == Array(range(6)) and blank_document.validate().is_empty(), "documento vazio configura tela retangular, timeline e taxa de quadros antes de criar cels")
	var previous_blank_size := Vector2i(blank_document.width, blank_document.height)
	var rejected_over_budget: bool = not blank_document.initialize_blank(512, 512, 32, 8)
	expect(rejected_over_budget and Vector2i(blank_document.width, blank_document.height) == previous_blank_size and blank_document.frames == 6 and blank_document.validate().is_empty(), "tela fora do orçamento é recusada sem alterar o documento em edição")
	d.checkpoint()
	d.pixel(Vector2i(2, 3), Color.RED, true)
	expect(d.current().get_pixel(2, 3) == Color.RED and d.current().get_pixel(29, 3) == Color.RED, "mirrored brush")
	expect(d.layers[0].cels[1][0].get_pixel(2, 3).a == 0, "independent direction buffers")
	d.undo()
	expect(d.current().get_pixel(2, 3).a == 0, "undo pixels")
	d.redo()
	expect(d.current().get_pixel(2, 3) == Color.RED, "redo pixels")
	d.selection = Rect2i(5, 5, 3, 3)
	d.flood(Vector2i(6, 6), Color.BLUE)
	expect(d.current().get_pixel(5, 5) == Color.BLUE and d.current().get_pixel(8, 5).a == 0, "flood respects mask")
	d.selection = Rect2i()
	d.layers[0].locked = true
	d.pixel(Vector2i(0, 0), Color.GREEN)
	expect(d.current().get_pixel(0, 0).a == 0, "layer lock")
	d.layers[0].locked = false
	d.pixel(Vector2i(10, 10), Color.GREEN, false, 3)
	expect(d.current().get_pixel(9, 9) == Color.GREEN and d.current().get_pixel(11, 11) == Color.GREEN and d.current().get_pixel(12, 12).a == 0, "3 pixel brush coverage")
	d.duplicate_frame()
	d.pixel(Vector2i(1, 1), Color.YELLOW)
	expect(d.frames == 5 and d.layers[0].cels[0][0].get_pixel(1, 1).a == 0, "duplicate frame deep copy")
	d.delete_frame()
	expect(d.frames == 4, "delete frame")
	var grid_sheet := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	for direction in 8:
		for frame_index in 2:
			var marker := Color(direction / 8.0, frame_index / 2.0, 0.25, 1.0)
			for y in 32:
				for x in 32: grid_sheet.set_pixel(frame_index * 32 + x, direction * 32 + y, marker)
	var sheet_document = Doc.new()
	var sheet_result: Dictionary = SpriteSheetImporter.import_into(sheet_document, grid_sheet, {"cell_width": 32, "cell_height": 32, "columns": 2, "rows": 8, "start_frame": 1, "all_directions": true})
	expect(sheet_result.get("ok", false), "spritesheet grid accepts a valid 8-direction grid")
	expect(int(sheet_result.get("cells", 0)) == 16, "spritesheet grid reports all 16 imported cels")
	var expected_sheet_color := Color(7.0 / 8.0, 0.5, 0.25, 1.0)
	var imported_sheet_color: Color = sheet_document.layers[0].cels[7][2].get_pixel(0, 0)
	var sheet_color_error := maxf(maxf(absf(imported_sheet_color.r - expected_sheet_color.r), absf(imported_sheet_color.g - expected_sheet_color.g)), absf(imported_sheet_color.b - expected_sheet_color.b))
	expect(sheet_color_error <= 1.0 / 255.0 and imported_sheet_color.a == 1.0, "spritesheet cells preserve row/direction order and pixel colors within one RGBA8 level")
	expect(sheet_document.undo() and sheet_document.layers[0].cels[7][2].get_pixel(0, 0).a == 0, "spritesheet import is one undoable operation")
	var invalid_sheet: Dictionary = SpriteSheetImporter.import_into(sheet_document, grid_sheet, {"cell_width": 16, "cell_height": 32, "columns": 2, "rows": 8, "start_frame": 0, "all_directions": true})
	expect(not invalid_sheet.ok and sheet_document.layers[0].cels[7][0].get_pixel(0, 0).a == 0, "invalid spritesheet dimensions are rejected without changing cels")
	var single_direction_document = Doc.new()
	single_direction_document.direction = 3
	var single_direction_result: Dictionary = SpriteSheetImporter.import_into(single_direction_document, grid_sheet, {"cell_width": 32, "cell_height": 32, "columns": 2, "rows": 1, "start_frame": 0, "all_directions": false})
	expect(single_direction_result.ok and single_direction_document.layers[0].cels[3][1].get_pixel(0, 0).g > 0.49 and single_direction_document.layers[0].cels[2][1].get_pixel(0, 0).a == 0, "single-row sheet replaces only the selected direction")
	var fit_sheet := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	fit_sheet.fill(Color(0, 0, 0, 0))
	fit_sheet.fill_rect(Rect2i(10, 2, 12, 20), Color.CORAL)
	var fit_document = Doc.new()
	var fit_result: Dictionary = SpriteSheetImporter.import_into(fit_document, fit_sheet, {"cell_width": 32, "cell_height": 32, "columns": 1, "rows": 1, "start_frame": 0, "all_directions": false, "content_scale": 0.5, "alignment": "bottom_center"})
	var fitted_bounds: Rect2i = fit_document.layers[0].cels[0][0].get_used_rect()
	expect(fit_result.ok and fitted_bounds.size == Vector2i(6, 10), "spritesheet fit shrinks imported content without changing the target canvas")
	expect(fitted_bounds.position.x == 13 and fitted_bounds.end.y == 27, "spritesheet fit preserves centered alignment and keeps the feet anchor stable")
	var invalid_fit: Dictionary = SpriteSheetImporter.import_into(fit_document, fit_sheet, {"cell_width": 32, "cell_height": 32, "columns": 1, "rows": 1, "start_frame": 0, "all_directions": false, "content_scale": 2.0})
	expect(not invalid_fit.ok and fit_document.layers[0].cels[0][0].get_used_rect() == fitted_bounds, "invalid content scale is rejected without changing pixels")
	var irregular_grid := Image.create(67, 66, false, Image.FORMAT_RGBA8)
	irregular_grid.fill(Color(0, 0, 0, 0))
	irregular_grid.fill_rect(Rect2i(36, 37, 26, 27), Color.CORAL)
	var grid_row_document = Doc.new()
	grid_row_document.direction = 3
	var grid_row_result: Dictionary = SpriteSheetImporter.import_grid_row(grid_row_document, irregular_grid, {"columns": 2, "source_rows": 2, "source_row": 1, "fit_grid": true, "start_frame": 0, "content_scale": 0.75, "alignment": "bottom_center"})
	expect(grid_row_result.ok and grid_row_document.layers[0].cels[3][1].get_used_rect().size != Vector2i.ZERO, "grid-row importer normalizes an irregular atlas and imports the selected action row")
	expect(grid_row_document.layers[0].cels[2][0].get_used_rect().size == Vector2i.ZERO, "grid-row import writes only to the active direction")
	single_direction_document.art.locked = true
	var art_locked_sheet: Dictionary = SpriteSheetImporter.import_into(single_direction_document, grid_sheet, {"cell_width": 32, "cell_height": 32, "columns": 2, "rows": 1, "start_frame": 0, "all_directions": false})
	expect(not art_locked_sheet.ok, "spritesheet import respects Art Lock")
	var approval_sheet_document = Doc.new()
	approval_sheet_document.art.candidate_status = "approved"
	approval_sheet_document.art.pose_approvals = [{"clip": "attack"}]
	approval_sheet_document.manifest.approvals = [{"human": true}]
	var approval_sheet_result: Dictionary = SpriteSheetImporter.import_into(approval_sheet_document, grid_sheet, {"cell_width": 32, "cell_height": 32, "columns": 2, "rows": 1, "start_frame": 0, "all_directions": false})
	expect(approval_sheet_result.ok and approval_sheet_document.art.candidate_status == "candidate" and approval_sheet_document.art.pose_approvals.is_empty() and approval_sheet_document.manifest.approvals.is_empty(), "spritesheet edits clear stale approvals and return the document to candidate")
	var rejected_sheet_document = Doc.new()
	rejected_sheet_document.art.candidate_status = "rejected"
	var rejected_sheet_result: Dictionary = SpriteSheetImporter.import_into(rejected_sheet_document, grid_sheet, {"cell_width": 32, "cell_height": 32, "columns": 2, "rows": 1, "start_frame": 0, "all_directions": false})
	expect(rejected_sheet_result.ok and rejected_sheet_document.art.candidate_status == "rejected", "spritesheet edit does not silently reopen rejected art")
	d.add_layer("Sword", true)
	d.pixel(Vector2i(0, 0), Color.WHITE)
	expect(d.composite().get_pixel(24, 18) == Color.WHITE, "equipment anchor composition")
	d.layers[1].visible = false
	expect(d.composite().get_pixel(24, 18).a == 0, "hidden equipment")
	d.layers[1].visible = true
	var s = Storage.new()
	var project_path := output.path_join("roundtrip.sfs.json")
	expect(s.save_document(d, project_path) == OK, "save project")
	var loaded = s.load_document(project_path)
	expect(loaded != null, "load project")
	if loaded != null:
		expect(loaded.composite().get_data() == d.composite().get_data(), "RGBA roundtrip exact")
		expect(loaded.map_data == d.map_data and loaded.anchors == d.anchors, "map and anchors roundtrip")
	expect(s.save_document(d, project_path) == OK and FileAccess.file_exists(project_path + ".bak"), "atomic replacement keeps backup")
	var export_path := output.path_join("export")
	expect(s.export_all(d, export_path) == OK, "export complete package")
	var sheet := Image.new()
	sheet.load_png_from_buffer(FileAccess.get_file_as_bytes(export_path.path_join("spritesheet.png")))
	expect(sheet != null and sheet.get_size() == Vector2i(128, 256), "spritesheet dimensions")
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(export_path.path_join("metadata.json")))
	expect(metadata is Dictionary and metadata.frames.size() == 32, "metadata all directions and frames")
	var map_scene = load(export_path.path_join("map.tscn"))
	expect(map_scene is PackedScene, "exported map scene loads")
	var tiles := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	tiles.fill(Color.GREEN)
	d.map_data.tileset_png = Marshalls.raw_to_base64(tiles.save_png_to_buffer())
	expect(d.tile_images().size() == 2 and d.tile_images()[0].get_size() == Vector2i(16, 16), "dedicated tileset slicing")
	d.map_data.cells[0] = 1
	d.map_data.collision[0] = true
	d.map_data.lights.append([1, 1])
	expect(s.save_document(d, output.path_join("tileset.sfs.json")) == OK and s.load_document(output.path_join("tileset.sfs.json")) != null, "tileset persists in project")
	expect(s.export_all(d, output.path_join("tileset_export")) == OK, "tileset map exports")
	var mapped = load(output.path_join("tileset_export/map.tscn")).instantiate()
	var bodies: int = 0
	var lights: int = 0
	for child in mapped.get_children():
		if child is StaticBody2D: bodies += 1
		if child is PointLight2D: lights += 1
	expect(bodies == 1 and lights == 1, "map scene contains real collision and point light")
	expect(mapped.get_node("Ground") is TileMapLayer and mapped.get_node("Navigation") is NavigationRegion2D, "map uses real TileMapLayer and navigation region")
	expect(load(output.path_join("tileset_export/tileset.tres")) is TileSet and load(output.path_join("tileset_export/animations.tres")) is SpriteFrames, "standalone TileSet and animation resources load")
	mapped.free()
	var packed = load(export_path.path_join("character.tscn"))
	expect(packed is PackedScene, "exported Godot scene loads")
	if packed is PackedScene:
		var instance = packed.instantiate()
		expect(instance.get_node("AnimatedSprite2D").sprite_frames.get_animation_names().size() == 8, "scene has 8 playable animations")
		var camera := instance.get_node("SFSFollowCamera") as Camera2D
		expect(camera != null and camera.zoom == Vector2(2, 2) and camera.limit_right == d.map_data.width * 24 and camera.limit_bottom == d.map_data.height * 24, "exported follow camera carries zoom and room bounds")
		expect(camera.get_script() != null and camera.get("snap_to_pixels") == true, "exported camera snaps to physical pixels through its reusable controller")
		instance.free()
	s.atomic_json(output.path_join("invalid.json"), {"schema": 99})
	expect(s.load_document(output.path_join("invalid.json")) == null, "reject schema")
	var partial := FileAccess.open(output.path_join("partial_progress.json"), FileAccess.WRITE)
	partial.store_string("{")
	partial.close()
	expect(Storage.read_json(output.path_join("partial_progress.json")) == null and Storage.read_json(output.path_join("absent_progress.json")) == null, "transient or incomplete progress JSON handled without parse exception")
	var invalid: Dictionary = s.encode(d)
	invalid.layers[0].cels[0] = []
	s.atomic_json(output.path_join("invalid.json"), invalid)
	expect(s.load_document(output.path_join("invalid.json")) == null, "reject truncated cels")
	invalid = s.encode(d)
	invalid.width = 999999
	s.atomic_json(output.path_join("invalid.json"), invalid)
	expect(s.load_document(output.path_join("invalid.json")) == null, "reject oversized document")
	invalid = s.encode(d)
	invalid.layers[0].cels[0][0] = "garbage"
	s.atomic_json(output.path_join("invalid.json"), invalid)
	expect(s.load_document(output.path_join("invalid.json")) == null, "reject corrupted PNG")
	var m = Memory.new()
	d.art.candidates.append(m.propose(d))
	d.art.locked = true
	expect(not m.approve(d, 0), "Art Lock blocks approval")
	d.art.locked = false
	d.mark_changed()
	expect(not m.approve(d, 0), "stale candidate rejected")
	d.art.candidates.append(m.propose(d))
	expect(m.approve(d, 1) and d.art.memory.size() == 1, "tested candidate explicit approval")
	var gateway = Gateway.new()
	var ai_payload := {"prompt": "sprite de teste", "model": "gpt-image-2.5-sunburst", "quality": "low", "transparent": true}
	expect(not gateway.request(ai_payload).ok and not gateway.request(ai_payload, {"single_call_approved": true}).ok, "AI rejects calls without a one-shot approval token")
	var ai_approval: Dictionary = gateway.prepare_approval(ai_payload)
	expect(ai_approval.ok and gateway.consume_approval(ai_payload, ai_approval.token), "AI approval is bound to the reviewed payload")
	expect(not gateway.consume_approval(ai_payload, ai_approval.token), "AI approval token is single-use")
	var changed_approval: Dictionary = gateway.prepare_approval(ai_payload)
	expect(not gateway.consume_approval({"prompt": "different"}, changed_approval.token), "AI approval cannot authorize a changed payload")
	expect(not gateway.validate_payload({"prompt": " ", "model": "invalid"}).ok and not gateway.validate_payload({"prompt": "sprite", "quality": "invalid"}).ok, "AI validates prompt and provider options before approval")
	gateway.free()
	var q = Queue.new()
	q.checkpoint_path = output.path_join("queue.json")
	q.request_root = output.path_join("worker_requests")
	root.add_child(q)
	q.jobs.clear()
	var batch_folder := output.path_join("batch_" + str(Time.get_ticks_usec()))
	q.enqueue(project_path, batch_folder)
	q.running = true
	q._process(0)
	await wait_job(q, 0)
	expect(q.jobs[0].status == "done", "batch executes")
	q.jobs[0].status = "pending"
	q.running = true
	q._process(0)
	await wait_job(q, 0)
	expect(q.jobs[0].status == "cached", "batch cache hit")
	var corrupt := FileAccess.open(batch_folder.path_join("frame.png"), FileAccess.WRITE)
	corrupt.store_string("corrupt")
	corrupt.close()
	q.jobs[0].status = "pending"
	q.running = true
	q._process(0)
	await wait_job(q, 0)
	expect(q.jobs[0].status == "done", "cache detects corrupted output")
	q.enqueue(output.path_join("absent.json"), output.path_join("missing"))
	q.running = true
	q._process(0)
	await wait_job(q, 1)
	expect(q.jobs[1].status == "failed", "batch records missing input failure")
	var duplicate: String = q.enqueue("same.json", "same_folder")
	expect(q.enqueue("same.json", "same_folder") == duplicate, "pending tasks deduplicate by input and destination")
	q.cancel(duplicate)
	expect(q.find_job(duplicate).status == "cancelled", "queued task cancellation")
	var budget_id: String = q.enqueue(project_path, output.path_join("over_budget"))
	q.find_job(budget_id).estimated_mb = q.ram_budget_mb + 1
	q.running = true
	await process_frame
	expect(q.find_job(budget_id).status == "failed" and q.active_pid == -1, "memory admission blocks over-budget job before spawning")
	q.running = false
	q.jobs[0].status = "running"
	q.persist()
	var resumed = Queue.new()
	resumed.checkpoint_path = q.checkpoint_path
	root.add_child(resumed)
	expect(resumed.jobs[0].status == "pending" and not resumed.running, "checkpoint resumes interrupted job without auto execution")
	resumed.free()
	q.free()
	await extended_tests()
	# Instantiate the real UI and exercise document changes without a display.
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = output.path_join("regression_workspace_" + str(Time.get_ticks_usec()))
	root.add_child(ui)
	ui.queue.jobs.clear()
	ui.queue.checkpoint_path = output.path_join("ui_queue_" + str(Time.get_ticks_usec()) + ".json")
	ui.queue.request_root = output.path_join("ui_worker_requests")
	await process_frame
	var workspace_names: Array = []
	for index in ui.tabs.get_tab_count(): workspace_names.append(ui.tabs.get_tab_title(index))
	expect(ui.canvas.texture != null and workspace_names.has("IA Assistida") and workspace_names.has("HyperLearn Lab") and workspace_names.has("Biblioteca pública") and workspace_names.has("Revisão animada"), "UI boots with editor, AI, library and animation review workspaces")
	var original_document_id: String = ui.workspace.active_id
	var document_count_before: int = ui.workspace.records.size()
	var oversized_document_id: String = ui.create_blank_document(512, 512, 32, 8)
	expect(oversized_document_id.is_empty() and ui.workspace.records.size() == document_count_before, "UI recusa nova tela acima do limite antes de adicionar documento à sessão")
	ui.new_document()
	await process_frame
	var new_document_dialog: ConfirmationDialog = ui.get_node_or_null("NewDocumentDialog")
	var canvas_width_input: SpinBox = new_document_dialog.find_child("CanvasWidth", true, false) if new_document_dialog != null else null
	var canvas_height_input: SpinBox = new_document_dialog.find_child("CanvasHeight", true, false) if new_document_dialog != null else null
	var frame_count_input: SpinBox = new_document_dialog.find_child("FrameCount", true, false) if new_document_dialog != null else null
	var frame_rate_input: SpinBox = new_document_dialog.find_child("FrameRate", true, false) if new_document_dialog != null else null
	var new_dialog_complete := canvas_width_input != null and canvas_height_input != null and frame_count_input != null and frame_rate_input != null
	if new_dialog_complete:
		canvas_width_input.value = 48; canvas_height_input.value = 64; frame_count_input.value = 6; frame_rate_input.value = 12
		new_document_dialog.emit_signal("confirmed")
	await process_frame
	var blank_document_id: String = ui.workspace.active_id
	var blank_document_record: Dictionary = ui.workspace.find(blank_document_id)
	var new_blank: Variant = blank_document_record.get("doc")
	var new_blank_clear: bool = new_blank != null and new_blank.width == 48 and new_blank.height == 64 and new_blank.frames == 6 and new_blank.fps == 12 and new_blank.validate().is_empty()
	expect(new_dialog_complete and blank_document_id != original_document_id and new_blank_clear, "diálogo real cria e abre projeto transparente retangular com timeline e FPS configurados")
	if not blank_document_id.is_empty(): ui.workspace.close_document(blank_document_id, true, false)
	ui.workspace.activate(original_document_id)
	ui.refresh_all()
	var timeline_widget: Control = ui.timeline_view
	var timeline_cells: Array = timeline_widget.get("frame_cells")
	expect(timeline_cells.size() == ui.doc.layers.size() and timeline_cells[0].size() == ui.doc.frames, "timeline builds a frame track for every layer")
	var timeline_thumb: Button = timeline_cells[0][0]
	var thumb_texture: TextureRect = timeline_thumb.get_child(0).get_child(0) as TextureRect
	expect(timeline_thumb.get_child_count() == 1 and thumb_texture != null and thumb_texture.texture != null, "timeline cell contains a nearest-neighbor image thumbnail")
	var frame_button: Button = timeline_cells[0][2]
	frame_button.emit_signal("pressed")
	expect(ui.doc.frame == 2, "timeline selection changes the editor frame")
	ui.seek_frame(0)
	ui.canvas.tool = "Lápis"
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = ui.canvas.origin() + Vector2(2.5, 2.5) * ui.canvas.zoom
	ui.canvas._gui_input(press)
	press.pressed = false
	ui.canvas._gui_input(press)
	expect(ui.doc.current().get_pixel(2, 2) == ui.canvas.color, "canvas mouse stroke writes correct pixel")
	ui.canvas.onion = true
	ui.canvas.refresh()
	expect(ui.canvas.onion_texture != null and ui.canvas.onion_next_texture != null, "onion skin prepares the adjacent frames from the active clip sequence")
	ui.canvas.onion = false
	ui.canvas.refresh()
	ui.step_frame(1)
	expect(ui.doc.frame == 1 and not ui.playing, "frame step pauses playback")
	ui.step_frame(-1)
	ui.doc.checkpoint()
	ui.doc.pixel(Vector2i(0, 0), Color.RED)
	ui.edited()
	ui.undo()
	expect(ui.doc.current().get_pixel(0, 0).a == 0, "UI undo updates document")
	ui.redo()
	expect(ui.doc.current().get_pixel(0, 0) == Color.RED, "UI redo updates document")
	ui.doc.duplicate_frame()
	ui.refresh_all()
	timeline_cells = timeline_widget.get("frame_cells")
	expect(timeline_cells[0].size() == 5, "per-layer timeline refreshes after frame insertion")
	expect(ui.world.solid(Vector2(0, 0)) and not ui.world.solid(Vector2(160, 120)), "playable preview collision boundaries")
	var imported_id: String = ui.queue.enqueue("res://examples/arton/biblioteca.json", output.path_join("queued_arton_" + str(Time.get_ticks_usec())), 100, [], "import_arton", {"family": "humanoide", "garments": true})
	ui.queue.request_root = output.path_join("ui_arton_requests")
	ui.queue.running = true
	var import_deadline := Time.get_ticks_msec() + 20000
	while ui.queue.find_job(imported_id).status in ["pending", "running", "preparing", "validating"] and Time.get_ticks_msec() < import_deadline: await process_frame
	var imported_job: Dictionary = ui.queue.find_job(imported_id)
	expect(imported_job.status == "done" and FileAccess.file_exists(imported_job.project_path), "Arton import completes through real isolated worker")
	if imported_job.status == "done":
		ui.selected_open(imported_job.project_path)
		expect(ui.doc.width == 256 and ui.doc.frames == 1 and ui.doc.layers.size() == 2, "UI opens native-resolution imported project")
		ui.doc.active_layer = 1
		ui.refresh_layer()
		ui.set_layer("visible", true)
		expect(ui.layers_list.get_item_text(1).begins_with("●"), "visibility inspector updates layer list")
	var python: String = OS.get_environment("SFS_TEST_PYTHON")
	if python != "":
		ui.catalog.python_path = python
		ui.catalog.data_root = output.path_join("catalog_" + str(Time.get_ticks_usec()))
		var response: Array = []
		ui.catalog.completed.connect(func(result): response.append(result))
		expect(ui.catalog.index(ui.doc, ""), "Godot launches optional Python catalog service")
		var deadline := Time.get_ticks_msec() + 20000
		while response.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
		expect(not response.is_empty() and response[0].get("ok", false) and FileAccess.file_exists(ui.catalog.data_root.path_join("catalog.sqlite")), "Godot Python SQLite protocol completes")
	ui.free()
	s.atomic_json(output.path_join("report.json"), {"passed": passed, "failed": failed, "engine": Engine.get_version_info().string, "checks": checks})
	print("RESULT ", passed, " passed / ", failed, " failed")
	quit(1 if failed > 0 else 0)

func extended_tests() -> void:
	var storage = Storage.new()
	var p = Doc.new()
	p.palette = ["#000000", "#ffffff"]
	p.pixel(Vector2i(3, 3), Color("abcdef"))
	p.pixel(Vector2i(2, 2), Color.RED)
	p.selection = Rect2i(3, 3, 1, 1)
	var precision = Precision.new()
	var draft: Dictionary = precision.draft_palette(p)
	expect(p.current().get_pixel(3, 3) == Color("abcdef"), "precision draft leaves source untouched")
	expect(draft.changed == 1 and draft.after.get_pixel(2, 2) == Color.RED, "precision changes selection only")
	expect(precision.accept(p, draft) and p.current().get_pixel(3, 3) == Color.WHITE, "precision explicit acceptance")
	p.undo()
	expect(p.current().get_pixel(3, 3) == Color("abcdef"), "accepted precision correction is undoable")
	draft = precision.draft_palette(p)
	p.mark_changed()
	expect(not precision.accept(p, draft), "precision stale proposal refused")
	p.protect_selection()
	p.pixel(Vector2i(3, 3), Color.GREEN)
	expect(p.current().get_pixel(3, 3) == Color("abcdef") and not p.transform_pixels("flip_x"), "protected pixels block paint and transforms")
	storage.save_document(p, output.path_join("protected.sfs.json"))
	var loaded = storage.load_document(output.path_join("protected.sfs.json"))
	expect(loaded != null and not loaded.allowed(Vector2i(3, 3)), "pixel protection survives JSON number conversion")
	p.protect_selection(true)
	p.selection = Rect2i(2, 2, 2, 2)
	p.copy_pixels()
	p.transform_pixels("flip_x")
	expect(p.current().get_pixel(3, 2) == Color.RED, "selection horizontal flip")
	p.undo()
	p.transform_pixels("rotate")
	expect(p.current().get_pixel(3, 2) == Color.RED, "square selection 90 degree rotation")
	p.undo()
	p.transform_pixels("move", Vector2i(2, 0))
	expect(p.current().get_pixel(4, 2) == Color.RED and p.current().get_pixel(2, 2).a == 0, "selection translation clears source")
	p.paste_pixels()
	expect(p.current().get_pixel(4, 2) == Color.RED, "pixel clipboard paste")
	var asymmetric = Doc.new()
	asymmetric.layers[0].asymmetric = true
	asymmetric.pixel(Vector2i(1, 1), Color.RED, true)
	expect(asymmetric.current().get_pixel(1, 1) == Color.RED and asymmetric.current().get_pixel(30, 1).a == 0, "asymmetric layer refuses automatic mirroring")
	var tile_doc = Doc.new()
	tile_doc.map_data.cells[0] = 3 * tile_doc.frames + 3
	tile_doc.duplicate_frame()
	expect(tile_doc.map_data.cells[0] == 3 * 5 + 4, "frame insertion preserves map cel tile identity")
	tile_doc.delete_frame()
	expect(tile_doc.map_data.cells[0] == 3 * 4 + 3, "frame deletion preserves map cel tile identity")
	var rigged = Doc.new()
	rigged.set_anchor("hand", Vector2i(5, 6))
	expect(rigged.anchor_at("hand", 0, 0) == [5, 6] and rigged.anchor_at("hand", 1, 0) == [24, 18], "anchors vary by direction and frame")
	rigged.add_layer("Sword", true)
	rigged.pixel(Vector2i.ZERO, Color.WHITE)
	expect(rigged.composite().get_pixel(5, 6) == Color.WHITE, "equipment uses current cel anchor")
	rigged.rig.family = "quadruped"
	expect(not rigged.validate().is_empty() and rigged.composite().get_pixel(5, 6).a == 0, "incompatible anatomy blocks equipment and export validation")
	rigged.rig.family = "humanoid"
	expect(rigged.add_clip("attack", 1, 3) and not rigged.add_clip("attack", 0, 1), "named clips and unique names")
	rigged.clip().durations_ms["1"] = 350
	rigged.animation.events["0:1"] = ["hitbox_on"]
	rigged.animation.hitboxes["0:1"] = [1, 1, 3, 3]
	rigged.frame = 1
	rigged.duplicate_frame()
	expect(rigged.clip().frames == [1, 2, 3, 4] and rigged.animation.events.has("0:2"), "frame insertion remaps clips and events")
	rigged.delete_frame()
	expect(rigged.clip().frames == [1, 2, 3] and rigged.animation.hitboxes.has("0:1"), "frame deletion remaps hitboxes")
	storage.save_document(rigged, output.path_join("rigged.sfs.json"))
	loaded = storage.load_document(output.path_join("rigged.sfs.json"))
	expect(loaded != null and loaded.clip().frames.find(1) == 0 and is_equal_approx(loaded.frame_seconds(1), 0.35), "clips and variable durations roundtrip with integer indices")
	var damaged: Dictionary = storage.encode(rigged)
	damaged.animation.clips[0].frames = [99]
	storage.atomic_json(output.path_join("bad_clip.json"), damaged)
	expect(storage.load_document(output.path_join("bad_clip.json")) == null, "contract rejects out-of-range animation frame")
	damaged = storage.encode(rigged)
	damaged.rig.protected_pixels = {"0:0": [999999]}
	storage.atomic_json(output.path_join("bad_mask.json"), damaged)
	expect(storage.load_document(output.path_join("bad_mask.json")) == null, "contract rejects malformed protected pixel coordinates")
	storage.export_all(rigged, output.path_join("clips_export"))
	var frames = load(output.path_join("clips_export/animations.tres"))
	expect(frames.get_animation_names().size() == 16 and is_equal_approx(frames.get_frame_duration("attack_N", 0), 0.35), "export named clips with exact duration")
	var old = Doc.new()
	old.pixel(Vector2i(3, 3), Color.RED)
	var legacy: Dictionary = storage.encode(old)
	legacy.schema = 1
	legacy.direction = 4
	for key in ["manifest", "rig", "animation", "revision"]: legacy.erase(key)
	for layer in legacy.layers:
		var rows: Array = layer.cels
		layer.cels = [rows[4], rows[5], rows[6], rows[7], rows[0], rows[1], rows[2], rows[3]]
	legacy.map.cells[0] = 16
	storage.atomic_json(output.path_join("legacy.sfs.json"), legacy)
	loaded = storage.load_document(output.path_join("legacy.sfs.json"))
	expect(loaded != null and loaded.direction == 0 and loaded.current().get_pixel(3, 3) == Color.RED and loaded.map_data.cells[0] == 0, "schema 1 migration preserves orientation and tile indices")
	var refs = References.new()
	var art_doc = Doc.new()
	art_doc.demo()
	art_doc.art.references.append(refs.normalize({"name": "Study", "path": "", "sha256": "abcd", "provenance": "own", "thumbnail": ""}))
	refs.transition(art_doc, 0, "partial", "palette")
	expect(refs.eligible(art_doc, "palette").size() == 1 and refs.eligible(art_doc, "anatomy").is_empty(), "partial reference approval restricts features")
	refs.link(art_doc, 0)
	var memory = Memory.new()
	art_doc.art.candidates.append(memory.propose(art_doc))
	expect(memory.approve(art_doc, 0) and memory.recall(art_doc).size() == 1, "memory recalls approved valid reference rules")
	refs.transition(art_doc, 0, "rejected")
	expect(memory.recall(art_doc).is_empty() and art_doc.manifest.dependencies[0].stale and art_doc.art.references.size() == 1, "rejection invalidates dependents and keeps provenance")
	art_doc.art.locked = true
	refs.transition(art_doc, 0, "approved")
	expect(art_doc.art.references[0].state == "rejected", "Art Lock prevents reference state changes")
	var quality = Quality.new()
	quality.root = output.path_join("approved_" + str(Time.get_ticks_usec()))
	expect(not quality.approve(old, [90, 90, 90, 90], "Reviewer", false), "quality cannot invent human approval")
	expect(not quality.score([100, 100, 100, 70]).passed and quality.score([85, 85, 85, 85]).passed, "weighted quality threshold and per-criterion floor")
	expect(quality.approve(old, [90, 90, 90, 90], "Reviewer", true), "explicit human review creates approved snapshot")
	expect(not quality.approve(old, [90, 90, 90, 90], "Reviewer", true, true), "character approval requires the directional animation gate")
	var character_path := ProjectSettings.globalize_path("res://examples/animation_proof/sentinela.sfs.json")
	var character_doc = storage.load_document(character_path)
	var rejected_memory: RefCounted = character_doc.detached_copy()
	rejected_memory.art.candidates.append(memory.propose(rejected_memory))
	expect(not memory.approve(rejected_memory, 0) and rejected_memory.art.memory.is_empty(), "memória artística não aprende de personagem reprovado")
	var broken_character: RefCounted = character_doc.detached_copy()
	broken_character.animation.events.erase("0:13")
	var broken_character_audit: Dictionary = preload("res://core/character_audit.gd").new().evaluate(broken_character)
	expect(not broken_character_audit.technical_passed, "technical gate refuses a broken attack contact")
	expect(not quality.approve(character_doc, [90, 90, 90, 90], "Reviewer", true, true), "character approval refuses the human-rejected art fixture")
	expect(not quality.reopen_rejected_candidate(character_doc), "rejected art cannot reopen without an edited revision")
	var replacement_candidate: RefCounted = character_doc.detached_copy()
	replacement_candidate.mark_changed()
	expect(quality.reopen_rejected_candidate(replacement_candidate) and replacement_candidate.art.candidate_status == "revision_pending", "edited art opens a new candidate revision without inheriting approval")
	expect(not quality.approve(replacement_candidate, [90, 90, 90, 90], "Reviewer", false, true), "new candidate still requires explicit human review")
	var test_character: RefCounted = character_doc.detached_copy()
	test_character.art.candidate_status = "candidate"
	test_character.mark_changed()
	expect(quality.approve(test_character, [90, 90, 90, 90], "Reviewer", true, true), "a separate unreviewed character can be approved only after technical gate and human confirmation")
	var character_versions: Array = quality.versions(test_character)
	var saved_character = storage.load_document(character_versions[0].path)
	expect(saved_character.manifest.approvals[0].technical_gate.passed and saved_character.manifest.approvals[0].technical_gate.checks > 0, "approved character snapshot preserves its audit provenance")
	var versions: Array = quality.versions(old)
	old.pixel(Vector2i(5, 5), Color.BLUE)
	var comparison: Dictionary = quality.compare(old, versions[0].path)
	expect(comparison.changed == 1 and not comparison.artistic_approval, "version comparison counts changed pixels without approval")
	loaded = storage.load_document(versions[0].path)
	expect(loaded.current().get_pixel(5, 5).a == 0 and loaded.manifest.approvals[0].human, "approved version remains immutable after later edits")
	var planner = Plan.new()
	var plan: Dictionary = planner.plan("Armored character")
	expect(planner.ready(plan.tasks).size() == 1 and planner.ready(plan.tasks)[0].id == "inspect", "DAG starts only satisfied tasks")
	plan.tasks[0].status = "completed"
	expect(planner.ready(plan.tasks)[0].id == "compose", "DAG unlocks dependent task")
	plan.tasks[0].dependencies = ["export"]
	expect(not planner.validate(plan.tasks).is_empty() and planner.ready(plan.tasks).is_empty(), "DAG rejects cycle")
	var nav = Navigation.new()
	var map_doc = Doc.new()
	expect(nav.analyze(map_doc.map_data).connected, "navigation connected open map")
	for y in 16: map_doc.map_data.collision[y * 24 + 12] = true
	expect(nav.analyze(map_doc.map_data).components.size() == 2, "navigation detects disconnected areas")
	# Cancellation before work must preserve pre-existing outputs.
	var cancel := output.path_join("cancel_" + str(Time.get_ticks_usec()))
	var f := FileAccess.open(cancel, FileAccess.WRITE); f.store_string("cancel"); f.close()
	var worker_result: Dictionary = preload("res://core/batch_worker.gd").execute({"input": output.path_join("roundtrip.sfs.json"), "output": output.path_join("export"), "id": "cancel_test", "progress": cancel + ".progress", "cancel": cancel})
	expect(worker_result.status == "cancelled", "worker honors cancellation before publication")
