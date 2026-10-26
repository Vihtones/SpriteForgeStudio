extends RefCounted
const BoneRig = preload("res://core/imported_bone_rig.gd")
const EquipmentAsset = preload("res://core/rigid_equipment_asset.gd")
const EQUIPMENT := ["shield", "sword"]

func validate(root: Node, sockets: Dictionary) -> Dictionary:
	if sockets.size() > 2: return {"ok": false, "message": "Configure apenas os encaixes de arma e escudo."}
	var normalized: Dictionary = {}
	for equipment in sockets:
		if not str(equipment) in EQUIPMENT or not sockets[equipment] is Dictionary: return {"ok": false, "message": "Encaixe de equipamento inválido."}
		var entry: Dictionary = sockets[equipment]
		var checked: Dictionary = BoneRig.new().validate(root, {"left_arm": {"skeleton": entry.get("skeleton", ""), "bone": entry.get("bone", ""), "axis": "X"}})
		if not checked.ok: return checked
		var result: Dictionary = checked.mappings.left_arm.duplicate(true)
		result.erase("axis")
		for property in ["offset", "rotation_degrees"]:
			var vector_value: Variant = entry.get(property, [0.0, 0.0, 0.0])
			if not vector_value is Array or vector_value.size() != 3: return {"ok": false, "message": "Posição e rotação precisam de três coordenadas."}
			var limit := 10.0 if property == "offset" else 360.0
			var components: Array[float] = []
			for value in vector_value:
				if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > limit: return {"ok": false, "message": "Coordenada de equipamento fora do limite permitido."}
				components.append(float(value))
			result[property] = components
		var scale_value: Variant = entry.get("scale", 1.0)
		if not (scale_value is int or scale_value is float) or not is_finite(float(scale_value)) or float(scale_value) < 0.01 or float(scale_value) > 10.0: return {"ok": false, "message": "A escala do equipamento deve estar entre 0,01 e 10."}
		result.scale = float(scale_value)
		if entry.has("asset"):
			if not entry.asset is Dictionary: return {"ok": false, "message": "Asset de equipamento inválido."}
			var asset_check: Dictionary = EquipmentAsset.new().descriptor(entry.asset)
			if not asset_check.ok: return asset_check
			result.asset = asset_check.asset
		normalized[str(equipment)] = result
	return {"ok": true, "sockets": normalized}

func attach(root: Node3D, equipment: String, entry: Dictionary, template: Node3D) -> Dictionary:
	var checked := validate(root, {equipment: entry})
	if not checked.ok or not is_instance_valid(template): return {"ok": false, "message": "Modelo, encaixe ou geometria indisponível."}
	var config: Dictionary = checked.sockets[equipment]
	var skeleton := root.get_node(NodePath(config.skeleton)) as Skeleton3D
	var attachment := BoneAttachment3D.new()
	attachment.name = "SFS_" + equipment + "_Socket"
	skeleton.add_child(attachment)
	attachment.bone_name = str(config.bone)
	var mount := template.duplicate() as Node3D
	mount.name = "Equipment"
	mount.position = Vector3(config.offset[0], config.offset[1], config.offset[2])
	mount.rotation_degrees = Vector3(config.rotation_degrees[0], config.rotation_degrees[1], config.rotation_degrees[2])
	mount.scale = Vector3.ONE * float(config.scale)
	attachment.add_child(mount)
	var pending: Array[Node] = [mount]
	var part_index := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			node.name = "EquipmentPart_%d" % part_index
			part_index += 1
			if node.has_meta("sfs_procedural_mesh"): node.remove_meta("sfs_procedural_mesh")
			if node.has_meta("sfs_capture_pass_key"): node.remove_meta("sfs_capture_pass_key")
			node.add_to_group("sfs_imported_model_mesh")
			for role in ["body", "shield", "sword"]:
				if node.is_in_group("sfs_capture_pass_" + role): node.remove_from_group("sfs_capture_pass_" + role)
			node.add_to_group("sfs_capture_pass_" + equipment)
			node.visible = true
		for child in node.get_children(): pending.append(child)
	return {"ok": true, "attachment": attachment, "mount": mount}
