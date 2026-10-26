extends RefCounted
## Bounded, local-only loader for portable, self-contained binary glTF models.

const MAX_GLB_BYTES := 16 * 1024 * 1024
const MAX_MESHES := 128
const MAX_VERTEX_COUNT := 1_000_000

func load_glb(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20 or bytes.size() > MAX_GLB_BYTES:
		return {"ok": false, "message": "O modelo GLB precisa ter entre 20 bytes e 16 MiB."}
	if bytes.decode_u32(0) != 0x46546C67:
		return {"ok": false, "message": "O arquivo não possui a assinatura binária GLB válida."}
	if bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size():
		return {"ok": false, "message": "O GLB precisa usar a versão 2 e declarar o tamanho integral do arquivo."}
	var json_length := bytes.decode_u32(12)
	if bytes.decode_u32(16) != 0x4E4F534A or json_length > bytes.size() - 20:
		return {"ok": false, "message": "O GLB não contém um bloco JSON válido."}
	var parser := JSON.new()
	if parser.parse(bytes.slice(20, 20 + json_length).get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok": false, "message": "Os metadados JSON do GLB estão inválidos."}
	for collection in ["buffers", "images"]:
		var entries: Variant = parser.data.get(collection, [])
		if not entries is Array: return {"ok": false, "message": "A estrutura de recursos do GLB está inválida."}
		for entry in entries:
			if not entry is Dictionary: return {"ok": false, "message": "A estrutura de recursos do GLB está inválida."}
			var uri: Variant = entry.get("uri", "")
			if not uri is String or (not uri.is_empty() and not uri.begins_with("data:")):
				return {"ok": false, "message": "Use GLB autocontido: buffers e imagens externos não são aceitos."}
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_buffer(bytes, "", state)
	if error != OK:
		return {"ok": false, "message": "O Godot não conseguiu interpretar o GLB (erro %d)." % error}
	var scene := document.generate_scene(state)
	if scene == null:
		return {"ok": false, "message": "O GLB não pôde ser convertido em uma cena 3D."}
	var mesh_count := 0
	var vertex_count := 0
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			mesh_count += 1
			for surface in node.mesh.get_surface_count():
				vertex_count += node.mesh.surface_get_array_len(surface)
		for child in node.get_children(): pending.append(child)
	if mesh_count == 0:
		scene.free()
		return {"ok": false, "message": "O GLB não contém malhas 3D visíveis para a captura."}
	if mesh_count > MAX_MESHES or vertex_count > MAX_VERTEX_COUNT:
		scene.free()
		return {"ok": false, "message": "O GLB excede o limite do estúdio (%d malhas ou %d vértices)." % [MAX_MESHES, MAX_VERTEX_COUNT]}
	var animation_names := PackedStringArray()
	var players := 0
	pending = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is AnimationPlayer:
			players += 1
			for animation_name in node.get_animation_list():
				if animation_name not in ["RESET", "__default"] and not animation_names.has(animation_name): animation_names.append(animation_name)
		for child in node.get_children(): pending.append(child)
	if players > 8:
		scene.free()
		return {"ok": false, "message": "O GLB contém mais de oito controladores de animação."}
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return {"ok": true, "scene": scene, "mesh_count": mesh_count, "vertex_count": vertex_count, "animation_names": animation_names, "sha256": hash_context.finish().hex_encode()}
