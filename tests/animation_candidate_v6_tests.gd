extends SceneTree

const Storage = preload("res://core/storage.gd")
const Doc = preload("res://core/document.gd")
const Studio = preload("res://ui/studio.gd")
const DIRECTIONS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const CLIP_SPECS := {
	"idle_breathing": {"first": 0, "loop": true},
	"jump": {"first": 6, "loop": false},
	"attack": {"first": 12, "loop": false},
}
var checks: Array[Dictionary] = []
var failed := 0
var frame_changes := 0

func expect(value: bool, title: String) -> void:
	checks.append({"name": title, "passed": value})
	if value: print("PASS ", title)
	else:
		failed += 1
		printerr("FAIL ", title)

func _on_frame_changed() -> void:
	frame_changes += 1

func find_button(node: Node, target: String) -> Button:
	if node is Button and node.text == target: return node
	for child in node.get_children():
		var found := find_button(child, target)
		if found != null: return found
	return null

func find_dialog(node: Node, target: String) -> ConfirmationDialog:
	if node is ConfirmationDialog and node.title == target: return node
	for child in node.get_children():
		var found := find_dialog(child, target)
		if found != null: return found
	return null

func find_checkbox(node: Node, target_prefix: String) -> CheckBox:
	if node is CheckBox and node.text.begins_with(target_prefix): return node
	for child in node.get_children():
		var found := find_checkbox(child, target_prefix)
		if found != null: return found
	return null

func collect_spinboxes(node: Node, result: Array[SpinBox]) -> void:
	if node is SpinBox: result.append(node)
	for child in node.get_children(): collect_spinboxes(child, result)

func secondary_component_area(image: Image) -> int:
	var rgba: Image = image.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8: rgba.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = rgba.get_data()
	var width: int = rgba.get_width()
	var height: int = rgba.get_height()
	var bounds: Rect2i = rgba.get_used_rect()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var largest := 0
	var second := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var start: int = y * width + x
			if visited[start] != 0 or bytes[start * 4 + 3] < 128: continue
			visited[start] = 1
			var pending: Array[int] = [start]
			var area := 0
			while not pending.is_empty():
				var point: int = pending.pop_back()
				var px: int = point % width
				var py: int = point / width
				area += 1
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0: continue
						var nx: int = px + dx
						var ny: int = py + dy
						if nx < bounds.position.x or nx >= bounds.end.x or ny < bounds.position.y or ny >= bounds.end.y: continue
						var neighbor: int = ny * width + nx
						if visited[neighbor] == 0 and bytes[neighbor * 4 + 3] >= 128:
							visited[neighbor] = 1
							pending.append(neighbor)
			if area > largest:
				second = largest
				largest = area
			elif area > second:
				second = area
	return second

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var storage = Storage.new()
	var source_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v6/sentinela-v6.sfs.json")
	var doc = storage.load_document(source_path)
	expect(doc != null, "carrega candidato v6 no modelo editável SFS")
	if doc == null:
		finish()
		return
	expect(doc.width == 208 and doc.height == 208 and doc.frames == 18 and doc.layers.size() == 1 and doc.validate().is_empty(), "documento SFS válido: 208×208, 18 quadros e uma camada raster")
	expect(doc.art.get("candidate_status", "") == "candidate" and doc.manifest.approvals.is_empty(), "aprovação parcial não promove a Sentinela inteira")
	expect(doc.art.direction_coverage == DIRECTIONS, "documento cobre oito vistas ordenadas sem espelhamento implícito")
	var built_in_sample = storage.load_document(ProjectSettings.globalize_path("res://samples/sentinela_v6.sfs.json"))
	expect(built_in_sample != null and built_in_sample.width == 208 and built_in_sample.frames == 18 and built_in_sample.animation.clips.size() == 3, "demonstração embutida pode ser aberta pelo botão Demo animada")
	expect(built_in_sample != null and built_in_sample.art.direction_coverage == DIRECTIONS and built_in_sample.art.candidate_status == "candidate", "demonstração embutida preserva as oito direções e o status de revisão parcial")
	var studio := Studio.new()
	studio.workspace_root = ProjectSettings.globalize_path("res://test_results/demo-ui-workspace")
	root.add_child(studio)
	await process_frame
	var demo_button := find_button(studio, "Demo animada")
	expect(demo_button != null, "editor exibe o comando direto para a demonstração animada")
	if demo_button != null:
		demo_button.pressed.emit()
		await process_frame
		var active_record: Dictionary = studio.workspace.current()
		expect(studio.workspace.records.size() == 2 and not active_record.is_empty() and active_record.doc.width == 208 and active_record.doc.animation.clips.size() == 3, "comando Demo animada abre a Sentinela no espaço de trabalho do editor")
	var scale_button := find_button(studio, "Estudo 64×64")
	expect(scale_button != null, "editor oferece a variante na escala-base do personagem")
	if scale_button != null:
		scale_button.pressed.emit()
		await process_frame
		var scale_record: Dictionary = studio.workspace.current()
		expect(studio.workspace.records.size() == 3 and not scale_record.is_empty() and scale_record.doc.width == 64 and scale_record.doc.art.pose_approvals.is_empty(), "comando Estudo 64×64 abre a escala da Bíblia como revisão independente")
		var before_atlas_attack: PackedByteArray = scale_record.doc.layers[0].cels[4][12].get_data()
		var atlas_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v8/sentinela-sheet-candidate-v1.png")
		studio.open_spritesheet_import_dialog(atlas_path)
		await process_frame
		var atlas_dialog := find_dialog(studio, "Importar spritesheet ou atlas por grade")
		var atlas_spins: Array[SpinBox] = []
		if atlas_dialog != null: collect_spinboxes(atlas_dialog, atlas_spins)
		var fit_checkbox := find_checkbox(atlas_dialog, "Ajustar atlas") if atlas_dialog != null else null
		expect(atlas_dialog != null and atlas_spins.size() >= 9 and fit_checkbox != null and fit_checkbox.button_pressed, "importador oferece grade regular e ajuste de atlas de alta resolução")
		if atlas_dialog != null and atlas_spins.size() >= 9 and fit_checkbox != null:
			atlas_dialog.find_child("source_row", true, false).value = 3
			atlas_dialog.find_child("content_scale", true, false).value = 72
			atlas_dialog.find_child("start_frame", true, false).value = 13
			atlas_dialog.confirmed.emit()
			await process_frame
			var imported_record: Dictionary = studio.workspace.current()
			expect(imported_record.doc.layers[0].cels[4][12].get_data() != before_atlas_attack and imported_record.doc.art.candidate_status == "candidate" and imported_record.doc.manifest.approvals.is_empty(), "importador aplica a linha escolhida em South e invalida aprovações antigas")
	var resize_button := find_button(studio, "Redimensionar canvas…")
	expect(resize_button != null, "editor oferece redimensionamento reversível no Pixel Studio")
	if resize_button != null:
		resize_button.pressed.emit()
		await process_frame
		var resize_dialog := find_dialog(studio, "Redimensionar canvas")
		var dimension_fields: Array[SpinBox] = []
		if resize_dialog != null: collect_spinboxes(resize_dialog, dimension_fields)
		expect(resize_dialog != null and dimension_fields.size() == 2, "diálogo de redimensionamento permite configurar as duas dimensões")
		if resize_dialog != null and dimension_fields.size() == 2:
			dimension_fields[0].value = 48
			dimension_fields[1].value = 64
			resize_dialog.confirmed.emit()
			await process_frame
			var resized_record: Dictionary = studio.workspace.current()
			expect(resized_record.doc.width == 48 and resized_record.doc.height == 64 and resized_record.doc.layers[0].cels[4][0].get_size() == Vector2i(48, 64), "diálogo aplica o redimensionamento ao projeto editável")
	var breathing_button := find_button(studio, "Gerar respiração")
	expect(breathing_button != null, "timeline oferece criação de idle respirando")
	if breathing_button != null:
		var before_breathing: PackedByteArray = studio.workspace.current().doc.layers[0].cels[4][1].get_data()
		breathing_button.pressed.emit()
		await process_frame
		var breathing_record: Dictionary = studio.workspace.current()
		expect(breathing_record.doc.width == 48 and breathing_record.doc.layers[0].cels[4][1].get_data() != before_breathing, "comando da timeline gera ciclo no documento ativo sem alterar o tamanho")
	studio.queue_free()
	await process_frame
	var clips_valid: bool = doc.animation.clips.size() == 3
	var clip_by_name: Dictionary = {}
	for clip in doc.animation.clips:
		clip_by_name[clip.name] = clip
	for clip_name in CLIP_SPECS:
		var spec: Dictionary = CLIP_SPECS[clip_name]
		var clip: Dictionary = clip_by_name.get(clip_name, {})
		clips_valid = clips_valid and not clip.is_empty() and clip.frames.size() == 6 and clip.loop == spec.loop
	expect(clips_valid, "idle, pulo e ataque têm seis frames e semântica de loop correta")
	if not clips_valid:
		finish()
		return
	var all_cels_valid := true
	var all_frames_inside_canvas := true
	var all_cels_isolated := true
	var distinct_tracks := true
	var total_visible := 0
	for direction in 8:
		for clip_name in CLIP_SPECS:
			var clip: Dictionary = clip_by_name[clip_name]
			var first_frame := int(clip.frames[0])
			var first: Image = doc.layers[0].cels[direction][first_frame]
			var unique_frames: Dictionary = {}
			for clip_index in clip.frames.size():
				var frame_index := int(clip.frames[clip_index])
				var cel: Image = doc.layers[0].cels[direction][frame_index]
				var bounds := cel.get_used_rect()
				all_cels_valid = all_cels_valid and cel.get_size() == Vector2i(208, 208) and bounds.size != Vector2i.ZERO
				all_frames_inside_canvas = all_frames_inside_canvas and bounds.position.x > 0 and bounds.position.y > 0 and bounds.end.x < 208 and bounds.end.y < 208
				all_cels_isolated = all_cels_isolated and secondary_component_area(cel) <= 100
				unique_frames[cel.get_data().hex_encode()] = true
				total_visible += 1 if bounds.size != Vector2i.ZERO else 0
			distinct_tracks = distinct_tracks and unique_frames.size() == 6
			expect(unique_frames.size() == 6, "%s %s possui seis poses raster distintas" % [clip_name, DIRECTIONS[direction]])
	expect(all_cels_valid and total_visible == 144, "144 cels RGBA estão no canvas e contêm pixels visíveis")
	expect(all_frames_inside_canvas, "nenhum personagem ou equipamento foi cortado pelo limite do canvas")
	expect(all_cels_isolated, "144 cels não contêm componentes de pixels estranhos acima de 100 pixels")
	expect(distinct_tracks, "24 combinações de animação/direção não são duplicatas estáticas")
	var north_approval_count := 0
	var south_approval_count := 0
	var approval_metadata_exact := true
	for approval in doc.art.pose_approvals:
		if not approval.get("human", false) or approval.get("feedback", "") not in ["aprovado", "aprovada"]:
			approval_metadata_exact = false
		elif approval.get("direction", "") == "N" and approval.get("clip", "") == "attack": north_approval_count += 1
		elif approval.get("direction", "") == "S" and approval.get("clip", "") == "attack" and int(approval.get("frame", -1)) == 2: south_approval_count += 1
		else: approval_metadata_exact = false
	expect(approval_metadata_exact and north_approval_count == 6 and south_approval_count == 1, "aprovações humanas ficam limitadas às seis poses de ataque N e ao terceiro quadro de ataque S")
	var north_attack_exact := true
	for i in 6:
		var exported_pose := Image.load_from_file(ProjectSettings.globalize_path("res://examples/animation_candidate_v6/frames/N-attack-%02d.png" % i))
		var document_pose: Image = doc.layers[0].cels[0][12 + i]
		north_attack_exact = north_attack_exact and not exported_pose.is_empty() and exported_pose.get_data() == document_pose.get_data()
	expect(north_attack_exact, "seis poses Norte no documento SFS preservam exatamente as cels aprovadas exibidas")
	var v3_path := ProjectSettings.globalize_path("res://examples/animation_candidate_v3/sentinela-v3.sfs.json")
	var old_doc = storage.load_document(v3_path)
	var south_attack_exact := old_doc != null
	if old_doc != null:
		var source_attack: Dictionary = old_doc.animation.clips.filter(func(c): return c.name == "attack")[0]
		var target_attack: Dictionary = clip_by_name["attack"]
		var source_frame := int(source_attack.frames[2])
		var target_frame := int(target_attack.frames[2])
		south_attack_exact = old_doc.layers[0].cels[4][source_frame].get_data() == doc.layers[0].cels[4][target_frame].get_data()
	expect(south_attack_exact, "terceiro quadro do ataque Sul mantém os pixels da pose corrigida aprovada")
	var native: SpriteFrames = load("res://examples/animation_candidate_v6/directional_animations.res")
	expect(native != null and native.get_animation_names().size() == 24, "recurso nativo SpriteFrames contém 24 clips direcionais")
	if native != null:
		var native_tracks_valid := true
		for direction_name in DIRECTIONS:
			for clip_name in CLIP_SPECS:
				var name: String = str(clip_name) + "_" + direction_name
				var spec: Dictionary = CLIP_SPECS[clip_name]
				native_tracks_valid = native_tracks_valid and native.has_animation(name) and native.get_frame_count(name) == 6 and native.get_animation_loop(name) == spec.loop
				if native.has_animation(name):
					for i in 6:
						native_tracks_valid = native_tracks_valid and is_equal_approx(native.get_frame_duration(name, i), doc.frame_seconds(int(clip_by_name[clip_name].frames[i]), clip_by_name[clip_name]))
		expect(native_tracks_valid, "SpriteFrames preserva 24 nomes, imagens, duração e loop do documento")
		var actor := AnimatedSprite2D.new()
		actor.sprite_frames = native.duplicate(true)
		actor.speed_scale = 4.0
		root.add_child(actor)
		actor.frame_changed.connect(_on_frame_changed)
		for direction_name in DIRECTIONS:
			for clip_name in CLIP_SPECS:
				var name: String = str(clip_name) + "_" + direction_name
				actor.play(name)
				expect(actor.animation == name and actor.is_playing(), "AnimatedSprite2D reproduz %s" % name)
		actor.play("idle_breathing_N")
		var before := frame_changes
		await create_timer(0.35).timeout
		expect(frame_changes > before, "Godot avança frames da respiração em reprodução real")
		actor.pause()
		var paused_frame := actor.frame
		await create_timer(0.2).timeout
		expect(not actor.is_playing() and actor.frame == paused_frame, "Pause congela a animação no frame atual")
		actor.speed_scale = 20.0
		for direction_name in DIRECTIONS:
			var idle_name: String = "idle_breathing_" + direction_name
			var before_idle := frame_changes
			actor.play(idle_name)
			await create_timer(0.1).timeout
			expect(actor.is_playing() and frame_changes > before_idle, "idle respira e avança em %s" % direction_name)
			for action_name in ["jump", "attack"]:
				var action_anim: String = action_name + "_" + direction_name
				var before_action := frame_changes
				actor.play(action_anim)
				await create_timer(0.15).timeout
				expect(not actor.is_playing() and actor.frame == 5 and frame_changes > before_action, "%s avança e conclui sem loop em %s" % [action_name, direction_name])
		actor.queue_free()
		await process_frame
	var preview: PackedScene = load("res://examples/animation_candidate_v6/preview.tscn")
	expect(preview != null, "cena Godot de prévia está carregável")
	if preview != null:
		var instance: Node = preview.instantiate()
		root.add_child(instance)
		await process_frame
		var actors: Array = instance.get("actors")
		var preview_ok := actors.size() == 3
		for i in mini(actors.size(), 3): preview_ok = preview_ok and actors[i] is AnimatedSprite2D and actors[i].animation == ["idle_breathing_N", "jump_N", "attack_N"][i]
		expect(preview_ok, "prévia monta os três clips com personagens animados na direção Norte")
		if actors.size() == 3:
			instance.call("set_direction", "S")
			var switched := true
			for i in 3: switched = switched and actors[i].animation.ends_with("_S")
			expect(switched, "seletor de direção troca os três clips para Sul")
			instance.call("_toggle_play")
			var paused := true
			for actor in actors: paused = paused and not actor.is_playing()
			expect(paused, "controle Play/Pause congela os três clips em conjunto")
			var old_frame: int = actors[0].frame
			instance.call("_step_frame")
			expect(not instance.get("running") and actors[0].frame == (old_frame + 1) % 6, "avanço de quadro move os três clips sem retomar reprodução")
		instance.queue_free()
		await process_frame
	var export_path := ProjectSettings.globalize_path("res://test_results/animation-v6-export")
	DirAccess.make_dir_recursive_absolute(export_path)
	var export_error: Error = storage.export_all(doc, export_path)
	expect(export_error == OK, "SFS exporta o candidato para recursos e cena Godot")
	if export_error == OK:
		var exported_frames: SpriteFrames = load("res://test_results/animation-v6-export/animations.tres")
		expect(exported_frames != null and exported_frames.get_animation_names().size() == 24 and exported_frames.get_frame_count("attack_N") == 6, "exportação do editor mantém clips direcionais no recurso do Godot")
		var exported_scene: PackedScene = load("res://test_results/animation-v6-export/character.tscn")
		expect(exported_scene != null, "cena de personagem exportada é carregável no Godot")
	finish()

func finish() -> void:
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/animation-v6-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("Animation candidate v6: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
