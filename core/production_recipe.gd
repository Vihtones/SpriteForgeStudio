extends RefCounted
## Portable, bounded recipe for repeating local 3D-to-pixel production.

const ModelImporter = preload("res://core/three_d_model_importer.gd")
const MAX_RECIPE_BYTES := 25165824
const MAX_ART_DIRECTION_CHARS := 12000

func create(doc: RefCounted) -> Dictionary:
	if doc == null:
		return {"ok": false, "message": "Não há projeto ativo para criar a receita."}
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig: Dictionary = rig_value.duplicate(true) if rig_value is Dictionary else {}
	var recipe := {
		"schema": 1,
		"generator": "Sprite Forge Studio",
		"canvas": {"width": int(doc.width), "height": int(doc.height), "frames": int(doc.frames), "fps": int(doc.fps)},
		"palette": doc.palette.duplicate(true),
		"animation": doc.animation.duplicate(true),
		"art_direction": str(doc.art.get("bible", "")),
		"rig": rig,
	}
	var serialized := JSON.stringify(recipe)
	if serialized.to_utf8_buffer().size() > MAX_RECIPE_BYTES:
		return {"ok": false, "message": "A receita ultrapassa 24 MiB. Remova ou reduza o modelo GLB incorporado."}
	return {"ok": true, "recipe": recipe}

func validate(recipe: Variant, doc: RefCounted) -> Dictionary:
	if not recipe is Dictionary or int(recipe.get("schema", 0)) != 1:
		return _failure("Arquivo de receita inválido ou versão não compatível.")
	if doc == null:
		return _failure("Não há projeto ativo para receber a receita.")
	var canvas_value: Variant = recipe.get("canvas", null)
	if not canvas_value is Dictionary:
		return _failure("A receita não contém dimensões válidas de canvas.")
	if int(canvas_value.get("width", 0)) != doc.width or int(canvas_value.get("height", 0)) != doc.height or int(canvas_value.get("frames", 0)) != doc.frames:
		return _failure("A receita exige o mesmo tamanho de canvas e quantidade de quadros do projeto atual.")
	var fps := int(canvas_value.get("fps", 0))
	if fps < 1 or fps > 60:
		return _failure("A taxa de quadros da receita está fora do limite de 1–60 FPS.")
	var palette: Variant = recipe.get("palette", null)
	if not palette is Array or palette.is_empty() or palette.size() > 32:
		return _failure("A receita precisa ter uma paleta de 1 a 32 cores.")
	var color_pattern := RegEx.new()
	color_pattern.compile("^#?[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")
	for color in palette:
		if not color is String or color_pattern.search(color) == null:
			return _failure("A receita contém uma cor de paleta inválida.")
	var bible: Variant = recipe.get("art_direction", null)
	if not bible is String or bible.length() > MAX_ART_DIRECTION_CHARS:
		return _failure("A direção de arte precisa ser texto de até 12.000 caracteres.")
	var rig_value: Variant = recipe.get("rig", null)
	var animation_value: Variant = recipe.get("animation", null)
	if not rig_value is Dictionary or not animation_value is Dictionary:
		return _failure("A receita não contém rig e animação válidos.")
	var rig: Dictionary = rig_value.duplicate(true)
	var model_value: Variant = rig.get("model_asset", {})
	if model_value is Dictionary and not str(model_value.get("glb_base64", "")).is_empty():
		var encoded := str(model_value.glb_base64)
		if encoded.length() > ceili(float(ModelImporter.MAX_GLB_BYTES) * 4.0 / 3.0) + 8:
			return _failure("O modelo incorporado ultrapassa o limite de 16 MiB.")
		var bytes := Marshalls.base64_to_raw(encoded)
		var imported: Dictionary = ModelImporter.new().load_glb(bytes)
		if not imported.get("ok", false):
			return _failure("O modelo da receita não passou na validação GLB: " + str(imported.get("message", "arquivo inválido")))
		var expected_hash := str(model_value.get("sha256", ""))
		if not expected_hash.is_empty() and str(imported.get("sha256", "")) != expected_hash:
			(imported.scene as Node).free()
			return _failure("O hash do modelo GLB não corresponde à receita.")
		(imported.scene as Node).free()
	var candidate: RefCounted = doc.detached_copy()
	candidate.palette = palette.duplicate(true)
	candidate.fps = fps
	candidate.animation = animation_value.duplicate(true)
	candidate.art["bible"] = bible
	candidate.art["three_d_motion_rig"] = rig
	var issues: Array[String] = candidate.validate()
	if not issues.is_empty(): return _failure("A receita não é compatível com este projeto: " + "; ".join(issues))
	return {"ok": true, "rig": rig, "palette": palette.duplicate(true), "fps": fps, "animation": animation_value.duplicate(true), "art_direction": bible}

func apply(recipe: Variant, doc: RefCounted) -> Dictionary:
	var checked := validate(recipe, doc)
	if not checked.get("ok", false): return checked
	if doc.art.get("locked", false): return _failure("Art Lock impede aplicar uma receita de produção.")
	doc.checkpoint("Aplicar receita de produção 3D")
	doc.palette = checked.palette
	doc.fps = int(checked.fps)
	doc.animation = checked.animation
	doc.art["bible"] = str(checked.art_direction)
	doc.art["three_d_motion_rig"] = checked.rig
	doc.mark_changed()
	return {"ok": true, "message": "Receita aplicada. Confira a prévia do modelo e revise a direção de arte antes de capturar."}

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
