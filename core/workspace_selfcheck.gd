extends Node
## Exercises threaded persistence from the shipped pack, without normal user data.
const Workspace = preload("res://core/workspace.gd")
const Doc = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, title: String) -> void:
	checks.append({"ok": ok, "title": title})
	if not ok: failed += 1

func settle(workspace: Node) -> void:
	var started := Time.get_ticks_msec()
	while workspace.busy() and Time.get_ticks_msec() - started < 15000:
		await get_tree().process_frame
	check(not workspace.busy(), "background writer completes")

func run(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var workspace := Workspace.new()
	workspace.data_root = folder.path_join("session")
	add_child(workspace)
	var a := Doc.new()
	var b := Doc.new()
	var a_id := workspace.add_document(a)
	var b_id := workspace.add_document(b)
	a.checkpoint("Initial stroke")
	a.pixel(Vector2i(1, 1), Color.RED)
	var target := folder.path_join("saved.sfs.json")
	check(workspace.request_save(a_id, target), "save admitted")
	a.checkpoint("Edit while saving")
	a.pixel(Vector2i(1, 1), Color.BLUE)
	await settle(workspace)
	var saved = Storage.new().load_document(target)
	check(saved != null and saved.current().get_pixel(1, 1) == Color.RED and a.dirty, "snapshot isolation and concurrent edits")
	b.checkpoint("Unsaved stroke")
	b.pixel(Vector2i(2, 2), Color.GREEN)
	workspace.activate(b_id)
	workspace.request_checkpoint()
	await settle(workspace)
	var restore := Workspace.new()
	restore.data_root = workspace.data_root
	add_child(restore)
	check(restore.restore_session() == 2, "both documents recovered")
	check(restore.current().doc.current().get_pixel(2, 2) == Color.GREEN and restore.current().doc.dirty, "active unsaved pixels recovered")
	restore.free()
	workspace.free()
	Storage.new().atomic_json(folder.path_join("workspace-pack-report.json"), {"ok": failed == 0, "failed": failed, "checks": checks, "engine": Engine.get_version_info().string})
	get_tree().quit(0 if failed == 0 else 1)
