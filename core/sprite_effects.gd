extends RefCounted
## Deterministic sprite effects baked into a dedicated raster layer. The recipe stays on the
## layer so the effect can be regenerated; the pixels stay ordinary cels for editing and export.
const TYPES := ["glow", "flash", "particles"]
const VERSION := 1
const MAX_LAYERS := 16
const NEIGHBORS_4 := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
const NEIGHBORS_8 := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]
## Inclusive numeric bounds per type. Missing params take the first listed default.
const PARAMS := {
	"glow": {"radius": [2, 1, 4], "neighbors": [8, 4, 8], "pulse": [0, 0, 1]},
	"flash": {},
	"particles": {"count": [3, 1, 8], "life": [4, 1, 8], "speed": [1.5, 0.25, 6.0], "angle": [-90.0, -180.0, 180.0], "spread": [45.0, 0.0, 180.0], "gravity": [0.25, -2.0, 2.0], "size": [1, 1, 2]},
}

## recipe: {type, frames, source_layer_id (glow/flash), ramp (glow/particles), color (flash),
## anchor/clip/seed (particles), params}. target_layer_id regenerates an existing effect layer.
func build(doc: RefCounted, recipe: Dictionary, target_layer_id: String = "") -> Dictionary:
	if doc == null or doc.layers.is_empty(): return _failure("Documento ou camada inválidos.")
	if doc.art.get("locked", false): return _failure("Art Lock impede gerar efeitos.")
	var normalized := normalize_recipe(doc, recipe)
	if not normalized.get("ok", false): return normalized
	var effect: Dictionary = normalized.effect
	var target_index := -1
	if not target_layer_id.is_empty():
		target_index = _layer_index(doc, target_layer_id)
		if target_index < 0 or not doc.layers[target_index].get("effect") is Dictionary: return _failure("A camada de efeito a regenerar não existe.")
		if doc.layers[target_index].locked: return _failure("A camada de efeito está bloqueada.")
		if str(effect.get("source_layer_id", "")) == target_layer_id: return _failure("Um efeito não pode usar a própria camada como fonte.")
	elif doc.layers.size() >= MAX_LAYERS or doc.width * doc.height * 4 * doc.frames * 8 * (doc.layers.size() + 1) > doc.pixel_budget_limit:
		return _failure("Limite de 16 camadas ou de memória atingido.")
	var cels := render(doc, effect)
	var retouched: Array[String] = []
	if target_index >= 0:
		var baseline: Dictionary = doc.layers[target_index].effect.get("baseline", {})
		for d in 8:
			for f in doc.frames:
				var key: String = doc.cel_key(d, f)
				if _image_hash(doc.layers[target_index].cels[d][f]) != str(baseline.get(key, _blank_hash(doc))): retouched.append(key)
	var changed := 0
	for d in 8:
		for f in doc.frames:
			var before: Image = doc.layers[target_index].cels[d][f] if target_index >= 0 else doc.blank()
			if before.get_data() != cels[d][f].get_data(): changed += 1
	return {
		"ok": true, "document_instance": doc.get_instance_id(), "revision": doc.revision, "effect": effect,
		"target_layer_id": target_layer_id, "cels": cels, "changed_cels": changed, "retouched_cels": retouched,
		"palette_before": doc.palette.duplicate(), "ramps_before": doc.art.get("material_ramps", []).duplicate(true),
		"message": "%s • %d cels alteradas • %d cels retocadas serão substituídas." % [str(effect.type), changed, retouched.size()],
	}

func apply(doc: RefCounted, proposal: Dictionary, layer_name: String = "") -> bool:
	if doc == null or not proposal.get("ok", false): return false
	if int(proposal.get("document_instance", -1)) != doc.get_instance_id() or int(proposal.get("revision", -1)) != doc.revision: return false
	if doc.art.get("locked", false) or doc.palette != proposal.get("palette_before", []) or doc.art.get("material_ramps", []) != proposal.get("ramps_before", []): return false
	var effect: Variant = proposal.get("effect")
	var cels: Variant = proposal.get("cels")
	if not effect is Dictionary or not cels is Array or cels.size() != 8: return false
	for row in cels:
		if not row is Array or row.size() != doc.frames: return false
		for image in row:
			if not image is Image or image.get_size() != Vector2i(doc.width, doc.height): return false
	var target_id := str(proposal.get("target_layer_id", ""))
	var target_index := -1
	if not target_id.is_empty():
		target_index = _layer_index(doc, target_id)
		if target_index < 0 or doc.layers[target_index].locked or not doc.layers[target_index].get("effect") is Dictionary: return false
	elif doc.layers.size() >= MAX_LAYERS: return false
	var source_index := _layer_index(doc, str(effect.get("source_layer_id", "")))
	if effect.type != "particles" and source_index < 0: return false
	var stored: Dictionary = effect.duplicate(true)
	var baseline := {}
	var blank_hash := _blank_hash(doc)
	for d in 8:
		for f in doc.frames:
			var digest := _image_hash(cels[d][f])
			if digest != blank_hash: baseline[doc.cel_key(d, f)] = digest
	stored.baseline = baseline
	doc.checkpoint("Gerar efeito")
	var copied: Array = []
	for row in cels:
		var images: Array = []
		for image in row: images.append(image.duplicate())
		copied.append(images)
	if target_index >= 0:
		var layer: Dictionary = doc.layers[target_index]
		_remove_events(doc, str(layer.effect.get("event_tag", "")))
		layer.cels = copied
		stored.event_tag = str(layer.effect.get("event_tag", layer.name))
		layer.effect = stored
		doc.active_layer = target_index
	else:
		var title := layer_name.strip_edges().left(64)
		if title.is_empty(): title = "Efeito %s" % _type_label(str(effect.type))
		var layer := {"id": Crypto.new().generate_random_bytes(8).hex_encode(), "name": title, "retarget_key": "effect_" + str(effect.type), "visible": true, "locked": false, "opacity": 1.0, "equipment": false, "asymmetric": false, "families": [doc.rig.family], "anchor": "feet", "pivot": "feet", "bone": [], "offset": [0, 0], "cels": copied}
		stored.event_tag = _event_tag(title)
		layer.effect = stored
		# Glow sits under its source; flash covers it. Particles go on top of everything.
		var insert_at: int = doc.layers.size()
		if source_index >= 0: insert_at = source_index if effect.type == "glow" else source_index + 1
		doc.layers.insert(insert_at, layer)
		if source_index >= 0:
			var source_id := str(doc.layers[source_index + (1 if insert_at <= source_index else 0)].id)
			for depth_values in doc.rig.get("depth", {}).values():
				if depth_values.has(source_id): depth_values[str(layer.id)] = depth_values[source_id]
		doc.active_layer = insert_at
	_write_events(doc, stored)
	doc.art.pose_approvals = []
	doc.art.candidate_status = "candidate"
	doc.manifest.approvals = []
	doc.manifest.provenance = str(doc.manifest.get("provenance", "")) + " Efeito %s gerado deterministicamente (v%d); aprovações artísticas reiniciadas." % [str(effect.type), VERSION]
	return true

## Validates and fills a recipe against the document. Returns {ok, effect} or a failure.
func normalize_recipe(doc: RefCounted, recipe: Dictionary) -> Dictionary:
	var type := str(recipe.get("type", ""))
	if type not in TYPES: return _failure("Tipo de efeito desconhecido.")
	var effect := {"type": type, "version": VERSION, "params": {}}
	var raw_frames: Variant = recipe.get("frames", [])
	if not raw_frames is Array or raw_frames.is_empty() or raw_frames.size() > 32: return _failure("Escolha de 1 a 32 quadros.")
	var frames: Array = []
	for value in raw_frames:
		if not _integer(value) or int(value) < 0 or int(value) >= doc.frames or frames.has(int(value)): return _failure("Quadro inválido ou repetido.")
		frames.append(int(value))
	effect.frames = frames
	if type in ["glow", "flash"]:
		var source_id := str(recipe.get("source_layer_id", ""))
		var source_index := _layer_index(doc, source_id)
		if source_index < 0: return _failure("Escolha uma camada-fonte existente.")
		if doc.layers[source_index].get("effect") is Dictionary: return _failure("A camada-fonte não pode ser outra camada de efeito.")
		effect.source_layer_id = source_id
	if type in ["glow", "particles"]:
		var ramp := _ramp(doc, str(recipe.get("ramp", "")))
		if ramp.is_empty(): return _failure("Escolha uma rampa de material salva.")
		effect.ramp = str(ramp.name)
	if type == "flash":
		var color := str(recipe.get("color", ""))
		if not _palette_contains(doc.palette, color): return _failure("A cor do clarão precisa estar na paleta.")
		effect.color = _canonical(Color(color))
	if type == "particles":
		var anchor := str(recipe.get("anchor", ""))
		if not doc.anchors.has(anchor) and anchor not in ["shield_mount", "weapon_mount"]: return _failure("Âncora de emissão inexistente.")
		effect.anchor = anchor
		var clip_name := str(recipe.get("clip", ""))
		var clip := _clip(doc, clip_name)
		if clip.is_empty(): return _failure("Clip de emissão inexistente.")
		effect.clip = clip_name
		var seed: Variant = recipe.get("seed", 1)
		if not _integer(seed) or int(seed) < 0 or int(seed) > 2147483647: return _failure("Seed inválida.")
		effect.seed = int(seed)
	var params: Variant = recipe.get("params", {})
	if not params is Dictionary: return _failure("Parâmetros inválidos.")
	for name in params:
		if not PARAMS[type].has(name): return _failure("Parâmetro desconhecido: %s." % name)
	for name in PARAMS[type]:
		var bounds: Array = PARAMS[type][name]
		var value: Variant = params.get(name, bounds[0])
		if (not value is int and not value is float) or not is_finite(float(value)) or float(value) < float(bounds[1]) or float(value) > float(bounds[2]): return _failure("Parâmetro fora do limite: %s." % name)
		if bounds[0] is int:
			if not _integer(value): return _failure("Parâmetro inteiro esperado: %s." % name)
			value = int(value)
		else: value = float(value)
		if name == "neighbors" and value not in [4, 8]: return _failure("Vizinhança deve ser 4 ou 8.")
		effect.params[name] = value
	return {"ok": true, "effect": effect}

## Renders all 8×frames cels for a normalized effect. Frames outside effect.frames stay blank.
func render(doc: RefCounted, effect: Dictionary) -> Array:
	var cels: Array = []
	for d in 8:
		var row: Array = []
		for f in doc.frames: row.append(doc.blank())
		cels.append(row)
	var ordered := _ordered_frames(doc, effect)
	for d in 8:
		for position in ordered.size():
			var f: int = ordered[position]
			match str(effect.type):
				"glow": _render_glow(doc, effect, d, f, position, cels[d][f])
				"flash": _render_flash(doc, effect, d, f, cels[d][f])
				"particles": _render_particles(doc, effect, d, ordered, position, cels[d][f])
	return cels

## Lists cels whose pixels differ from the last generation (manual retouches).
func retouched_cels(doc: RefCounted, layer_id: String) -> Array[String]:
	var result: Array[String] = []
	var index := _layer_index(doc, layer_id)
	if index < 0 or not doc.layers[index].get("effect") is Dictionary: return result
	var baseline: Dictionary = doc.layers[index].effect.get("baseline", {})
	for d in 8:
		for f in doc.frames:
			var key: String = doc.cel_key(d, f)
			if _image_hash(doc.layers[index].cels[d][f]) != str(baseline.get(key, _blank_hash(doc))): result.append(key)
	return result

func _render_glow(doc: RefCounted, effect: Dictionary, d: int, f: int, position: int, target: Image) -> void:
	var source: Image = doc.composite_layer(_layer_index(doc, str(effect.source_layer_id)), d, f, true)
	var ramp: Array = _ramp(doc, str(effect.ramp)).colors
	var radius: int = int(effect.params.radius)
	if int(effect.params.pulse) == 1 and position % 2 == 1: radius = maxi(1, radius - 1)
	var neighbors: Array = NEIGHBORS_8 if int(effect.params.neighbors) == 8 else NEIGHBORS_4
	var distance := PackedInt32Array()
	distance.resize(doc.width * doc.height)
	distance.fill(-1)
	var queue: Array[int] = []
	for y in doc.height:
		for x in doc.width:
			if source.get_pixel(x, y).a > 0.0:
				distance[y * doc.width + x] = 0
				queue.append(y * doc.width + x)
	var head := 0
	while head < queue.size():
		var index: int = queue[head]
		head += 1
		var step: int = distance[index] + 1
		if step > radius: continue
		var point := Vector2i(index % doc.width, int(index / doc.width))
		for offset_value in neighbors:
			var neighbor: Vector2i = point + offset_value
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= doc.width or neighbor.y >= doc.height: continue
			var neighbor_index: int = neighbor.y * doc.width + neighbor.x
			if distance[neighbor_index] >= 0: continue
			distance[neighbor_index] = step
			queue.append(neighbor_index)
			# Innermost ring takes the lightest ramp tone; outer rings step toward shadow.
			if _writable(doc, d, f, neighbor): target.set_pixelv(neighbor, Color(str(ramp[maxi(0, ramp.size() - step)])))

func _render_flash(doc: RefCounted, effect: Dictionary, d: int, f: int, target: Image) -> void:
	var source: Image = doc.composite_layer(_layer_index(doc, str(effect.source_layer_id)), d, f, true)
	var color := Color(str(effect.color))
	for y in doc.height:
		for x in doc.width:
			var alpha: float = source.get_pixel(x, y).a
			if alpha > 0.0 and _writable(doc, d, f, Vector2i(x, y)): target.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))

func _render_particles(doc: RefCounted, effect: Dictionary, d: int, ordered: Array, position: int, target: Image) -> void:
	var params: Dictionary = effect.params
	var ramp: Array = _ramp(doc, str(effect.ramp)).colors
	var life: int = int(params.life)
	var size: int = int(params.size)
	# Oldest particles first so younger, brighter ones draw on top.
	for birth in range(maxi(0, position - life + 1), position + 1):
		var age: int = position - birth
		var origin: Array = doc.anchor_at(str(effect.anchor), d, int(ordered[birth]))
		var color := Color(str(ramp[clampi(roundi((1.0 - float(age) / float(life)) * (ramp.size() - 1)), 0, ramp.size() - 1)]))
		for k in int(params.count):
			var state := _seed_state(int(effect.seed), birth, k)
			var r1 := _random(state)
			var r2 := _random(r1.state)
			var angle: float = deg_to_rad(float(params.angle) + (r1.value * 2.0 - 1.0) * float(params.spread))
			var speed: float = float(params.speed) * (0.5 + 0.5 * r2.value)
			var x: float = float(origin[0]) + cos(angle) * speed * age
			var y: float = float(origin[1]) + sin(angle) * speed * age + 0.5 * float(params.gravity) * age * age
			var top_left := Vector2i(roundi(x), roundi(y))
			for oy in size:
				for ox in size:
					var point := top_left + Vector2i(ox, oy)
					if point.x < 0 or point.y < 0 or point.x >= doc.width or point.y >= doc.height: continue
					if _writable(doc, d, int(ordered[position]), point): target.set_pixelv(point, color)

func _ordered_frames(doc: RefCounted, effect: Dictionary) -> Array:
	if effect.type != "particles": return effect.frames.duplicate()
	# Particles simulate along clip order so trails follow playback, not frame indices.
	var ordered: Array = []
	for f in _clip(doc, str(effect.clip)).get("frames", []):
		if effect.frames.has(int(f)) and not ordered.has(int(f)): ordered.append(int(f))
	for f in effect.frames:
		if not ordered.has(int(f)): ordered.append(int(f))
	return ordered

func _writable(doc: RefCounted, d: int, f: int, point: Vector2i) -> bool:
	if doc.selection.size != Vector2i.ZERO and not doc.selection.has_point(point): return false
	return not doc.rig.get("protected_pixels", {}).get(doc.cel_key(d, f), []).has(point.y * doc.width + point.x)

func _write_events(doc: RefCounted, effect: Dictionary) -> void:
	var ordered := _ordered_frames(doc, effect)
	var tag := str(effect.get("event_tag", ""))
	for d in 8:
		for pair in [["fx_start:", ordered[0]], ["fx_end:", ordered[ordered.size() - 1]]]:
			var key: String = doc.cel_key(d, int(pair[1]))
			var events: Array = doc.animation.events.get(key, []).duplicate()
			if events.size() < 64: events.append(str(pair[0]) + tag)
			doc.animation.events[key] = events

func _remove_events(doc: RefCounted, tag: String) -> void:
	if tag.is_empty(): return
	for key in doc.animation.events.keys():
		var events: Array = doc.animation.events[key].filter(func(event): return event != "fx_start:" + tag and event != "fx_end:" + tag)
		if events.is_empty(): doc.animation.events.erase(key)
		else: doc.animation.events[key] = events

func _event_tag(title: String) -> String:
	var tag := ""
	for character in title.to_lower():
		tag += character if (character >= "a" and character <= "z") or (character >= "0" and character <= "9") else "_"
	return tag.left(64)

## Small explicit PRNG (splitmix-style) so results never depend on engine hashing.
func _seed_state(seed: int, birth: int, index: int) -> int:
	return (seed * 2654435761 + birth * 40503 + index * 9973 + 1) & 0xFFFFFFFF

func _random(state: int) -> Dictionary:
	var next := (state + 0x6D2B79F5) & 0xFFFFFFFF
	var t := next
	t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
	t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF
	t = (t ^ (t >> 14)) & 0xFFFFFFFF
	return {"state": next, "value": float(t) / 4294967296.0}

func _image_hash(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()

func _blank_hash(doc: RefCounted) -> String:
	return _image_hash(doc.blank())

func _layer_index(doc: RefCounted, layer_id: String) -> int:
	if layer_id.is_empty(): return -1
	for index in doc.layers.size():
		if str(doc.layers[index].id) == layer_id: return index
	return -1

func _clip(doc: RefCounted, name: String) -> Dictionary:
	for clip in doc.animation.clips:
		if str(clip.name) == name: return clip
	return {}

func _ramp(doc: RefCounted, name: String) -> Dictionary:
	var ramps: Variant = doc.art.get("material_ramps", [])
	if not ramps is Array: return {}
	for ramp in ramps:
		if ramp is Dictionary and str(ramp.get("name", "")) == name and ramp.get("colors") is Array and not ramp.colors.is_empty(): return ramp
	return {}

func _type_label(type: String) -> String:
	return {"glow": "brilho", "flash": "clarão", "particles": "partículas"}.get(type, type)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _canonical(color: Color) -> String:
	return "#" + color.to_html(false).to_lower()

static func _palette_contains(palette: Array, hex: String) -> bool:
	if not Color.html_is_valid(hex): return false
	var wanted := _canonical(Color(hex))
	for item in palette:
		if _canonical(Color(str(item))) == wanted: return true
	return false

func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
