extends SceneTree
const Doc = preload("res://core/document.gd")
const Playback = preload("res://core/playback.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, title: String) -> void:
	if value: passed += 1; print("PASS ", title)
	else: failed += 1; printerr("FAIL ", title)

func fixture(doc: RefCounted) -> void:
	doc.animation = {"active": 0, "clips": [
		{"name": "idle", "frames": [0, 1], "loop": true, "durations_ms": {"0": 100, "1": 200}},
		{"name": "action", "frames": [2, 3], "loop": false, "durations_ms": {"2": 50, "3": 100}}
	], "events": {}, "hitboxes": {}}
	doc.frame = 0

func run() -> void:
	var doc = Doc.new()
	fixture(doc)
	var clock = Playback.new()
	var tick: Dictionary = clock.tick_sequence(doc, [0, 1], 0, 0, 0.31)
	expect(tick.slot == 1 and tick.frame == 2 and tick.entered == [1, 2] and is_equal_approx(clock.elapsed, 0.01), "a fronteira ignora o loop individual e preserva o tempo restante no próximo clip")
	tick = clock.tick_sequence(doc, [0, 1], tick.slot, tick.frame, 0.14)
	expect(tick.finished and tick.frame == 3 and tick.entered == [3] and clock.elapsed == 0.0, "a sequência termina somente após a duração inteira do último quadro")
	clock.reset()
	tick = clock.tick_sequence(doc, [0, 1], 0, 0, 0.46, 1.0, false, true)
	expect(not tick.finished and tick.slot == 0 and tick.frame == 0 and tick.entered == [1, 2, 3, 0] and is_equal_approx(clock.elapsed, 0.01), "repetição engloba a sequência completa com corte direto ao primeiro clip")
	clock.reset()
	tick = clock.tick_sequence(doc, [0, 1], 1, 3, 0.16, 1.0, true)
	expect(tick.slot == 0 and tick.frame == 1 and tick.entered == [2, 1] and is_equal_approx(clock.elapsed, 0.01), "reverso percorre quadros e clips na ordem inversa")
	clock.reset()
	tick = clock.tick_sequence(doc, [0, 1], 0, 0, 0.155, 2.0)
	expect(tick.slot == 1 and tick.frame == 2 and is_equal_approx(clock.elapsed, 0.005), "velocidade aplica-se às durações sem perder tempo na transição")
	expect(not clock.valid_sequence(doc, []) and not clock.valid_sequence(doc, [9]) and not clock.valid_sequence(doc, [0.5]) and clock.valid_sequence(doc, [0, 1, 0]), "validação recusa referências inválidas e permite repetir clips em uma lista")
	for clip in doc.animation.clips:
		for frame in clip.frames: clip.durations_ms[str(frame)] = 10
	clock.reset()
	tick = clock.tick_sequence(doc, [0, 1], 0, 0, 100.0, 4.0, false, true)
	expect(tick.catchup_limited and tick.entered.size() == 64 and clock.elapsed == 0.0, "uma interface atrasada limita o trabalho de recuperação a 64 passos")
	var ui = load("res://main.tscn").instantiate()
	ui.workspace_root = "res://test_results/sequence-workspace-%d" % Time.get_ticks_usec()
	root.add_child(ui)
	ui.set_process(false)
	await process_frame
	fixture(ui.doc)
	ui.refresh_all()
	var original_clips := JSON.stringify(ui.doc.animation.clips)
	var original_revision: int = ui.doc.revision
	var original_dirty: bool = ui.doc.dirty
	var original_art := JSON.stringify(ui.doc.art)
	expect(ui.start_clip_sequence([0, 1]) and ui.playing and ui.doc.frame == 0, "editor inicia a prévia usando os mesmos clips e cels da timeline")
	ui.advance_animation_preview(0.31)
	expect(ui.doc.animation.active == 1 and ui.doc.frame == 2 and ui.clip_picker.selected == 1, "troca de clip atualiza a timeline e o seletor na fronteira correta")
	ui.toggle_playback()
	ui.advance_animation_preview(0.10)
	expect(not ui.playing and ui.doc.frame == 2 and ui.preview_sequence.size() == 2, "Pause preserva a sequência e sua posição")
	ui.toggle_playback()
	ui.advance_animation_preview(0.14)
	expect(not ui.playing and ui.doc.frame == 3 and ui.preview_sequence.is_empty(), "retomar conclui o último quadro e encerra a sequência")
	expect(ui.doc.revision == original_revision and ui.doc.dirty == original_dirty and JSON.stringify(ui.doc.animation.clips) == original_clips and JSON.stringify(ui.doc.art) == original_art, "prévia não muda durações, loops, aprovações ou histórico do documento")
	ui.open_clip_sequence_dialog()
	await process_frame
	var dialog: ConfirmationDialog = ui.get_node_or_null("ClipSequenceDialog")
	var available: OptionButton = dialog.find_child("AvailableClips", true, false)
	var add: Button = dialog.find_child("AddSequenceClip", true, false)
	var entries: ItemList = dialog.find_child("SequenceEntries", true, false)
	available.select(0); add.pressed.emit()
	available.select(1); add.pressed.emit()
	available.select(0); add.pressed.emit()
	entries.select(2)
	dialog.find_child("MoveSequenceUp", true, false).pressed.emit()
	entries.select(1)
	dialog.find_child("RemoveSequenceClip", true, false).pressed.emit()
	dialog.confirmed.emit()
	await process_frame
	expect(ui.playing and ui.preview_sequence == [0, 1], "diálogo real permite adicionar, ordenar, remover e reproduzir os clips")
	ui.doc.mark_changed()
	ui.advance_animation_preview(0.01)
	expect(not ui.playing and ui.preview_sequence.is_empty(), "uma edição invalida a prévia e evita usar índices obsoletos")
	ui.open_clip_sequence_dialog()
	await process_frame
	dialog = ui.get_node_or_null("ClipSequenceDialog")
	dialog.find_child("AddSequenceClip", true, false).pressed.emit()
	ui.doc.mark_changed()
	dialog.confirmed.emit()
	await process_frame
	expect(not ui.playing, "diálogo recusa iniciar a sequência se o documento mudou durante a configuração")
	ui.free()
	await process_frame
	var report := FileAccess.open("res://test_results/clip-sequence-report.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": passed, "failed": failed}, "\t"))
		report.close()
	print("Clip sequence: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or report == null else 0)
