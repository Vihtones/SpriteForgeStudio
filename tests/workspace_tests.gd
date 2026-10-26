extends SceneTree
const Doc = preload("res://core/document.gd")
const Workspace = preload("res://core/workspace.gd")
const Storage = preload("res://core/storage.gd")
const Playback = preload("res://core/playback.gd")
var passed: int = 0
var failed: int = 0
var checks: Array = []
var folder: String = "res://test_results/workspace_" + str(Time.get_ticks_usec())

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: passed += 1; print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func settle(workspace: Node) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while workspace.busy() and Time.get_ticks_msec() < deadline: await process_frame
	expect(not workspace.busy(), "background persistence completes")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var storage := Storage.new()
	var rock := Node.new()
	root.add_child(rock)
	var workspace := Workspace.new()
	workspace.data_root = folder.path_join("session")
	rock.add_child(workspace)
	expect(workspace.is_in_group("Saveable"), "workspace runs on a plain parent and exposes persistence contract")
	var a := Doc.new()
	var b := Doc.new()
	var a_id: String = workspace.add_document(a)
	var b_id: String = workspace.add_document(b)
	a.checkpoint("Lápis A")
	a.pixel(Vector2i(2, 2), Color.RED)
	b.checkpoint("Lápis B")
	b.pixel(Vector2i(2, 2), Color.BLUE)
	workspace.activate(a_id)
	expect(workspace.current().doc == a and b.current().get_pixel(2, 2) == Color.BLUE, "switching document preserves independent buffers")
	a.undo()
	expect(a.current().get_pixel(2, 2).a == 0 and b.current().get_pixel(2, 2) == Color.BLUE, "undo is isolated per document")
	a.redo()
	expect(a.undo_stack[-1].label == "Lápis A", "history labels survive undo/redo")
	a.frame = 2
	a.direction = 3
	a.selection = Rect2i(1, 1, 2, 2)
	a.checkpoint("Contexto")
	a.frame = 1
	a.direction = 0
	a.selection = Rect2i()
	a.undo()
	expect(a.frame == 2 and a.direction == 3 and a.selection == Rect2i(1, 1, 2, 2), "undo restores frame, direction and selection context")
	a.frame = 0; a.direction = 0; a.selection = Rect2i()
	var a_path := folder.path_join("a.sfs.json")
	expect(workspace.request_save(a_id, a_path), "save request accepted")
	a.checkpoint("Edição durante salvamento")
	a.pixel(Vector2i(3, 3), Color.GREEN)
	await settle(workspace)
	var saved = storage.load_document(a_path)
	expect(saved != null and saved.current().get_pixel(3, 3).a == 0, "writer uses immutable captured snapshot")
	expect(a.current().get_pixel(3, 3) == Color.GREEN and a.dirty, "edits during save remain dirty and untouched")
	expect(workspace.destination(a_id) == a_path, "successful save binds destination to correct document")
	expect(not workspace.request_save(b_id, a_path), "another tab cannot overwrite an open document destination")
	workspace.request_save(a_id, a_path)
	await settle(workspace)
	expect(not a.dirty and storage.load_document(a_path).current().get_pixel(3, 3) == Color.GREEN, "latest save clears dirty only at matching revision")
	var same: String = workspace.add_document(storage.load_document(a_path), a_path)
	expect(same == a_id and workspace.records.size() == 2, "opening same file activates existing tab")
	workspace.request_save(b_id, folder.path_join("missing/no.sfs.json"))
	await settle(workspace)
	expect(b.dirty and workspace.find(b_id).path == "" and b.current().get_pixel(2, 2) == Color.BLUE, "failed save retains draft, path and pixels")
	workspace.protected_roots.append(folder.path_join("approved"))
	expect(not workspace.request_save(b_id, folder.path_join("approved/version.sfs.json")), "approved library is protected from Save As overwrite")
	var protected_root := OS.get_environment("SFS_TEST_PROTECTED_ROOT")
	var protected_alias := OS.get_environment("SFS_TEST_PROTECTED_ALIAS")
	if not protected_root.is_empty() and not protected_alias.is_empty():
		workspace.protected_roots.append(protected_root)
		var alias_parent := DirAccess.open(protected_alias.get_base_dir())
		expect(alias_parent != null and alias_parent.is_link(protected_alias.get_file()), "Windows junction security fixture is recognized")
		expect(not workspace.request_save(b_id, protected_alias.path_join("forbidden.sfs.json")), "Save As cannot bypass approved library protection through a junction")
	else:
		print("SKIP Windows junction security regression (fixture unavailable)")
	workspace.find(b_id).view = {"zoom": 7.0, "pan": [17.0, 8.0], "fit": false}
	b.frame = 2; b.direction = 5
	workspace.activate(b_id)
	workspace.request_checkpoint()
	await settle(workspace)
	var manifest = Storage.read_json(workspace.data_root.path_join("session.json"))
	expect(manifest is Dictionary and manifest.documents.size() == 2, "session manifest contains all open documents")
	var reopened := Workspace.new()
	reopened.data_root = workspace.data_root
	rock.add_child(reopened)
	expect(reopened.restore_session() == 2, "session restores saved file and unsaved recovery draft")
	expect(reopened.current().id == b_id and reopened.current().doc.dirty, "recovery restores active dirty draft")
	expect(reopened.current().doc.layers[0].cels[0][0].get_pixel(2, 2) == Color.BLUE and reopened.current().view.pan == [17.0, 8.0], "recovery retains pixels and view state")
	expect(reopened.current().doc.frame == 2 and reopened.current().doc.direction == 5, "recovery restores timeline and direction context")
	b.frame = 0; b.direction = 0
	reopened.free()
	# Queue an older checkpoint, then a newer save with higher priority.
	b.checkpoint("Antes da recuperação")
	b.pixel(Vector2i(5, 5), Color.YELLOW)
	workspace.request_checkpoint()
	b.checkpoint("Versão mais recente")
	b.pixel(Vector2i(6, 6), Color.MAGENTA)
	var b_path := folder.path_join("b.sfs.json")
	workspace.request_save(b_id, b_path)
	await settle(workspace)
	manifest = Storage.read_json(workspace.data_root.path_join("session.json"))
	var b_entry: Dictionary = manifest.documents.filter(func(entry): return entry.id == b_id)[0]
	expect(b_entry.recovery_path == "", "older checkpoint cannot shadow a newer saved version")
	reopened = Workspace.new()
	reopened.data_root = workspace.data_root
	rock.add_child(reopened)
	reopened.restore_session()
	expect(reopened.find(b_id).doc.current().get_pixel(6, 6) == Color.MAGENTA, "restoration selects latest saved bytes over stale recovery")
	reopened.free()
	var export_path := folder.path_join("export_snapshot.sfs.json")
	a.checkpoint("Edit before export"); a.pixel(Vector2i(7, 7), Color.CYAN)
	workspace.request_export_snapshot(a_id, export_path)
	await settle(workspace)
	expect(a.dirty and storage.load_document(export_path).current().get_pixel(7, 7) == Color.CYAN, "export snapshot never marks editing document saved")
	expect(not workspace.close_document(a_id), "dirty close is refused without explicit discard")
	expect(workspace.close_document(a_id, true) and workspace.records.size() == 1, "explicit discard closes only requested document")
	workspace.close_document(b_id)
	expect(workspace.records.size() == 1 and workspace.current().doc != b, "closing final tab creates a fresh usable document")
	var before: Dictionary = workspace.get_save_data()
	storage.atomic_json(workspace.data_root.path_join("session.json"), {"schema": 99})
	expect(workspace.restore_session() == 0 and workspace.records.size() == before.documents.size(), "invalid recovery leaves existing documents intact")
	workspace.free()
	var limited := Workspace.new()
	limited.data_root = folder.path_join("limited")
	rock.add_child(limited)
	for i in 8: limited.add_document(Doc.new())
	expect(limited.add_document(Doc.new()) == "" and limited.records.size() == 8, "workspace document count admission is enforced")
	limited.free()
	limited = Workspace.new()
	limited.data_root = folder.path_join("budget")
	limited.pixel_budget_bytes = 393216
	rock.add_child(limited)
	var budget_a := Doc.new()
	var budget_b := Doc.new()
	limited.add_document(budget_a)
	limited.add_document(budget_b)
	expect(budget_b.add_layer("Extra"), "remaining workspace pixel budget admits one layer")
	limited.refresh_budgets()
	expect(not budget_a.add_layer("Too much") and not budget_b.duplicate_frame(), "document growth respects aggregate workspace budget")
	limited.free()
	var shutdown_workspace := Workspace.new()
	shutdown_workspace.data_root = folder.path_join("shutdown-flush")
	rock.add_child(shutdown_workspace)
	var shutdown_doc := Doc.new()
	shutdown_workspace.add_document(shutdown_doc)
	shutdown_doc.checkpoint("Antes de fechar")
	shutdown_doc.pixel(Vector2i(12, 12), Color.ORANGE)
	shutdown_workspace.request_checkpoint()
	shutdown_workspace.free()
	var post_shutdown_workspace := Workspace.new()
	post_shutdown_workspace.data_root = folder.path_join("shutdown-flush")
	rock.add_child(post_shutdown_workspace)
	var shutdown_restored := post_shutdown_workspace.restore_session()
	expect(shutdown_restored == 1 and post_shutdown_workspace.current().doc.current().get_pixel(12, 12) == Color.ORANGE, "closing the workspace flushes queued recovery data before exiting the tree")
	post_shutdown_workspace.free()
	var racing_workspace := Workspace.new()
	racing_workspace.data_root = folder.path_join("checkpoint-race")
	rock.add_child(racing_workspace)
	var racing_doc := Doc.new()
	var racing_id := racing_workspace.add_document(racing_doc)
	racing_doc.checkpoint("Antes do checkpoint")
	racing_doc.pixel(Vector2i(9, 9), Color.RED)
	expect(racing_workspace.request_checkpoint(), "initial recovery checkpoint is accepted")
	racing_workspace._process(0.0)
	racing_doc.checkpoint("Durante o checkpoint")
	racing_doc.pixel(Vector2i(10, 10), Color.CYAN)
	expect(racing_workspace.request_checkpoint(), "edits during an active checkpoint request one coalesced follow-up")
	await settle(racing_workspace)
	var race_manifest: Variant = Storage.read_json(racing_workspace.data_root.path_join("session.json"))
	var race_entry: Dictionary = race_manifest.documents.filter(func(entry): return entry.id == racing_id)[0] if race_manifest is Dictionary and race_manifest.get("documents", []) is Array and not race_manifest.documents.is_empty() else {}
	var recovered_race = storage.load_document(str(race_entry.get("recovery_path", ""))) if not race_entry.is_empty() else null
	expect(recovered_race != null and recovered_race.current().get_pixel(9, 9) == Color.RED and recovered_race.current().get_pixel(10, 10) == Color.CYAN, "coalesced recovery contains edits made while the previous checkpoint was writing")
	racing_workspace.free()
	var source := Doc.new()
	expect(source.rig.skeleton.size() == 13 and source.anchors.has("elbow_l") and source.validate().is_empty(), "anatomy rig starts with named joints and connected skeleton guides")
	expect(source.add_anchor("tail_tip", Vector2i(4, 4)), "custom articulation is added within the canvas")
	source.direction = 2
	source.frame = 1
	source.set_anchor("tail_tip", Vector2i(5, 6))
	expect(source.anchor_at("tail_tip") == [5, 6] and source.anchor_at("tail_tip", 2, 0) == [4, 4], "custom joint poses are independent by direction and frame")
	source.layers[0].anchor = "tail_tip"
	expect(not source.remove_anchor("tail_tip"), "an articulation bound to a modular layer cannot be removed")
	source.layers[0].anchor = "hand"
	expect(source.remove_anchor("tail_tip") and not source.anchors.has("tail_tip"), "unused custom articulation can be removed with its pose overrides")
	expect(source.undo() and source.anchors.has("tail_tip") and source.anchor_at("tail_tip", 2, 1) == [5, 6], "joint removal and per-cel pose are undoable")
	expect(not source.add_anchor("bad name", Vector2i(1, 1)) and not source.add_anchor("outside", Vector2i(-1, 0)), "articulation names and coordinates are validated")
	var pose := Doc.new()
	var pose_layer: Dictionary = pose.layers[0]
	var pose_source: Image = pose_layer.cels[0][0]
	pose_source.set_pixel(20, 6, Color.RED)
	pose_layer.pivot = "head"
	expect(pose.set_layer_rotation(pose_layer.id, 90.0) and pose.composite().get_pixel(16, 10) == Color.RED, "rigid layer rotation follows its selected joint with nearest-neighbor sampling")
	expect(pose_source.get_pixel(20, 6) == Color.RED and pose_source.get_pixel(16, 10).a == 0.0, "posing preserves the original cel pixels")
	expect(not pose.set_layer_rotation(pose_layer.id, 181.0), "layer pose rejects rotation outside the supported range")
	pose.direction = 3
	pose.frame = 1
	expect(pose.set_layer_rotation(pose_layer.id, -45.0) and pose.duplicate_frame(), "frame insertion accepts and remaps rigid joint poses")
	expect(is_equal_approx(pose.layer_rotation(pose_layer.id, 3, 1), -45.0) and is_equal_approx(pose.layer_rotation(pose_layer.id, 3, 2), -45.0), "frame insertion duplicates per-layer rotation keys")
	pose.frame = 2
	pose.delete_frame()
	expect(is_equal_approx(pose.layer_rotation(pose_layer.id, 3, 1), -45.0), "frame deletion keeps the corresponding rigid pose")
	pose.undo()
	expect(is_equal_approx(pose.layer_rotation(pose_layer.id, 3, 2), -45.0), "frame remapping of rig poses is undoable")
	var rig_path := folder.path_join("rig_roundtrip.sfs.json")
	expect(storage.save_document(pose, rig_path) == OK, "anatomy rig saves through the native project format")
	var loaded_rig = storage.load_document(rig_path)
	expect(loaded_rig != null and loaded_rig.rig.skeleton == pose.rig.skeleton and is_equal_approx(loaded_rig.layer_rotation(pose_layer.id, 3, 2), -45.0), "skeleton topology and rigid poses survive save and load")
	var pose_export := folder.path_join("pose_export")
	expect(storage.export_all(pose, pose_export) == OK, "rotated anatomy exports to the Godot animation package")
	var pose_sheet := Image.new()
	expect(pose_sheet.load(pose_export.path_join("spritesheet.png")) == OK and pose_sheet.get_pixel(16, 10) == Color.RED and pose_sheet.get_pixel(20, 6).a == 0.0, "spritesheet bakes the joint pose while preserving the untouched source cel")
	var correction = preload("res://core/precision.gd").new()
	source.pixel(Vector2i(1, 1), Color.RED)
	var draft := correction.draft_palette(source)
	var other: RefCounted = source.detached_copy()
	expect(not correction.accept(other, draft), "precision proposal cannot cross identical document instances")
	other.pixel(Vector2i(1, 1), Color.BLUE)
	expect(source.current().get_pixel(1, 1) == Color.RED, "detached snapshot owns independent images")
	var anim := Doc.new()
	anim.fps = 10
	anim.clip().durations_ms = {"0": 100, "1": 200, "2": 100, "3": 100}
	var original_clip_frames: Array = anim.clip().frames.duplicate()
	expect(anim.duplicate_clip(), "animation clip duplicates as a reusable independent definition")
	var cloned_clip_name: String = anim.clip().name
	anim.clip().frames[0] = 3
	anim.clip().durations_ms["0"] = 900
	expect(anim.animation.clips[0].frames == original_clip_frames and anim.animation.clips[0].durations_ms.get("0", 0) != 900, "editing a copied clip does not mutate its source")
	expect(anim.rename_clip("attack_heavy") and anim.clip().name == "attack_heavy", "animation clip renames with a stable unique identifier")
	expect(not anim.rename_clip("walk") and not anim.rename_clip("com ataque"), "animation clip rejects duplicate and unsafe names")
	expect(anim.delete_clip() and anim.animation.clips.size() == 1 and anim.clip().name == "walk", "clip deletion preserves frames and selects the remaining clip")
	expect(not anim.delete_clip() and not anim.animation.clips.is_empty(), "document cannot delete its final animation clip")
	expect(anim.undo() and anim.animation.clips.size() == 2, "clip deletion is undoable")
	anim.animation.active = 0
	anim.animation.clips[1].name = cloned_clip_name
	var clock := Playback.new()
	var tick: Dictionary = clock.tick(anim, 0, 0.35)
	expect(tick.frame == 2 and tick.entered == [1, 2] and is_equal_approx(clock.elapsed, 0.05), "playback catches up multiple frames and preserves fractional time")
	clock.reset()
	tick = clock.tick(anim, 0, 0.3, 1.0, true)
	expect(tick.frame == 1 and tick.entered == [3, 2, 1], "reverse playback follows clip sequence")
	anim.clip().loop = false
	clock.reset()
	tick = clock.tick(anim, 0, 1.0)
	expect(tick.frame == 3 and tick.finished, "non-looping playback stops after final frame duration")
	clock.reset()
	tick = clock.tick(anim, 0, 0.05, 2.0)
	expect(tick.frame == 1, "playback speed scales frame durations")
	anim.clip().loop = true
	clock.reset()
	tick = clock.tick(anim, 0, 100, 400.0)
	expect(tick.catchup_limited and tick.entered.size() <= 64, "large playback stall has bounded work")
	await ui_tests()
	rock.free()
	storage.atomic_json("res://test_results/workspace-report.json", {"passed": passed, "failed": failed, "checks": checks})
	print("WORKSPACE RESULT ", passed, " passed / ", failed, " failed")
	quit(1 if failed > 0 else 0)

func ui_tests() -> void:
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = folder.path_join("ui_workspace")
	root.add_child(ui)
	ui.queue.jobs.clear()
	ui.queue.checkpoint_path = folder.path_join("ui_queue.json")
	await process_frame
	expect(ui.clip_picker != null and ui.clip_picker.item_count >= 1, "animation studio exposes managed clip selection")
	expect(ui.joint_picker != null and ui.joint_picker.item_count >= 13, "pixel studio exposes named joints for the rig overlay")
	expect(ui.pivot_picker != null and ui.rotation_control != null, "pixel studio exposes per-layer pivot and pose controls")
	expect(ui.world.textures.is_empty() and ui.art_library_data.is_empty(), "hidden map and database do not populate startup caches")
	var first_id: String = ui.workspace.active_id
	var first: RefCounted = ui.doc
	ui.select_drawing_tool(3)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	press.position = ui.canvas.origin() + Vector2(2.5, 2.5) * ui.canvas.zoom
	ui.canvas._gui_input(press)
	var second := Doc.new()
	var second_id: String = ui.workspace.add_document(second)
	press.pressed = false
	ui.canvas._gui_input(press)
	expect(not ui.canvas.drawing and second.current().get_pixel(2, 2).a == 0, "switching tabs cancels pending geometry gesture")
	ui.workspace.activate(first_id)
	ui.select_drawing_tool(0)
	ui.playing = true
	press.pressed = true
	press.position = ui.canvas.origin() + Vector2(2.5, 2.5) * ui.canvas.zoom
	ui.canvas._gui_input(press)
	press.pressed = false
	ui.canvas._gui_input(press)
	expect(not ui.playing and first.current().get_pixel(2, 2) == ui.canvas.color, "painting pauses playback before changing pixels")
	first.selection = Rect2i(2, 2, 1, 1)
	ui.copy_pixels()
	ui.workspace.activate(second_id)
	second.selection = Rect2i(5, 5, 1, 1)
	ui.paste_pixels()
	expect(second.current().get_pixel(5, 5) == first.current().get_pixel(2, 2), "pixel clipboard works across document tabs")
	var target := folder.path_join("ui_saved.sfs.json")
	ui._save_target_id = second_id
	ui.dialog_action = "save"
	ui.selected_path(target)
	await settle(ui.workspace)
	expect(ui.workspace.find(second_id).path == target and not second.dirty, "UI background Save As updates matching tab and dirty state")
	ui.workspace.activate(first_id)
	expect(ui.doc == first and ui.document_tabs.tab_count == 2 and first.dirty, "returning to another tab preserves pending edits")
	ui.canvas.fit_canvas()
	expect(ui.canvas.pan == Vector2.ZERO and ui.canvas.zoom > 0, "fit canvas resets view without editing pixels")
	ui.seek_frame(2)
	expect(ui.doc.frame == 2 and not ui.playing, "timeline seek pauses animation")
	first.add_layer("Equipment", true)
	first.set_anchor("hand", Vector2i.ZERO)
	first.layers[first.active_layer].offset = [4, 3]
	first.selection = Rect2i()
	ui.select_drawing_tool(0)
	press.pressed = true
	press.position = ui.canvas.origin() + Vector2(5.5, 4.5) * ui.canvas.zoom
	ui.canvas._gui_input(press)
	press.pressed = false
	ui.canvas._gui_input(press)
	expect(first.current().get_pixel(1, 1) == ui.canvas.color and first.composite().get_pixel(5, 4) == ui.canvas.color, "painting offset equipment maps visible cursor to local pixels")
	first.selection = Rect2i(1, 1, 2, 2)
	ui.hitbox_from_selection()
	expect(first.animation.hitboxes[first.cel_key()] == [5, 4, 2, 2], "equipment selection creates hitbox in document coordinates")
	ui.start_save_all(false)
	ui.dialog.canceled.emit()
	ui.dialog.hide()
	expect(ui._save_all_ids.is_empty() and ui._pending_close_id == "" and not ui._quit_after_save, "cancelling Save All clears pending close and exit actions")
	var count: int = ui.workspace.records.size()
	ui.request_close_document(first_id)
	for child in ui.get_children():
		if child is ConfirmationDialog and child.visible and child != ui.confirm:
			child.canceled.emit(); child.hide()
	expect(ui.workspace.records.size() == count and first.dirty, "cancelled dirty close retains document and edits")
	ui._quit_after_save = true
	ui._continue_save_all()
	expect(not ui._quit_after_save and ui.workspace.records.size() == count, "Save All exit rechecks edits in earlier tabs before quitting")
	expect(ui.character_audit_button != null and ui.character_audit_report != null and ui.character_approval_button != null, "quality panel exposes technical test and gated character approval actions")
	var proof_path := ProjectSettings.globalize_path("res://examples/animation_proof/sentinela.sfs.json")
	var proof_doc = Storage.new().load_document(proof_path)
	var previous_doc: RefCounted = ui.doc
	ui.doc = proof_doc
	if ui.character_audit_button != null:
		ui.character_audit_button.pressed.emit()
	var gate: Dictionary = ui.character_audit_result
	expect(gate.get("technical_passed", false) and gate.get("human_review_required", false) and not gate.get("artistic_approval", true) and gate.get("art_candidate_status", "") == "rejected", "quality panel runs the technical proof while preserving rejection status")
	expect(ui.character_audit_report.text.contains("ARTE REPROVADA"), "quality panel warns that this sprite is only a rejected technical fixture")
	proof_doc.mark_changed()
	ui.refresh_character_audit_view()
	expect(ui.character_audit_report.text.contains("desatualizado"), "character audit becomes visibly stale after edits")
	proof_doc.art.candidate_status = "approved"
	if ui.character_audit_button != null: ui.character_audit_button.pressed.emit()
	expect(ui.character_audit_report.text.contains("aprovada por revisor humano"), "quality panel shows human approval for an approved character revision")
	ui.doc = previous_doc
	ui.free()
