extends VBoxContainer
signal sample_requested
signal current_requested
signal editor_requested
const Review = preload("res://core/animation_review.gd")
const Surface = preload("res://ui/review_sprite.gd")
var review = Review.new()
var surfaces: Array = []
var details: Array = []
var info: Label
var bleed_coverage: Label
var play: Button
var direction_picker: OptionButton

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var title := Label.new(); title.text = "REVISÃO DE MOVIMENTOS"; title.add_theme_font_size_override("font_size", 24); add_child(title)
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(info)
	bleed_coverage = Label.new(); bleed_coverage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bleed_coverage.add_theme_color_override("font_color", Color("ffb286")); add_child(bleed_coverage)
	var toolbar := HFlowContainer.new(); toolbar.add_theme_constant_override("h_separation", 8); add_child(toolbar)
	_button("Carregar Sentinela atual", toolbar, func(): sample_requested.emit())
	_button("Revisar projeto atual", toolbar, func(): current_requested.emit())
	_button("Abrir no editor", toolbar, func(): editor_requested.emit())
	direction_picker = OptionButton.new()
	for direction in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]: direction_picker.add_item(direction)
	direction_picker.select(4); toolbar.add_child(direction_picker)
	direction_picker.item_selected.connect(func(index): review.direction = index; refresh())
	play = _button("Pausar", toolbar, func(): review.playing = not review.playing; refresh())
	_button("◀ Quadro", toolbar, func(): review.step(-1); refresh())
	_button("Quadro ▶", toolbar, func(): review.step(1); refresh())
	_button("Reiniciar", toolbar, func(): review.restart(); refresh())
	var cards := HBoxContainer.new(); cards.add_theme_constant_override("separation", 12); cards.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(cards)
	for action in ["Idle • respiração", "Pulo", "Ataque"]:
		var card := VBoxContainer.new(); card.custom_minimum_size.x = 260; card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cards.add_child(card)
		var heading := Label.new(); heading.text = action; heading.add_theme_font_size_override("font_size", 20); card.add_child(heading)
		var surface = Surface.new(); surface.custom_minimum_size.y = 280; surface.size_flags_vertical = Control.SIZE_EXPAND_FILL; surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; card.add_child(surface); surfaces.append(surface)
		var detail := Label.new(); detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; card.add_child(detail); details.append(detail)
	var note := Label.new(); note.text = "A prévia repete pulo e ataque para revisão. Contagem de poses considera os pixels reais; holds não são novos desenhos."; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)

func _button(text: String, parent: Node, action: Callable) -> Button:
	var button := Button.new(); button.text = text; button.pressed.connect(action); parent.add_child(button); return button

func bind(doc: RefCounted) -> bool:
	if not review.bind(doc): review.playing = false; refresh(); return false
	review.playing = true
	refresh(); return true

func refresh() -> void:
	play.disabled = review.document == null
	if review.document == null:
		info.text = review.error
		bleed_coverage.text = ""
		for surface in surfaces: surface.show_image(null)
		for detail in details: detail.text = ""
		return
	var doc: RefCounted = review.document
	var state: String = {"approved": "aprovado", "rejected": "reprovado", "candidate": "candidato"}.get(str(doc.art.get("candidate_status", "candidate")), "em revisão")
	info.text = "%s · %d×%d · %s\nEstado artístico registrado: %s. A reprodução e os testes não concedem nova aprovação." % [doc.manifest.name, doc.width, doc.height, doc.DIRECTIONS[review.direction], state]
	bleed_coverage.text = _bleed_coverage_text(doc)
	play.text = "Pausar" if review.playing else "Reproduzir"
	for index in surfaces.size():
		surfaces[index].show_image(review.image(index))
		var metric: Dictionary = review.metrics(index)
		details[index].text = "Quadro %d/%d · %d poses distintas\n%d ms por ciclo" % [metric.position, metric.frames, metric.poses, metric.duration_ms]

func _bleed_coverage_text(doc: RefCounted) -> String:
	var fix: Dictionary = doc.art.get("bleed_fix", {})
	if fix.is_empty(): return "Mistura visual entre ações: não verificada. Isolamento de figuras: sem cobertura registrada."
	var coverage: Dictionary = fix.get("coverage", {})
	var pieces: Array[String] = []
	for action in ["idle_breathing", "jump", "attack"]:
		var directions: Array = coverage.get(action, [])
		var label: String = {"idle_breathing": "idle", "jump": "pulo", "attack": "ataque"}[action]
		if directions.is_empty():
			pieces.append(label + ": sem reparo")
		else:
			pieces.append(label + ": " + ", ".join(directions) + " (%d/8 vistas)" % directions.size())
	return "Mistura visual entre idle, pulo e ataque: não verificada. Isolamento de figuras — " + "; ".join(pieces) + ". Cobertura parcial não comprova correção das vistas pendentes."

func _process(delta: float) -> void:
	if is_visible_in_tree() and review.tick(delta): refresh()
