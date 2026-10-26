extends RefCounted
## Explicit mappings; no name guessing or anatomical approval.
const JOINTS = ["torso", "left_arm", "right_arm", "left_elbow", "right_elbow", "left_leg", "right_leg", "left_knee", "right_knee"]
const AXES = {"X": Vector3.RIGHT, "Y": Vector3.UP, "Z": Vector3.BACK, "-X": Vector3.LEFT, "-Y": Vector3.DOWN, "-Z": Vector3.FORWARD}

func bones(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(root): return result
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Skeleton3D:
			for index in node.get_bone_count():
				result.append({"skeleton": str(root.get_path_to(node)), "bone": str(node.get_bone_name(index))})
		for child in node.get_children(): pending.append(child)
	return result

func validate(root: Node, mappings: Dictionary) -> Dictionary:
	if mappings.size() > JOINTS.size(): return {"ok": false, "message": "O mapeamento excede nove articulações."}
	var normalized: Dictionary = {}
	var used: Array[String] = []
	for joint in mappings:
		if not str(joint) in JOINTS or not mappings[joint] is Dictionary: return {"ok": false, "message": "Articulação ou vínculo inválido."}
		var entry: Dictionary = mappings[joint]
		var path := str(entry.get("skeleton", ""))
		var bone := str(entry.get("bone", ""))
		var axis := str(entry.get("axis", "X"))
		if not is_instance_valid(root) or not AXES.has(axis): return {"ok": false, "message": "Modelo ausente ou eixo inválido."}
		var skeleton := root.get_node_or_null(NodePath(path)) as Skeleton3D
		if skeleton == null or (skeleton != root and not root.is_ancestor_of(skeleton)) or skeleton.find_bone(bone) < 0: return {"ok": false, "message": "O osso selecionado não pertence ao modelo atual."}
		var identity := path + "|" + bone
		if used.has(identity): return {"ok": false, "message": "Cada osso pode controlar apenas uma articulação SFS."}
		used.append(identity)
		normalized[str(joint)] = {"skeleton": path, "bone": bone, "axis": axis}
	return {"ok": true, "mappings": normalized}

func apply_pose(root: Node, mappings: Dictionary, pose: Dictionary) -> bool:
	var checked := validate(root, mappings)
	if not checked.ok: return false
	for joint in checked.mappings:
		var entry: Dictionary = checked.mappings[joint]
		var angle_value: Variant = pose.get(joint, 0.0)
		if not (angle_value is float or angle_value is int) or not is_finite(float(angle_value)): return false
	for joint in checked.mappings:
		var entry: Dictionary = checked.mappings[joint]
		var skeleton := root.get_node(NodePath(entry.skeleton)) as Skeleton3D
		var index := skeleton.find_bone(str(entry.bone))
		var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(index, (rest_rotation * Quaternion(AXES[entry.axis], float(pose.get(joint, 0.0)))).normalized())
	return true

func reset(root: Node, mappings: Dictionary) -> void:
	if not validate(root, mappings).ok: return
	for entry in mappings.values():
		var skeleton := root.get_node(NodePath(entry.skeleton)) as Skeleton3D
		var index := skeleton.find_bone(str(entry.bone))
		skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion())

func reset_model_pose(root: Node) -> void:
	if not is_instance_valid(root): return
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Skeleton3D: node.reset_bone_poses()
		for child in node.get_children(): pending.append(child)
