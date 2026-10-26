extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ui = load("res://main.tscn").instantiate()
	root.add_child(ui)
	for i in 12: await process_frame
	var times: Array = []
	var previous := Time.get_ticks_usec()
	for i in 60:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
	times.sort()
	var method := RenderingServer.get_current_rendering_method()
	var memory: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var data := {"engine": Engine.get_version_info().string, "method": method, "driver": RenderingServer.get_current_rendering_driver_name(), "gpu": RenderingServer.get_video_adapter_name(), "processor": OS.get_processor_name(), "frame_interval_median_ms": times[30], "frame_interval_p95_ms": times[56], "samples": 60, "reported_video_memory_bytes": memory if memory > 0 else null, "static_memory_bytes": OS.get_static_memory_usage(), "note": "Idle editor probe with existing driver/vsync; no stress, stability certification or guaranteed FPS."}
	var file := FileAccess.open("res://test_results/renderer-" + method + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	print(JSON.stringify(data))
	ui.free()
	quit()
