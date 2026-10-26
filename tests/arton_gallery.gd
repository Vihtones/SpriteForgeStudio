extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func add_label(parent: Node, text: String, point: Vector2, font_size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2560, 1730)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := Node2D.new()
	viewport.add_child(canvas)
	var background := ColorRect.new()
	background.size = Vector2(2560, 1730)
	background.color = Color("152329")
	canvas.add_child(background)
	add_label(canvas, "ARTON / IMPORTAÇÃO NO SPRITE FORGE — VISTAS ESTÁTICAS, NÃO ANIMAÇÃO", Vector2(24, 14), 27)
	var storage := preload("res://core/storage.gd").new()
	var rows: Array = [["humanoide", 0.75], ["humanoide", 1.0], ["humanoide", 1.25], ["canideo", 1.0], ["felino", 1.0]]
	for row in rows.size():
		var doc = storage.load_document("res://examples/arton_projects/" + rows[row][0] + ".sfs.json")
		if doc == null: quit(1); return
		if doc.layers.size() > 1: doc.layers[1].visible = true
		var factor: float = rows[row][1]
		var top: float = 62 + row * 325
		add_label(canvas, rows[row][0] + (" + colete candidato" if row < 3 else " — anatomia própria") + " / " + str(roundi(factor * 100)) + "%", Vector2(24, top), 21)
		for d in 8:
			var sprite := Sprite2D.new()
			sprite.texture = ImageTexture.create_from_image(doc.composite(d, 0))
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.centered = false
			sprite.scale = Vector2.ONE * factor
			sprite.position = Vector2(d * 320 + 160 - 128 * factor, top + 303 - 240 * factor)
			canvas.add_child(sprite)
			add_label(canvas, doc.DIRECTIONS[d], Vector2(d * 320 + 10, top + 30), 17)
	add_label(canvas, "Bases RGBA preservadas em 256×256. Escalas de exibição uniformes. Encaixe do colete reproduz calibração da fonte; revisão artística continua pendente.", Vector2(24, 1700), 17)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://test_results/arton-gallery.png")
	viewport.free()
	quit()
