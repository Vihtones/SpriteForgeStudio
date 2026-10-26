extends SceneTree
func _initialize() -> void:
	var rows: Array = []
	for side in [32, 64, 128]:
		var doc = preload("res://core/document.gd").new()
		doc.width = side
		doc.height = side
		doc.layers.clear()
		for i in 3:
			doc.add_layer("Layer " + str(i))
			doc.current().fill(Color(0.1 * i, 0.3, 0.4, 0.5))
		var times: Array = []
		for i in 60:
			var start := Time.get_ticks_usec()
			var image: Image = doc.composite()
			if image.get_width() != side: quit(1); return
			times.append(Time.get_ticks_usec() - start)
		times.sort()
		rows.append({"size": side, "layers": 3, "frames": 4, "directions": 8, "samples": times.size(), "median_us": times[30], "p95_us": times[56], "max_us": times[-1]})
	var result := {"engine": Engine.get_version_info().string, "processor": OS.get_processor_name(), "headless": DisplayServer.get_name() == "headless", "static_memory_bytes": OS.get_static_memory_usage(), "static_peak_bytes": OS.get_static_memory_peak_usage(), "cpu_composition": rows, "note": "CPU composition microbenchmark; not an FPS, VRAM or full hardware certification."}
	var file := FileAccess.open("res://test_results/benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print(JSON.stringify(result))
	quit()
