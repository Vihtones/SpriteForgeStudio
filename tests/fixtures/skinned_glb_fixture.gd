extends RefCounted
static func build(parent: Node) -> PackedByteArray:
	var source := Node3D.new()
	parent.add_child(source)
	var skeleton := Skeleton3D.new()
	skeleton.name = "TestSkeleton"
	source.add_child(skeleton)
	skeleton.owner = source
	skeleton.add_bone("Shoulder")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	skeleton.reset_bone_poses()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1.2, 0.3)
	var arrays: Array = box.surface_get_arrays(0)
	var bone_indices := PackedInt32Array()
	var weights := PackedFloat32Array()
	bone_indices.resize(arrays[Mesh.ARRAY_VERTEX].size() * 4)
	weights.resize(bone_indices.size())
	for index in arrays[Mesh.ARRAY_VERTEX].size(): weights[index * 4] = 1.0
	arrays[Mesh.ARRAY_BONES] = bone_indices
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	var mesh := MeshInstance3D.new()
	mesh.name = "SkinnedBody"
	mesh.mesh = geometry
	mesh.skin = skin
	mesh.skeleton = NodePath("..")
	skeleton.add_child(mesh)
	mesh.owner = source
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var error := gltf.append_from_scene(source, state)
	var bytes: PackedByteArray = gltf.generate_buffer(state) if error == OK else PackedByteArray()
	source.free()
	return bytes


