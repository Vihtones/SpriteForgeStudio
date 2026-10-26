extends RefCounted
const ModelImporter = preload("res://core/three_d_model_importer.gd")
const MAX_BYTES := 4 * 1024 * 1024

static func provenance(asset: Dictionary) -> Dictionary:
	var result := asset.duplicate(true)
	result.erase("glb_base64")
	return result

func descriptor(asset: Dictionary) -> Dictionary:
	for key in ["glb_base64", "sha256", "filename", "source", "license"]:
		if not asset.get(key) is String: return {"ok": false, "message": "Dados de origem do equipamento estão incompletos."}
	if str(asset.glb_base64).length() > ceili(float(MAX_BYTES) * 4.0 / 3.0) + 8 or str(asset.glb_base64).is_empty(): return {"ok": false, "message": "Equipamento GLB excede 4 MiB ou está vazio."}
	if str(asset.sha256).length() != 64 or not str(asset.sha256).is_valid_hex_number(): return {"ok": false, "message": "Hash do equipamento inválido."}
	if str(asset.filename).length() > 256 or str(asset.source).length() > 2048 or str(asset.license).length() > 2048: return {"ok": false, "message": "Nome, origem ou licença excedem o limite de texto."}
	return {"ok": true, "asset": {"glb_base64": asset.glb_base64, "sha256": str(asset.sha256).to_lower(), "filename": str(asset.filename).get_file(), "source": str(asset.source).strip_edges(), "license": str(asset.license).strip_edges(), "review_required": true}}

func prepare(bytes: PackedByteArray, filename: String, source: String = "Arquivo local do usuário", license_text: String = "Não informada") -> Dictionary:
	if bytes.size() > MAX_BYTES: return {"ok": false, "message": "Equipamento GLB deve ter no máximo 4 MiB."}
	var imported: Dictionary = ModelImporter.new().load_glb(bytes)
	if not imported.get("ok", false): return imported
	var root: Node = imported.scene
	var rigid := true
	var affects_stage := false
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Skeleton3D or (node is MeshInstance3D and node.skin != null): rigid = false
		if node is AnimationPlayer and not node.get_animation_list().is_empty(): rigid = false
		if node is Camera3D or node is Light3D or node is WorldEnvironment: affects_stage = true
		for child in node.get_children(): pending.append(child)
	if affects_stage:
		root.free()
		return {"ok": false, "message": "Exporte apenas a geometria do equipamento, sem câmera, luzes ou ambiente."}
	if not rigid or int(imported.mesh_count) > 32 or int(imported.vertex_count) > 100000:
		root.free()
		return {"ok": false, "message": "Use equipamento rígido, sem skin/animação, com até 32 malhas e 100 mil vértices."}
	var normalized: Dictionary = descriptor({"filename": filename, "source": source, "license": license_text, "sha256": imported.sha256, "glb_base64": Marshalls.raw_to_base64(bytes)})
	if not normalized.ok:
		root.free()
		return normalized
	var template := Node3D.new()
	template.name = "RigidEquipmentTemplate"
	template.add_child(root)
	return {"ok": true, "asset": normalized.asset, "template": template}

func load_asset(asset: Dictionary) -> Dictionary:
	var checked := descriptor(asset)
	if not checked.ok: return checked
	var bytes := Marshalls.base64_to_raw(str(checked.asset.glb_base64))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	if context.finish().hex_encode() != checked.asset.sha256: return {"ok": false, "message": "O equipamento GLB falhou na verificação de integridade."}
	return prepare(bytes, str(checked.asset.filename), str(checked.asset.source), str(checked.asset.license))
