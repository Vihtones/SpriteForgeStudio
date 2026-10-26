extends SceneTree
const Doc = preload("res://core/document.gd")
const Shapes = preload("res://core/pixel_shapes.gd")
var checks: Array[Dictionary] = []
var failed := 0

func expect(value: bool, name: String) -> void:
	checks.append({"name": name, "passed": value})
	if value: print("PASS ", name)
	else: failed += 1; printerr("FAIL ", name)

func _initialize() -> void:
	var shapes = Shapes.new()
	var outline: Array[Vector2i] = shapes.rasterize("rectangle", Vector2i(2, 3), Vector2i(6, 6))
	var fill: Array[Vector2i] = shapes.rasterize("rectangle", Vector2i(2, 3), Vector2i(6, 6), true)
	expect(outline.size() == 14 and not outline.has(Vector2i(4, 4)), "retângulo vazado inclui bordas sem preencher o interior")
	expect(fill.size() == 20 and fill.has(Vector2i(4, 4)), "retângulo preenchido inclui todos os pixels dos limites")
	var ellipse: Array[Vector2i] = shapes.rasterize("ellipse", Vector2i(3, 3), Vector2i(9, 7))
	var ellipse_fill: Array[Vector2i] = shapes.rasterize("ellipse", Vector2i(3, 3), Vector2i(9, 7), true)
	var symmetric := true
	for point in ellipse_fill:
		symmetric = symmetric and ellipse_fill.has(Vector2i(12 - point.x, 10 - point.y))
	expect(not ellipse.is_empty() and not ellipse.has(Vector2i(6, 5)) and ellipse_fill.size() > ellipse.size(), "elipse vazada separa interior e contorno")
	expect(symmetric, "elipse preenchida mantém simetria bilateral na grade")
	expect(shapes.rasterize("ellipse", Vector2i(4, 4), Vector2i(4, 8), true).size() == 5, "elipse degenerada de um pixel de largura continua válida")
	var doc = Doc.new()
	var layer: Dictionary = doc.layers[0]
	var key := doc.cel_key(0, 0)
	doc.selection = Rect2i(2, 2, 4, 4)
	doc.rig.protected_pixels = {key: [2 * doc.width + 3]}
	var written: int = shapes.apply(doc, "rectangle", Vector2i(2, 2), Vector2i(6, 5), Color.RED, false, true)
	expect(written == 15 and doc.current().get_pixel(2, 2) == Color.RED and doc.current().get_pixel(3, 2).a == 0.0 and doc.current().get_pixel(5, 5) == Color.RED, "pintura preenchida respeita seleção e máscara protegida")
	doc.selection = Rect2i()
	doc.rig.protected_pixels.clear()
	shapes.apply(doc, "rectangle", Vector2i(2, 2), Vector2i(4, 3), Color.BLUE, true, true)
	expect(doc.current().get_pixel(29, 2) == Color.BLUE and doc.current().get_pixel(2, 3) == Color.BLUE, "espelho replica formas ao redor do eixo vertical do canvas")
	var before_lock: PackedByteArray = doc.current().get_data()
	doc.art.locked = true
	expect(shapes.apply(doc, "ellipse", Vector2i(8, 8), Vector2i(12, 12), Color.GREEN, false, true) == 0 and doc.current().get_data() == before_lock, "Art Lock impede rasterização geométrica")
	doc.art.locked = false
	layer.locked = true
	expect(shapes.apply(doc, "rectangle", Vector2i(8, 8), Vector2i(12, 12), Color.GREEN, false, true) == 0, "camada bloqueada impede rasterização geométrica")
	var report := {"passed": checks.size() - failed, "failed": failed, "checks": checks}
	var file := FileAccess.open("res://test_results/pixel-shapes-report.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("Pixel shapes: %d passed, %d failed" % [report.passed, failed])
	quit(1 if failed else 0)
