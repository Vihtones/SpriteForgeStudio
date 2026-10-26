extends SceneTree

func _initialize() -> void:
	var doc = preload("res://core/document.gd").new()
	doc.demo()
	var storage = preload("res://core/storage.gd").new()
	DirAccess.make_dir_recursive_absolute("res://examples")
	var result: Error = storage.save_document(doc, "res://examples/demo.sfs.json")
	if result == OK: result = storage.export_all(doc, "res://examples/export")
	var notices := FileAccess.open("res://THIRD_PARTY_LICENSES.txt", FileAccess.WRITE)
	notices.store_string(Engine.get_license_text() + "\n\nTHIRD PARTY COPYRIGHT NOTICES\n\n")
	for info in Engine.get_copyright_info():
		notices.store_string(str(info) + "\n\n")
	for key in Engine.get_license_info():
		notices.store_string(str(key) + "\n" + str(Engine.get_license_info()[key]) + "\n\n")
	notices.close()
	quit(0 if result == OK else 1)
