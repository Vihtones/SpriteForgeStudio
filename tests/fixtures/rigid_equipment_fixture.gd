extends RefCounted

static func build(include_camera: bool = false) -> PackedByteArray:
	var source := Node3D.new()
	source.name = "CustomWeapon"
	var mesh := MeshInstance3D.new()
	mesh.name = "CustomBlade"
	var shape := BoxMesh.new()
	shape.size = Vector3(0.12, 0.75, 0.08)
	mesh.mesh = shape
	mesh.position = Vector3(0.0, -0.35, 0.0)
	source.add_child(mesh)
	mesh.owner = source
	if include_camera:
		var camera := Camera3D.new()
		source.add_child(camera)
		camera.owner = source
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var error := gltf.append_from_scene(source, state)
	var bytes: PackedByteArray = gltf.generate_buffer(state) if error == OK else PackedByteArray()
	source.free()
	return bytes
