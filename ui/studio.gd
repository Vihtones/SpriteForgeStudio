extends Control
const Document = preload("res://core/document.gd")
const Storage = preload("res://core/storage.gd")
const ArtMemory = preload("res://core/art_memory.gd")
const PixelCanvas = preload("res://ui/pixel_canvas.gd")
const WorldView = preload("res://ui/world_view.gd")
const BatchQueue = preload("res://core/batch_queue.gd")
const Precision = preload("res://core/precision.gd")
const ClusterCleaner = preload("res://core/cluster_cleaner.gd")
const MaterialRamps = preload("res://core/material_ramps.gd")
const MaterialRecolor = preload("res://core/material_recolor.gd")
const SpriteEffects = preload("res://core/sprite_effects.gd")
const RigSegmentExtractor = preload("res://core/rig_segment_extractor.gd")
const References = preload("res://core/reference_library.gd")
const Plan = preload("res://core/production_plan.gd")
const Quality = preload("res://core/quality_library.gd")
const CharacterAudit = preload("res://core/character_audit.gd")
const Catalog = preload("res://core/catalog_client.gd")
const Arton = preload("res://core/arton_importer.gd")
const Workspace = preload("res://core/workspace.gd")
const Automation = preload("res://core/automation.gd")
const AIPanel = preload("res://ui/ai_panel.gd")
const AnimationTimeline = preload("res://ui/animation_timeline.gd")
const SpriteSheetImporter = preload("res://core/spritesheet_importer.gd")
const CanvasResizer = preload("res://core/canvas_resizer.gd")
const AnimationSynthesizer = preload("res://core/animation_synthesizer.gd")
const RigInterpolator = preload("res://core/rig_interpolator.gd")
const PoseRetargeter = preload("res://core/pose_retargeter.gd")
const InterDocumentRetargeter = preload("res://core/inter_document_retargeter.gd")
const RasterInbetweener = preload("res://core/raster_inbetweener.gd")
const HyperLearn = preload("res://core/hyperlearn.gd")
const ThreeDMotionCapture = preload("res://core/three_d_motion_capture.gd")
const ThreeDMotionPanel = preload("res://ui/three_d_motion_panel.gd")
const ProductionRecipe = preload("res://core/production_recipe.gd")
const DEMO_SAMPLE_PATH := "res://samples/sentinela_v6.sfs.json"
const SCALE_STUDY_PATH := "res://samples/sentinela_scale_study.sfs.json"
const APPROVED_SAMPLE_PATH := "res://samples/sentinela_artist_v9.sfs.json"
const CURRENT_SAMPLE_PATH := "res://samples/sentinela_candidate_v10.sfs.json"
var automation: Node
var automation_panel: Control
var _capture_all_running := false
var _capture_all_cancel_requested := false
var ai_gateway: Node
var ai_panel: Control
var ai_approval_dialog: ConfirmationDialog
var ai_pending_request: Dictionary = {}
var ai_last_output_path: String = ""
var hyperlearn = HyperLearn.new()
var hyperlearn_panel: Control
var three_d_motion_panel: Control
var three_d_motion_capture = ThreeDMotionCapture.new()
var production_recipe = ProductionRecipe.new()
var production_recipe_dialog: FileDialog
var production_recipe_action := ""
var _three_d_pose_document: RefCounted
var _three_d_pose_context := ""
var local_image_provider: Node
var public_library_panel: Control
var animation_review_panel: Control
var hyperlearn_evaluation: Dictionary = {}
var doc = Document.new()
var store = Storage.new()
var memory = ArtMemory.new()
var canvas: Control
var world: Control
var world_controls: Control
var queue: Node
var tabs: TabContainer
var status: Label
var layers_list: ItemList
var timeline_view: Control
var direction_picker: OptionButton
var layer_name: LineEdit
var layer_retarget_key: LineEdit
var visibility: CheckBox
var locked: CheckBox
var opacity: HSlider
var equipment: CheckBox
var anchor_picker: OptionButton
var joint_picker: OptionButton
var pivot_picker: OptionButton
var bone_picker: OptionButton
var rotation_control: HSlider
var rotation_label: Label
var offset_x: SpinBox
var offset_y: SpinBox
var color_picker: ColorPickerButton
var palette_box: HBoxContainer
var bible: TextEdit
var art_lock: CheckBox
var reference_list: ItemList
var reference_preview: TextureRect
var candidate_list: ItemList
var batch_list: ItemList
var batch_input: LineEdit
var batch_output: LineEdit
var path: String = ""
var playing: bool = false
var elapsed: float = 0.0
var autosave_elapsed: float = 0.0
var syncing: bool = false
var rotation_dragging: bool = false
var play_button: Button
var fps_control: SpinBox
var dialog: FileDialog
var dialog_action: String = ""
var title_label: Label
var pending_action: Callable
var confirm: ConfirmationDialog
var precision = Precision.new()
var cluster_cleaner = ClusterCleaner.new()
var material_ramps = MaterialRamps.new()
var material_recolor = MaterialRecolor.new()
var sprite_effects = SpriteEffects.new()
var rig_segment_extractor = RigSegmentExtractor.new()
var rig_interpolator = RigInterpolator.new()
var pose_retargeter = PoseRetargeter.new()
var inter_document_retargeter = InterDocumentRetargeter.new()
var raster_inbetweener = RasterInbetweener.new()
var references = References.new()
var clip_picker: OptionButton
var duration_control: SpinBox
var loop_control: CheckBox
var playback_speed: float = 1.0
var reverse_playback: bool = false
var layer_mask_status: Label
var preview_sequence: Array = []
var preview_sequence_slot := 0
var preview_sequence_repeat := false
var preview_sequence_revision := -1
var preview_sequence_document := 0
var preview_sequence_status: Label
var ref_state: OptionButton
var ref_feature: OptionButton
var ref_license: LineEdit
var pixel_preview: TextureRect
var plan_list: ItemList
var priority_control: SpinBox
var quality = Quality.new()
var character_audit = CharacterAudit.new()
var quality_report: RichTextLabel
var character_audit_report: RichTextLabel
var character_audit_button: Button
var character_approval_button: Button
var reopen_rejected_candidate_button: Button
var character_audit_result: Dictionary = {}
var character_audit_revision: int = -1
var version_list: ItemList
var quality_scores: Array = []
var reviewer: LineEdit
var human_check: CheckBox
var available_versions: Array = []
var catalog: Node
var family_picker: OptionButton
var depth_control: SpinBox
var asymmetric_control: CheckBox
var anchor_names: Array = []
const FAMILIES = ["humanoid", "canid", "felid", "quadruped", "avian", "custom"]
var art_library_path: LineEdit
var art_family: OptionButton
var art_library_info: RichTextLabel
var art_library_preview: TextureRect
var art_library_data: Dictionary = {}
var workspace: Node
var workspace_root: String = "user://workspace"
var document_tabs: TabBar
var _binding_tabs: bool = false
var _bound_id: String = ""
var _save_target_id: String = ""
var _pending_close_id: String = ""
var _save_all_ids: Array[String] = []
var _quit_after_save: bool = false
var _export_targets: Dictionary = {}
var _selected_export_profile := "playable"
var export_profile_dialog: Window
var export_profile_picker: OptionButton
var history_list: ItemList
var _history_revision: int = -1
var preview_toggle: CheckBox
var clock = preload("res://core/playback.gd").new()
var shared_clipboard: Image
var tool_picker: OptionButton
var rig_control: CheckBox
var show_animation_events: bool = false
const DRAWING_TOOLS = ["Lápis", "Borracha", "Balde", "Linha", "Retângulo", "Máscara", "Conta-gotas", "Âncora", "Retângulo preenchido", "Elipse", "Elipse preenchida"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] in ["--sfs-produce", "--sfs-watch"]:
		set_process(false)
		var runner := preload("res://core/production_runner.gd").new()
		add_child(runner); runner.run(args)
		return
	if args.size() == 2 and args[0] == "--sfs-workspace-check":
		set_process(false)
		var workspace_checker := preload("res://core/workspace_selfcheck.gd").new()
		add_child(workspace_checker)
		workspace_checker.run(args[1])
		return
	if args.size() == 2 and args[0] == "--sfs-worker":
		set_process(false)
		get_tree().quit(preload("res://core/batch_worker.gd").run_request(args[1]))
		return
	if args.size() == 3 and args[0] == "--sfs-selfcheck":
		set_process(false)
		var checker := preload("res://core/pack_selfcheck.gd").new()
		add_child(checker)
		checker.run(args[1], args[2])
		return
	if args.size() == 1 and args[0] == "--sfs-sample-check":
		set_process(false)
		var sample_checker := preload("res://core/sample_selfcheck.gd").new()
		add_child(sample_checker)
		sample_checker.run()
		return
	DisplayServer.window_set_title("Sprite Forge Studio • " + str(ProjectSettings.get_setting("application/config/version", "")))
	get_tree().auto_accept_quit = false
	doc.demo()
	queue = BatchQueue.new()
	add_child(queue)
	catalog = Catalog.new()
	add_child(catalog)
	catalog.completed.connect(func(result): notify("Índice SQLite atualizado." if result.get("ok", false) else "Catálogo: " + str(result.get("error", "falha"))))
	workspace = Workspace.new()
	workspace.data_root = workspace_root
	add_child(workspace)
	workspace.activated.connect(_activate_document)
	workspace.changed.connect(_refresh_document_tabs)
	workspace.persisted.connect(_on_workspace_persisted)
	automation = Automation.new()
	automation.config_path = workspace_root.path_join("automation.json")
	add_child(automation)
	automation.work_requested.connect(func(source, destination, options, token):
		var id: String = queue.enqueue(source, destination, 50, [], "production", options)
		automation.bind_job(token, id)
		if id != "": queue.running = true
	)
	automation.changed.connect(refresh_automation)
	build_theme()
	build_ui()
	queue.updated.connect(refresh_batch)
	queue.updated.connect(func(): automation.reconcile(queue.jobs))
	automation.reconcile(queue.jobs)
	refresh_automation()
	workspace.add_document(doc, "", true)
	refresh_batch()
	notify("Pronto • projeto de demonstração • processamento local, sem chamadas de IA")
	if args.has("--sfs-review"):
		_bind_review_sample()
		tabs.current_tab = animation_review_panel.get_index()
	elif args.has("--sfs-public-library"):
		tabs.current_tab = public_library_panel.get_index()

func build_theme() -> void:
	var t := Theme.new()
	t.default_font_size = 14
	for type in ["Button", "OptionButton", "LineEdit", "TextEdit", "ItemList", "PanelContainer", "TabContainer"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("182132")
		style.border_color = Color("344158")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		for state in ["normal", "panel"]: t.set_stylebox(state, type, style)
		var hover_style := style.duplicate()
		hover_style.bg_color = Color("304662")
		t.set_stylebox("hover", type, hover_style)
		t.set_stylebox("pressed", type, hover_style)
		t.set_color("font_color", type, Color("d9e3ee"))
	t.set_color("font_color", "Label", Color("c4d0e0"))
	theme = t

func label(text: String, parent: Node, font_size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l

func button(text: String, parent: Node, action: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func check(text: String, parent: Node, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.toggled.connect(action)
	parent.add_child(c)
	return c

func row(parent: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	parent.add_child(r)
	return r

func column(parent: Node) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 8)
	parent.add_child(c)
	return c

func choice(options: Array, parent: Node, action: Callable) -> OptionButton:
	var o := OptionButton.new()
	for item in options: o.add_item(str(item))
	o.item_selected.connect(action)
	parent.add_child(o)
	return o

func spin(parent: Node, low: int, high: int, value: int, action: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.value = value
	s.value_changed.connect(action)
	parent.add_child(s)
	return s

func build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(margin)
	var root := column(margin)
	var header := row(root)
	label("SFS", header, 28).add_theme_color_override("font_color", Color("78d8c3"))
	var identity := column(header)
	label("SPRITE FORGE STUDIO", identity, 19)
	title_label = label("OFICINA DE PIXEL ART   /   " + str(ProjectSettings.get_setting("application/config/version", "")), identity, 11)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	button("Novo", header, new_document, "Ctrl+N")
	button("Abrir", header, func(): browse("open"), "Ctrl+O")
	button("Demo animada", header, open_animation_demo, "Abre a Sentinela com idle, pulo e ataque nas oito direções.")
	button("Sentinela atual · 8f", header, func(): selected_open(CURRENT_SAMPLE_PATH, true), "Abre a variante com recorte corrigido; revisão artística pendente.")
	button("Estudo 64×64", header, open_scale_study, "Abre a cópia redimensionada à escala-base da Bíblia de Arte; as aprovações foram reiniciadas.")
	button("Salvar", header, save_project, "Ctrl+S")
	button("Salvar como", header, func(): _save_target_id = workspace.active_id; browse("save"), "Ctrl+Shift+S")
	button("Exportar…", header, show_export_profiles)
	button("Validar", header, validate_project)
	var documents := row(root)
	document_tabs = TabBar.new()
	document_tabs.custom_minimum_size = Vector2(400, 34)
	document_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document_tabs.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	document_tabs.tab_changed.connect(func(index):
		if not _binding_tabs and index >= 0 and index < workspace.records.size(): workspace.activate(workspace.records[index].id)
	)
	document_tabs.tab_close_pressed.connect(func(index): request_close_document(workspace.records[index].id))
	documents.add_child(document_tabs)
	button("Salvar todos", documents, func(): start_save_all(false))
	button("Recuperar sessão", documents, restore_workspace)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	build_editor()
	build_world()
	build_art()
	build_batch()
	build_quality()
	build_acervo()
	build_help()
	build_automation()
	build_ai()
	build_public_library()
	build_animation_review()
	build_3d_motion()
	build_hyperlearn()
	tabs.tab_changed.connect(func(index):
		stop_playback()
		world.cancel_gesture()
		if index == 1: world.refresh(); refresh_world_controls()
		if index == 4: refresh_quality()
		if index == 5 and art_library_data.is_empty(): load_art_library(art_library_path.text)
		if index == tabs.get_child_count() - 2: _load_3d_motion_pose()
		if index == tabs.get_child_count() - 1: refresh_hyperlearn()
	)
	status = label("", root, 13)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = false
	dialog.size = Vector2i(900, 600)
	dialog.file_selected.connect(selected_path)
	dialog.dir_selected.connect(selected_path)
	dialog.canceled.connect(func():
		if dialog_action == "save": _save_all_ids.clear(); _pending_close_id = ""; _quit_after_save = false; _save_target_id = ""
	)
	add_child(dialog)
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Há alterações não salvas. Continuar descarta essas alterações."
	confirm.title = "Alterações pendentes"
	confirm.confirmed.connect(func(): pending_action.call())
	add_child(confirm)
	export_profile_dialog = Window.new()
	export_profile_dialog.title = "Escolher perfil de exportação"
	export_profile_dialog.size = Vector2i(560, 220)
	export_profile_dialog.min_size = Vector2i(500, 190)
	export_profile_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	export_profile_dialog.close_requested.connect(func(): export_profile_dialog.hide())
	var profile_layout := VBoxContainer.new()
	profile_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: profile_layout.add_theme_constant_override("margin_" + edge, 18)
	profile_layout.add_theme_constant_override("separation", 12)
	export_profile_dialog.add_child(profile_layout)
	var profile_help := Label.new()
	profile_help.text = "Selecione os recursos para Godot ou a sequência PNG para outra ferramenta de arte."
	profile_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_layout.add_child(profile_help)
	export_profile_picker = OptionButton.new()
	for option in [["Sprite isolado", "sprite"], ["Personagem animado", "animated"], ["Personagem modular", "modular"], ["Projeto jogável completo", "playable"], ["Mapa e salas", "map"], ["Sequência PNG + timing JSON", "sequence"]]:
		export_profile_picker.add_item(str(option[0]))
		export_profile_picker.set_item_metadata(export_profile_picker.item_count - 1, str(option[1]))
	export_profile_picker.select(3)
	profile_layout.add_child(export_profile_picker)
	var profile_actions := HBoxContainer.new()
	profile_actions.alignment = BoxContainer.ALIGNMENT_END
	profile_layout.add_child(profile_actions)
	var profile_cancel := Button.new()
	profile_cancel.text = "Cancelar"
	profile_cancel.pressed.connect(func(): export_profile_dialog.hide())
	profile_actions.add_child(profile_cancel)
	var profile_continue := Button.new()
	profile_continue.text = "Escolher pasta…"
	profile_continue.pressed.connect(func():
		_selected_export_profile = str(export_profile_picker.get_item_metadata(export_profile_picker.selected))
		export_profile_dialog.hide()
		browse("export")
	)
	profile_actions.add_child(profile_continue)
	add_child(export_profile_dialog)

func show_export_profiles() -> void:
	if is_instance_valid(export_profile_dialog): export_profile_dialog.popup_centered(Vector2i(560, 220))

func build_ai() -> void:
	ai_gateway = preload("res://core/ai_gateway.gd").new()
	add_child(ai_gateway)
	ai_gateway.completed.connect(_on_ai_completed)
	var scroll := ScrollContainer.new()
	scroll.name = "IA Assistida"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	ai_panel = AIPanel.new()
	ai_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ai_panel)
	ai_panel.generate_requested.connect(_request_ai_generation)
	ai_panel.save_requested.connect(func(path: String): ai_last_output_path = path; browse("ai_save"))
	ai_approval_dialog = ConfirmationDialog.new()
	ai_approval_dialog.title = "Autorizar uma chamada paga"
	ai_approval_dialog.ok_button_text = "Autorizar uma chamada"
	ai_approval_dialog.cancel_button_text = "Voltar"
	ai_approval_dialog.confirmed.connect(_execute_approved_ai_request)
	add_child(ai_approval_dialog)

func _request_ai_generation(payload: Dictionary) -> void:
	var capabilities: Dictionary = ai_gateway.capabilities()
	if not capabilities.get("openai", false):
		ai_panel.set_status("Integração não configurada. Defina OPENAI_API_KEY no ambiente ou use .env.local durante o desenvolvimento. O editor continua disponível offline.")
		return
	var approval: Dictionary = ai_gateway.prepare_approval(payload)
	if not approval.get("ok", false):
		ai_panel.set_status(str(approval.get("error", "Pedido inválido.")))
		return
	ai_pending_request = {"payload": approval.payload, "token": approval.token}
	var background := "transparente" if approval.payload.transparent else "opaco"
	ai_approval_dialog.dialog_text = "Uma imagem PNG 1024×1024 será enviada ao provedor OpenAI.\nModelo: %s\nQualidade: %s\nFundo: %s\n\nA descrição completa permanece visível no painel. A chamada pode gerar cobrança. Esta aprovação vale para este pedido, uma única vez; não haverá repetição automática." % [approval.payload.model, approval.payload.quality, background]
	ai_approval_dialog.popup_centered(Vector2i(600, 300))

func _execute_approved_ai_request() -> void:
	if ai_pending_request.is_empty(): return
	var result: Dictionary = ai_gateway.request(ai_pending_request.payload, {"approval_token": ai_pending_request.token})
	ai_pending_request.clear()
	if not result.get("started", false):
		ai_panel.set_busy(false)
		ai_panel.set_status(str(result.get("error", "A chamada não foi iniciada.")))
		return
	ai_panel.set_busy(true)

func _on_ai_completed(result: Dictionary) -> void:
	ai_panel.set_busy(false)
	if not result.get("ok", false):
		ai_panel.set_status(str(result.get("error", "Falha na geração.")))
		return
	ai_last_output_path = str(result.path)
	if ai_panel.set_preview(ai_last_output_path):
		ai_panel.set_status("Imagem recebida e salva localmente • %d × %d • revise e salve como PNG." % [int(result.width), int(result.height)])
	else:
		ai_panel.set_status("A imagem foi gerada, mas não foi possível abrir a prévia local.")

func build_public_library() -> void:
	public_library_panel = preload("res://ui/public_asset_panel.gd").new()
	public_library_panel.name = "Biblioteca pública"
	tabs.add_child(public_library_panel)
	public_library_panel.tile_requested.connect(func(id, tile_index):
		var library = preload("res://core/public_asset_library.gd").new()
		var imported: RefCounted = library.tile_document(id, tile_index)
		if imported == null: notify(library.error); return
		if workspace.add_document(imported, "", true) == "": notify(workspace.error); return
		tabs.current_tab = 0; notify("Tile importado com origem e licença. Revisão artística pendente.")
	)
	public_library_panel.spritesheet_requested.connect(func(id):
		var library = preload("res://core/public_asset_library.gd").new()
		var image: Image = library.image(id)
		if image == null: notify(library.error); return
		var cache_path := workspace_root.path_join("public_asset_import").path_join("%s.png" % str(id).validate_filename())
		var absolute_path := ProjectSettings.globalize_path(cache_path)
		DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
		var save_error := image.save_png(absolute_path)
		if save_error != OK: notify("Não foi possível preparar a spritesheet para importação."); return
		open_spritesheet_import_dialog(absolute_path, str(id))
	)
	public_library_panel.tileset_requested.connect(func(id):
		var popup := ConfirmationDialog.new()
		popup.dialog_text = "Aplicar este tileset e limpar os tiles/terrenos da sala atual? A operação pode ser desfeita."
		add_child(popup)
		popup.canceled.connect(popup.queue_free)
		popup.confirmed.connect(func():
			popup.queue_free()
			var library = preload("res://core/public_asset_library.gd").new()
			var result: Dictionary = library.apply_tileset(doc, id)
			if not result.ok: notify(str(result.error)); return
			world.tile = 0; world.terrain = -1; world.refresh(); refresh_world_controls(); update_title()
			tabs.current_tab = 1; notify("Tileset aplicado com procedência. Use Undo para restaurar a sala.")
		)
		popup.popup_centered()
	)

func build_animation_review() -> void:
	animation_review_panel = preload("res://ui/animation_review_panel.gd").new()
	animation_review_panel.name = "Revisão animada"
	tabs.add_child(animation_review_panel)
	animation_review_panel.sample_requested.connect(_bind_review_sample)
	animation_review_panel.current_requested.connect(func(): animation_review_panel.bind(doc))
	animation_review_panel.editor_requested.connect(func():
		var reviewed: RefCounted = animation_review_panel.review.document
		if reviewed == null: return
		if reviewed != doc: workspace.add_document(reviewed.detached_copy(), "", true)
		tabs.current_tab = 0
	)
	_bind_review_sample()

func _bind_review_sample() -> void:
	var sample: RefCounted = store.load_document(CURRENT_SAMPLE_PATH)
	if sample == null: notify(store.error); return
	animation_review_panel.bind(sample)

func build_3d_motion() -> void:
	three_d_motion_panel = ThreeDMotionPanel.new()
	three_d_motion_panel.name = "3D Motion Studio"
	three_d_motion_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	three_d_motion_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(three_d_motion_panel)
	three_d_motion_panel.capture_requested.connect(_capture_3d_motion_clip)
	three_d_motion_panel.capture_all_requested.connect(_capture_all_3d_motion_clips)
	three_d_motion_panel.cancel_capture_all_requested.connect(_request_cancel_capture_all)
	three_d_motion_panel.save_recipe_requested.connect(func(): _open_production_recipe_dialog("save"))
	three_d_motion_panel.load_recipe_requested.connect(func(): _open_production_recipe_dialog("load"))
	three_d_motion_panel.pose_base_requested.connect(_save_3d_motion_pose)
	three_d_motion_panel.frame_pose_requested.connect(_save_3d_motion_frame_pose)
	three_d_motion_panel.frame_pose_remove_requested.connect(_remove_3d_motion_frame_pose)
	three_d_motion_panel.proportions_requested.connect(_save_3d_motion_proportions)
	three_d_motion_panel.equipment_attachments_requested.connect(_save_3d_motion_attachments)
	three_d_motion_panel.capture_passes_requested.connect(_save_3d_motion_capture_passes)
	three_d_motion_panel.imported_model_requested.connect(_import_3d_motion_model)
	three_d_motion_panel.imported_model_removed_requested.connect(_remove_3d_motion_model)
	three_d_motion_panel.imported_bone_mappings_requested.connect(_save_imported_bone_mappings)
	three_d_motion_panel.imported_equipment_sockets_requested.connect(_save_imported_equipment_sockets)
	three_d_motion_panel.turntable_export_requested.connect(_export_3d_motion_turntable)
	three_d_motion_panel.turntable_import_requested.connect(_import_turntable_as_directions)
	production_recipe_dialog = FileDialog.new()
	production_recipe_dialog.name = "ProductionRecipeDialog"
	production_recipe_dialog.access = FileDialog.ACCESS_FILESYSTEM
	production_recipe_dialog.use_native_dialog = false
	production_recipe_dialog.size = Vector2i(900, 600)
	production_recipe_dialog.filters = PackedStringArray(["*.sfsrecipe.json ; Sprite Forge production recipe"])
	production_recipe_dialog.file_selected.connect(_on_production_recipe_path_selected)
	production_recipe_dialog.canceled.connect(func(): production_recipe_action = "")
	add_child(production_recipe_dialog)
	production_recipe_dialog.current_file = "production.sfsrecipe.json"

func _open_production_recipe_dialog(action: String) -> void:
	if production_recipe_dialog == null or doc == null: return
	production_recipe_action = action
	production_recipe_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "save" else FileDialog.FILE_MODE_OPEN_FILE
	production_recipe_dialog.title = "Salvar receita de produção" if action == "save" else "Aplicar receita de produção"
	production_recipe_dialog.current_file = "production.sfsrecipe.json"
	production_recipe_dialog.popup_centered(Vector2i(900, 600))

func _on_production_recipe_path_selected(selected_path: String) -> void:
	var action := production_recipe_action
	production_recipe_action = ""
	if action == "save":
		var created: Dictionary = production_recipe.create(doc)
		if not created.get("ok", false):
			three_d_motion_panel.set_status(str(created.get("message", "Não foi possível criar a receita.")))
			return
		var save_error: Error = store.atomic_json(selected_path, created.recipe)
		three_d_motion_panel.set_status("Receita salva: %s" % selected_path if save_error == OK else "Não foi possível salvar a receita (erro %d)." % save_error)
		return
	if action != "load": return
	var file := FileAccess.open(selected_path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > ProductionRecipe.MAX_RECIPE_BYTES:
		three_d_motion_panel.set_status("Arquivo de receita ausente, vazio ou maior que 24 MiB.")
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		three_d_motion_panel.set_status("JSON da receita inválido na linha %d." % parser.get_error_line())
		return
	var applied: Dictionary = production_recipe.apply(parser.data, doc)
	if not applied.get("ok", false):
		three_d_motion_panel.set_status(str(applied.get("message", "A receita não foi aplicada.")))
		return
	_three_d_pose_document = null
	_three_d_pose_context = ""
	_load_3d_motion_pose()
	refresh_all()
	workspace.request_checkpoint()
	three_d_motion_panel.set_status("%s Undo restaura integralmente a configuração anterior. Confira o modelo e a direção de arte; a receita não aprova os sprites." % str(applied.message))

func _load_3d_motion_pose() -> void:
	if three_d_motion_panel == null or doc == null: return
	if doc.animation.clips.is_empty(): return
	var clip_index := clampi(int(doc.animation.active), 0, doc.animation.clips.size() - 1)
	var clip_data: Dictionary = doc.animation.clips[clip_index]
	var frames: Array = clip_data.get("frames", [])
	if frames.is_empty(): return
	var frame_index := int(doc.frame) if frames.has(int(doc.frame)) else int(frames[0])
	var context_key := "%d:%d" % [clip_index, frame_index]
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary: rig_data = {}
	var model_asset_value: Variant = rig_data.get("model_asset", {})
	var model_asset: Dictionary = model_asset_value if model_asset_value is Dictionary else {}
	var encoded_model := str(model_asset.get("glb_base64", ""))
	if encoded_model.is_empty():
		three_d_motion_panel.clear_imported_model()
	else:
		var expected_hash := str(model_asset.get("sha256", ""))
		if expected_hash == three_d_motion_panel.imported_model_sha256 and is_instance_valid(three_d_motion_panel.imported_model_root):
			three_d_motion_panel.set_capture_pass_assignments(rig_data.get("capture_pass_assignments", {}))
		elif encoded_model.length() > ceili(float(ThreeDMotionCapture.MAX_MODEL_BYTES) * 4.0 / 3.0) + 8:
			three_d_motion_panel.clear_imported_model()
			three_d_motion_panel.set_status("O modelo GLB embutido excede o limite de 16 MiB; o manequim procedural foi mantido.")
		else:
			var model_bytes := Marshalls.base64_to_raw(encoded_model)
			var load_result: Dictionary = three_d_motion_panel.load_imported_model(model_bytes, str(model_asset.get("filename", "modelo.glb")), rig_data.get("capture_pass_assignments", {}))
			if not load_result.get("ok", false) or (not expected_hash.is_empty() and str(load_result.get("sha256", "")) != expected_hash):
				three_d_motion_panel.clear_imported_model()
				three_d_motion_panel.set_status("O modelo GLB embutido não passou na validação de integridade; o manequim procedural foi mantido.")
	var passes_value: Variant = rig_data.get("capture_pass_assignments", {})
	var sockets_value: Variant = model_asset.get("equipment_sockets", {})
	var restored_sockets: Dictionary = three_d_motion_panel.set_imported_equipment_sockets(sockets_value if sockets_value is Dictionary else {})
	if not restored_sockets.get("ok", false): three_d_motion_panel.set_imported_equipment_sockets({})
	three_d_motion_panel.set_capture_pass_assignments(passes_value if passes_value is Dictionary else {})
	var mapping_value: Variant = model_asset.get("bone_mappings", {})
	var mapped: Dictionary = three_d_motion_panel.set_imported_bone_mappings(mapping_value if mapping_value is Dictionary else {})
	if not mapped.get("ok", false): three_d_motion_panel.set_imported_bone_mappings({})
	var base_value: Variant = rig_data.get("pose_base", {})
	var base_pose: Dictionary = base_value if base_value is Dictionary else {}
	var keys_value: Variant = rig_data.get("pose_keys", {})
	var pose_keys: Dictionary = keys_value if keys_value is Dictionary else {}
	var pose_value: Variant = pose_keys.get(context_key, base_pose)
	var pose: Dictionary = pose_value if pose_value is Dictionary else base_pose
	if _three_d_pose_document != doc or _three_d_pose_context != context_key:
		three_d_motion_panel.set_base_pose(base_pose)
		three_d_motion_panel.set_current_pose(pose)
		_three_d_pose_document = doc
		_three_d_pose_context = context_key
	var proportions_value: Variant = rig_data.get("proportions", ThreeDMotionCapture.DEFAULT_PROPORTIONS)
	three_d_motion_panel.set_proportions(proportions_value if proportions_value is Dictionary else ThreeDMotionCapture.DEFAULT_PROPORTIONS)
	var attachment_value: Variant = rig_data.get("equipment_attachments", ThreeDMotionCapture.DEFAULT_EQUIPMENT_ATTACHMENTS)
	three_d_motion_panel.set_equipment_attachments(attachment_value if attachment_value is Dictionary else ThreeDMotionCapture.DEFAULT_EQUIPMENT_ATTACHMENTS)
	three_d_motion_panel.set_frame_context(clip_index, frame_index, str(clip_data.get("name", "clip")), frames.find(frame_index) + 1, frames.size())
	if not three_d_motion_panel.imported_bone_mappings.is_empty():
		three_d_motion_panel.set_status("Vínculos de ossos ativos: sliders e poses-chave controlam o modelo GLB a partir do repouso. Confira os eixos locais antes de capturar.")
	else:
		three_d_motion_panel.set_status("GLB embutido ativo; capturas percorrem sua animação selecionada. Mapeie ossos para editar poses com os controles SFS." if not three_d_motion_panel.imported_model_sha256.is_empty() else "Rig procedural salvo carregado. Capturas são locais e entram como nova camada revisável.")
	if not restored_sockets.get("ok", false): three_d_motion_panel.set_status("Equipamentos não carregados: " + str(restored_sockets.get("message", "dados inválidos")) + " Os dados salvos foram preservados para correção.")

func _save_imported_equipment_sockets(sockets: Dictionary, project_byte_limit: int = Storage.MAX_FILE_BYTES) -> void:
	if doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impediu alterar os encaixes GLB.")
		return
	var checked: Dictionary = three_d_motion_panel.imported_socket_service.validate(three_d_motion_panel.imported_model_root, sockets)
	if not checked.get("ok", false):
		three_d_motion_panel.set_status(str(checked.get("message", "Encaixes inválidos.")))
		return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_value is Dictionary or not rig_value.get("model_asset", {}) is Dictionary or rig_value.get("model_asset", {}).is_empty(): return
	var rig_data: Dictionary = rig_value.duplicate(true)
	if rig_data.model_asset.get("equipment_sockets", {}) == checked.sockets: return
	var previous_sockets: Dictionary = three_d_motion_panel.imported_equipment_sockets.duplicate(true)
	var previous_passes: Dictionary = three_d_motion_panel.get_capture_pass_assignments()
	var applied: Dictionary = three_d_motion_panel.set_imported_equipment_sockets(checked.sockets)
	if not applied.get("ok", false):
		three_d_motion_panel.set_status(str(applied.get("message", "Não foi possível montar os equipamentos.")))
		return
	rig_data.model_asset["equipment_sockets"] = checked.sockets.duplicate(true)
	rig_data["capture_pass_assignments"] = three_d_motion_panel.get_capture_pass_assignments()
	var encoded: Dictionary = store.encode(doc)
	encoded.art = doc.art.duplicate(true)
	encoded.art.three_d_motion_rig = rig_data
	if JSON.stringify(encoded).to_utf8_buffer().size() > mini(Storage.MAX_FILE_BYTES, maxi(1, project_byte_limit)):
		three_d_motion_panel.set_imported_equipment_sockets(previous_sockets)
		three_d_motion_panel.set_capture_pass_assignments(previous_passes)
		three_d_motion_panel.set_status("Os equipamentos tornariam o projeto maior que 64 MiB. Reduza os arquivos antes de aplicar.")
		return
	doc.checkpoint("Encaixar equipamentos no esqueleto GLB")
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	three_d_motion_panel.set_status("Equipamentos vinculados aos ossos GLB. Arquivos próprios ficam incorporados ao projeto com origem e licença declaradas; revise os encaixes antes de capturar.")

func _save_imported_bone_mappings(mappings: Dictionary) -> void:
	if doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impediu alterar os vínculos dos ossos.")
		return
	var checked: Dictionary = three_d_motion_panel.imported_bone_rig.validate(three_d_motion_panel.imported_model_root, mappings)
	if not checked.get("ok", false):
		three_d_motion_panel.set_status(str(checked.get("message", "Vínculos inválidos.")))
		return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_value is Dictionary or not rig_value.get("model_asset", {}) is Dictionary or rig_value.get("model_asset", {}).is_empty(): return
	var rig_data: Dictionary = rig_value.duplicate(true)
	if rig_data.model_asset.get("bone_mappings", {}) == checked.mappings: return
	doc.checkpoint("Vincular ossos GLB aos controles SFS")
	rig_data.model_asset["bone_mappings"] = checked.mappings.duplicate(true)
	doc.art["three_d_motion_rig"] = rig_data
	three_d_motion_panel.set_imported_bone_mappings(checked.mappings)
	doc.mark_changed()
	three_d_motion_panel.set_status("Vínculos salvos. Sliders, caminhada e poses-chave controlam os ossos selecionados a partir do repouso; revise os eixos e a anatomia.")

func _save_3d_motion_capture_passes(assignments: Dictionary) -> void:
	if doc == null or three_d_motion_panel == null: return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	if doc.art.get("locked", false):
		var previous: Variant = rig_data.get("capture_pass_assignments", {})
		three_d_motion_panel.set_capture_pass_assignments(previous if previous is Dictionary else {})
		three_d_motion_panel.set_status("Art Lock impediu alterar os passes das peças.")
		return
	var normalized: Dictionary = three_d_motion_panel.normalize_capture_pass_assignments(assignments)
	var previous_value: Variant = rig_data.get("capture_pass_assignments", three_d_motion_panel.default_capture_pass_assignments)
	var previous: Dictionary = three_d_motion_panel.normalize_capture_pass_assignments(previous_value if previous_value is Dictionary else {})
	if previous == normalized:
		three_d_motion_panel.set_capture_pass_assignments(normalized)
		return
	doc.checkpoint("Atribuir malhas aos passes 3D")
	rig_data["version"] = maxi(4, int(rig_data.get("version", 2)))
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["capture_pass_assignments"] = normalized.duplicate(true)
	doc.art["three_d_motion_rig"] = rig_data
	three_d_motion_panel.set_capture_pass_assignments(normalized)
	doc.mark_changed()
	three_d_motion_panel.set_status("Atribuições de Corpo/Escudo/Arma salvas. Undo/Redo restaura a configuração; malhas ignoradas continuam visíveis na prévia.")

func _import_3d_motion_model(bytes: PackedByteArray, filename: String) -> void:
	if doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impediu importar ou substituir o modelo 3D.")
		return
	var loaded: Dictionary = three_d_motion_panel.load_imported_model(bytes, filename)
	if not loaded.get("ok", false):
		three_d_motion_panel.set_status(str(loaded.get("message", "Falha ao importar o modelo GLB.")))
		return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	var old_asset: Variant = rig_data.get("model_asset", {})
	if old_asset is Dictionary and str(old_asset.get("sha256", "")) == str(loaded.sha256): return
	var candidate_rig := rig_data.duplicate(true)
	candidate_rig["capture_pass_assignments"] = loaded.capture_pass_assignments.duplicate(true)
	candidate_rig["model_asset"] = {"filename": filename.get_file(), "sha256": loaded.sha256, "glb_base64": Marshalls.raw_to_base64(bytes), "mesh_count": loaded.mesh_count, "vertex_count": loaded.vertex_count, "animations": loaded.animation_names.duplicate()}
	var original_art: Dictionary = doc.art.duplicate(true)
	doc.art["three_d_motion_rig"] = candidate_rig
	var candidate_size := JSON.stringify(store.encode(doc)).to_utf8_buffer().size()
	doc.art = original_art
	if candidate_size > Storage.MAX_FILE_BYTES:
		if old_asset is Dictionary and not str(old_asset.get("glb_base64", "")).is_empty():
			three_d_motion_panel.load_imported_model(Marshalls.base64_to_raw(str(old_asset.glb_base64)), str(old_asset.get("filename", "modelo.glb")), rig_data.get("capture_pass_assignments", {}))
		else:
			three_d_motion_panel.clear_imported_model()
		three_d_motion_panel.set_status("O modelo tornaria o projeto maior que 64 MiB. Reduza o arquivo GLB ou remova dados do projeto.")
		return
	doc.checkpoint("Importar modelo 3D GLB")
	rig_data["version"] = maxi(5, int(rig_data.get("version", 2)))
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["capture_pass_assignments"] = candidate_rig.capture_pass_assignments
	rig_data["model_asset"] = candidate_rig.model_asset
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	three_d_motion_panel.set_status("Modelo GLB incorporado ao projeto SFS. Capturas usarão suas animações selecionadas e passes configuráveis; ossos do modelo não são retargeteados pelo rig procedural.")

func _remove_3d_motion_model() -> void:
	if doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impediu remover o modelo 3D.")
		return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	if not rig_data.has("model_asset"): return
	doc.checkpoint("Remover modelo 3D GLB")
	rig_data.erase("model_asset")
	rig_data.erase("capture_pass_assignments")
	doc.art["three_d_motion_rig"] = rig_data
	three_d_motion_panel.clear_imported_model()
	doc.mark_changed()
	three_d_motion_panel.set_status("Modelo removido; o manequim procedural está ativo novamente. Undo restaura o modelo e os passes.")

func _save_3d_motion_proportions(proportions: Dictionary) -> void:
	if doc == null: return
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary: rig_data = {}
	if doc.art.get("locked", false):
		var previous: Variant = rig_data.get("proportions", ThreeDMotionCapture.DEFAULT_PROPORTIONS)
		three_d_motion_panel.set_proportions(previous if previous is Dictionary else ThreeDMotionCapture.DEFAULT_PROPORTIONS)
		three_d_motion_panel.set_status("Art Lock impediu salvar as proporções do manequim.")
		return
	var normalized := three_d_motion_capture.normalize_proportions(proportions)
	var previous_value: Variant = rig_data.get("proportions", ThreeDMotionCapture.DEFAULT_PROPORTIONS)
	var previous := three_d_motion_capture.normalize_proportions(previous_value if previous_value is Dictionary else {})
	if previous == normalized: return
	doc.checkpoint("Ajustar proporções do manequim 3D")
	rig_data["version"] = maxi(2, int(rig_data.get("version", 2)))
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["proportions"] = normalized
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	three_d_motion_panel.set_status("Proporções salvas no projeto. Undo/Redo restaura o conjunto anterior.")

func _save_3d_motion_attachments(attachments: Dictionary) -> void:
	if doc == null or three_d_motion_panel == null: return
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	if doc.art.get("locked", false):
		var previous: Variant = rig_data.get("equipment_attachments", ThreeDMotionCapture.DEFAULT_EQUIPMENT_ATTACHMENTS)
		three_d_motion_panel.set_equipment_attachments(previous if previous is Dictionary else ThreeDMotionCapture.DEFAULT_EQUIPMENT_ATTACHMENTS)
		three_d_motion_panel.set_status("Art Lock impediu alterar os encaixes 3D/2D.")
		return
	var normalized := three_d_motion_capture.normalize_equipment_attachments(attachments)
	var previous_value: Variant = rig_data.get("equipment_attachments", ThreeDMotionCapture.DEFAULT_EQUIPMENT_ATTACHMENTS)
	var previous := three_d_motion_capture.normalize_equipment_attachments(previous_value if previous_value is Dictionary else {})
	if previous == normalized: return
	doc.checkpoint("Ajustar encaixes de equipamento 3D/2D")
	rig_data["version"] = maxi(3, int(rig_data.get("version", 2)))
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["equipment_attachments"] = normalized
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	three_d_motion_panel.set_status("Encaixes salvos. As capturas projetarão escudo e arma para as âncoras das camadas 2D; Undo/Redo restaura o rig.")

func _save_3d_motion_pose(pose: Dictionary) -> void:
	if doc == null or doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impede gravar alterações ao rig.")
		return
	doc.checkpoint("Gravar pose-base 3D")
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary: rig_data = {}
	rig_data["version"] = 2
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["pose_base"] = pose.duplicate(true)
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	_three_d_pose_document = doc
	three_d_motion_panel.set_status("Pose-base gravada no projeto e incluída no Undo/Redo.")

func _save_3d_motion_frame_pose(pose: Dictionary, clip_index: int, frame_index: int) -> void:
	if doc == null or doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impede gravar uma pose-chave.")
		return
	if clip_index < 0 or clip_index >= doc.animation.clips.size() or not doc.animation.clips[clip_index].get("frames", []).has(frame_index):
		three_d_motion_panel.set_status("O quadro de destino não pertence ao clip ativo.")
		return
	doc.checkpoint("Gravar pose-chave 3D")
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary: rig_data = {}
	var keys_value: Variant = rig_data.get("pose_keys", {})
	var pose_keys: Dictionary = keys_value if keys_value is Dictionary else {}
	pose_keys["%d:%d" % [clip_index, frame_index]] = pose.duplicate(true)
	rig_data["version"] = 2
	rig_data["rig_type"] = "procedural_humanoid_poc"
	rig_data["pose_keys"] = pose_keys
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	_three_d_pose_document = doc
	_three_d_pose_context = "%d:%d" % [clip_index, frame_index]
	three_d_motion_panel.set_status("Pose-chave 3D gravada no clip e quadro atual; a captura interpolará os quadros sem chave.")

func _remove_3d_motion_frame_pose(clip_index: int, frame_index: int) -> void:
	if doc == null or doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impede remover poses-chave.")
		return
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary:
		three_d_motion_panel.set_status("Este projeto não tem um rig 3D salvo.")
		return
	var keys_value: Variant = rig_data.get("pose_keys", {})
	if not keys_value is Dictionary or not keys_value.has("%d:%d" % [clip_index, frame_index]):
		three_d_motion_panel.set_status("Não há pose-chave 3D neste quadro.")
		return
	doc.checkpoint("Remover pose-chave 3D")
	keys_value.erase("%d:%d" % [clip_index, frame_index])
	rig_data["pose_keys"] = keys_value
	doc.art["three_d_motion_rig"] = rig_data
	doc.mark_changed()
	_three_d_pose_document = null
	_load_3d_motion_pose()
	three_d_motion_panel.set_status("Pose-chave removida; a captura interpolará as chaves restantes ou usará a caminhada procedural.")

func _capture_3d_motion_clip() -> void:
	if doc == null or doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock está ativo. Desbloqueie a Bíblia de Arte para capturar.")
		return
	var clip_index := int(doc.animation.active)
	if clip_index < 0 or clip_index >= doc.animation.clips.size():
		three_d_motion_panel.set_status("O projeto não tem um clip ativo válido.")
		return
	var clip_data: Dictionary = doc.animation.clips[clip_index]
	var frame_indices: Array = clip_data.get("frames", [])
	if frame_indices.is_empty() or frame_indices.size() > ThreeDMotionCapture.MAX_CAPTURE_FRAMES:
		three_d_motion_panel.set_status("A prova de conceito captura clips de 1–8 quadros; escolha ou crie um clip desse tamanho.")
		return
	var capture_document = doc
	var capture_revision := int(doc.revision)
	var capture_palette: Array = doc.palette.duplicate(true)
	var capture_frames: Array = frame_indices.duplicate(true)
	var capture_configuration := _three_d_motion_capture_configuration()
	var capture_signature: String = three_d_motion_capture.capture_signature(doc, clip_index, capture_configuration)
	var rig_data: Variant = doc.art.get("three_d_motion_rig", {})
	if not rig_data is Dictionary: rig_data = {}
	var base_value: Variant = rig_data.get("pose_base", {})
	var capture_base_pose: Dictionary = base_value if base_value is Dictionary else {}
	var saved_pose_keys: Dictionary = {}
	var pose_keys_value: Variant = rig_data.get("pose_keys", {})
	var all_pose_keys: Dictionary = pose_keys_value if pose_keys_value is Dictionary else {}
	var prefix := str(clip_index) + ":"
	for key in all_pose_keys:
		if str(key).begins_with(prefix): saved_pose_keys[str(key).substr(prefix.length())] = all_pose_keys[key].duplicate(true)
	var pose_sequence: Array = three_d_motion_capture.build_pose_sequence(capture_base_pose, saved_pose_keys, capture_frames, bool(clip_data.get("loop", true)), clip_data.get("durations_ms", {}))
	three_d_motion_panel.capture_button.disabled = true
	three_d_motion_panel.set_status("Preparando captura 3D nas oito direções…")
	var result: Dictionary = await three_d_motion_panel.capture_sequence(capture_frames, Vector2i(capture_document.width, capture_document.height), capture_palette, pose_sequence)
	if not result.get("ok", false):
		three_d_motion_panel.set_status(str(result.get("message", "Falha na captura 3D.")))
		three_d_motion_panel.capture_button.disabled = false
		return
	if doc != capture_document or int(capture_document.revision) != capture_revision or int(capture_document.animation.active) != clip_index or capture_document.animation.clips[clip_index].get("frames", []) != capture_frames or three_d_motion_capture.capture_signature(capture_document, clip_index, _three_d_motion_capture_configuration()) != capture_signature:
		three_d_motion_panel.set_status("Projeto, clip ou pixels mudaram durante a captura; resultado descartado para evitar aplicar a uma versão desatualizada.")
		three_d_motion_panel.capture_button.disabled = false
		return
	var metadata := {"base_pose": result.get("base_pose", {}), "pose_sequence": pose_sequence.duplicate(true), "proportions": three_d_motion_panel.get_proportions(), "equipment_attachments": result.get("equipment_attachments", {}), "attachment_anchor_positions": result.get("attachment_anchor_positions", []), "capture_pass_assignments": three_d_motion_panel.get_capture_pass_assignments(), "capture_signature": capture_signature, "clip_id": str(clip_index), "source_frame_indices": capture_frames.duplicate(), "capture_method": "SubViewport + Camera3D ortográfica + quantização por paleta + passes geométricos configuráveis"}
	metadata["imported_model"] = three_d_motion_panel.imported_model_asset()
	var applied: Dictionary = three_d_motion_capture.apply_modular_capture(capture_document, clip_index, result.get("pass_images", {}), metadata)
	three_d_motion_panel.capture_button.disabled = false
	if not applied.get("ok", false):
		three_d_motion_panel.set_status(str(applied.get("message", "A captura foi recusada.")))
		return
	if not _capture_all_running: workspace.request_checkpoint()
	refresh_all()
	tabs.current_tab = 0
	three_d_motion_panel.set_status(str(applied.message) + " Use a timeline existente para revisar e sincronizar Corpo, Escudo e Arma.")
	notify("Captura 3D modular importada na timeline; revisão artística necessária.")

func _request_cancel_capture_all() -> void:
	if not _capture_all_running: return
	_capture_all_cancel_requested = true
	three_d_motion_panel.set_batch_capture_state(true, true)
	three_d_motion_panel.set_status("Cancelamento solicitado; o clip em renderização terminará para preservar uma captura íntegra.")

func _three_d_motion_capture_configuration() -> Dictionary:
	if three_d_motion_panel == null: return {}
	return {"proportions": three_d_motion_panel.get_proportions(), "equipment_attachments": three_d_motion_panel.get_equipment_attachments(), "capture_pass_assignments": three_d_motion_panel.get_capture_pass_assignments(), "imported_model": three_d_motion_panel.imported_model_asset()}

func _capture_all_3d_motion_clips() -> void:
	if _capture_all_running or doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock está ativo. Desbloqueie a Bíblia de Arte para capturar.")
		return
	var capture_configuration := _three_d_motion_capture_configuration()
	var capture_signatures: Dictionary = {}
	for clip_index in doc.animation.clips.size(): capture_signatures[str(clip_index)] = three_d_motion_capture.capture_signature(doc, clip_index, capture_configuration)
	var plan: Dictionary = three_d_motion_capture.build_clip_batch_plan(doc, Vector2i(doc.width, doc.height), three_d_motion_panel.get_capture_pass_counts(), capture_signatures)
	if not plan.get("ok", false):
		three_d_motion_panel.set_status(str(plan.get("message", "O lote não passou pela pré-verificação.")))
		return
	if int(plan.get("pending_count", 0)) == 0:
		three_d_motion_panel.set_status("Todos os %d clips já têm os três passes 3D na timeline. Nada precisa ser recapturado." % int(plan.clips))
		return
	_capture_all_running = true
	_capture_all_cancel_requested = false
	three_d_motion_panel.set_batch_capture_state(true)
	three_d_motion_panel.set_status("Lote validado: %d clips restantes de %d · %d renders 3D estimados. A revisão continua manual." % [int(plan.pending_count), int(plan.clips), int(plan.render_count)])
	var target_document = doc
	var original_clip := int(doc.animation.active)
	var completed := 0
	var failure := ""
	for clip_position in plan.pending_clip_indices.size():
		if _capture_all_cancel_requested: break
		var clip_index := int(plan.pending_clip_indices[clip_position])
		target_document.animation.active = clip_index
		var prior_revision := int(target_document.revision)
		three_d_motion_panel.set_status("Capturando clip %d/%d · clip %d da fila · %d renders estimados…" % [clip_index + 1, int(plan.clips), clip_position + 1, int(plan.render_count)])
		await _capture_3d_motion_clip()
		if doc != target_document:
			failure = "O documento ativo foi trocado durante a captura."
			break
		if int(target_document.revision) <= prior_revision:
			failure = str(three_d_motion_panel.status_label.text if is_instance_valid(three_d_motion_panel.status_label) else "A captura do clip falhou.")
			break
		completed += 1
		three_d_motion_panel.set_status("Gravando recuperação do clip %d/%d…" % [clip_position + 1, int(plan.pending_count)])
		if not await _persist_capture_checkpoint(target_document.revision):
			failure = "O checkpoint deste clip não foi confirmado. A captura permanece aberta na sessão; lote pausado para proteger a retomada."
			break
	if doc == target_document:
		target_document.animation.active = original_clip
		refresh_all()
		tabs.current_tab = three_d_motion_panel.get_index()
	_capture_all_running = false
	var was_cancelled := _capture_all_cancel_requested
	_capture_all_cancel_requested = false
	three_d_motion_panel.set_batch_capture_state(false)
	if not failure.is_empty():
		three_d_motion_panel.set_status("Lote interrompido após %d novos clips; %d já estavam completos: %s Capturas concluídas continuam como candidatas e entram na recuperação da sessão." % [completed, plan.completed_clip_indices.size(), failure])
	elif was_cancelled:
		three_d_motion_panel.set_status("Lote cancelado após %d novos clips; %d já estavam completos. As capturas concluídas são candidatas recuperáveis." % [completed, plan.completed_clip_indices.size()])
	else:
		three_d_motion_panel.set_status("Lote concluído: %d clips capturados e %d retomados da sessão, todos com layers editáveis nas oito direções. Revise o pack antes de exportar." % [completed, plan.completed_clip_indices.size()])
	if completed > 0: notify("Capturas 3D do lote adicionadas à timeline como candidatas.")

func _persist_capture_checkpoint(required_revision: int) -> bool:
	var session_id: String = workspace.active_id
	if session_id.is_empty(): return false
	if workspace.recovery_revision(session_id) >= required_revision: return true
	var state := {"done": false, "ok": false}
	var listener := func(kind: String, persisted_id: String, result: int, _target: String) -> void:
		if kind != "checkpoint" or persisted_id != "": return
		if result != OK:
			state.done = true
			state.ok = false
		elif workspace.recovery_revision(session_id) >= required_revision:
			state.done = true
			state.ok = true
	workspace.persisted.connect(listener)
	workspace.request_checkpoint()
	var deadline := Time.get_ticks_msec() + 60000
	while not bool(state.done) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	workspace.persisted.disconnect(listener)
	return bool(state.ok)

func _export_3d_motion_turntable(angles: Array, requested_path: String) -> void:
	if doc == null or three_d_motion_panel == null: return
	var clip_index := int(doc.animation.active)
	if clip_index < 0 or clip_index >= doc.animation.clips.size():
		three_d_motion_panel.set_status("O projeto não tem um clip ativo válido para gerar o turntable.")
		return
	var clip_data: Dictionary = doc.animation.clips[clip_index]
	var frame_indices: Array = clip_data.get("frames", [])
	var resolution := Vector2i(doc.width, doc.height)
	var budget := three_d_motion_capture.validate_turntable_budget(angles.size(), frame_indices.size(), resolution)
	if not budget.get("ok", false):
		three_d_motion_panel.set_status(str(budget.get("message", "Orçamento multivista inválido.")))
		return
	if requested_path.strip_edges().is_empty():
		three_d_motion_panel.set_status("Escolha onde salvar o atlas PNG.")
		return
	var capture_document = doc
	var capture_revision := int(doc.revision)
	var capture_palette: Array = doc.palette.duplicate(true)
	var capture_frames: Array = frame_indices.duplicate(true)
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	var base_value: Variant = rig_data.get("pose_base", {})
	var capture_base_pose: Dictionary = base_value if base_value is Dictionary else {}
	var saved_pose_keys: Dictionary = {}
	var pose_keys_value: Variant = rig_data.get("pose_keys", {})
	var all_pose_keys: Dictionary = pose_keys_value if pose_keys_value is Dictionary else {}
	var prefix := str(clip_index) + ":"
	for key in all_pose_keys:
		if str(key).begins_with(prefix): saved_pose_keys[str(key).substr(prefix.length())] = all_pose_keys[key].duplicate(true)
	var pose_sequence: Array = three_d_motion_capture.build_pose_sequence(capture_base_pose, saved_pose_keys, capture_frames, bool(clip_data.get("loop", true)), clip_data.get("durations_ms", {}))
	three_d_motion_panel.turntable_export_button.disabled = true
	three_d_motion_panel.set_status("Preparando %d vistas e %d quadros…" % [angles.size(), capture_frames.size()])
	var result: Dictionary = await three_d_motion_panel.capture_turntable(capture_frames, resolution, capture_palette, pose_sequence, angles)
	three_d_motion_panel.turntable_export_button.disabled = false
	if not result.get("ok", false):
		three_d_motion_panel.set_status(str(result.get("message", "Falha na captura multivista.")))
		return
	if doc != capture_document or int(capture_document.revision) != capture_revision or int(capture_document.animation.active) != clip_index or capture_document.animation.clips[clip_index].get("frames", []) != capture_frames:
		three_d_motion_panel.set_status("O projeto ou clip mudou durante a captura; atlas descartado para evitar misturar estados diferentes.")
		return
	var safe_path := _unique_turntable_path(requested_path)
	if safe_path.is_empty():
		three_d_motion_panel.set_status("Não há um nome de arquivo livre; escolha outra pasta ou nome para o turntable.")
		return
	var image_count := angles.size() * capture_frames.size()
	var columns := mini(8, image_count)
	var rows := ceili(float(image_count) / float(columns))
	var atlas := Image.create(resolution.x * columns, resolution.y * rows, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var cells: Array[Dictionary] = []
	for view_index in angles.size():
		for frame_slot in capture_frames.size():
			var flat_index := view_index * capture_frames.size() + frame_slot
			var x := (flat_index % columns) * resolution.x
			var y := int(flat_index / columns) * resolution.y
			var cel: Image = result.images[view_index][frame_slot]
			atlas.blit_rect(cel, Rect2i(Vector2i.ZERO, resolution), Vector2i(x, y))
			cells.append({"index": flat_index, "view_index": view_index, "angle_degrees": float(angles[view_index]), "direction": str(result.direction_order[view_index]), "frame": int(capture_frames[frame_slot]), "x": x, "y": y, "width": resolution.x, "height": resolution.y})
	var png_error: Error = atlas.save_png(safe_path)
	if png_error != OK:
		three_d_motion_panel.set_status("Não foi possível escrever o atlas PNG. Código: %d" % png_error)
		return
	var metadata_path := safe_path.get_basename() + ".json"
	var metadata := {"schema": 1, "generator": "Sprite Forge Studio 3D Motion", "projection": "orthographic", "angles_degrees": angles.duplicate(true), "direction_order": result.direction_order.duplicate(true), "frame_indices": capture_frames, "columns": columns, "rows": rows, "cell_width": resolution.x, "cell_height": resolution.y, "cells": cells, "proportions": three_d_motion_panel.get_proportions(), "equipment_attachments": result.get("equipment_attachments", {}), "attachment_anchor_positions": result.get("attachment_anchor_positions", []), "pose_base": result.get("base_pose", {}), "pose_sequence": pose_sequence, "palette_quantized": true, "review_required": true, "source_document_revision": capture_revision, "clip": str(clip_data.get("name", ""))}
	metadata["imported_model"] = three_d_motion_panel.imported_model_asset()
	var json_error: Error = store.atomic_json(metadata_path, metadata)
	if json_error != OK:
		DirAccess.remove_absolute(safe_path)
		three_d_motion_panel.set_status("Não foi possível gravar o JSON do atlas; o PNG incompleto foi removido. Código: %d" % json_error)
		return
	three_d_motion_panel.set_status("Atlas salvo: %d vistas × %d quadros · %s + JSON. Captura mantida como candidata." % [angles.size(), capture_frames.size(), safe_path])
	notify("Turntable multivista salvo; revisão artística necessária.")

func _unique_turntable_path(requested_path: String) -> String:
	var base := requested_path if requested_path.to_lower().ends_with(".png") else requested_path + ".png"
	var metadata := base.get_basename() + ".json"
	if not FileAccess.file_exists(base) and not FileAccess.file_exists(metadata): return base
	var stem := base.get_basename()
	for suffix in range(2, 10000):
		var candidate := "%s-%02d.png" % [stem, suffix]
		if not FileAccess.file_exists(candidate) and not FileAccess.file_exists(candidate.get_basename() + ".json"): return candidate
	return ""

func _import_turntable_as_directions(angles: Array) -> void:
	if doc == null or three_d_motion_panel == null: return
	if doc.art.get("locked", false):
		three_d_motion_panel.set_status("Art Lock impede gerar e inserir novas cels no documento.")
		return
	var clip_index := int(doc.animation.active)
	if clip_index < 0 or clip_index >= doc.animation.clips.size():
		three_d_motion_panel.set_status("O projeto não tem um clip ativo válido.")
		return
	var clip_data: Dictionary = doc.animation.clips[clip_index]
	var frame_indices: Array = clip_data.get("frames", [])
	var resolution := Vector2i(doc.width, doc.height)
	var mapping: Dictionary = three_d_motion_capture.map_turntable_to_directions(angles)
	if not mapping.get("ok", false):
		three_d_motion_panel.set_status(str(mapping.get("message", "Não foi possível mapear as vistas nas oito direções.")))
		return
	var budget: Dictionary = three_d_motion_capture.validate_turntable_budget(angles.size(), frame_indices.size(), resolution)
	if not budget.get("ok", false):
		three_d_motion_panel.set_status(str(budget.get("message", "Orçamento multivista inválido.")))
		return
	var capture_document = doc
	var capture_revision := int(doc.revision)
	var capture_palette: Array = doc.palette.duplicate(true)
	var capture_frames: Array = frame_indices.duplicate(true)
	var rig_value: Variant = doc.art.get("three_d_motion_rig", {})
	var rig_data: Dictionary = rig_value if rig_value is Dictionary else {}
	var base_value: Variant = rig_data.get("pose_base", {})
	var capture_base_pose: Dictionary = base_value if base_value is Dictionary else {}
	var saved_pose_keys: Dictionary = {}
	var pose_keys_value: Variant = rig_data.get("pose_keys", {})
	var all_pose_keys: Dictionary = pose_keys_value if pose_keys_value is Dictionary else {}
	var prefix := str(clip_index) + ":"
	for key in all_pose_keys:
		if str(key).begins_with(prefix): saved_pose_keys[str(key).substr(prefix.length())] = all_pose_keys[key].duplicate(true)
	var pose_sequence: Array = three_d_motion_capture.build_pose_sequence(capture_base_pose, saved_pose_keys, capture_frames, bool(clip_data.get("loop", true)), clip_data.get("durations_ms", {}))
	three_d_motion_panel.turntable_import_button.disabled = true
	three_d_motion_panel.set_status("Capturando %d vistas para mapear às oito direções…" % angles.size())
	var result: Dictionary = await three_d_motion_panel.capture_turntable(capture_frames, resolution, capture_palette, pose_sequence, angles)
	three_d_motion_panel.turntable_import_button.disabled = false
	if not result.get("ok", false):
		three_d_motion_panel.set_status(str(result.get("message", "Falha na captura multivista.")))
		return
	if doc != capture_document or int(capture_document.revision) != capture_revision or int(capture_document.animation.active) != clip_index or capture_document.animation.clips[clip_index].get("frames", []) != capture_frames:
		three_d_motion_panel.set_status("O projeto ou clip mudou durante a captura; cels descartadas para proteger a versão atual.")
		return
	var mapped_images: Array = []
	for view_index in mapping.view_indices:
		mapped_images.append(result.images[int(view_index)].duplicate(true))
	var mapped_attachment_anchors: Array = []
	var all_attachment_anchors: Variant = result.get("attachment_anchor_positions", [])
	if all_attachment_anchors is Array:
		for view_index in mapping.view_indices:
			if int(view_index) < all_attachment_anchors.size(): mapped_attachment_anchors.append(all_attachment_anchors[int(view_index)].duplicate(true))
	var metadata := {"capture_method": "SubViewport turntable multivista; vistas mais próximas mapeadas às oito direções", "source_turntable_angles": angles.duplicate(true), "selected_turntable_view_indices": mapping.view_indices.duplicate(true), "camera_yaw_degrees": mapping.camera_yaw_degrees.duplicate(true), "directional_angle_errors_degrees": mapping.angular_errors_degrees.duplicate(true), "proportions": three_d_motion_panel.get_proportions(), "equipment_attachments": result.get("equipment_attachments", {}), "attachment_anchor_positions": mapped_attachment_anchors, "pose_sequence": pose_sequence.duplicate(true), "clip_id": str(clip_index), "source_frame_indices": capture_frames.duplicate()}
	metadata["imported_model"] = three_d_motion_panel.imported_model_asset()
	var applied: Dictionary = three_d_motion_capture.apply_capture(capture_document, clip_index, mapped_images, metadata)
	if not applied.get("ok", false):
		three_d_motion_panel.set_status(str(applied.get("message", "A captura mapeada foi recusada.")))
		return
	refresh_all()
	tabs.current_tab = 0
	three_d_motion_panel.set_status("%d vistas capturadas; oito foram alinhadas às direções canônicas e inseridas em uma camada candidata. Ângulo máximo de erro: %.2f°; revisão necessária." % [angles.size(), mapping.angular_errors_degrees.max()])
	notify("Turntable multivista alinhado às oito direções e adicionado como layer revisável.")

func build_hyperlearn() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "HyperLearn Lab"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	hyperlearn_panel = preload("res://ui/hyperlearn_panel.gd").new()
	hyperlearn_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hyperlearn_panel)
	local_image_provider = preload("res://core/local_image_provider.gd").new()
	add_child(local_image_provider)
	local_image_provider.progress.connect(func(message): hyperlearn_panel.set_local_status(message, true))
	local_image_provider.completed.connect(_on_local_generation_completed)
	hyperlearn_panel.review_requested.connect(_record_hyperlearn_review)
	hyperlearn_panel.train_requested.connect(_train_hyperlearn)
	hyperlearn_panel.evaluate_requested.connect(_evaluate_hyperlearn)
	hyperlearn_panel.model_path.text = local_image_provider.default_model_path()
	hyperlearn_panel.lora_path.text = local_image_provider.default_lora_path()
	hyperlearn_panel.local_check_requested.connect(_check_local_generation)
	hyperlearn_panel.local_generate_requested.connect(_generate_local)
	hyperlearn_panel.local_stop_requested.connect(func(): local_image_provider.stop(); hyperlearn_panel.set_local_status("Motor local parado."))
	hyperlearn_panel.generation_save_requested.connect(func(file): ai_last_output_path = file; browse("ai_save"))
	var model_dialog := FileDialog.new()
	model_dialog.title = "Selecionar modelo local Stable Diffusion GGUF"
	model_dialog.access = FileDialog.ACCESS_FILESYSTEM
	model_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	model_dialog.filters = PackedStringArray(["*.gguf ; Modelo GGUF"])
	model_dialog.file_selected.connect(func(file): hyperlearn_panel.model_path.text = file)
	add_child(model_dialog)
	hyperlearn_panel.local_model_browse_requested.connect(func(): model_dialog.popup_centered(Vector2i(900, 600)))
	var lora_dialog := FileDialog.new()
	lora_dialog.title = "Selecionar LoRA local de pixel art"
	lora_dialog.access = FileDialog.ACCESS_FILESYSTEM
	lora_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	lora_dialog.filters = PackedStringArray(["*.safetensors,*.gguf,*.ckpt,*.pt ; LoRA compatível"])
	lora_dialog.file_selected.connect(func(file): hyperlearn_panel.lora_path.text = file)
	add_child(lora_dialog)
	hyperlearn_panel.local_lora_browse_requested.connect(func(): lora_dialog.popup_centered(Vector2i(900, 600)))
	hyperlearn_panel.local_models_folder_requested.connect(func():
		var folder := ProjectSettings.globalize_path("user://local_ai/models")
		DirAccess.make_dir_recursive_absolute(folder)
		OS.shell_open(folder)
	)
	refresh_hyperlearn()

func refresh_hyperlearn() -> void:
	if hyperlearn_panel == null: return
	var state := hyperlearn.evaluate(doc, false)
	hyperlearn_panel.show_report(hyperlearn.counts(), hyperlearn.model, state, hyperlearn.examples)

func _record_hyperlearn_review(approved: bool, reviewer_name: String, note: String, confirmed: bool, direction_indices: Array) -> void:
	var result: Dictionary = hyperlearn.record_review(doc, approved, reviewer_name, note, confirmed, direction_indices)
	if not result.get("ok", false): notify(str(result.get("error", "Não foi possível registrar a decisão."))); return
	var learned: Dictionary = hyperlearn.train()
	refresh_hyperlearn()
	var scope_text := "no pack inteiro" if direction_indices.is_empty() else "em %d direção(ões)" % direction_indices.size()
	var learn_text := "Modelo geral recalibrado." if learned.get("ok", false) else str(learned.get("reason", "Avaliação preservada para revisão humana."))
	notify("Decisão humana registrada " + scope_text + ". " + learn_text)

func _train_hyperlearn() -> void:
	var result: Dictionary = hyperlearn.train()
	refresh_hyperlearn()
	var trained_model: Dictionary = result.get("model", {})
	notify("HyperLearn recalibrado: %d exemplos completos; validação balanceada %.0f%%, recall aprovado/reprovado %.0f%% / %.0f%%, Brier %.3f. Isso não representa anatomia." % [int(trained_model.get("training_examples", 0)), float(trained_model.get("validation_balanced_accuracy", 0.0)) * 100.0, float(trained_model.get("validation_approved_recall", 0.0)) * 100.0, float(trained_model.get("validation_rejected_recall", 0.0)) * 100.0, float(trained_model.get("validation_brier_score", 1.0))] if result.get("ok", false) else str(result.get("reason", "Treino não iniciado.")))

func _evaluate_hyperlearn(autonomous: bool) -> void:
	hyperlearn_evaluation = hyperlearn.evaluate(doc, autonomous)
	if autonomous and hyperlearn_evaluation.get("decision", "") in ["auto_approve_candidate", "auto_reject_candidate"]:
		# Automated decisions are kept separate from human approval and never mutate pixels.
		doc.checkpoint("Decisão candidata HyperLearn")
		doc.art["hyperlearn_last_decision"] = {"decision": hyperlearn_evaluation.decision, "probability": hyperlearn_evaluation.probability, "model_examples": hyperlearn.model.training_examples, "at": Time.get_datetime_string_from_system(true), "human_approval": false}
		doc.mark_changed()
		notify("HyperLearn classificou um candidato. Isso não cria aprovação artística humana nem libera exportação final.")
	else: notify(str(hyperlearn_evaluation.get("reason", "Revisão humana necessária.")))
	refresh_hyperlearn()

func _check_local_generation(model_path: String, lora_path: String) -> void:
	var request_result: Dictionary = local_image_provider.check(model_path, lora_path)
	hyperlearn_panel.set_local_status("Consultando apenas a instância local…", true) if request_result.get("started", false) else hyperlearn_panel.set_local_status(str(request_result.get("error", "Conexão não iniciada.")))

func _generate_local(model_path: String, lora_path: String, prompt: String, negative_prompt: String, width: int, height: int, steps: int, seed: int, use_lora: bool, lora_strength: float) -> void:
	var request_result: Dictionary = local_image_provider.generate(model_path, lora_path, prompt, negative_prompt, width, height, steps, seed, use_lora, lora_strength)
	var generating_status := "Gerando somente no computador local…"
	if model_path.get_file().to_lower().contains("dreamshaper8_lcm"):
		generating_status = "Gerando localmente com DreamShaper 8 LCM · até 8 passos…"
	var status_message := "Inicializando motor local; a primeira carga pode levar alguns minutos…" if request_result.get("starting_engine", false) else generating_status
	hyperlearn_panel.set_local_status(status_message, true) if request_result.get("started", false) else hyperlearn_panel.set_local_status(str(request_result.get("error", "Geração não iniciada.")))

func _on_local_generation_completed(result: Dictionary) -> void:
	var details: Dictionary = result.get("details", {})
	if details.get("stage", "") == "health": hyperlearn_panel.set_local_status(str(result.get("message", "Motor local pronto. Nenhuma chamada GPT foi feita."))); return
	if not result.get("ok", false): hyperlearn_panel.set_local_status(str(result.get("message", "Falha local."))); return
	if hyperlearn_panel.set_generated_image(str(details.get("path", ""))):
		hyperlearn_panel.set_local_status("%s · %d×%d · candidato sem aprovação automática." % [str(result.message), int(details.width), int(details.height)])
	else: hyperlearn_panel.set_local_status("A geração terminou, mas a prévia não pôde ser carregada.")

func build_editor() -> void:
	var editor := column(tabs)
	editor.name = "Pixel Studio"
	var tools := row(editor)
	tool_picker = choice(DRAWING_TOOLS, tools, select_drawing_tool)
	label("Ponta", tools)
	spin(tools, 1, 8, 1, func(v): canvas.brush_size = int(v))
	color_picker = ColorPickerButton.new()
	color_picker.color = Color(doc.palette[2])
	color_picker.custom_minimum_size = Vector2(44, 30)
	color_picker.color_changed.connect(func(c): canvas.color = c)
	tools.add_child(color_picker)
	check("Espelhar", tools, func(v): canvas.mirror = v)
	var grid_check := check("Grade", tools, func(v): canvas.grid = v; canvas.queue_redraw())
	grid_check.set_pressed_no_signal(true)
	check("Onion", tools, func(v): canvas.onion = v; canvas.refresh())
	rig_control = check("Rig", tools, func(v): canvas.rig = v or canvas.tool == "Âncora"; canvas.queue_redraw())
	button("Limpar máscara", tools, func(): doc.selection = Rect2i(); canvas.queue_redraw())
	button("↶", tools, undo, "Ctrl+Z")
	button("↷", tools, redo, "Ctrl+Y")
	button("Histórico", tools, history_dialog)
	button("Enquadrar", tools, func(): canvas.fit_canvas())
	var transforms := row(editor)
	button("Redimensionar canvas…", transforms, resize_canvas_dialog, "Escala as cels e metadados espaciais em uma operação reversível.")
	button("Copiar", transforms, copy_pixels, "Ctrl+C")
	button("Colar", transforms, paste_pixels, "Ctrl+V")
	button("Virar H", transforms, func(): transform("flip_x"))
	button("Virar V", transforms, func(): transform("flip_y"))
	button("Girar 90°", transforms, func(): transform("rotate"), "Seleção quadrada; rotação exata, sem interpolação")
	for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		button({Vector2i.LEFT: "←", Vector2i.RIGHT: "→", Vector2i.UP: "↑", Vector2i.DOWN: "↓"}[delta], transforms, func(): transform("move", delta))
	button("Proteger região", transforms, func(): doc.protect_selection(); edited())
	button("Desproteger cel", transforms, func(): doc.protect_selection(true); edited())
	var cluster_row := row(editor)
	button("Revisar clusters pequenos…", cluster_row, review_cluster_cleanup, "Propõe remover ilhas conectadas de até 64 pixels no cel ativo. A prévia é obrigatória; máscaras e seleções são respeitadas.")
	var rig_segment_row := row(editor)
	button("Extrair região em camada de rig…", rig_segment_row, open_rig_segment_extractor, "Move os pixels da seleção ou de um componente conectado para uma camada própria e permite mapeá-la a um osso.")
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_child(split)
	canvas = PixelCanvas.new()
	canvas.doc = doc
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.edited.connect(edited)
	canvas.stroke_started.connect(stop_playback)
	canvas.picked.connect(func(c): color_picker.color = c; canvas.color = c)
	split.add_child(canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 270
	split.add_child(scroll)
	var side := column(scroll)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label("CAMADAS / EQUIPAMENTOS", side, 13)
	layers_list = ItemList.new()
	layers_list.custom_minimum_size = Vector2(245, 180)
	layers_list.item_selected.connect(func(index): doc.active_layer = index; refresh_layer())
	side.add_child(layers_list)
	var actions := row(side)
	button("+", actions, func():
		workspace.refresh_budgets()
		if doc.layers.size() >= 16 or doc.pixel_bytes() + doc.width * doc.height * 4 * doc.frames * 8 > doc.pixel_budget_limit: notify("Limite de camadas ou memória da área de trabalho atingido."); return
		doc.checkpoint("Adicionar camada"); doc.add_layer("Camada " + str(doc.layers.size() + 1)); refresh_all()
	)
	button("−", actions, func():
		if doc.layers.size() <= 1: return
		doc.checkpoint(); doc.layers.remove_at(doc.active_layer); doc.active_layer = maxi(0, doc.active_layer - 1); refresh_all()
	)
	button("↑", actions, func(): move_layer(1), "Subir na composição")
	button("↓", actions, func(): move_layer(-1))
	button("Efeito…", actions, open_sprite_effect_dialog, "Gera brilho, clarão ou partículas como camada de pixels. Pode regenerar a camada de efeito ativa.").name = "SpriteEffectButton"
	layer_mask_status = label("Máscara de visibilidade da cel", side, 11)
	var mask_actions := row(side)
	button("Ocultar seleção", mask_actions, func(): edit_layer_visibility_mask("hide"), "Oculta a seleção somente nesta layer, direção e quadro, preservando os pixels originais.").name = "HideLayerSelection"
	button("Revelar seleção", mask_actions, func(): edit_layer_visibility_mask("reveal")).name = "RevealLayerSelection"
	button("Remover máscara da cel", side, func(): edit_layer_visibility_mask("clear")).name = "ClearLayerMask"
	layer_name = LineEdit.new()
	layer_name.placeholder_text = "Nome da camada (Enter)"
	layer_name.text_submitted.connect(func(t): doc.checkpoint(); doc.layers[doc.active_layer].name = t; refresh_all())
	side.add_child(layer_name)
	layer_retarget_key = LineEdit.new()
	layer_retarget_key.placeholder_text = "Chave de retarget entre projetos"
	layer_retarget_key.text_submitted.connect(func(t):
		var key: String = str(t).strip_edges().to_lower()
		if key.is_empty(): notify("A chave de retarget não pode ficar vazia."); refresh_layer(); return
		if str(doc.layers[doc.active_layer].get("retarget_key", "")) == key: return
		doc.checkpoint("Chave de retarget")
		doc.layers[doc.active_layer].retarget_key = key
		edited()
	)
	side.add_child(layer_retarget_key)
	visibility = check("Visível", side, func(v): set_layer("visible", v))
	locked = check("Bloqueada", side, func(v): set_layer("locked", v))
	label("Opacidade", side)
	opacity = HSlider.new()
	opacity.min_value = 0
	opacity.max_value = 1
	opacity.step = 0.05
	opacity.drag_started.connect(func(): if not syncing: doc.checkpoint())
	opacity.value_changed.connect(func(v):
		if not syncing: doc.layers[doc.active_layer].opacity = v; edited()
	)
	side.add_child(opacity)
	equipment = check("Equipamento modular", side, func(v): set_layer("equipment", v))
	label("Âncora do equipamento / ferramenta", side)
	anchor_picker = choice([], side, func(i):
		set_layer("anchor", anchor_names[i])
	)
	label("Articulações do rig nesta vista", side)
	var joint_row := row(side)
	joint_picker = choice([], joint_row, func(i): canvas.anchor_name = anchor_names[i]; canvas.queue_redraw())
	button("+ Articulação", joint_row, add_joint_dialog)
	button("Remover", joint_row, remove_selected_joint)
	label("Use a ferramenta Âncora para colocar a articulação selecionada. Linhas do esqueleto são guias; não deformam pixels.", side, 11)
	button("Marcar pose-chave do rig", side, mark_rig_pose_key, "Registra a rotação visível, o offset da camada modular e a articulação atual; inclui valores neutros como 0°.")
	button("Interpolar poses do rig…", side, interpolate_rig_dialog, "Preenche rotações, offsets e articulações entre chaves do clip atual; mantém pixels e poses-chave.")
	button("Criar quadros raster intermediários…", side, raster_inbetween_dialog, "Gera até oito cels editáveis entre duas poses-chave no mesmo clip/direção. Exige camadas visíveis mapeadas ao rig; prévia e Undo incluídos.")
	button("Inserir e gerar novos quadros…", side, raster_insert_frames_dialog, "Insere até oito frames reais entre poses adjacentes, redistribui o tempo sem alterar o intervalo e gera uma prévia raster revisável.")
	button("Retargetar pose por segmentos…", side, retarget_pose_dialog, "Aplica orientação de ossos mapeados a outra pose do mesmo clip e direção, mantendo os pixels de origem.")
	button("Retargetar de outro projeto…", side, func(): browse("retarget_source"), "Transfere rotações de um projeto SFS compatível para a pose atual. Exige chaves de camada e rig correspondentes.")
	button("Aplicar pose à camada (pixels)…", side, bake_layer_pose_dialog, "Converte rotação/offset da camada e pose atuais em pixels editáveis nesta cel, preservando a composição. Confirme a prévia; Undo reverte.")
	label("Offset local X / Y • direção/frame", side)
	var offsets := row(side)
	offset_x = spin(offsets, -1024, 1024, 0, func(v): change_offset(0, int(v)))
	offset_y = spin(offsets, -1024, 1024, 0, func(v): change_offset(1, int(v)))
	button("Importar PNG na cel", side, func(): browse("import"))
	button("Importar spritesheet", side, func(): browse("spritesheet"), "Recorta uma grade sem interpolar pixels e importa uma faixa, quatro direções LPC ou oito direções.")
	button("Importar sequência PNG…", side, func(): browse("png_sequence"), "Abre sequence.json como um novo projeto composto, preservando clips, timing, pivôs e eventos.")
	button("Revisar correção pela paleta", side, review_correction, "Gera proposta limitada à máscara e compara antes/depois.")
	label("Família anatômica", side)
	family_picker = choice(FAMILIES, side, func(i): if not syncing: doc.checkpoint(); doc.rig.family = FAMILIES[i]; edited())
	asymmetric_control = check("Assimétrico: preservar lateralidade", side, func(v): set_layer("asymmetric", v))
	label("Profundidade nesta direção/frame", side)
	depth_control = spin(side, -20, 20, 0, func(v):
		if syncing: return
		doc.checkpoint()
		if not doc.rig.depth.has(doc.cel_key()): doc.rig.depth[doc.cel_key()] = {}
		doc.rig.depth[doc.cel_key()][doc.layers[doc.active_layer].id] = int(v)
		edited()
	)
	label("Pivô de rotação / pose desta direção e frame", side)
	pivot_picker = choice([], side, func(i):
		if syncing: return
		doc.checkpoint("Pivô do rig")
		doc.layers[doc.active_layer].pivot = anchor_names[i]
		if not doc.layers[doc.active_layer].get("bone", []).is_empty() and str(doc.layers[doc.active_layer].bone[0]) != anchor_names[i]: doc.layers[doc.active_layer].bone = []
		edited()
		refresh_layer()
	)
	label("Segmento anatômico desta camada", side)
	bone_picker = OptionButton.new()
	bone_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bone_picker.item_selected.connect(func(i):
		if syncing: return
		var segment: Array = [] if i == 0 else doc.rig.skeleton[i - 1].duplicate(true)
		if doc.set_layer_bone(str(doc.layers[doc.active_layer].id), segment):
			edited()
			refresh_layer()
	)
	side.add_child(bone_picker)
	var rotation_row := row(side)
	rotation_label = label("0°", rotation_row)
	rotation_control = HSlider.new()
	rotation_control.min_value = -180
	rotation_control.max_value = 180
	rotation_control.step = 1
	rotation_control.tooltip_text = "Rotação rígida por vizinho próximo; pixels fonte não são alterados."
	rotation_control.drag_started.connect(func():
		if not syncing:
			doc.checkpoint("Posar camada")
			rotation_dragging = true
	)
	rotation_control.drag_ended.connect(func(_changed): rotation_dragging = false)
	rotation_control.value_changed.connect(func(value):
		rotation_label.text = "%d°" % roundi(value)
		if syncing: return
		var layer: Dictionary = doc.layers[doc.active_layer]
		if doc.set_layer_rotation(layer.id, value, -1, -1, not rotation_dragging): edited()
	)
	rotation_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_row.add_child(rotation_control)
	button("Validar adaptação do equipamento", side, func():
		if not doc.layers[doc.active_layer].equipment: return
		doc.checkpoint(); doc.layers[doc.active_layer].families = [doc.rig.family]; edited(); notify("Compatibilidade registrada manualmente; revise o encaixe.")
	)
	label("Âncoras: por direção e frame", side, 12)
	pixel_preview = TextureRect.new()
	pixel_preview.custom_minimum_size = Vector2(128, 80)
	pixel_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pixel_preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pixel_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	side.add_child(pixel_preview)
	label("Prévia 1:1", side, 12)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	for control in side.get_children():
		if control is Label: control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if control is Button:
			control.clip_text = true
			if control.tooltip_text.is_empty(): control.tooltip_text = control.text
	label("Paleta", editor)
	palette_box = row(editor)
	var palette_actions := row(editor)
	button("Criar rampa de material…", palette_actions, open_material_ramp_dialog, "Gera e registra uma rampa nomeada entre sombra, base e luz. A prévia exige confirmação.")
	button("Recolorir região com rampa…", palette_actions, open_material_recolor_dialog, "Substitui uma cor-fonte pela cor de material escolhida dentro da seleção ou componente conectado.")
	var timeline := row(editor)
	direction_picker = choice(Document.DIRECTIONS, timeline, func(i):
		doc.direction = i
		canvas.refresh()
		refresh_layer()
		refresh_frame_highlight()
		if timeline_view != null: timeline_view.refresh()
	)
	button("|◀", timeline, func(): step_frame(-1))
	play_button = button("▶ Play", timeline, toggle_playback)
	button("▶|", timeline, func(): step_frame(1))
	label("FPS", timeline)
	fps_control = spin(timeline, 1, 60, doc.fps, func(v): doc.checkpoint(); doc.fps = int(v); update_title())
	button("+ Frame", timeline, func():
		workspace.refresh_budgets()
		if doc.duplicate_frame(): refresh_all()
		else: notify("Limite de frames ou memória da área de trabalho atingido.")
	)
	button("− Frame", timeline, func(): doc.delete_frame(); refresh_all())
	button("Copiar direção → próxima", timeline, copy_direction)
	timeline_view = AnimationTimeline.new()
	timeline_view.set_document(doc)
	timeline_view.frame_selected.connect(seek_frame)
	editor.add_child(timeline_view)
	var clips_row := row(editor)
	clip_picker = choice([], clips_row, func(i):
		stop_playback(); doc.animation.active = i; doc.frame = int(doc.clip().frames[0]); refresh_all()
	)
	button("Novo clip", clips_row, create_clip_dialog)
	var clip_actions := row(editor)
	button("Duplicar clip", clip_actions, func():
		if doc.duplicate_clip(): refresh_all()
		else: notify("Limite de 32 clips atingido.")
	)
	button("Renomear clip", clip_actions, rename_clip_dialog)
	button("Excluir clip", clip_actions, delete_clip_dialog)
	button("Prévia de sequência…", clip_actions, open_clip_sequence_dialog, "Reproduz clips em ordem para revisar cortes e transições, sem modificar os quadros.")
	preview_sequence_status = label("", clip_actions)
	button("■ Stop", clips_row, func(): stop_playback(); doc.frame = int(doc.clip().frames[0]); refresh_all())
	loop_control = check("Loop", clips_row, func(v): if not syncing: doc.checkpoint(); doc.clip().loop = v)
	check("Reverso", clips_row, func(v): reverse_playback = v)
	label("Velocidade", clips_row)
	var speed := spin(clips_row, 1, 400, 100, func(v): playback_speed = v / 100.0)
	speed.suffix = "%"
	label("Frame ms", clips_row)
	duration_control = spin(clips_row, 10, 10000, 125, func(v): if not syncing: doc.checkpoint(); doc.clip().durations_ms[str(doc.frame)] = int(v))
	button("Hitbox = máscara", clips_row, hitbox_from_selection)
	button("Gerar respiração", clips_row, generate_breathing_cycle, "Cria um ciclo sutil a partir da pose-base do clip em loop, para as oito direções.")
	button("Evento", clips_row, event_dialog)
	check("Mostrar eventos", clips_row, func(v): show_animation_events = v)

func hitbox_from_selection() -> void:
	var region := Rect2i(doc.selection.position + doc.layer_offset(), doc.selection.size).intersection(Rect2i(0, 0, doc.width, doc.height))
	if region.size.x <= 0 or region.size.y <= 0: notify("Selecione uma região visível para a hitbox."); return
	doc.checkpoint("Hitbox")
	doc.animation.hitboxes[doc.cel_key()] = [region.position.x, region.position.y, region.size.x, region.size.y]
	edited()

func generate_breathing_cycle() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var result: Dictionary = AnimationSynthesizer.generate_breathing(doc, doc.active_layer, str(doc.clip().name), 2.0)
	if not result.get("ok", false):
		notify(str(result.get("error", "Não foi possível gerar a respiração.")))
		return
	refresh_all()
	notify("Respiração criada em oito direções a partir da pose-base. Revise as poses e os intervalos; Undo reverte.")

func build_world() -> void:
	var page := column(tabs)
	page.name = "Mapa e prévia"
	var toolbar := HFlowContainer.new(); page.add_child(toolbar)
	choice(["Tile", "Terreno", "Colisão", "Luz", "Porta"], toolbar, func(i): world.cancel_gesture(); world.mode = ["Tile", "Terreno", "Colisão", "Luz", "Porta"][i])
	choice(["Lápis", "Balde", "Retângulo"], toolbar, func(i): world.cancel_gesture(); world.brush = ["Lápis", "Balde", "Retângulo"][i])
	button("Importar tileset", toolbar, func(): browse("tileset"))
	preview_toggle = check("Prévia jogável", toolbar, func(v):
		world.cancel_gesture(); world.set_preview(v); world.clock.reset(); world.grab_focus()
		if v and world.solid(world.player): world.reset_player()
	)
	button("Reiniciar posição", toolbar, func(): if not world.reset_player(): notify("Não há célula livre para a prévia."))
	button("Enquadrar mapa", toolbar, func(): world.fit_map())
	button("Checar caminhos", toolbar, func():
		var report: Dictionary = preload("res://core/navigation.gd").new().analyze(doc.map_data)
		notify("%d células livres • %d regiões • conectividade: %s" % [report.walkable, report.components.size(), "OK" if report.connected else "revisar obstáculos"])
	)
	var lighting := HFlowContainer.new(); page.add_child(lighting)
	label("Luz", lighting)
	var color := ColorPickerButton.new(); color.color = Color("ffcf8b"); lighting.add_child(color)
	color.color_changed.connect(func(value): world.light.color = value.to_html())
	label("Energia", lighting); var energy := spin(lighting, 0, 8, 1, func(value): world.light.energy = value); energy.step = 0.1
	label("Raio (tiles)", lighting); var radius := spin(lighting, 1, 16, 4, func(value): world.light.radius = value); radius.step = 0.5
	check("Sombras na exportação", lighting, func(value): world.light.shadows = value)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; page.add_child(split)
	world = WorldView.new()
	world.doc = doc
	world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world.edited.connect(func(): doc.mark_changed(); update_title())
	world.message.connect(notify)
	world.room_changed.connect(refresh_world_controls)
	split.add_child(world)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size = Vector2(320, 360); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(scroll)
	world_controls = preload("res://ui/world_controls.gd").new(); world_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(world_controls)
	world_controls.command.connect(world_command)
	label("Porta: escolha o modo e clique em dois tiles livres para conectá-los; na prévia, aproxime-se e pressione E. Botão direito cancela. Luz ilustrativa aqui; sombras reais na cena Godot exportada.", page, 12)

func refresh_world_controls() -> void:
	if world_controls != null: world_controls.display(doc.map_data, world.textures, world.tile, world.terrain)

func world_command(action: Dictionary) -> void:
	var map: Dictionary = doc.map_data
	var data = preload("res://core/world_data.gd")
	if action.kind != "select_room": world.cancel_gesture()
	match action.kind:
		"select_room":
			if int(action.index) == int(map.active_room): return
			doc.checkpoint("Trocar sala")
			data.switch_room(map, int(action.index))
			world.terrain = -1; world.fit_map(); world.reset_player()
		"add_room":
			if map.rooms.size() >= 32: notify("Limite de 32 salas por projeto."); return
			doc.checkpoint("Adicionar sala")
			data.create_room(map)
			world.terrain = -1; world.fit_map(); world.reset_player()
		"generate_village":
			if map.width < 16 or map.height < 12: notify("O layout de vilarejo precisa de pelo menos 16 × 12 células."); return
			if world.textures.size() < 3: notify("Importe um tileset com ao menos 3 tiles: solo, caminho e praça."); return
			doc.checkpoint("Gerar vilarejo")
			if not data.generate_village(map, int(action.seed), world.textures.size(), action.get("roles", {})): doc.undo(); notify("Seleção de papéis ou dimensões inválida; confira o tileset e tente novamente."); return
			world.fit_map(); world.reset_player(); notify("Layout de vilarejo gerado. Edite a arte e use Desfazer para restaurar a sala.")
		"camera_settings":
			var camera: Dictionary = action.settings
			if camera == map.camera_settings: return
			doc.checkpoint("Câmera do mapa")
			map.camera_settings = camera.duplicate(true)
			world.refresh_surface(); refresh_world_controls()
		"ambient_color":
			var ambient: String = str(action.value)
			if not Color.html_is_valid(ambient) or ambient == map.ambient_color: return
			doc.checkpoint("Luz ambiente")
			map.ambient_color = ambient
			world.refresh_surface(); refresh_world_controls()
		"rename_room":
			doc.checkpoint("Renomear sala")
			if not data.rename_room(map, int(map.active_room), str(action.value)): doc.undo(); notify("Nome de sala inválido."); return
		"remove_room":
			if map.rooms.size() <= 1: notify("O projeto precisa manter pelo menos uma sala."); return
			doc.checkpoint("Remover sala")
			data.remove_room(map, int(map.active_room))
			world.terrain = -1; world.fit_map(); world.reset_player()
		"door_name": world.door_name = str(action.value).strip_edges().left(80); notify("Próxima conexão: " + world.door_name); return
		"tile": world.tile = int(action.value); refresh_world_controls(); return
		"terrain": world.terrain = int(action.value); return
		"layer": map.active_layer = int(action.index); refresh_world_controls(); return
		"resize":
			if action.width == map.width and action.height == map.height: return
			if action.width < map.width or action.height < map.height:
				var popup := ConfirmationDialog.new(); popup.title = "Redimensionar mapa"; popup.dialog_text = "Tiles, colisões e luzes fora da nova área serão recortados. Desfazer restaura a área anterior."
				popup.confirmed.connect(func(): _resize_world(int(action.width), int(action.height)); popup.queue_free())
				popup.canceled.connect(popup.queue_free); add_child(popup); popup.popup_centered(Vector2i(520, 150)); return
			_resize_world(int(action.width), int(action.height)); return
		"add_layer":
			if map.layers.size() >= 7: notify("Limite de oito camadas de mapa."); return
			doc.checkpoint("Adicionar camada de mapa"); data.add_layer(map, "Camada " + str(map.layers.size() + 2))
		"remove_layer":
			if map.active_layer == 0: notify("A camada Solo é a base e não pode ser removida."); return
			doc.checkpoint("Remover camada de mapa"); data.remove_layer(map)
		"move_layer":
			var index := int(map.active_layer) - 1
			var target := index + int(action.offset)
			if index < 0 or target < 0 or target >= map.layers.size(): return
			doc.checkpoint("Reordenar mapa"); var previous = map.layers[index]; map.layers[index] = map.layers[target]; map.layers[target] = previous; map.active_layer = target + 1
		"rename", "visible", "locked", "opacity":
			doc.checkpoint("Propriedade da camada de mapa")
			var property: String = "name" if action.kind == "rename" else action.kind
			data.metadata(map)[property] = str(action.value).left(80) if property == "name" else action.value
		"add_terrain":
			if map.terrain_sets.size() >= 16 or int(action.start) + 16 > world.textures.size(): notify("O terreno precisa de 16 tiles consecutivos disponíveis; limite de 16 terrenos."); return
			doc.checkpoint("Criar terreno")
			map.terrain_sets.append({"name": str(action.name).left(80) if action.name != "" else "Terreno " + str(map.terrain_sets.size() + 1), "tiles": range(int(action.start), int(action.start) + 16)})
			world.terrain = map.terrain_sets.size() - 1
		"remove_door":
			if int(action.index) < 0 or int(action.index) >= map.doors.size(): notify("Selecione uma conexão para remover."); return
			doc.checkpoint("Remover conexão de porta")
			data.remove_door(map, int(action.index))
		"remove_connection":
			if int(action.index) < 0 or int(action.index) >= map.connections.size(): notify("Selecione uma ligação entre salas para remover."); return
			doc.checkpoint("Remover ligação entre salas")
			data.remove_connection(map, int(action.index))
	world.refresh_surface(); refresh_world_controls(); update_title()

func _resize_world(width: int, height: int) -> void:
	doc.checkpoint("Redimensionar mapa")
	preload("res://core/world_data.gd").resize(doc.map_data, width, height)
	world.fit_map(); world.reset_player(); refresh_world_controls(); update_title()

func build_art() -> void:
	var page := column(tabs)
	page.name = "Art Bible e memória"
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	var left := column(split)
	left.custom_minimum_size.x = 480
	label("ART BIBLE", left, 20)
	bible = TextEdit.new()
	bible.custom_minimum_size.y = 180
	bible.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	bible.focus_entered.connect(func(): if not doc.art.locked: doc.checkpoint())
	bible.text_changed.connect(func():
		if not syncing and not doc.art.locked:
			doc.art.bible = bible.text
			doc.manifest.art_bible_version += 1
			doc.mark_changed()
	)
	left.add_child(bible)
	art_lock = check("Art Lock — congelar diretrizes, referências e aprovação", left, func(v):
		if syncing: return
		doc.checkpoint(); doc.art.locked = v; bible.editable = not v; update_title()
	)
	label("REFERÊNCIAS • arquivos locais + procedência", left)
	var actions := row(left)
	button("Importar referência", actions, func():
		if doc.art.locked: notify("Desbloqueie o Art Lock para alterar referências."); return
		browse("reference")
	)
	button("Arquivar", actions, func():
		if doc.art.locked or reference_list.get_selected_items().is_empty(): return
		references.transition(doc, reference_list.get_selected_items()[0], "archived"); refresh_art()
	)
	reference_list = ItemList.new()
	reference_list.custom_minimum_size.y = 180
	reference_list.item_selected.connect(show_reference)
	left.add_child(reference_list)
	label("Procedência / licença (Enter para registrar)", left)
	var provenance := LineEdit.new()
	provenance.placeholder_text = "Autor, origem e permissão de uso"
	provenance.text_submitted.connect(func(value):
		if doc.art.locked or reference_list.get_selected_items().is_empty(): return
		doc.checkpoint(); doc.art.references[reference_list.get_selected_items()[0]].provenance = value; refresh_art()
	)
	left.add_child(provenance)
	var reference_controls := row(left)
	ref_state = choice(References.STATES, reference_controls, func(_i): pass)
	ref_feature = choice(["palette", "lighting", "anatomy", "materials"], reference_controls, func(_i): pass)
	button("Aplicar estado", reference_controls, func():
		if reference_list.get_selected_items().is_empty(): return
		var impacted: Array = references.transition(doc, reference_list.get_selected_items()[0], ref_state.get_item_text(ref_state.selected), ref_feature.get_item_text(ref_feature.selected))
		refresh_art(); update_title(); notify("Estado registrado; %d dependentes sinalizados quando houver rejeição." % impacted.size())
	)
	ref_license = LineEdit.new()
	ref_license.placeholder_text = "Licença (Enter para registrar)"
	ref_license.text_submitted.connect(func(value):
		if doc.art.locked or reference_list.get_selected_items().is_empty(): return
		doc.checkpoint(); doc.art.references[reference_list.get_selected_items()[0]].license = value; update_title()
	)
	left.add_child(ref_license)
	button("Vincular referência aprovada ao recurso", left, func():
		if reference_list.get_selected_items().is_empty(): return
		notify("Vínculo registrado." if references.link(doc, reference_list.get_selected_items()[0]) else "A referência precisa estar aprovada, ao menos parcialmente.")
	)
	var right := column(split)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reference_preview = TextureRect.new()
	reference_preview.custom_minimum_size = Vector2(320, 230)
	reference_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reference_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(reference_preview)
	label("HYPERLEARN • memória de regras", right, 20)
	label("Extrai paleta; testa integridade; aguarda aprovação explícita.", right)
	var memory_actions := row(right)
	button("Propor regra", memory_actions, func():
		if doc.art.locked: notify("Art Lock ativo."); return
		var proposal: Dictionary = memory.propose(doc)
		doc.art.candidates.append(proposal)
		doc.dirty = true
		refresh_art()
	)
	button("Aprovar selecionada", memory_actions, func():
		if candidate_list.get_selected_items().is_empty(): return
		var ok: bool = memory.approve(doc, candidate_list.get_selected_items()[0])
		notify("Regra aprovada e paleta aplicada." if ok else "Aprovação recusada: bloqueio, teste falhou ou proposta desatualizada.")
		refresh_all()
	)
	button("Rejeitar", memory_actions, func():
		if doc.art.locked or candidate_list.get_selected_items().is_empty(): return
		doc.checkpoint(); doc.art.candidates[candidate_list.get_selected_items()[0]].status = "rejected"; refresh_art()
	)
	candidate_list = ItemList.new()
	candidate_list.custom_minimum_size.y = 200
	right.add_child(candidate_list)
	label("Não treina modelos. Aprovações alteram apenas a paleta do documento.", right, 12)

func build_batch() -> void:
	var page := column(tabs)
	page.name = "Lotes"
	label("FILA DE EXPORTAÇÃO", page, 22)
	label("Processo auxiliar isolado • prioridades • cancelamento por etapa • checkpoints automáticos", page)
	var input_row := row(page)
	batch_input = LineEdit.new()
	batch_input.placeholder_text = "Projeto de entrada"
	batch_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(batch_input)
	button("Escolher projeto", input_row, func(): browse("batch_input"))
	var output_row := row(page)
	batch_output = LineEdit.new()
	batch_output.placeholder_text = "Pasta de saída exclusiva desta tarefa"
	batch_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(batch_output)
	button("Escolher pasta", output_row, func(): browse("batch_output"))
	var actions := row(page)
	button("Adicionar", actions, func():
		if not FileAccess.file_exists(batch_input.text) or batch_output.text.is_empty(): notify("Escolha entrada existente e pasta de saída."); return
		queue.enqueue(batch_input.text, batch_output.text, int(priority_control.value))
	)
	button("Executar / retomar", actions, func(): queue.running = true)
	button("Pausar", actions, func(): queue.running = false; queue.persist())
	label("Prioridade", actions)
	priority_control = spin(actions, 0, 100, 0, func(_v): pass)
	button("Cancelar selecionada", actions, func():
		if not batch_list.get_selected_items().is_empty(): queue.cancel(queue.jobs[batch_list.get_selected_items()[0]].id)
	)
	button("Abrir importação", actions, func():
		if batch_list.get_selected_items().is_empty(): return
		var job: Dictionary = queue.jobs[batch_list.get_selected_items()[0]]
		if str(job.get("project_path", "")).is_empty(): notify("Esta tarefa não contém projeto importado."); return
		selected_open(job.project_path)
	)
	button("Ver relatório técnico", actions, func():
		if batch_list.get_selected_items().is_empty(): notify("Selecione uma tarefa em Lotes."); return
		var job: Dictionary = queue.jobs[batch_list.get_selected_items()[0]]
		var validation: Variant = job.get("validation", {})
		if validation is Dictionary and not validation.is_empty():
			_show_technical_report(validation, "Validação da exportação")
			return
		var report_path := str(job.get("report_path", ""))
		if report_path.is_empty(): notify("Esta tarefa ainda não gerou um relatório técnico."); return
		var report = Storage.read_json(report_path)
		if not report is Dictionary: notify("Relatório ainda não existe ou é inválido."); return
		_show_technical_report(report, "Relatório técnico da tarefa")
	)
	button("Repetir falhas", actions, func():
		queue.retry_failed()
	)
	button("Limpar concluídos", actions, func():
		queue.jobs = queue.jobs.filter(func(job): return job.status not in ["done", "cached"])
		queue.persist()
	)
	batch_list = ItemList.new()
	batch_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(batch_list)
	var planning := row(page)
	var request := LineEdit.new()
	request.placeholder_text = "Objetivo de produção (plano determinístico de dependências)"
	request.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	planning.add_child(request)
	button("Inspecionar plano", planning, func():
		var plan: Dictionary = Plan.new().plan(request.text, not quality.versions(doc).is_empty())
		var lines: String = "Rota: " + plan.route + "\n"
		for task in plan.tasks: lines += task.id + " [" + task.skill + "] ← " + str(task.dependencies) + "\n"
		var popup := AcceptDialog.new(); popup.title = "Plano proposto — não executa geração"; popup.dialog_text = lines; add_child(popup); popup.popup_centered(Vector2i(560, 320)); popup.confirmed.connect(popup.queue_free)
	)
	label("Cache SHA-256 inclui entrada e integridade de todas as saídas. Arquivos alterados são reconstruídos.", page)

func build_automation() -> void:
	automation_panel = preload("res://ui/automation_panel.gd").new()
	tabs.add_child(automation_panel)
	automation_panel.configuration_requested.connect(func(values):
		if automation.configure(values):
			queue.resume_on_start = automation.config.resume and automation.config.enabled
			queue.running = true; queue.persist()
			notify("Automação iniciada. Projetos estáveis serão processados em cópias.")
		else: notify(automation.error)
	)
	automation_panel.pause_requested.connect(func():
		automation.pause()
		queue.running = false; queue.resume_on_start = false; queue.persist()
	)
	automation_panel.scan_requested.connect(func(): automation.scan_now())
	automation_panel.clear_requested.connect(func(): automation.clear_finished())
	automation_panel.candidate_requested.connect(func(file): selected_open(file, true))
	automation_panel.report_requested.connect(func(file):
		var report = Storage.read_json(file)
		if not report is Dictionary: notify("Relatório ainda não existe ou é inválido."); return
		_show_technical_report(report, "Relatório técnico — sem aprovação artística")
	)

func refresh_automation() -> void:
	if automation_panel != null: automation_panel.display(automation.config, automation.ledger, automation.error)

func build_help() -> void:
	var page := column(tabs)
	page.name = "Guia e limites"
	var text := RichTextLabel.new()
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.bbcode_enabled = true
	text.text = FileAccess.get_file_as_string("res://GUIDE.txt")
	page.add_child(text)
	button("Abrir recuperação antiga (0.3)", page, func(): selected_open("user://autosave.sfs.json", true))
	button("Abrir pasta de dados", page, func(): OS.shell_open(ProjectSettings.globalize_path("user://")))

func refresh_all() -> void:
	canvas.doc = doc
	world.doc = doc
	canvas.refresh()
	world.anim_frame = mini(world.anim_frame, doc.frames - 1)
	if tabs.current_tab == 1: world.refresh(); refresh_world_controls()
	layers_list.clear()
	for l in doc.layers: layers_list.add_item(("● " if l.visible else "○ ") + l.name + (" [lock]" if l.locked else "") + (" [efeito]" if l.get("effect") is Dictionary else ""))
	layers_list.select(doc.active_layer)
	refresh_layer()
	for child in palette_box.get_children(): child.free()
	var ramp_names_by_color := {}
	for ramp in doc.art.get("material_ramps", []):
		if not ramp is Dictionary: continue
		var ramp_colors: Variant = ramp.get("colors", [])
		if not ramp_colors is Array: continue
		for ramp_color in ramp_colors:
			var canonical_ramp_color := "#" + Color(str(ramp_color)).to_html(false).to_lower()
			var names: Array = ramp_names_by_color.get(canonical_ramp_color, [])
			names.append(str(ramp.get("name", "Material")))
			ramp_names_by_color[canonical_ramp_color] = names
	for hex in doc.palette:
		var b := button(" ", palette_box, func(): color_picker.color = Color(hex); canvas.color = Color(hex))
		b.custom_minimum_size = Vector2(30, 25)
		var swatch := StyleBoxFlat.new()
		swatch.bg_color = Color(hex)
		swatch.set_corner_radius_all(4)
		swatch.set_border_width_all(1)
		swatch.border_color = Color("8998ac")
		b.add_theme_stylebox_override("normal", swatch)
		b.add_theme_stylebox_override("hover", swatch)
		var canonical_color := "#" + Color(str(hex)).to_html(false).to_lower()
		b.tooltip_text = str(hex) + ("\nRampa: " + ", ".join(ramp_names_by_color[canonical_color]) if ramp_names_by_color.has(canonical_color) else "")
	button("+ cor", palette_box, func():
		if doc.art.locked: notify("Art Lock ativo."); return
		if doc.palette.size() < 32: doc.checkpoint(); doc.palette.append("#" + color_picker.color.to_html(false)); refresh_all()
	)
	if timeline_view != null: timeline_view.refresh()
	refresh_frame_highlight()
	direction_picker.select(doc.direction)
	fps_control.set_value_no_signal(doc.fps)
	syncing = true
	clip_picker.clear()
	for c in doc.animation.clips: clip_picker.add_item(c.name)
	clip_picker.select(int(doc.animation.active))
	duration_control.set_value_no_signal(round(doc.frame_seconds() * 1000))
	loop_control.set_pressed_no_signal(doc.clip().loop)
	syncing = false
	refresh_art()
	if tabs.current_tab == 4: refresh_quality()
	refresh_hyperlearn()
	update_title()

func refresh_frame_highlight() -> void:
	if layer_mask_status != null: layer_mask_status.text = "Máscara da cel: %d pixels ocultos" % doc.layers[doc.active_layer].get("visibility_masks", {}).get(doc.cel_key(), []).size()
	if timeline_view != null: timeline_view.update_selection()
	if duration_control != null: duration_control.set_value_no_signal(round(doc.frame_seconds() * 1000))
	if pixel_preview != null: pixel_preview.texture = ImageTexture.create_from_image(doc.composite())
	if depth_control != null:
		depth_control.set_value_no_signal(doc.rig.depth.get(doc.cel_key(), {}).get(doc.layers[doc.active_layer].id, doc.active_layer))
		var layer: Dictionary = doc.layers[doc.active_layer]
		var local: Array = doc.rig.get("offsets", {}).get(doc.cel_key(), {}).get(layer.id, layer.offset)
		offset_x.set_value_no_signal(local[0])
		offset_y.set_value_no_signal(local[1])

func refresh_layer() -> void:
	if layer_mask_status != null: layer_mask_status.text = "Máscara da cel: %d pixels ocultos" % doc.layers[doc.active_layer].get("visibility_masks", {}).get(doc.cel_key(), []).size()
	syncing = true
	rotation_dragging = false
	var l: Dictionary = doc.layers[doc.active_layer]
	layer_name.text = l.name
	layer_retarget_key.text = str(l.get("retarget_key", str(l.get("name", "")).to_lower()))
	visibility.button_pressed = l.visible
	locked.button_pressed = l.locked
	opacity.value = l.opacity
	equipment.button_pressed = l.equipment
	anchor_names = doc.anchors.keys()
	anchor_names.sort()
	if anchor_names.is_empty(): anchor_names = ["feet"]
	for attachment_anchor in ["shield_mount", "weapon_mount"]:
		if not anchor_names.has(attachment_anchor): anchor_names.append(attachment_anchor)
	anchor_picker.clear()
	joint_picker.clear()
	pivot_picker.clear()
	bone_picker.clear()
	bone_picker.add_item("Sem segmento")
	var selected_bone := 0
	for name in anchor_names:
		anchor_picker.add_item(name)
		joint_picker.add_item(name)
		pivot_picker.add_item(name)
	for index in doc.rig.get("skeleton", []).size():
		var segment: Array = doc.rig.skeleton[index]
		bone_picker.add_item("%s → %s" % [str(segment[0]), str(segment[1])])
		if l.get("bone", []) == segment: selected_bone = index + 1
	bone_picker.select(selected_bone)
	anchor_picker.select(maxi(0, anchor_names.find(l.anchor)))
	var selected_joint := anchor_names.find(canvas.anchor_name)
	if selected_joint < 0: selected_joint = anchor_names.find("hand")
	joint_picker.select(maxi(0, selected_joint))
	canvas.anchor_name = anchor_names[maxi(0, selected_joint)]
	var selected_pivot := anchor_names.find(str(l.get("pivot", l.get("anchor", "feet"))))
	pivot_picker.select(maxi(0, selected_pivot))
	rotation_control.set_value_no_signal(doc.layer_rotation(l.id))
	rotation_label.text = "%d°" % roundi(doc.layer_rotation(l.id))
	var local: Array = doc.rig.get("offsets", {}).get(doc.cel_key(), {}).get(l.id, l.offset)
	offset_x.value = local[0]
	offset_y.value = local[1]
	family_picker.select(maxi(0, FAMILIES.find(doc.rig.family)))
	asymmetric_control.set_pressed_no_signal(l.get("asymmetric", false))
	depth_control.set_value_no_signal(doc.rig.depth.get(doc.cel_key(), {}).get(l.id, doc.active_layer))
	syncing = false

func refresh_art() -> void:
	syncing = true
	bible.text = doc.art.bible
	bible.editable = not doc.art.locked
	art_lock.button_pressed = doc.art.locked
	reference_list.clear()
	for i in doc.art.references.size():
		var ref: Dictionary = references.normalize(doc.art.references[i])
		doc.art.references[i] = ref
		reference_list.add_item("[" + ref.state + "] " + ref.name + " • " + ref.provenance)
	candidate_list.clear()
	for candidate in doc.art.candidates:
		candidate_list.add_item(str(candidate.get("status", "?")) + " | teste: " + str(candidate.get("test", "?")) + " | " + str(candidate.get("palette", []).size()) + " cores")
	syncing = false

func refresh_batch() -> void:
	if batch_list == null: return
	batch_list.clear()
	for job in queue.jobs: batch_list.add_item("[" + job.status + " %d%%] P%d " % [int(job.progress), int(job.priority)] + job.input.get_file() + " → " + job.output + (" • " + job.error if job.error != "" else ""))
	if queue.last_error != "": notify(queue.last_error)

func show_reference(index: int) -> void:
	var ref: Dictionary = doc.art.references[index]
	ref_state.select(maxi(0, References.STATES.find(ref.get("state", "imported"))))
	ref_license.text = ref.get("license", "não informada")
	var image := Image.new()
	if ref.has("thumbnail") and image.load_png_from_buffer(Marshalls.base64_to_raw(ref.thumbnail)) == OK:
		reference_preview.texture = ImageTexture.create_from_image(image)

func set_layer(key: String, value: Variant) -> void:
	if syncing: return
	doc.checkpoint()
	doc.layers[doc.active_layer][key] = value
	var layer: Dictionary = doc.layers[doc.active_layer]
	layers_list.set_item_text(doc.active_layer, ("● " if layer.visible else "○ ") + layer.name + (" [lock]" if layer.locked else ""))
	canvas.refresh()
	update_title()

func change_offset(axis: int, value: int) -> void:
	if syncing: return
	doc.checkpoint()
	if not doc.rig.has("offsets"): doc.rig.offsets = {}
	if not doc.rig.offsets.has(doc.cel_key()): doc.rig.offsets[doc.cel_key()] = {}
	var layer: Dictionary = doc.layers[doc.active_layer]
	var local: Array = doc.rig.offsets[doc.cel_key()].get(layer.id, layer.offset.duplicate())
	local[axis] = value
	doc.rig.offsets[doc.cel_key()][layer.id] = local
	edited()

func move_layer(delta: int) -> void:
	var target: int = doc.active_layer + delta
	if target < 0 or target >= doc.layers.size(): return
	doc.checkpoint()
	var l = doc.layers.pop_at(doc.active_layer)
	doc.layers.insert(target, l)
	doc.active_layer = target
	refresh_all()

func edited() -> void:
	doc.mark_changed()
	canvas.refresh()
	if timeline_view != null: timeline_view.update_frame(doc.frame)
	if pixel_preview != null: pixel_preview.texture = ImageTexture.create_from_image(doc.composite())
	update_title()

func update_title() -> void:
	title_label.text = (path.get_file() if path != "" else "Sem título") + (" • alterações pendentes" if doc.dirty else (" • salvo" if path != "" else " • sem alterações")) + "   /   %d × %d • %d frames" % [doc.width, doc.height, doc.frames]
	_refresh_document_tabs()
	if workspace != null: workspace.refresh_budgets()

func notify(message: String) -> void:
	status.text = message

func _show_technical_report(report: Dictionary, title: String) -> void:
	var popup := AcceptDialog.new()
	popup.title = title
	var text := TextEdit.new()
	text.editable = false
	text.custom_minimum_size = Vector2(760, 460)
	text.text = JSON.stringify(report, "  ")
	popup.add_child(text)
	add_child(popup)
	popup.popup_centered()
	popup.confirmed.connect(popup.queue_free)

func undo() -> void:
	stop_playback()
	canvas.cancel_gesture()
	world.cancel_gesture()
	if doc.undo():
		_three_d_pose_document = null
		_load_3d_motion_pose()
		refresh_all()
		notify("Alteração desfeita.")

func redo() -> void:
	stop_playback()
	canvas.cancel_gesture()
	world.cancel_gesture()
	if doc.redo():
		_three_d_pose_document = null
		_load_3d_motion_pose()
		refresh_all()
		notify("Alteração refeita.")

func step_frame(delta: int) -> void:
	stop_playback()
	canvas.cancel_gesture()
	var sequence: Array = doc.clip().frames
	doc.frame = int(sequence[posmod(sequence.find(doc.frame) + delta, sequence.size())])
	canvas.refresh()
	refresh_frame_highlight()

func copy_direction() -> void:
	var target: int = (doc.direction + 1) % 8
	var projected_masks: int = doc.layer_mask_pixels()
	for l in doc.layers:
		if l.locked: continue
		for f in doc.frames: projected_masks += l.get("visibility_masks", {}).get(doc.cel_key(doc.direction, f), []).size() - l.get("visibility_masks", {}).get(doc.cel_key(target, f), []).size()
	if projected_masks > Document.MAX_LAYER_MASK_PIXELS: notify("A cópia excederia o limite de memória das máscaras."); return
	doc.checkpoint()
	for l in doc.layers:
		if l.locked: continue
		for f in doc.frames:
			l.cels[target][f] = l.cels[doc.direction][f].duplicate()
			if l.has("visibility_masks"):
				l.visibility_masks.erase(doc.cel_key(target, f))
				var mask: Array = l.visibility_masks.get(doc.cel_key(doc.direction, f), [])
				if not mask.is_empty(): l.visibility_masks[doc.cel_key(target, f)] = mask.duplicate()
	notify("Direção copiada para " + Document.DIRECTIONS[target] + ". Revise a orientação manualmente.")

func edit_layer_visibility_mask(mode: String) -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.edit_layer_mask(mode): refresh_all()
	else: notify("Sem alteração: selecione uma região local sem rotação/deslocamento ativo, libere a camada e o Art Lock e respeite o limite de máscara. Pixels protegidos permanecem preservados.")

func protect(action: Callable) -> void:
	if doc.dirty:
		pending_action = action
		confirm.popup_centered()
	else: action.call()

func new_document() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var popup := ConfirmationDialog.new()
	popup.name = "NewDocumentDialog"
	popup.title = "Novo documento"
	var controls := column(popup)
	var help := label("Crie uma tela transparente para desenhar do zero. Dimensão máxima: 512 px por lado; memória total da tela e animação: 64 MiB.", controls)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 520
	var dimensions := row(controls)
	label("Largura", dimensions)
	var width_input := spin(dimensions, 8, 512, 32, func(_v): pass)
	width_input.name = "CanvasWidth"
	width_input.custom_minimum_size.x = 105
	label("Altura", dimensions)
	var height_input := spin(dimensions, 8, 512, 32, func(_v): pass)
	height_input.name = "CanvasHeight"
	height_input.custom_minimum_size.x = 105
	var animation_settings := row(controls)
	label("Quadros", animation_settings)
	var frame_input := spin(animation_settings, 1, 32, 4, func(_v): pass)
	frame_input.name = "FrameCount"
	frame_input.custom_minimum_size.x = 105
	label("FPS", animation_settings)
	var fps_input := spin(animation_settings, 1, 60, 8, func(_v): pass)
	fps_input.name = "FrameRate"
	fps_input.custom_minimum_size.x = 105
	popup.confirmed.connect(func():
		create_blank_document(int(width_input.value), int(height_input.value), int(frame_input.value), int(fps_input.value))
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(620, 300))

func create_blank_document(canvas_width: int, canvas_height: int, frame_count: int, frame_rate: int) -> String:
	var created = Document.new()
	if not created.initialize_blank(canvas_width, canvas_height, frame_count, frame_rate):
		notify("Configuração inválida ou acima do limite de 64 MiB. Reduza a tela ou a quantidade de quadros.")
		return ""
	var new_id: String = workspace.add_document(created)
	if new_id.is_empty():
		notify(workspace.error)
		return ""
	refresh_all()
	update_title()
	return new_id

func browse(action: String) -> void:
	if action in ["import", "spritesheet", "png_sequence", "export", "tileset", "retarget_source"]: stop_playback(); canvas.cancel_gesture()
	dialog_action = action
	dialog.filters = PackedStringArray()
	if action in ["export", "batch_output"]:
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	elif action == "save":
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.filters = PackedStringArray(["*.sfs.json ; Sprite Forge"])
		var record: Dictionary = workspace.find(_save_target_id)
		var title: String = str(record.get("title", "personagem"))
		dialog.current_file = title if title.ends_with(".sfs.json") else title + ".sfs.json"
	elif action == "ai_save":
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.filters = PackedStringArray(["*.png ; PNG"])
		dialog.current_file = "sprite-forge-gerado.png"
	else:
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray(["*.png ; PNG"]) if action in ["import", "spritesheet", "reference", "tileset"] else PackedStringArray(["*.json ; Sprite Forge JSON"])
	dialog.title = {"open": "Abrir projeto", "save": "Salvar projeto", "export": "Exportar pacote (subpasta com data)", "import": "Importar PNG na cel", "spritesheet": "Importar spritesheet PNG", "reference": "Importar referência PNG", "retarget_source": "Projeto de origem para retarget", "batch_input": "Projeto para lote", "batch_output": "Pasta da tarefa", "ai_save": "Salvar imagem gerada"}.get(action, action)
	dialog.popup_centered()
	if action == "png_sequence": dialog.title = "Importar sequence.json como projeto candidato"

func import_png_sequence(file_path: String, allow_modified: bool = false, expected_snapshot: Dictionary = {}) -> void:
	var result: Dictionary = preload("res://core/png_sequence_importer.gd").new().load_sequence(file_path, allow_modified, expected_snapshot)
	if result.get("requires_confirmation", false):
		var popup := ConfirmationDialog.new()
		popup.name = "ModifiedSequenceConfirmation"
		popup.title = "Importar PNGs modificados?"
		popup.dialog_text = "%d quadro(s) diferem dos hashes da exportação. Importar essas imagens como uma nova candidata? O projeto anterior será preservado e as alterações ficarão registradas para revisão." % result.changed_frames.size()
		popup.confirmed.connect(func(): import_png_sequence(file_path, true, result.snapshot); popup.queue_free())
		popup.canceled.connect(popup.queue_free)
		add_child(popup)
		popup.popup_centered(Vector2i(620, 220))
		return
	if not result.get("ok", false): notify(str(result.get("error", "Importação da sequência recusada."))); return
	if workspace.add_document(result.document).is_empty(): notify(workspace.error); return
	refresh_all()
	notify("Sequência importada como nova candidata composta; clips e timing preservados. Revise a arte antes de aprovar.")

func save_project() -> void:
	_save_target_id = workspace.active_id
	var target: String = workspace.destination(_save_target_id)
	if target == "" or target.begins_with("res://"): browse("save")
	elif workspace.request_save(_save_target_id, target): notify("Salvando em segundo plano…")
	else: notify(workspace.error)

func selected_open(file_path: String, as_copy: bool = false) -> void:
	var loaded = store.load_document(file_path)
	if loaded == null: notify(store.error); return
	if file_path == "user://autosave.sfs.json" or workspace.canonical(file_path).begins_with(workspace.canonical(quality.root) + "/"): as_copy = true
	if as_copy: loaded.dirty = true
	if workspace.add_document(loaded, "" if as_copy else file_path) == "": notify(workspace.error)
	else: notify("Projeto aberto em aba própria.")

func open_animation_demo() -> void:
	stop_playback()
	canvas.cancel_gesture()
	selected_open(DEMO_SAMPLE_PATH, true)

func open_approved_demo() -> void:
	stop_playback()
	canvas.cancel_gesture()
	selected_open(APPROVED_SAMPLE_PATH, true)

func open_scale_study() -> void:
	stop_playback()
	canvas.cancel_gesture()
	selected_open(SCALE_STUDY_PATH, true)

func selected_path(file_path: String) -> void:
	match dialog_action:
		"open": selected_open(file_path)
		"retarget_source": open_inter_document_retarget_dialog(file_path)
		"save":
			var target := file_path if file_path.ends_with(".sfs.json") else file_path + ".sfs.json"
			if workspace.request_save(_save_target_id, target): notify("Salvando em segundo plano…")
			else: notify(workspace.error); _save_all_ids.clear(); _quit_after_save = false; _pending_close_id = ""
		"export":
			var folder := file_path.path_join("SFS_" + Time.get_datetime_string_from_system().replace(":", "-") + "_" + str(Time.get_ticks_msec()))
			var requests := "user://export_requests"
			DirAccess.make_dir_recursive_absolute(requests)
			var snapshot_path := ProjectSettings.globalize_path(requests.path_join(doc.manifest.id + "_" + str(Time.get_ticks_usec()) + ".sfs.json"))
			_export_targets[snapshot_path] = {"folder": folder, "profile": _selected_export_profile}
			if workspace.request_export_snapshot(workspace.active_id, snapshot_path): notify("Preparando exportação em segundo plano…")
			else: _export_targets.erase(snapshot_path); notify(workspace.error)
		"import", "reference": import_png(file_path, dialog_action == "reference")
		"spritesheet": open_spritesheet_import_dialog(file_path)
		"png_sequence": import_png_sequence(file_path)
		"tileset":
			var image := Image.load_from_file(file_path)
			if image == null or image.get_width() > 256 or image.get_height() > 256 or image.get_width() % 16 != 0 or image.get_height() % 16 != 0:
				notify("Use PNG até 256×256, com dimensões múltiplas de 16."); return
			doc.checkpoint()
			doc.map_data.tileset_png = Marshalls.raw_to_base64(image.save_png_to_buffer())
			doc.map_data.terrain_sets.clear()
			for data in preload("res://core/world_data.gd").layers(doc.map_data): data.cells.fill(-1); data.terrain.fill(-1)
			world.tile = 0
			world.refresh()
			world.terrain = -1; refresh_world_controls()
			update_title()
		"batch_input": batch_input.text = file_path
		"batch_output": batch_output.text = file_path
		"arton_library": load_art_library(file_path)
		"ai_save":
			var target := file_path if file_path.to_lower().ends_with(".png") else file_path + ".png"
			var bytes := FileAccess.get_file_as_bytes(ai_last_output_path)
			var output := FileAccess.open(target, FileAccess.WRITE)
			if bytes.is_empty() or output == null:
				notify("Não foi possível salvar a imagem PNG.")
			else:
				output.store_buffer(bytes)
				output.close()
				notify("Imagem PNG salva.")

func import_png(file_path: String, reference: bool) -> void:
	var original := FileAccess.get_file_as_bytes(file_path)
	if original.size() > 16777216: notify("PNG excede 16 MiB."); return
	var image := Image.new()
	if image.load(file_path) != OK: notify("PNG inválido."); return
	if image.get_width() > 4096 or image.get_height() > 4096: notify("Imagem excede 4096 px."); return
	image.convert(Image.FORMAT_RGBA8)
	if reference:
		if doc.art.locked or doc.art.references.size() >= 64: notify("Art Lock ativo ou limite de 64 referências."); return
		var hash := FileAccess.get_sha256(file_path)
		var original_encoded := Marshalls.raw_to_base64(original)
		var total: int = original_encoded.length()
		for ref in doc.art.references:
			if ref.sha256 == hash: notify("Referência idêntica já está na biblioteca."); return
			total += str(ref.get("original_png", "")).length()
		if total > 16777216: notify("Orçamento de 16 MiB de referências incorporadas excedido."); return
		doc.checkpoint()
		var dimensions := [image.get_width(), image.get_height()]
		var ratio: float = minf(1.0, 256.0 / maxi(image.get_width(), image.get_height()))
		image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)), Image.INTERPOLATE_NEAREST)
		doc.art.references.append(references.normalize({"name": file_path.get_file(), "path": file_path, "sha256": hash, "dimensions": dimensions, "original_png": original_encoded, "provenance": "não informada", "thumbnail": Marshalls.raw_to_base64(image.save_png_to_buffer())}))
		refresh_art()
	else:
		if doc.layers[doc.active_layer].locked: notify("Camada bloqueada."); return
		if image.get_size() != Vector2i(doc.width, doc.height): notify("A imagem deve ter exatamente %d × %d px. Nenhum redimensionamento foi aplicado." % [doc.width, doc.height]); return
		doc.checkpoint()
		for y in doc.height:
			for x in doc.width:
				if doc.allowed(Vector2i(x, y)): doc.current().set_pixel(x, y, image.get_pixel(x, y))
		edited()
	update_title()

func open_spritesheet_import_dialog(file_path: String, source_id: String = "") -> void:
	if doc.art.get("locked", false): notify("Art Lock ativo."); return
	if doc.layers[doc.active_layer].locked: notify("A camada ativa está bloqueada."); return
	var image := Image.load_from_file(file_path)
	if image == null or image.is_empty(): notify("Spritesheet PNG inválido."); return
	if image.get_width() > 4096 or image.get_height() > 4096 or image.get_data().size() > 67108864:
		notify("Spritesheet excede 4096 px por lado ou 64 MiB descompactados."); return
	image.convert(Image.FORMAT_RGBA8)
	var target_doc = doc
	var target_layer: int = doc.active_layer
	var target_direction: int = doc.direction
	var max_columns: int = mini(32, maxi(1, image.get_width() / doc.width))
	var popup := ConfirmationDialog.new()
	popup.title = "Importar spritesheet ou atlas por grade"
	popup.dialog_text = "%d × %d px • importe uma faixa, quatro linhas cardinais LPC ou oito direções." % [image.get_width(), image.get_height()]
	var fields := column(popup)
	label("Layout", fields)
	var mode := choice(["Uma faixa → direção atual", "Oito linhas → N, NE, E, SE, S, SW, W, NW", "Quatro linhas LPC → N, W, S, E"], fields, func(_i): pass)
	var mode_info := Label.new()
	mode_info.name = "lpc_mode_info"
	mode_info.text = "LPC requer cels e documento de 64×64 px. Importa N/W/S/E e mantém diagonais vazias."
	mode_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_info.visible = false
	fields.add_child(mode_info)
	label("Células a importar (colunas)", fields)
	var suggested_columns := mini(max_columns, 6 if max_columns >= 6 else max_columns)
	var count := spin(fields, 1, max_columns, suggested_columns, func(_v): pass)
	count.name = "columns"
	label("Linhas existentes no atlas", fields)
	var suggested_rows := clampi(roundi(float(image.get_height()) / maxf(1.0, float(image.get_width()) / suggested_columns)), 1, 8)
	var source_rows := spin(fields, 1, 8, suggested_rows, func(_v): pass)
	source_rows.name = "source_rows"
	label("Linha do atlas a importar (começa em 1)", fields)
	var source_row := spin(fields, 1, 8, 1, func(_v): pass)
	source_row.name = "source_row"
	var fit_grid := check("Ajustar atlas inteiro para colunas × linhas do canvas", fields, func(_v): pass)
	fit_grid.button_pressed = absf(float(image.get_width()) / image.get_height() - float(suggested_columns) / suggested_rows) < 0.03
	fit_grid.tooltip_text = "Redimensiona a folha toda. Use quando a imagem não tiver margem nem espaçamento entre células."
	var isolate := check("Separar figuras que atravessam a grade (fundo transparente)", fields, func(_v): pass)
	isolate.name = "isolate_silhouettes"
	isolate.tooltip_text = "Isola cada figura antes de cortar. Para oito direções use uma folha transparente com oito linhas na ordem N, NE, E, SE, S, SW, W, NW. Recusa figuras encostadas/ambíguas."
	label("Área mínima da silhueta na origem (pixels)", fields)
	var component_area := spin(fields, 1, 8192, 100, func(_v): pass)
	component_area.name = "component_area"
	label("Escala do conteúdo dentro do canvas (%)", fields)
	var content_scale := spin(fields, 10, 100, 100, func(_v): pass)
	content_scale.name = "content_scale"
	content_scale.step = 5
	label("Alinhamento do conteúdo", fields)
	var alignment := choice(["Centro", "Pés no rodapé", "Canto superior esquerdo"], fields, func(_i): pass)
	alignment.name = "content_alignment"
	label("Inserir a partir do frame", fields)
	var first_frame := spin(fields, 1, doc.frames, 1, func(_v): pass)
	first_frame.name = "start_frame"
	label("Margens X / Y", fields)
	var margin_row := row(fields)
	var margin_x := spin(margin_row, 0, 4096, 0, func(_v): pass)
	var margin_y := spin(margin_row, 0, 4096, 0, func(_v): pass)
	label("Espaçamento X / Y", fields)
	var spacing_row := row(fields)
	var spacing_x := spin(spacing_row, 0, 4096, 0, func(_v): pass)
	var spacing_y := spin(spacing_row, 0, 4096, 0, func(_v): pass)
	mode.item_selected.connect(func(index: int):
		var lpc_mode := index == 2
		mode_info.visible = lpc_mode
		if index == 2:
			source_rows.value = 4
			if image.get_width() % target_doc.width == 0:
				count.value = clampi(image.get_width() / target_doc.width, 1, max_columns)
			fit_grid.button_pressed = false
			fit_grid.tooltip_text = "O mapeamento LPC usa células exatas de 64 × 64 px e quatro linhas na ordem N, W, S, E."
		else:
			fit_grid.tooltip_text = "Redimensiona a folha toda. Use quando a imagem não tiver margem nem espaçamento entre células."
		source_rows.editable = not lpc_mode
		source_row.editable = not lpc_mode
		fit_grid.disabled = lpc_mode
		isolate.disabled = lpc_mode
		if lpc_mode: isolate.button_pressed = false
	)
	popup.confirmed.connect(func():
		if doc != target_doc or doc.active_layer != target_layer or doc.direction != target_direction:
			notify("Documento, camada ou direção mudou; abra a importação novamente.")
			popup.queue_free(); return
		var import_config := {
			"columns": int(count.value), "start_frame": int(first_frame.value) - 1,
			"all_directions": mode.selected == 1, "content_scale": float(content_scale.value) / 100.0,
			"alignment": ["center", "bottom_center", "top_left"][alignment.selected],
			"margin": Vector2i(int(margin_x.value), int(margin_y.value)),
			"spacing": Vector2i(int(spacing_x.value), int(spacing_y.value)),
		}
		var result: Dictionary
		if isolate.button_pressed:
			if mode.selected == 2:
				notify("O isolamento por silhueta ainda usa o modo de oito direções; desmarque-o para importar LPC."); popup.queue_free(); return
			if margin_x.value != 0 or margin_y.value != 0 or spacing_x.value != 0 or spacing_y.value != 0:
				notify("Silhuetas: margem e espaçamento devem ser zero."); popup.queue_free(); return
			if mode.selected == 1 and int(source_rows.value) != 8:
				notify("Para separar oito direções, configure exatamente oito linhas de origem."); popup.queue_free(); return
			var job = preload("res://core/silhouette_atlas.gd").new()
			job.input_image = image; job.column_count = int(count.value); job.row_count = int(source_rows.value); job.minimum_area = int(component_area.value)
			var captured_revision: int = target_doc.revision
			var task: int = WorkerThreadPool.add_task(job.compute)
			notify("Separando silhuetas em segundo plano…")
			while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
			WorkerThreadPool.wait_for_task_completion(task)
			if doc != target_doc or target_doc.revision != captured_revision or doc.active_layer != target_layer or doc.direction != target_direction:
				notify("O projeto mudou durante o recorte; importe novamente para preservar as edições."); popup.queue_free(); return
			var isolated_config := {"start_frame": int(first_frame.value) - 1, "content_scale": float(content_scale.value) / 100.0, "alignment": ["center", "bottom_center", "top_left"][alignment.selected]}
			if mode.selected == 1:
				result = SpriteSheetImporter.import_isolated_directions(target_doc, job.result, isolated_config)
			else:
				isolated_config["source_row"] = int(source_row.value) - 1
				result = SpriteSheetImporter.import_isolated_row(target_doc, job.result, isolated_config)
		elif mode.selected == 0 and (fit_grid.button_pressed or int(source_rows.value) > 1):
			result = SpriteSheetImporter.import_grid_row(target_doc, image, {
				"columns": int(count.value), "source_rows": int(source_rows.value),
				"source_row": int(source_row.value) - 1, "fit_grid": fit_grid.button_pressed,
				"start_frame": int(first_frame.value) - 1, "content_scale": float(content_scale.value) / 100.0,
				"alignment": ["center", "bottom_center", "top_left"][alignment.selected],
				"margin_x": int(margin_x.value), "margin_y": int(margin_y.value),
				"spacing_x": int(spacing_x.value), "spacing_y": int(spacing_y.value),
			})
		else:
			import_config["cell_width"] = target_doc.width
			import_config["cell_height"] = target_doc.height
			if mode.selected == 2:
				if int(source_rows.value) != 4 or fit_grid.button_pressed:
					notify("LPC requer quatro linhas, células exatas e ajuste da grade desativado."); popup.queue_free(); return
				import_config["rows"] = 4
				import_config["direction_map"] = [0, 6, 4, 2]
			else:
				import_config["rows"] = 8 if mode.selected == 1 else 1
			result = SpriteSheetImporter.import_into(target_doc, image, import_config)
		if result.ok:
			if not source_id.is_empty():
				var import_details := {
					"mode": "eight_directions" if mode.selected == 1 else ("lpc_four_cardinals" if mode.selected == 2 else "single_action_row"),
					"direction_map": ["N", "W", "S", "E"] if mode.selected == 2 else (target_doc.DIRECTIONS if mode.selected == 1 else [target_doc.DIRECTIONS[target_direction]]),
					"columns": int(count.value), "source_rows": int(source_rows.value),
					"source_row": int(source_row.value), "start_frame": int(first_frame.value),
					"content_scale_percent": float(content_scale.value),
					"alignment": ["center", "bottom_center", "top_left"][alignment.selected],
					"isolated_silhouettes": isolate.button_pressed,
					"fit_grid": fit_grid.button_pressed,
					"margin": [int(margin_x.value), int(margin_y.value)],
					"spacing": [int(spacing_x.value), int(spacing_y.value)],
				}
				var library = preload("res://core/public_asset_library.gd").new()
				var attribution: Dictionary = library.record_spritesheet_import(target_doc, source_id, import_details)
				if not attribution.ok:
					target_doc.undo(); refresh_all(); notify(str(attribution.error)); popup.queue_free(); return
			refresh_all()
			notify("%d cels importadas • %d direção(ões) • conteúdo %.0f%% • procedência e créditos guardados." % [result.cells, result.directions, float(content_scale.value)])
		else:
			notify(str(result.error))
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(620, 680))

func validate_project() -> void:
	var issues: Array = doc.validate()
	notify("Validação estrutural OK • %d camadas, 8 direções, %d frames. Qualidade artística requer revisão humana." % [doc.layers.size(), doc.frames] if issues.is_empty() else "; ".join(issues))

func _process(delta: float) -> void:
	if playing and tabs.current_tab == 0:
		advance_animation_preview(delta)
	autosave_elapsed += delta
	if autosave_elapsed >= 30:
		autosave_elapsed = 0
		_store_workspace_view()
		workspace.request_checkpoint()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				if event.shift_pressed: _save_target_id = workspace.active_id; browse("save")
				else: save_project()
				get_viewport().set_input_as_handled()
			KEY_Z: undo(); get_viewport().set_input_as_handled()
			KEY_Y: redo(); get_viewport().set_input_as_handled()
			KEY_N: new_document(); get_viewport().set_input_as_handled()
			KEY_O: browse("open"); get_viewport().set_input_as_handled()
			KEY_W: request_close_document(workspace.active_id); get_viewport().set_input_as_handled()
			KEY_TAB:
				var index: int = workspace.records.find(workspace.current())
				workspace.activate(workspace.records[posmod(index + (-1 if event.shift_pressed else 1), workspace.records.size())].id)
				get_viewport().set_input_as_handled()
			KEY_C: copy_pixels(); get_viewport().set_input_as_handled()
			KEY_V: paste_pixels(); get_viewport().set_input_as_handled()
	elif tabs.current_tab == 0 and not event.alt_pressed:
		var shortcuts := {KEY_B: 0, KEY_E: 1, KEY_G: 2, KEY_L: 3, KEY_R: 4, KEY_M: 5, KEY_I: 6, KEY_U: 8, KEY_Q: 9, KEY_J: 10}
		if shortcuts.has(event.keycode): select_drawing_tool(shortcuts[event.keycode]); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE: toggle_playback(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT: step_frame(-1); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_RIGHT: step_frame(1); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DELETE: transform("clear"); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()

func transform(operation: String, offset: Vector2i = Vector2i.ZERO) -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.transform_pixels(operation, offset): edited()
	else: notify("Transformação recusada: camada/pixels protegidos ou seleção não quadrada para rotação.")

func resize_canvas_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var popup := ConfirmationDialog.new()
	popup.title = "Redimensionar canvas"
	var fields := column(popup)
	label("Ajusta todas as cels proporcionalmente; pivôs, offsets, hitboxes e máscaras acompanham a escala. A revisão artística derivada volta a pendente.", fields, 12)
	var size_row := row(fields)
	label("Largura", size_row)
	var width_field := spin(size_row, 8, 512, doc.width, func(_value): pass)
	label("Altura", size_row)
	var height_field := spin(size_row, 8, 512, doc.height, func(_value): pass)
	label("Filtro", fields)
	var filter := OptionButton.new()
	filter.add_item("Nearest — pixel art", Image.INTERPOLATE_NEAREST)
	filter.add_item("Bilinear", Image.INTERPOLATE_BILINEAR)
	filter.add_item("Cubic", Image.INTERPOLATE_CUBIC)
	filter.select(0)
	fields.add_child(filter)
	label("Alinhamento", fields)
	var alignment := OptionButton.new()
	alignment.add_item("Centro", 0)
	alignment.add_item("Pés no centro", 1)
	alignment.add_item("Canto superior esquerdo", 2)
	alignment.select(1)
	fields.add_child(alignment)
	var target_instance: int = doc.get_instance_id()
	popup.confirmed.connect(func():
		popup.queue_free()
		if doc.get_instance_id() != target_instance:
			notify("O documento mudou; redimensione o documento ativo novamente.")
			return
		var alignments := ["center", "bottom_center", "top_left"]
		var result: Dictionary = CanvasResizer.resize_document(doc, int(width_field.value), int(height_field.value), filter.get_selected_id(), alignments[alignment.get_selected_id()])
		if not result.get("ok", false):
			notify(str(result.get("error", "Redimensionamento recusado.")))
			return
		refresh_all()
		notify("Canvas redimensionado para %d × %d. Aprovações herdadas foram removidas; revise o novo raster." % [doc.width, doc.height])
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(560, 330))

func show_comparison(title: String, before: Image, after: Image, note: String, accept: Callable = Callable()) -> void:
	var popup := ConfirmationDialog.new()
	popup.title = title
	var body := column(popup)
	label(note, body)
	var views := row(body)
	for pair in [["Antes", before], ["Depois", after]]:
		var pane := column(views)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(pair[0], pane, 18)
		var image_view := TextureRect.new()
		image_view.texture = ImageTexture.create_from_image(pair[1])
		image_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image_view.custom_minimum_size = Vector2(300, 300)
		image_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pane.add_child(image_view)
	popup.get_ok_button().text = "Aceitar correção" if accept.is_valid() else "Fechar"
	popup.get_cancel_button().text = "Rejeitar"
	if not accept.is_valid(): popup.get_cancel_button().hide()
	popup.confirmed.connect(func():
		if accept.is_valid(): accept.call()
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(700, 420))

func review_correction() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.layers[doc.active_layer].locked: notify("Camada bloqueada."); return
	var draft: Dictionary = precision.draft_palette(doc)
	show_comparison("Correção localizada", draft.before, draft.after, "%d pixels alterados • proteção e máscara preservadas" % draft.changed, func():
		if precision.accept(doc, draft): edited(); notify("Correção aceita; Ctrl+Z permite reverter.")
		else: notify("Documento mudou desde a proposta. Gere outra correção.")
	)

func review_cluster_cleanup() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_layer: int = doc.active_layer
	var target_direction: int = doc.direction
	var target_frame: int = doc.frame
	var popup := ConfirmationDialog.new()
	popup.title = "Limpar clusters pequenos"
	var body := column(popup)
	label("Detecta componentes opacos com conectividade de 8 vizinhos na camada, direção e quadro ativos. Só propõe apagar componentes até o limite informado que estejam inteiramente dentro da seleção e fora de pixels protegidos. Cada proposta requer revisão visual.", body, 12)
	var threshold := SpinBox.new()
	threshold.min_value = 1; threshold.max_value = ClusterCleaner.MAX_CLUSTER_SIZE; threshold.value = 1; threshold.prefix = "Máximo de pixels por cluster: "
	body.add_child(threshold)
	popup.confirmed.connect(func():
		popup.hide()
		popup.queue_free()
		if doc.get_instance_id() != target_instance or doc.revision != target_revision or doc.active_layer != target_layer or doc.direction != target_direction or doc.frame != target_frame:
			notify("Documento ou cel mudou. Abra uma nova proposta de limpeza.")
			return
		var proposal: Dictionary = cluster_cleaner.build(doc, int(threshold.value))
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Limpeza recusada.")))
			return
		if int(proposal.get("removed_pixels", 0)) == 0:
			notify(str(proposal.get("message", "Nenhum cluster elegível.")))
			return
		var note := "%s\nCamada: %s • direção: %s • quadro: %d • limite: %d pixels • cores afetadas: %d. Pixels fora da seleção, protegidos ou ligados a clusters maiores são mantidos. Isso é uma proposta de limpeza, não uma aprovação artística." % [str(proposal.message), str(doc.layers[doc.active_layer].name), Document.DIRECTIONS[doc.direction], doc.frame + 1, int(proposal.max_cluster_size), proposal.color_counts.size()]
		show_comparison("Prévia de limpeza de clusters", proposal.before, proposal.after, note, func():
			if doc.get_instance_id() != target_instance or not cluster_cleaner.apply(doc, proposal):
				notify("Documento, seleção ou máscara mudou; nenhum pixel foi alterado.")
				return
			edited()
			notify("Clusters removidos. A aprovação artística foi reiniciada; Ctrl+Z desfaz a limpeza.")
		)
	)
	popup.canceled.connect(func(): popup.hide(); popup.queue_free())
	add_child(popup)
	popup.popup_centered(Vector2i(640, 300))

func open_material_ramp_dialog() -> void:
	stop_playback()
	if doc.art.get("locked", false): notify("Art Lock impede alterar a paleta."); return
	if doc.palette.size() < 3: notify("A paleta precisa ter ao menos três cores para definir sombra, base e luz."); return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var popup := ConfirmationDialog.new()
	popup.title = "Nova rampa de material"
	var body := column(popup)
	label("Escolha três cores existentes na ordem sombra, base e luz. O Sprite Forge interpola o matiz pelo menor arco e mantém a base exatamente no passo central. O resultado é uma proposta de paleta; nenhum pixel existente será repintado.", body, 12)
	var name_field := LineEdit.new()
	name_field.name = "MaterialRampName"
	name_field.placeholder_text = "Nome do material (ex.: aço, couro, pele)"
	name_field.text = "Novo material"
	body.add_child(name_field)
	var color_row := row(body)
	var selectors: Array[OptionButton] = []
	var roles := ["Sombra", "Base", "Luz"]
	for source_role in 3:
		label(roles[source_role], color_row)
		var selector := OptionButton.new()
		selector.name = ["RampShadow", "RampBase", "RampLight"][source_role]
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for palette_index in doc.palette.size():
			var color_hex := str(doc.palette[palette_index])
			var swatch := MaterialRamps.preview_strip([color_hex], 12, 12)
			selector.add_icon_item(ImageTexture.create_from_image(swatch), color_hex, palette_index)
		selectors.append(selector)
		color_row.add_child(selector)
	selectors[0].select(0)
	selectors[1].select(1)
	selectors[2].select(2)
	var steps_row := row(body)
	label("Passos (ímpar para centralizar a cor-base)", steps_row)
	var steps := SpinBox.new()
	steps.name = "RampStepCount"
	steps.min_value = MaterialRamps.MIN_STEPS
	steps.max_value = MaterialRamps.MAX_STEPS
	steps.step = 2
	steps.value = 5
	steps_row.add_child(steps)
	popup.confirmed.connect(func():
		popup.hide()
		popup.queue_free()
		if doc.get_instance_id() != target_instance or doc.revision != target_revision:
			notify("Documento alterado durante a configuração. Abra uma nova proposta de rampa.")
			return
		var proposal: Dictionary = material_ramps.build(doc, name_field.text, selectors[0].get_selected_id(), selectors[1].get_selected_id(), selectors[2].get_selected_id(), int(steps.value))
		if not proposal.get("ok", false): notify(str(proposal.get("message", "Rampa recusada."))); return
		var before: Image = MaterialRamps.preview_strip(proposal.source_colors, 24, 32)
		var after: Image = MaterialRamps.preview_strip(proposal.colors, 24, 32)
		var note := "%s\nSombra %s → base %s → luz %s. Passos gerados: %s. Cores novas: %d. Confirme para adicionar a paleta e registrar o material no projeto; nenhuma cel será alterada." % [str(proposal.message), str(proposal.source_colors[0]), str(proposal.source_colors[1]), str(proposal.source_colors[2]), ", ".join(proposal.colors), proposal.additions.size()]
		show_comparison("Prévia da rampa · " + str(proposal.name), before, after, note, func():
			if not material_ramps.apply(doc, proposal):
				notify("Paleta ou documento mudou; a proposta foi descartada.")
				return
			refresh_all()
			notify("Rampa %s registrada. Os tons estão na paleta e podem ser escolhidos no pincel. Ctrl+Z desfaz a rampa inteira." % str(proposal.name))
		)
	)
	popup.canceled.connect(func(): popup.hide(); popup.queue_free())
	add_child(popup)
	popup.popup_centered(Vector2i(760, 340))

func open_material_recolor_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.art.get("locked", false): notify("Art Lock impede recolorir pixels."); return
	if doc.layers.is_empty() or doc.palette.is_empty(): notify("O documento não tem camada ou paleta utilizável."); return
	var stored_ramps: Variant = doc.art.get("material_ramps", [])
	if not stored_ramps is Array or stored_ramps.is_empty(): notify("Crie primeiro uma rampa de material."); return
	var popup := ConfirmationDialog.new()
	popup.title = "Recolorir região com rampa"
	var body := column(popup)
	label("Mapeia pixels que correspondam exatamente à cor-fonte para um tom de uma rampa salva. A seleção e os pixels protegidos limitam sempre a operação. Escolha o modo componente para atingir somente a área conectada à semente indicada. A prévia exige aceite humano.", body, 12)
	var source_row := row(body)
	label("Cor-fonte", source_row)
	var source_selector := OptionButton.new()
	source_selector.name = "RecolorSource"
	for palette_index in doc.palette.size():
		var hex := str(doc.palette[palette_index])
		var swatch := MaterialRamps.preview_strip([hex], 12, 12)
		source_selector.add_icon_item(ImageTexture.create_from_image(swatch), hex, palette_index)
	source_row.add_child(source_selector)
	source_selector.select(0)
	var ramp_row := row(body)
	label("Material", ramp_row)
	var ramp_selector := OptionButton.new()
	ramp_selector.name = "RecolorRamp"
	var ramps: Array[Dictionary] = []
	for ramp_value in stored_ramps:
		if ramp_value is Dictionary:
			ramp_selector.add_item(str(ramp_value.get("name", "Material")), ramps.size())
			ramps.append(ramp_value)
	ramp_row.add_child(ramp_selector)
	var tone_row := row(body)
	label("Tom de destino", tone_row)
	var tone_selector := OptionButton.new()
	tone_selector.name = "RecolorTone"
	tone_row.add_child(tone_selector)
	var tone_colors: Array = []
	for ramp in ramps:
		var colors: Variant = ramp.get("colors", [])
		tone_colors.append(colors if colors is Array else [])
	var populate_tones := func(ramp_index: int):
		tone_selector.clear()
		if ramp_index < 0 or ramp_index >= tone_colors.size(): return
		for tone_index in tone_colors[ramp_index].size():
			var color_hex := str(tone_colors[ramp_index][tone_index])
			var preview: Image = MaterialRamps.preview_strip([color_hex], 12, 12)
			tone_selector.add_icon_item(ImageTexture.create_from_image(preview), "%d · %s" % [tone_index + 1, color_hex], tone_index)
		if tone_selector.item_count > 0: tone_selector.select(int(tone_selector.item_count / 2))
	if ramp_selector.item_count > 0:
		ramp_selector.select(0)
		populate_tones.call(0)
		ramp_selector.item_selected.connect(func(index): populate_tones.call(index))
	var mode_row := row(body)
	label("Região", mode_row)
	var mode_selector := OptionButton.new()
	mode_selector.name = "RecolorMode"
	mode_selector.add_item("Cel ativo limitado pela seleção/máscara", 0)
	mode_selector.add_item("Componente da cor conectado à semente", 1)
	mode_row.add_child(mode_selector)
	var seed_row := row(body)
	seed_row.name = "RecolorSeedRow"
	seed_row.visible = false
	label("Semente X / Y", seed_row)
	var seed_x := SpinBox.new()
	seed_x.name = "RecolorSeedX"
	seed_x.min_value = 0; seed_x.max_value = doc.width - 1; seed_x.value = int(doc.width / 2); seed_x.step = 1
	seed_row.add_child(seed_x)
	var seed_y := SpinBox.new()
	seed_y.name = "RecolorSeedY"
	seed_y.min_value = 0; seed_y.max_value = doc.height - 1; seed_y.value = int(doc.height / 2); seed_y.step = 1
	seed_row.add_child(seed_y)
	mode_selector.item_selected.connect(func(index): seed_row.visible = index == 1)
	popup.confirmed.connect(func():
		popup.hide()
		popup.queue_free()
		if ramp_selector.item_count == 0 or tone_selector.item_count == 0:
			notify("A rampa selecionada não contém tons utilizáveis.")
			return
		var selected_ramp_index: int = ramp_selector.get_selected_id()
		if selected_ramp_index < 0 or selected_ramp_index >= ramps.size():
			notify("Seleção de material inválida.")
			return
		var ramp_name := str(ramps[selected_ramp_index].get("name", ""))
		var tone_index: int = tone_selector.get_selected_id()
		if tone_index < 0 or tone_index >= tone_colors[selected_ramp_index].size():
			notify("Tom de destino inválido.")
			return
		var source_hex := str(doc.palette[source_selector.get_selected_id()])
		var target_hex := str(tone_colors[selected_ramp_index][tone_index])
		var mode := "connected" if mode_selector.get_selected_id() == 1 else "selection"
		var seed := Vector2i(int(seed_x.value), int(seed_y.value))
		var proposal: Dictionary = material_recolor.build(doc, ramp_name, source_hex, target_hex, mode, seed)
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Recolorização recusada.")))
			return
		var scope := "componente da semente %d,%d" % [seed.x, seed.y] if mode == "connected" else "cel ativo dentro da seleção"
		var note := "%d pixels • %s • cor-fonte %s → %s/%d (%s). Pixels protegidos e fora da seleção permanecem intactos. A alteração invalida aprovações artísticas deste documento." % [proposal.changed_pixels, scope, source_hex, ramp_name, tone_index + 1, target_hex]
		show_comparison("Prévia de recolorização · " + ramp_name, proposal.before, proposal.after, note, func():
			if not material_recolor.apply(doc, proposal):
				notify("Documento, cel, paleta ou máscara mudou; a proposta foi descartada.")
				return
			edited()
			notify("%d pixels recoloridos com %s. Ctrl+Z desfaz toda a operação." % [proposal.changed_pixels, ramp_name])
		)
	)
	popup.canceled.connect(func(): popup.hide(); popup.queue_free())
	add_child(popup)
	popup.popup_centered(Vector2i(820, 420))

func open_sprite_effect_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.art.get("locked", false): notify("Art Lock impede gerar efeitos."); return
	if doc.layers.is_empty(): notify("O documento não tem camadas."); return
	var source_indices: Array = []
	for index in doc.layers.size():
		if not doc.layers[index].get("effect") is Dictionary: source_indices.append(index)
	var ramp_names: Array = []
	for ramp in doc.art.get("material_ramps", []):
		if ramp is Dictionary and ramp.get("colors") is Array and not ramp.colors.is_empty(): ramp_names.append(str(ramp.get("name", "")))
	var anchor_names: Array = doc.anchors.keys()
	for name in ["shield_mount", "weapon_mount"]:
		if not anchor_names.has(name): anchor_names.append(name)
	var clip_names: Array = []
	for clip in doc.animation.clips: clip_names.append(str(clip.name))
	var active_is_effect: bool = doc.layers[doc.active_layer].get("effect") is Dictionary
	var popup := ConfirmationDialog.new()
	popup.title = "Gerar efeito"
	var body := column(popup)
	label("Brilho, clarão e partículas viram camadas de pixels com receita salva. Usam somente cores da paleta e respeitam seleção, máscaras e pixels protegidos. A prévia exige aceite humano.", body, 12)
	var type_row := row(body)
	label("Tipo", type_row)
	var type_selector := OptionButton.new()
	type_selector.name = "EffectType"
	type_selector.add_item("Brilho (aura)", 0)
	type_selector.add_item("Clarão (silhueta)", 1)
	type_selector.add_item("Partículas", 2)
	type_row.add_child(type_selector)
	var source_row := row(body)
	label("Camada-fonte", source_row)
	var source_selector := OptionButton.new()
	source_selector.name = "EffectSource"
	for index in source_indices: source_selector.add_item(str(doc.layers[index].name), index)
	source_row.add_child(source_selector)
	var ramp_row := row(body)
	label("Material", ramp_row)
	var ramp_selector := OptionButton.new()
	ramp_selector.name = "EffectRamp"
	for ramp_index in ramp_names.size(): ramp_selector.add_item(str(ramp_names[ramp_index]), ramp_index)
	ramp_row.add_child(ramp_selector)
	var color_row := row(body)
	label("Cor", color_row)
	var color_selector := OptionButton.new()
	color_selector.name = "EffectColor"
	for palette_index in doc.palette.size():
		var hex := str(doc.palette[palette_index])
		color_selector.add_icon_item(ImageTexture.create_from_image(MaterialRamps.preview_strip([hex], 12, 12)), hex, palette_index)
	color_row.add_child(color_selector)
	var anchor_row := row(body)
	label("Âncora", anchor_row)
	var anchor_selector := OptionButton.new()
	anchor_selector.name = "EffectAnchor"
	for anchor_index in anchor_names.size(): anchor_selector.add_item(str(anchor_names[anchor_index]), anchor_index)
	anchor_row.add_child(anchor_selector)
	var clip_row := row(body)
	label("Clip", clip_row)
	var clip_selector := OptionButton.new()
	clip_selector.name = "EffectClip"
	for clip_index in clip_names.size(): clip_selector.add_item(str(clip_names[clip_index]), clip_index)
	clip_row.add_child(clip_selector)
	var frames_row := row(body)
	label("Quadros (ex.: 0, 1, 2)", frames_row)
	var frames_field := LineEdit.new()
	frames_field.name = "EffectFrames"
	var all_frames: PackedStringArray = []
	for f in doc.frames: all_frames.append(str(f))
	frames_field.text = ", ".join(all_frames)
	frames_row.add_child(frames_field)
	var params_row := row(body)
	label("Raio / pulsar", params_row)
	var radius := SpinBox.new()
	radius.name = "EffectRadius"
	radius.min_value = 1; radius.max_value = 4; radius.value = 2; radius.step = 1
	params_row.add_child(radius)
	var pulse := CheckBox.new()
	pulse.name = "EffectPulse"
	pulse.text = "Pulsar"
	params_row.add_child(pulse)
	var particles_row := row(body)
	label("Quantidade / vida / seed", particles_row)
	var count := SpinBox.new()
	count.name = "EffectCount"
	count.min_value = 1; count.max_value = 8; count.value = 3; count.step = 1
	particles_row.add_child(count)
	var life := SpinBox.new()
	life.name = "EffectLife"
	life.min_value = 1; life.max_value = 8; life.value = 4; life.step = 1
	particles_row.add_child(life)
	var seed_box := SpinBox.new()
	seed_box.name = "EffectSeed"
	seed_box.min_value = 0; seed_box.max_value = 2147483647; seed_box.value = 1; seed_box.step = 1
	particles_row.add_child(seed_box)
	var name_field := LineEdit.new()
	name_field.name = "EffectLayerName"
	name_field.placeholder_text = "Nome da camada (vazio usa o tipo)"
	body.add_child(name_field)
	var regenerate := CheckBox.new()
	regenerate.name = "EffectRegenerate"
	regenerate.text = "Regenerar a camada de efeito ativa (substitui a camada e mostra os retoques)"
	regenerate.button_pressed = active_is_effect
	regenerate.visible = active_is_effect
	body.add_child(regenerate)
	type_selector.select(0)
	source_selector.select(0)
	ramp_selector.select(0)
	color_selector.select(0)
	anchor_selector.select(0)
	clip_selector.select(clampi(doc.animation.active, 0, maxi(0, clip_names.size() - 1)))
	var update_fields := func():
		var kind := type_selector.get_selected_id()
		source_row.visible = kind != 2
		ramp_row.visible = kind != 1
		color_row.visible = kind == 1
		anchor_row.visible = kind == 2
		clip_row.visible = kind == 2
		particles_row.visible = kind == 2
		params_row.visible = kind == 0
	type_selector.item_selected.connect(func(_index): update_fields.call())
	update_fields.call()
	var collect := func() -> Dictionary:
		var kind := type_selector.get_selected_id()
		var recipe := {"type": ["glow", "flash", "particles"][kind], "frames": []}
		for part in frames_field.text.split(",", false):
			var text := part.strip_edges()
			if text.is_empty(): continue
			if not text.is_valid_int(): return {"error": "Quadros devem ser números separados por vírgula."}
			recipe.frames.append(int(text))
		if kind != 2:
			if source_selector.selected < 0 or source_selector.selected >= source_indices.size(): return {"error": "Escolha uma camada-fonte."}
			recipe.source_layer_id = doc.layers[source_indices[source_selector.selected]].id
		if kind != 1:
			if ramp_selector.selected < 0 or ramp_selector.selected >= ramp_names.size(): return {"error": "Crie ou escolha uma rampa de material."}
			recipe.ramp = ramp_names[ramp_selector.selected]
		if kind == 0: recipe.params = {"radius": int(radius.value), "pulse": 1 if pulse.button_pressed else 0}
		if kind == 1:
			if color_selector.selected < 0: return {"error": "Escolha uma cor da paleta."}
			recipe.color = str(doc.palette[color_selector.selected])
		if kind == 2:
			if anchor_selector.selected < 0 or clip_selector.selected < 0: return {"error": "Escolha âncora e clip."}
			recipe.anchor = str(anchor_names[anchor_selector.selected])
			recipe.clip = str(clip_names[clip_selector.selected])
			recipe.seed = int(seed_box.value)
			recipe.params = {"count": int(count.value), "life": int(life.value)}
		var target := str(doc.layers[doc.active_layer].id) if regenerate.visible and regenerate.button_pressed else ""
		return {"recipe": recipe, "target": target, "name": name_field.text.strip_edges()}
	popup.confirmed.connect(func():
		popup.hide()
		popup.queue_free()
		var collected: Dictionary = collect.call()
		if collected.has("error"): notify(str(collected.error)); return
		var proposal: Dictionary = sprite_effects.build(doc, collected.recipe, collected.target)
		if not proposal.get("ok", false): notify(str(proposal.get("message", "Efeito recusado."))); return
		var preview_doc: RefCounted = doc.detached_copy()
		sprite_effects.apply(preview_doc, sprite_effects.build(preview_doc, collected.recipe, collected.target), collected.name)
		var note := "%s • %d cels alteradas • %d cels com retoque manual serão substituídas. Eventos fx_start e fx_end são gravados. A prévia mostra o quadro e a direção atuais. A alteração invalida aprovações artísticas." % [str(proposal.effect.type), proposal.changed_cels, proposal.retouched_cels.size()]
		show_comparison("Prévia de efeito · " + _effect_label(str(proposal.effect.type)), doc.composite(), preview_doc.composite(), note, func():
			if not sprite_effects.apply(doc, proposal, collected.name):
				notify("Documento, camadas ou efeito mudou; a proposta foi descartada.")
				return
			edited()
			notify("Efeito aplicado. Ctrl+Z desfaz a camada, os eventos e as aprovações.")
		)
	)
	popup.canceled.connect(func(): popup.hide(); popup.queue_free())
	add_child(popup)
	popup.popup_centered(Vector2i(820, 640))

func _effect_label(kind: String) -> String:
	return {"glow": "Brilho", "flash": "Clarão", "particles": "Partículas"}.get(kind, kind)

func open_rig_segment_extractor() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.art.get("locked", false): notify("Art Lock impede separar segmentos raster."); return
	if doc.active_layer < 0 or doc.active_layer >= doc.layers.size(): notify("Selecione uma camada raster."); return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var source_layer_name := str(doc.layers[doc.active_layer].name)
	var popup := ConfirmationDialog.new()
	popup.title = "Extrair região em camada de rig"
	var body := column(popup)
	label("Move pixels da camada ativa para uma nova camada, sem mudar a imagem composta. A região pode ser todo o cel dentro da seleção/máscara ou a componente opaca conectada a uma semente. A camada copia opacidade, equipamento, profundidade e alinhamento da origem; rotação ativa precisa ser rasterizada antes. Escolha opcionalmente o osso que corresponderá à nova camada.", body, 12)
	var name_field := LineEdit.new()
	name_field.name = "RigSegmentLayerName"
	name_field.placeholder_text = "Nome da parte (ex.: antebraço esquerdo)"
	name_field.text = "Novo segmento"
	body.add_child(name_field)
	var mode_row := row(body)
	label("Região", mode_row)
	var mode_selector := OptionButton.new()
	mode_selector.name = "RigSegmentMode"
	mode_selector.add_item("Pixels opacos do cel limitados pela seleção/máscara", 0)
	mode_selector.add_item("Componente opaca conectada à semente", 1)
	mode_row.add_child(mode_selector)
	var seed_row := row(body)
	seed_row.name = "RigSegmentSeedRow"
	seed_row.visible = false
	label("Semente X / Y", seed_row)
	var seed_x := SpinBox.new()
	seed_x.name = "RigSegmentSeedX"
	seed_x.min_value = 0; seed_x.max_value = doc.width - 1; seed_x.value = int(doc.width / 2); seed_x.step = 1
	seed_row.add_child(seed_x)
	var seed_y := SpinBox.new()
	seed_y.name = "RigSegmentSeedY"
	seed_y.min_value = 0; seed_y.max_value = doc.height - 1; seed_y.value = int(doc.height / 2); seed_y.step = 1
	seed_row.add_child(seed_y)
	mode_selector.item_selected.connect(func(index): seed_row.visible = index == 1)
	var bone_row := row(body)
	label("Mapear a segmento ósseo", bone_row)
	var bone_selector := OptionButton.new()
	bone_selector.name = "RigSegmentBone"
	bone_selector.add_item("Sem segmento (mapear depois)", 0)
	var skeleton: Array = doc.rig.get("skeleton", [])
	for index in skeleton.size():
		var segment: Array = skeleton[index]
		bone_selector.add_item("%s → %s" % [str(segment[0]), str(segment[1])], index + 1)
	bone_row.add_child(bone_selector)
	bone_selector.select(0)
	popup.confirmed.connect(func():
		popup.hide()
		popup.queue_free()
		if doc.get_instance_id() != target_instance or doc.revision != target_revision:
			notify("O documento foi alterado. Configure novamente a extração.")
			return
		var mode := "connected" if mode_selector.get_selected_id() == 1 else "selection"
		var seed := Vector2i(int(seed_x.value), int(seed_y.value))
		var bone_id := bone_selector.get_selected_id()
		var bone_segment: Array = [] if bone_id <= 0 or bone_id > skeleton.size() else skeleton[bone_id - 1].duplicate(true)
		var proposal: Dictionary = rig_segment_extractor.build(doc, name_field.text, mode, seed, bone_segment)
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Extração de segmento recusada.")))
			return
		var scope := "componente na semente %d,%d" % [seed.x, seed.y] if mode == "connected" else "pixels opacos no cel/seleção"
		var mapped_bone := "sem mapeamento ósseo" if bone_segment.is_empty() else "%s → %s" % [str(bone_segment[0]), str(bone_segment[1])]
		var note := "%d pixels • origem: %s • região: %s • destino: %s • osso: %s. A esquerda mostra a cel fonte; a direita, os pixels que serão isolados na nova camada. Opacidade, ordem e alinhamento da composição são preservados. Revise a segmentação antes de aceitar." % [proposal.pixels.size(), source_layer_name, scope, str(proposal.name), mapped_bone]
		show_comparison("Prévia da camada de rig · " + str(proposal.name), proposal.source_before, proposal.extracted, note, func():
			if not rig_segment_extractor.apply(doc, proposal):
				notify("Documento, pixels, seleção ou proteção mudou; nenhuma camada foi criada.")
				return
			refresh_all()
			notify("%d pixels extraídos para %s. Confira o mapeamento e retoque a camada; Ctrl+Z restaura a composição." % [proposal.pixels.size(), str(proposal.name)])
		)
	)
	popup.canceled.connect(func(): popup.hide(); popup.queue_free())
	add_child(popup)
	popup.popup_centered(Vector2i(820, 460))

func retarget_pose_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var clip_index: int = int(doc.animation.active)
	var active_clip: Dictionary = doc.animation.clips[clip_index]
	var target_frame: int = doc.frame
	if not active_clip.get("frames", []).has(target_frame):
		notify("O quadro de destino precisa pertencer ao clip ativo.")
		return
	var source_frames: Array = active_clip.frames.filter(func(frame_index): return int(frame_index) != target_frame)
	if source_frames.is_empty():
		notify("O clip precisa de outro quadro como origem da pose.")
		return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_direction: int = doc.direction
	var popup := ConfirmationDialog.new()
	popup.title = "Retargetar pose por segmentos"
	var body := column(popup)
	label("Destino: %s • Quadro %d • Direção %s" % [active_clip.name, target_frame + 1, Document.DIRECTIONS[target_direction]], body)
	label("A origem fornece orientação óssea; o destino mantém seu próprio raster. Mapeie cada camada visível a um segmento no painel do rig.", body, 12)
	var source_picker := OptionButton.new()
	for source_frame in source_frames:
		source_picker.add_item("Quadro %d" % (int(source_frame) + 1))
		source_picker.set_item_metadata(source_picker.item_count - 1, int(source_frame))
	body.add_child(source_picker)
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or doc.revision != target_revision or int(doc.animation.active) != clip_index or doc.direction != target_direction or doc.frame != target_frame:
			notify("Documento, clip, direção ou destino mudou; gere a prévia novamente.")
			popup.queue_free()
			return
		var source_frame := int(source_picker.get_item_metadata(source_picker.selected))
		var proposal: Dictionary = pose_retargeter.build(doc, clip_index, target_direction, source_frame, target_frame)
		popup.hide()
		popup.queue_free()
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Retarget recusado.")))
			return
		var before: Image = doc.composite(target_direction, target_frame)
		var preview_doc = doc.detached_copy()
		var preview_ok: bool = pose_retargeter.apply(preview_doc, proposal)
		var after: Image = preview_doc.composite(target_direction, target_frame) if preview_ok else before.duplicate()
		show_comparison("Prévia de retarget por segmentos", before, after,
			str(proposal.message) + "\nOrigem: quadro %d • destino: quadro %d • direção: %s.\nAprovar aplica rotações no destino; o raster fonte não muda." % [source_frame + 1, target_frame + 1, Document.DIRECTIONS[target_direction]],
			func():
				if doc.get_instance_id() != target_instance or not pose_retargeter.apply(doc, proposal):
					notify("A proposta ficou desatualizada; nenhum segmento foi alterado.")
					return
				refresh_all()
				notify("Retarget aplicado às camadas mapeadas. Ctrl+Z desfaz o grupo inteiro.")
		)
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(520, 260))

func open_inter_document_retarget_dialog(source_path: String) -> void:
	var source: RefCounted = store.load_document(source_path)
	if source == null:
		notify("Não foi possível abrir o projeto de origem: " + store.error)
		return
	if source.animation.clips.is_empty() or doc.animation.clips.is_empty():
		notify("Os dois projetos precisam ter ao menos um clip de animação.")
		return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_clip_index: int = int(doc.animation.active)
	var target_frame: int = doc.frame
	var target_direction: int = doc.direction
	var source_revision: int = source.revision
	var popup := ConfirmationDialog.new()
	popup.title = "Retarget de outro projeto"
	var body := column(popup)
	label("Destino: %s • quadro %d • direção %s" % [doc.animation.clips[target_clip_index].name, target_frame + 1, Document.DIRECTIONS[target_direction]], body)
	label("A origem precisa ter a mesma família e direção. As chaves das camadas mapeiam segmentos sem exigir a mesma topologia; confira as proporções ósseas na comparação. Pixels e âncoras do destino serão preservados.", body, 12)
	var source_clip_picker := OptionButton.new()
	for index in source.animation.clips.size():
		source_clip_picker.add_item(str(source.animation.clips[index].name))
		source_clip_picker.set_item_metadata(index, index)
	source_clip_picker.select(clampi(int(source.animation.active), 0, source.animation.clips.size() - 1))
	body.add_child(source_clip_picker)
	var source_frame_picker := OptionButton.new()
	body.add_child(source_frame_picker)
	var update_source_frames := func():
		source_frame_picker.clear()
		var selected_clip := int(source_clip_picker.get_item_metadata(source_clip_picker.selected))
		for source_frame in source.animation.clips[selected_clip].get("frames", []):
			source_frame_picker.add_item("Quadro %d" % (int(source_frame) + 1))
			source_frame_picker.set_item_metadata(source_frame_picker.item_count - 1, int(source_frame))
		if source_frame_picker.item_count > 0:
			var selected_frame := -1
			for frame_index in source_frame_picker.item_count:
				if int(source_frame_picker.get_item_metadata(frame_index)) == int(source.frame): selected_frame = frame_index; break
			source_frame_picker.select(maxi(0, selected_frame))
	source_clip_picker.item_selected.connect(func(_index): update_source_frames.call())
	update_source_frames.call()
	popup.confirmed.connect(func():
		if target_instance != doc.get_instance_id() or target_revision != doc.revision or target_clip_index != int(doc.animation.active) or target_frame != doc.frame or target_direction != doc.direction or source_revision != source.revision:
			notify("Um dos projetos mudou; gere uma nova prévia.")
			popup.queue_free()
			return
		if source_frame_picker.item_count == 0:
			notify("O clip de origem não tem quadros selecionáveis.")
			popup.queue_free()
			return
		var source_clip_index := int(source_clip_picker.get_item_metadata(source_clip_picker.selected))
		var source_frame := int(source_frame_picker.get_item_metadata(source_frame_picker.selected))
		var proposal: Dictionary = inter_document_retargeter.build(source, doc, source_clip_index, target_clip_index, target_direction, source_frame, target_frame)
		popup.hide()
		popup.queue_free()
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Retarget recusado.")))
			return
		var before: Image = doc.composite(target_direction, target_frame)
		var preview_doc: RefCounted = doc.detached_copy()
		var preview_proposal: Dictionary = inter_document_retargeter.build(source, preview_doc, source_clip_index, target_clip_index, target_direction, source_frame, target_frame)
		if not preview_proposal.get("ok", false) or not inter_document_retargeter.apply(preview_doc, preview_proposal):
			notify("Não foi possível criar uma prévia segura do retarget.")
			return
		var after: Image = preview_doc.composite(target_direction, target_frame)
		show_comparison("Prévia de retarget entre projetos", before, after,
			"Origem: %s / %s / quadro %d.\nDestino: %s / quadro %d / %s.\nProporções: %s.\nAprovar aplica somente rotações de camadas no destino; o projeto de origem não muda." % [source_clip_picker.get_item_text(source_clip_picker.selected), source_path.get_file(), source_frame + 1, doc.animation.clips[target_clip_index].name, target_frame + 1, Document.DIRECTIONS[target_direction], ", ".join(proposal.ratios)],
			func():
				if target_instance != doc.get_instance_id() or not inter_document_retargeter.apply(doc, proposal):
					notify("A proposta ficou desatualizada; nenhum segmento foi alterado.")
					return
				refresh_all()
				notify("Pose transferida. Ctrl+Z desfaz todas as rotações do retarget.")
		)
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(580, 340))

func bake_layer_pose_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var layer: Dictionary = doc.layers[doc.active_layer]
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var layer_id := str(layer.id)
	var target_direction: int = int(doc.direction)
	var target_frame: int = int(doc.frame)
	var source_pixels: Image = layer.cels[target_direction][target_frame].duplicate()
	var preview_doc: RefCounted = doc.detached_copy()
	if not preview_doc.bake_layer_pose(layer_id, target_direction, target_frame):
		notify("Não é possível aplicar a pose: camada precisa estar visível e compatível, destravada, sem Art Lock, com transformação ativa e sem máscara protegida nesta cel.")
		return
	var result_pixels: Image = preview_doc.layers[preview_doc.active_layer].cels[target_direction][target_frame].duplicate()
	show_comparison("Aplicar pose à camada em pixels", source_pixels, result_pixels,
		"Camada: %s • clip: %s • frame %d • direção %s.\nA imagem à direita incorpora o giro/offset à cel; opacidade e camadas separadas são mantidas. A composição da cena não deve mudar.\nConfirme para editar estes pixels diretamente. Undo restaura raster e rig." % [str(layer.name), str(doc.clip().name), target_frame + 1, Document.DIRECTIONS[target_direction]],
		func():
			if doc.get_instance_id() != target_instance or doc.revision != target_revision or doc.direction != target_direction or doc.frame != target_frame or str(doc.layers[doc.active_layer].id) != layer_id:
				notify("Documento, camada ou pose mudou; gere outra prévia.")
				return
			if not doc.bake_layer_pose(layer_id, target_direction, target_frame):
				notify("A pose não pôde ser rasterizada; nenhum pixel foi alterado.")
				return
			refresh_all()
			notify("Pose aplicada como pixels editáveis nesta cel. Ctrl+Z restaura a pose do rig.")
	)

func mark_rig_pose_key() -> void:
	if doc.mark_rig_pose_key(str(doc.layers[doc.active_layer].id), str(canvas.anchor_name)):
		refresh_all()
		notify("Pose-chave do rig registrada, incluindo valores neutros. Ctrl+Z desfaz.")
	else:
		notify("A pose já tem todas as chaves do rig ou a camada/articulação não é válida.")

func raster_inbetween_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var clip_index := int(doc.animation.active)
	if doc.animation.clips.size() <= clip_index or doc.clip().frames.size() < 3:
		notify("O clip precisa ter duas poses-chave e ao menos um frame existente entre elas.")
		return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_direction: int = doc.direction
	var popup := ConfirmationDialog.new()
	popup.title = "Criar quadros raster intermediários"
	var body := column(popup)
	label("Escolha duas poses-chave separadas por um a oito frames existentes. A nova opção de escala ajusta cada camada anatômica ao comprimento interpolado do osso, usando vizinho mais próximo e cores originais. A pose ainda pode exigir retoque.", body, 12)
	var scale_parts := CheckBox.new()
	scale_parts.text = "Ajustar escala das partes ao comprimento do osso (0,5×–2×)"
	scale_parts.button_pressed = true
	scale_parts.tooltip_text = "Redimensiona uniformemente cada camada não modular segundo o comprimento interpolado do seu segmento. Equipamentos permanecem rígidos."
	body.add_child(scale_parts)
	var source_picker := OptionButton.new()
	var target_picker := OptionButton.new()
	for frame in doc.clip().frames:
		source_picker.add_item("Quadro %d" % (int(frame) + 1))
		source_picker.set_item_metadata(source_picker.item_count - 1, int(frame))
		target_picker.add_item("Quadro %d" % (int(frame) + 1))
		target_picker.set_item_metadata(target_picker.item_count - 1, int(frame))
	var source_position: int = doc.clip().frames.find(doc.frame)
	source_picker.select(maxi(0, source_position))
	if source_picker.selected + 2 < target_picker.item_count: target_picker.select(source_picker.selected + 2)
	body.add_child(source_picker)
	body.add_child(target_picker)
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or doc.revision != target_revision or int(doc.animation.active) != clip_index or doc.direction != target_direction:
			notify("Documento, clip ou direção mudou; abra uma nova prévia.")
			popup.queue_free()
			return
		var source_frame := int(source_picker.get_item_metadata(source_picker.selected))
		var target_frame := int(target_picker.get_item_metadata(target_picker.selected))
		var proposal: Dictionary = raster_inbetweener.build(doc, clip_index, target_direction, source_frame, target_frame, scale_parts.button_pressed)
		popup.hide()
		popup.queue_free()
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Geração recusada.")))
			return
		var before: Image = raster_inbetweener.contact_sheet(doc, target_direction, proposal.frames)
		var preview_doc: RefCounted = doc.detached_copy()
		var preview_proposal: Dictionary = raster_inbetweener.build(preview_doc, clip_index, target_direction, source_frame, target_frame, scale_parts.button_pressed)
		if not preview_proposal.get("ok", false) or not raster_inbetweener.apply(preview_doc, preview_proposal):
			notify("Não foi possível gerar uma prévia raster segura.")
			return
		var after: Image = raster_inbetweener.contact_sheet(preview_doc, target_direction, proposal.frames)
		show_comparison("Prévia dos quadros raster intermediários", before, after,
			str(proposal.message) + "\nAntes/depois: folhas de contato na ordem do clip. Revise cada parte e todos os contatos antes de aprovar.",
			func():
				if doc.get_instance_id() != target_instance or not raster_inbetweener.apply(doc, proposal):
					notify("O documento mudou ou a proposta expirou; nenhum frame foi alterado.")
					return
				refresh_all()
				notify("Quadros raster intermediários criados. Revise e retoque cada cel; Ctrl+Z desfaz o lote.")
		)
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(620, 320))

func raster_insert_frames_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.animation.clips.is_empty():
		notify("O documento não possui clip de animação.")
		return
	var clip_index := int(doc.animation.active)
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_direction: int = doc.direction
	var popup := ConfirmationDialog.new()
	popup.title = "Inserir quadros raster intermediários"
	var body := column(popup)
	label("Escolha duas poses adjacentes no clip atual. Os novos frames serão inseridos sem alterar a duração total. A escala opcional ajusta partes anatômicas ao osso por vizinho mais próximo; revise cada cel antes de usar.", body, 12)
	var scale_parts := CheckBox.new()
	scale_parts.text = "Ajustar escala das partes ao comprimento do osso (0,5×–2×)"
	scale_parts.button_pressed = true
	scale_parts.tooltip_text = "Redimensiona uniformemente camadas anatômicas. Equipamentos permanecem rígidos."
	body.add_child(scale_parts)
	var source_picker := OptionButton.new()
	var target_picker := OptionButton.new()
	var clip_frames: Array = doc.clip().get("frames", [])
	for frame_value in clip_frames:
		var frame_index := int(frame_value)
		source_picker.add_item("Quadro %d" % (frame_index + 1))
		source_picker.set_item_metadata(source_picker.item_count - 1, frame_index)
		target_picker.add_item("Quadro %d" % (frame_index + 1))
		target_picker.set_item_metadata(target_picker.item_count - 1, frame_index)
	var source_position: int = clip_frames.find(doc.frame)
	source_picker.select(maxi(0, source_position))
	if source_picker.selected + 1 < target_picker.item_count: target_picker.select(source_picker.selected + 1)
	body.add_child(source_picker)
	body.add_child(target_picker)
	var count_row := row(body)
	label("Novos quadros", count_row)
	var count := SpinBox.new()
	count.min_value = 1; count.max_value = 8; count.step = 1; count.value = 2
	count_row.add_child(count)
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or doc.revision != target_revision or int(doc.animation.active) != clip_index or doc.direction != target_direction:
			notify("Documento, clip ou direção mudou; abra uma nova prévia.")
			popup.queue_free()
			return
		if source_picker.selected < 0 or target_picker.selected < 0:
			notify("Escolha duas poses no clip.")
			popup.queue_free()
			return
		var source_frame := int(source_picker.get_item_metadata(source_picker.selected))
		var target_frame := int(target_picker.get_item_metadata(target_picker.selected))
		var proposal: Dictionary = raster_inbetweener.build_inserted(doc, clip_index, target_direction, source_frame, target_frame, int(count.value), scale_parts.button_pressed)
		popup.hide(); popup.queue_free()
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Inserção recusada.")))
			return
		var preview_doc: RefCounted = proposal.preview_document
		var preview_frames: Array = proposal.preview_frames
		var before_frames: Array = [source_frame, target_frame]
		var before: Image = raster_inbetweener.contact_sheet(doc, target_direction, before_frames, 2)
		var after: Image = raster_inbetweener.contact_sheet(preview_doc, target_direction, preview_frames, mini(4, preview_frames.size()))
		show_comparison("Prévia: novos quadros na timeline", before, after,
			str(proposal.message) + "\nAntes: poses-chave. Depois: sequência completa após inserção. Todos os cels gerados continuam editáveis; a alteração pode ser desfeita como uma única operação.",
			func():
				if doc.get_instance_id() != target_instance or not raster_inbetweener.apply_inserted(doc, proposal):
					notify("O documento mudou ou a proposta expirou; nenhum frame foi inserido.")
					return
				doc.frame = source_frame + int(proposal.insert_count)
				refresh_all()
				notify("Novos quadros editáveis foram inseridos. O tempo total original foi preservado; Ctrl+Z desfaz a operação inteira.")
		)
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(720, 400))

func interpolate_rig_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	if doc.layers.is_empty() or doc.animation.clips.is_empty():
		notify("Documento sem camada ou clip para interpolar.")
		return
	var target_instance: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var target_direction: int = doc.direction
	var target_clip: int = int(doc.animation.active)
	var target_layer_id: String = str(doc.layers[doc.active_layer].id)
	var target_anchor: String = str(canvas.anchor_name)
	var dialog_window := ConfirmationDialog.new()
	dialog_window.title = "Interpolar poses do rig"
	var body := column(dialog_window)
	label("Clip: %s • Direção: %s • Camada: %s" % [doc.animation.clips[target_clip].name, Document.DIRECTIONS[target_direction], doc.layers[doc.active_layer].name], body)
	label("Preenche somente quadros sem chave entre poses já ajustadas dentro deste clip. Os pixels não são redesenhados.", body, 12)
	var rotate_keys := check("Rotação da camada selecionada", body, func(_value): pass)
	rotate_keys.button_pressed = true
	var offset_keys := check("Offset local da camada", body, func(_value): pass)
	offset_keys.button_pressed = bool(doc.layers[doc.active_layer].equipment)
	offset_keys.disabled = not bool(doc.layers[doc.active_layer].equipment)
	var anchor_keys := check("Articulação selecionada: %s" % target_anchor, body, func(_value): pass)
	anchor_keys.button_pressed = true
	dialog_window.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or doc.revision != target_revision or int(doc.animation.active) != target_clip or doc.direction != target_direction:
			notify("Documento, clip ou direção mudou. Gere a prévia novamente.")
			dialog_window.queue_free()
			return
		var channels := {"rotation": rotate_keys.button_pressed, "offset": offset_keys.button_pressed, "anchor": anchor_keys.button_pressed}
		var proposal: Dictionary = rig_interpolator.build(doc, target_direction, target_clip, target_layer_id, target_anchor, channels)
		if not proposal.get("ok", false):
			notify(str(proposal.get("message", "Interpolação recusada.")))
			dialog_window.queue_free()
			return
		if proposal.changes.is_empty():
			notify(str(proposal.message))
			dialog_window.queue_free()
			return
		var first_frame: int = int(proposal.changes[0].frame)
		var before: Image = doc.composite(target_direction, first_frame)
		var preview_doc = doc.detached_copy()
		var preview_ok: bool = rig_interpolator.apply(preview_doc, proposal)
		var after: Image = preview_doc.composite(target_direction, first_frame) if preview_ok else before.duplicate()
		var selected_channels: Array[String] = []
		for channel in ["rotation", "offset", "anchor"]:
			if channels[channel]: selected_channels.append({"rotation": "rotação", "offset": "offset", "anchor": "articulação"}[channel])
		dialog_window.hide()
		dialog_window.queue_free()
		show_comparison("Prévia da interpolação do rig", before, after,
			str(proposal.message) + "\nCanais: " + ", ".join(selected_channels) + ".\nPrévia do quadro %d; articulações são guias e não alteram o raster." % (first_frame + 1),
			func():
				if doc.get_instance_id() != target_instance or not rig_interpolator.apply(doc, proposal):
					notify("A proposta ficou desatualizada; nenhuma pose foi aplicada.")
					return
				refresh_all()
				notify("Poses intermediárias aplicadas em uma operação. Ctrl+Z desfaz tudo.")
		)
	)
	dialog_window.canceled.connect(dialog_window.queue_free)
	add_child(dialog_window)
	dialog_window.popup_centered(Vector2i(540, 300))

func add_joint_dialog() -> void:
	stop_playback()
	var popup := ConfirmationDialog.new()
	popup.title = "Nova articulação"
	var body := column(popup)
	label("Nome técnico (letras, números, _ ou -; até 24 caracteres)", body)
	var input := LineEdit.new()
	input.text = "joint_%d" % (doc.anchors.size() + 1)
	input.max_length = 24
	body.add_child(input)
	label("A articulação começa no centro do quadro. Depois, selecione a ferramenta Âncora e clique para posicioná-la.", body, 12)
	var target_instance: int = doc.get_instance_id()
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance:
			notify("O documento mudou; crie a articulação no documento atual.")
		elif doc.add_anchor(input.text, Vector2i(doc.width / 2, doc.height / 2)):
			canvas.anchor_name = input.text
			refresh_all()
			notify("Articulação criada. Posicione-a com a ferramenta Âncora.")
		else: notify("Nome duplicado/inválido, quadro cheio ou limite de 32 articulações atingido.")
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(500, 190))

func remove_selected_joint() -> void:
	var name: String = canvas.anchor_name
	if doc.remove_anchor(name):
		canvas.anchor_name = "hand"
		refresh_all()
	else:
		notify("A articulação é estrutural ou está ligada a uma camada. Desvincule a camada antes de removê-la.")

func create_clip_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var popup := ConfirmationDialog.new()
	popup.title = "Novo clip"
	var fields := column(popup)
	label("Nome: letras sem acentos, números, _ ou -", fields)
	var name_field := LineEdit.new()
	name_field.text = "idle"
	fields.add_child(name_field)
	label("Primeiro / último frame (1–%d)" % doc.frames, fields)
	var limits := row(fields)
	var first := spin(limits, 1, doc.frames, 1, func(_v): pass)
	var last_frame := spin(limits, 1, doc.frames, doc.frames, func(_v): pass)
	popup.confirmed.connect(func():
		if doc.add_clip(name_field.text, int(first.value) - 1, int(last_frame.value) - 1): refresh_all()
		else: notify("Nome duplicado/inválido, intervalo inválido ou limite de clips atingido.")
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(440, 220))

func rename_clip_dialog() -> void:
	stop_playback()
	var target_instance: int = doc.get_instance_id()
	var target_index: int = int(doc.animation.active)
	var popup := ConfirmationDialog.new()
	popup.title = "Renomear clip"
	var input := LineEdit.new()
	input.text = doc.clip().name
	input.max_length = 40
	input.placeholder_text = "Letras, números, _ ou -"
	popup.add_child(input)
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or int(doc.animation.active) != target_index:
			notify("A seleção mudou; renomeie o clip selecionado novamente.")
		elif doc.rename_clip(input.text): refresh_all()
		else: notify("Nome inválido, repetido ou sem alterações.")
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(400, 120))

func delete_clip_dialog() -> void:
	stop_playback()
	if doc.animation.clips.size() <= 1:
		notify("O documento precisa manter pelo menos um clip.")
		return
	var target_instance: int = doc.get_instance_id()
	var target_index: int = int(doc.animation.active)
	var popup := ConfirmationDialog.new()
	popup.title = "Excluir clip"
	popup.dialog_text = "Excluir '%s'? Os pixels permanecem no documento." % doc.clip().name
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance or int(doc.animation.active) != target_index:
			notify("A seleção mudou; exclua o clip selecionado novamente.")
		elif doc.delete_clip(): refresh_all()
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(420, 140))

func event_dialog() -> void:
	stop_playback()
	canvas.cancel_gesture()
	var target_instance: int = doc.get_instance_id()
	var target_cel: String = doc.cel_key()
	var popup := ConfirmationDialog.new()
	popup.title = "Eventos da direção/frame atual"
	var body := column(popup)
	label("Um evento por linha. São exportados como dados, sem lógica de dano.", body)
	var events := TextEdit.new()
	events.custom_minimum_size = Vector2(520, 180)
	events.text = "\n".join(doc.animation.events.get(doc.cel_key(), []))
	body.add_child(events)
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_instance: notify("O documento mudou; evento não foi aplicado."); popup.queue_free(); return
		doc.checkpoint()
		var values: Array = []
		for line in events.text.split("\n"):
			if not line.strip_edges().is_empty() and values.size() < 64: values.append(line.strip_edges().left(200))
		doc.animation.events[target_cel] = values
		popup.queue_free(); update_title()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered()

func build_quality() -> void:
	var page := column(tabs)
	page.name = "Qualidade e versões"
	label("AVALIAÇÃO TÉCNICA ≠ APROVAÇÃO ARTÍSTICA", page, 21)
	quality_report = RichTextLabel.new()
	quality_report.custom_minimum_size.y = 110
	page.add_child(quality_report)
	button("Diagnosticar cel atual", page, refresh_quality)
	label("PORTÃO TÉCNICO DE PERSONAGEM", page, 16)
	label("Verifica idle respirando, pulo e ataque nas oito direções, tempos e contatos. Não dá nota nem aprovação artística.", page, 12)
	character_audit_button = button("Testar animações do personagem", page, run_character_audit)
	character_audit_report = RichTextLabel.new()
	character_audit_report.custom_minimum_size.y = 120
	page.add_child(character_audit_report)
	reopen_rejected_candidate_button = button("Abrir nova revisão após alterar a arte", page, func():
		if quality.reopen_rejected_candidate(doc):
			character_audit_result.clear()
			character_audit_revision = -1
			refresh_all()
			notify("Nova versão marcada para revisão. Ela ainda não está aprovada.")
		else: notify(quality.error)
	)
	label("Notas atribuídas pelo revisor, de 0 a 100. Geral ≥85; cada critério ≥75.", page)
	var scores := row(page)
	for text in ["Anatomia 35%", "Paleta 25%", "Movimento 25%", "Luz/material 15%"]:
		var field := column(scores)
		label(text, field)
		quality_scores.append(spin(field, 0, 100, 0, func(_v): pass))
	reviewer = LineEdit.new()
	reviewer.placeholder_text = "Identificação do revisor"
	page.add_child(reviewer)
	human_check = check("Revisei a arte e aprovo explicitamente esta versão", page, func(_v): pass)
	var actions := row(page)
	button("Registrar versão aprovada", actions, func():
		var values: Array = quality_scores.map(func(s): return s.value)
		if quality.approve(doc, values, reviewer.text, human_check.button_pressed): human_check.set_pressed_no_signal(false); refresh_all(); notify("Versão aprovada preservada na biblioteca, separada do cache.")
		else: notify(quality.error)
	)
	character_approval_button = button("Aprovar personagem após teste técnico", page, func():
		var values: Array = quality_scores.map(func(s): return s.value)
		if quality.approve(doc, values, reviewer.text, human_check.button_pressed, true):
			human_check.set_pressed_no_signal(false)
			character_audit_result = character_audit.evaluate(doc)
			character_audit_revision = doc.revision
			refresh_all()
			notify("Personagem aprovado pelo revisor e salvo com o portão técnico concluído.")
		else: notify(quality.error)
	)
	button("Comparar selecionada", actions, func():
		if version_list.get_selected_items().is_empty(): return
		var version: Dictionary = available_versions[version_list.get_selected_items()[0]]
		var comparison: Dictionary = quality.compare(doc, version.path)
		if comparison.has("error"): notify(comparison.error); return
		show_comparison("Comparação com versão aprovada", comparison.before, comparison.after, "%d pixels diferentes na composição atual; isso não determina qualidade." % comparison.changed)
	)
	button("Restaurar selecionada", actions, func():
		if version_list.get_selected_items().is_empty(): return
		var version: Dictionary = available_versions[version_list.get_selected_items()[0]]
		selected_open(version.path, true)
	)
	version_list = ItemList.new()
	version_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(version_list)
	label("Indicadores de pixels são sugestões. Não estimam anatomia, fluidez ou qualidade artística automaticamente.", page, 12)
	var catalog_controls := row(page)
	var python_field := LineEdit.new()
	python_field.placeholder_text = "Opcional: caminho do executável Python 3.11+ para catálogo SQLite"
	python_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_controls.add_child(python_field)
	button("Atualizar índice SQLite", catalog_controls, func():
		catalog.python_path = python_field.text.strip_edges()
		if not catalog.index(doc, path): notify("Informe Python existente; o editor funciona sem esse serviço.")
	)

func refresh_quality() -> void:
	if quality_report == null: return
	if reopen_rejected_candidate_button != null:
		reopen_rejected_candidate_button.disabled = str(doc.art.get("candidate_status", "")) != "rejected"
	var metrics: Dictionary = precision.diagnose(doc.current(), doc.palette)
	quality_report.text = "Integridade estrutural: " + ("OK" if doc.validate().is_empty() else "; ".join(doc.validate())) + "\nCores fora da paleta: %d • Pixels isolados: %d • Alfa parcial: %d\nReferências dependentes desatualizadas: %d" % [metrics.outside_palette, metrics.isolated_pixels, metrics.partial_alpha, doc.manifest.dependencies.filter(func(item): return item.get("stale", false)).size()]
	refresh_character_audit_view()
	available_versions = quality.versions(doc)
	version_list.clear()
	for version in available_versions: version_list.add_item(version.id)

func run_character_audit() -> Dictionary:
	character_audit_result = character_audit.evaluate(doc)
	character_audit_revision = doc.revision
	refresh_character_audit_view()
	return character_audit_result

func refresh_character_audit_view() -> void:
	if character_audit_report == null: return
	if character_audit_result.is_empty():
		character_audit_report.text = "Ainda não executado."
		return
	if character_audit_revision != doc.revision:
		character_audit_report.text = "Resultado desatualizado após edição. Execute o teste novamente."
		return
	var checks: Array = character_audit_result.checks
	var passed: int = checks.filter(func(item): return item.passed).size()
	var art_status := str(character_audit_result.get("art_candidate_status", "unreviewed"))
	var approval_text := "Aprovação artística: pendente de revisão humana."
	if art_status == "approved": approval_text = "Aprovação artística: aprovada por revisor humano para esta versão."
	var lines: Array[String] = ["%s — %d/%d verificações técnicas" % [character_audit_result.summary, passed, checks.size()], approval_text]
	if art_status == "rejected":
		lines.append("ARTE REPROVADA — fixture apenas para teste técnico.")
		if not str(character_audit_result.get("review_feedback", "")).is_empty(): lines.append(str(character_audit_result.review_feedback))
	elif art_status == "revision_pending":
		lines.append("Nova revisão iniciada; a arte ainda aguarda avaliação humana.")
	for issue in character_audit_result.issues:
		lines.append("• " + str(issue))
	character_audit_report.text = "\n".join(lines)

func build_acervo() -> void:
	var page := column(tabs)
	page.name = "Acervo Arton"
	label("BASES E CAMADAS DO ACERVO", page, 23)
	label("Importe bases e peças de uma biblioteca modular com os encaixes registrados.", page)
	var path_row := row(page)
	art_library_path = LineEdit.new()
	art_library_path.text = "res://examples/arton/biblioteca.json"
	art_library_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(art_library_path)
	button("Escolher biblioteca", path_row, func(): browse("arton_library"))
	button("Ler catálogo", path_row, func(): load_art_library(art_library_path.text))
	var actions := row(page)
	art_family = choice([], actions, func(_i): refresh_art_library_info())
	button("Importar base + peças compatíveis", actions, func():
		if art_family.item_count == 0: notify("Selecione uma biblioteca modular válida."); return
		var folder := ProjectSettings.globalize_path("user://imports").path_join("arton_" + str(Time.get_ticks_usec()))
		queue.enqueue(art_library_path.text, folder, 100, [], "import_arton", {"family": art_family.get_item_text(art_family.selected), "garments": true})
		queue.running = true
		notify("Importação iniciada. Em Lotes, selecione a tarefa concluída e clique Abrir importação.")
	)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	art_library_preview = TextureRect.new()
	art_library_preview.custom_minimum_size = Vector2(320, 320)
	art_library_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_library_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art_library_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art_library_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(art_library_preview)
	art_library_info = RichTextLabel.new()
	art_library_info.custom_minimum_size.x = 420
	art_library_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(art_library_info)
	label("Os exemplos são protótipos estáticos, sem nova aprovação artística ou animação criada.", page)

func load_art_library(library_path: String) -> void:
	var importer := Arton.new()
	var data: Dictionary = importer.read_library(library_path)
	if data.is_empty():
		if art_library_info != null: art_library_info.text = importer.error + "\nEste adaptador atende o formato modular; bibliotecas históricas de equipamentos exigem outro adaptador."
		return
	art_library_path.text = library_path
	art_library_data = data
	art_family.clear()
	for key in data.families: art_family.add_item(key)
	if art_family.item_count > 0: art_family.select(0); refresh_art_library_info()

func refresh_art_library_info() -> void:
	if art_family.item_count == 0: return
	var family: String = art_family.get_item_text(art_family.selected)
	var entry: Dictionary = art_library_data.families[family]
	art_library_info.text = "Família: " + family + "\nMorfologia: " + str(entry.get("morphology", "não informada")) + "\nPose: " + str(art_library_data.get("pose", "não informada")) + "\nEstado da fonte: " + str(entry.get("status", "não avaliado")) + "\nEsqueleto completo declarado: " + str(entry.get("complete_skeleton", false)) + "\n\nOito vistas são importadas como direções, em um único frame estático. Base mantém RGBA e resolução; roupas candidatas usam a calibração registrada na fonte e começam ocultas.\n\nA direção de arte Arton é preservada como perfil próprio, sem substituir as definições dos outros projetos."
	if entry.get("views") is Array and not entry.views.is_empty():
		var importer := Arton.new()
		var image: Image = importer.image(art_library_path.text, entry.views[0].get("file"))
		if image != null: art_library_preview.texture = ImageTexture.create_from_image(image)

func _store_workspace_view() -> void:
	if workspace == null or canvas == null: return
	var record: Dictionary = workspace.find(_bound_id)
	if record.is_empty() or record.view.get("fit", false): return
	record.view = {"zoom": canvas.zoom, "pan": [canvas.pan.x, canvas.pan.y], "fit": false}

func _activate_document(record: Dictionary) -> void:
	_store_workspace_view()
	canvas.cancel_gesture()
	_bound_id = record.id
	doc = record.doc
	path = record.path
	playing = false
	clock.reset()
	play_button.text = "▶ Play"
	world.playing = false
	world.clock.reset()
	world.invalidate()
	preview_toggle.set_pressed_no_signal(false)
	canvas.doc = doc
	canvas.zoom = float(record.view.get("zoom", 14))
	var offset: Array = record.view.get("pan", [0, 0])
	canvas.pan = Vector2(float(offset[0]), float(offset[1]))
	_history_revision = -1
	refresh_all()
	if record.view.get("fit", false): _fit_document(record.id)

func _fit_document(id: String) -> void:
	await get_tree().process_frame
	if workspace == null or workspace.active_id != id: return
	var record: Dictionary = workspace.find(id)
	if record.is_empty(): return
	canvas.fit_canvas()
	record.view.fit = false
	_store_workspace_view()

func _refresh_document_tabs() -> void:
	if document_tabs == null or workspace == null: return
	_binding_tabs = true
	if document_tabs.tab_count != workspace.records.size():
		document_tabs.clear_tabs()
		for record in workspace.records: document_tabs.add_tab(record.title)
	for i in workspace.records.size():
		var record: Dictionary = workspace.records[i]
		var text: String = record.title + (" •" if record.doc.dirty else "")
		if document_tabs.get_tab_title(i) != text: document_tabs.set_tab_title(i, text)
		if record.id == workspace.active_id: document_tabs.current_tab = i
	_binding_tabs = false

func _on_workspace_persisted(kind: String, id: String, result: int, target: String) -> void:
	if kind == "export_snapshot":
		var export_target: Dictionary = _export_targets.get(target, {})
		_export_targets.erase(target)
		if result == OK and not export_target.is_empty():
			var parameters := {"profile": str(export_target.get("profile", "playable"))}
			if queue.enqueue(target, str(export_target.folder), 100, [], "export", parameters) != "": queue.running = true; notify("Exportação %s iniciada; acompanhe em Lotes." % str(parameters.profile))
			else: notify("A fila de exportação atingiu o limite de tarefas.")
		elif result != OK: notify("Falha ao preparar exportação: " + error_string(result))
		return
	if kind == "checkpoint":
		if result != OK: notify("Recuperação automática falhou: " + error_string(result))
		return
	if result != OK:
		notify("Não foi possível salvar: " + error_string(result))
		_save_all_ids.clear(); _quit_after_save = false; _pending_close_id = ""
		return
	var record: Dictionary = workspace.find(id)
	if not record.is_empty() and workspace.active_id == id: path = record.path; update_title()
	notify("Arquivo salvo; novas alterações continuam pendentes." if not record.is_empty() and record.doc.dirty else "Projeto salvo.")
	if _pending_close_id == id:
		_pending_close_id = ""
		if not record.is_empty() and not record.doc.dirty: workspace.close_document(id)
		else: notify("A aba recebeu novas alterações durante o salvamento e continua aberta.")
	if not _save_all_ids.is_empty() and _save_all_ids[0] == id:
		if not record.is_empty() and record.doc.dirty:
			_save_all_ids.clear(); _quit_after_save = false
			notify("Há edições posteriores à cópia salva. Revise antes de encerrar.")
		else: _save_all_ids.pop_front(); _continue_save_all()

func request_close_document(id: String) -> void:
	var record: Dictionary = workspace.find(id)
	if record.is_empty(): return
	if not record.doc.dirty: workspace.close_document(id); return
	var popup := ConfirmationDialog.new()
	popup.title = "Fechar " + record.title
	popup.dialog_text = "Este documento tem alterações não salvas."
	popup.get_ok_button().text = "Salvar e fechar"
	popup.get_cancel_button().text = "Cancelar"
	popup.add_button("Descartar alterações", true, "discard")
	popup.confirmed.connect(func():
		_pending_close_id = id
		workspace.activate(id)
		save_project()
		popup.queue_free()
	)
	popup.custom_action.connect(func(action):
		if action == "discard": workspace.close_document(id, true); popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(460, 160))

func start_save_all(quit_when_done: bool = false) -> void:
	_store_workspace_view()
	_save_all_ids.clear()
	_quit_after_save = quit_when_done
	for record in workspace.records:
		if record.doc.dirty or record.path == "": _save_all_ids.append(record.id)
	_continue_save_all()

func _continue_save_all() -> void:
	while not _save_all_ids.is_empty() and workspace.find(_save_all_ids[0]).is_empty(): _save_all_ids.pop_front()
	if _save_all_ids.is_empty():
		workspace.request_checkpoint()
		if _quit_after_save:
			_quit_after_save = false
			if workspace.records.any(func(record): return record.doc.dirty): notify("Há novas alterações em outra aba. Revise antes de encerrar.")
			else: get_tree().quit()
		else: notify("Todos os documentos solicitados foram salvos.")
		return
	workspace.activate(_save_all_ids[0])
	save_project()

func restore_workspace() -> void:
	_store_workspace_view()
	var count: int = workspace.restore_session()
	notify("%d documentos recuperados. A cópia pode ser anterior às últimas edições." % count if count > 0 else workspace.error)

func request_quit() -> void:
	if workspace == null: get_tree().quit(); return
	_store_workspace_view()
	if not workspace.records.any(func(record): return record.doc.dirty):
		workspace.request_checkpoint(); get_tree().quit(); return
	var popup := ConfirmationDialog.new()
	popup.title = "Encerrar Sprite Forge Studio"
	popup.dialog_text = "Há documentos com alterações não salvas. A recuperação contém somente a última cópia concluída."
	popup.get_ok_button().text = "Salvar todos e sair"
	popup.get_cancel_button().text = "Cancelar"
	popup.add_button("Sair sem salvar", true, "discard")
	popup.confirmed.connect(func(): start_save_all(true); popup.queue_free())
	popup.custom_action.connect(func(action):
		if action == "discard": get_tree().quit()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(580, 170))

func history_dialog() -> void:
	var source_id: String = workspace.active_id
	var popup := ConfirmationDialog.new()
	popup.title = "Histórico do documento"
	var body := column(popup)
	label("Selecione até onde desfazer. Operações recentes aparecem primeiro.", body)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(500, 300)
	for i in range(doc.undo_stack.size() - 1, -1, -1): list.add_item(str(doc.undo_stack[i].get("label", "Edição")))
	body.add_child(list)
	popup.get_ok_button().text = "Desfazer até selecionada"
	popup.confirmed.connect(func():
		if workspace.active_id == source_id and not list.get_selected_items().is_empty():
			for i in list.get_selected_items()[0] + 1: doc.undo()
			refresh_all()
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(560, 400))

func select_drawing_tool(index: int) -> void:
	if canvas == null: return
	canvas.cancel_gesture()
	canvas.tool = DRAWING_TOOLS[index]
	tool_picker.select(index)
	canvas.rig = index == 7 or (rig_control != null and rig_control.button_pressed)
	canvas.queue_redraw()

func copy_pixels() -> void:
	doc.copy_pixels()
	shared_clipboard = doc.clipboard.duplicate()
	notify("Região copiada; disponível para colar em outras abas.")

func paste_pixels() -> void:
	if shared_clipboard == null: notify("A área de transferência de pixels está vazia."); return
	stop_playback()
	canvas.cancel_gesture()
	doc.clipboard = shared_clipboard.duplicate()
	if doc.paste_pixels(): edited()
	else: notify("A camada está bloqueada.")

func stop_playback() -> void:
	playing = false
	clock.reset()
	preview_sequence.clear()
	if preview_sequence_status != null: preview_sequence_status.text = ""
	if play_button != null: play_button.text = "▶ Play"

func start_clip_sequence(indices: Array, repeat_sequence: bool = false) -> bool:
	if not clock.valid_sequence(doc, indices): return false
	stop_playback()
	canvas.cancel_gesture()
	preview_sequence = indices.duplicate()
	preview_sequence_repeat = repeat_sequence
	preview_sequence_slot = preview_sequence.size() - 1 if reverse_playback else 0
	preview_sequence_revision = doc.revision
	preview_sequence_document = doc.get_instance_id()
	doc.animation.active = int(preview_sequence[preview_sequence_slot])
	doc.frame = int(doc.clip().frames[-1] if reverse_playback else doc.clip().frames[0])
	refresh_all()
	playing = true
	play_button.text = "Ⅱ Pause"
	preview_sequence_status.text = "Sequência %d/%d · %s" % [preview_sequence_slot + 1, preview_sequence.size(), doc.clip().name]
	return true

func advance_animation_preview(delta: float) -> void:
	if not playing: return
	if not preview_sequence.is_empty() and (doc.revision != preview_sequence_revision or doc.get_instance_id() != preview_sequence_document):
		stop_playback()
		return
	var result: Dictionary
	if preview_sequence.is_empty():
		result = clock.tick(doc, doc.frame, delta, playback_speed, reverse_playback)
	else:
		result = clock.tick_sequence(doc, preview_sequence, preview_sequence_slot, doc.frame, delta, playback_speed, reverse_playback, preview_sequence_repeat)
		preview_sequence_slot = int(result.slot)
		if int(doc.animation.active) != int(result.clip_index):
			doc.animation.active = int(result.clip_index)
			clip_picker.select(int(result.clip_index))
			loop_control.set_pressed_no_signal(doc.clip().loop)
			timeline_view.refresh()
		preview_sequence_status.text = "Sequência %d/%d · %s" % [preview_sequence_slot + 1, preview_sequence.size(), doc.clip().name]
	if result.frame != doc.frame or not result.entered.is_empty():
		doc.frame = result.frame
		canvas.refresh()
		refresh_frame_highlight()
	if result.finished: stop_playback()
	if show_animation_events:
		for entered_frame in result.entered:
			var events: Array = doc.animation.events.get(doc.cel_key(doc.direction, entered_frame), [])
			if not events.is_empty(): notify("Frame %d • eventos: %s" % [entered_frame + 1, ", ".join(events)])

func open_clip_sequence_dialog() -> void:
	stop_playback()
	var target_document: int = doc.get_instance_id()
	var target_revision: int = doc.revision
	var popup := ConfirmationDialog.new()
	popup.name = "ClipSequenceDialog"
	popup.title = "Prévia de transições entre clips"
	popup.get_ok_button().text = "Reproduzir"
	var fields := column(popup)
	var help := label("Adicione os clips na ordem desejada. Cada entrada toca uma vez; o Loop do clip não interrompe a sequência. Play/Pause, velocidade, reverso e direção continuam disponíveis.", fields)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 560
	var options := row(fields)
	var available := OptionButton.new()
	for clip in doc.animation.clips: available.add_item(str(clip.name))
	options.add_child(available)
	var entries: Array = []
	var listing := ItemList.new()
	listing.name = "SequenceEntries"
	listing.custom_minimum_size = Vector2(440, 180)
	button("Adicionar", options, func():
		if entries.size() >= 32: return
		entries.append(available.selected)
		listing.add_item(available.get_item_text(available.selected))
		listing.select(entries.size() - 1)
	).name = "AddSequenceClip"
	available.name = "AvailableClips"
	fields.add_child(listing)
	var actions := row(fields)
	for direction in [-1, 1]:
		var shift: int = direction
		button("Subir" if shift < 0 else "Descer", actions, func():
			var selected := listing.get_selected_items()
			if selected.is_empty(): return
			var source: int = selected[0]
			var destination: int = source + shift
			if destination < 0 or destination >= entries.size(): return
			var old: int = entries[source]
			entries[source] = entries[destination]; entries[destination] = old
			var text := listing.get_item_text(source)
			listing.set_item_text(source, listing.get_item_text(destination)); listing.set_item_text(destination, text)
			listing.select(destination)
		).name = "MoveSequenceUp" if shift < 0 else "MoveSequenceDown"
	button("Remover", actions, func():
		var selected := listing.get_selected_items()
		if selected.is_empty(): return
		entries.remove_at(selected[0]); listing.remove_item(selected[0])
	).name = "RemoveSequenceClip"
	var repeat_control := check("Repetir sequência completa", fields, func(_value): pass)
	repeat_control.name = "RepeatSequence"
	popup.confirmed.connect(func():
		if doc.get_instance_id() != target_document or doc.revision != target_revision:
			notify("O documento mudou; configure a sequência novamente.")
		elif not start_clip_sequence(entries, repeat_control.button_pressed):
			notify("Adicione de 1 a 32 entradas válidas à sequência.")
		popup.queue_free()
	)
	popup.canceled.connect(popup.queue_free)
	add_child(popup)
	popup.popup_centered(Vector2i(660, 410))

func toggle_playback() -> void:
	canvas.cancel_gesture()
	playing = not playing
	play_button.text = "Ⅱ Pause" if playing else "▶ Play"

func seek_frame(frame: int) -> void:
	stop_playback()
	canvas.cancel_gesture()
	doc.frame = frame
	canvas.refresh()
	refresh_layer()
	refresh_frame_highlight()


