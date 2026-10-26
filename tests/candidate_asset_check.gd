extends SceneTree
const Storage = preload("res://core/storage.gd")
const Audit = preload("res://core/character_audit.gd")
var asset_root := "res://examples/animation_candidate_v3/"
var version := "3"
var checks: Array[Dictionary] = []
var changes := 0

func check(passed: bool, title: String) -> void:
	checks.append({"name": title, "passed": passed})
	print(("PASS " if passed else "FAIL ") + title)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0] == "2": version = "2"; asset_root = "res://examples/animation_candidate_v2/"
	var storage := Storage.new()
	var doc = storage.load_document(asset_root + "sentinela-v" + version + ".sfs.json")
	check(doc != null, "new generated character opens in SFS")
	if doc == null: quit(1); return
	check(doc.validate().is_empty(), "candidate satisfies storage and document contracts")
	var side := 208 if version == "3" else 168
	check(doc.width == side and doc.height == side and doc.frames == 18, "18 frames use one common canvas")
	check(doc.art.get("candidate_status") == ("candidate" if version == "3" else "rejected") and doc.manifest.approvals.is_empty(), "document preserves actual human review scope")
	if version == "3": check(doc.art.get("pose_approvals", []).size()==1 and doc.art.pose_approvals[0].frame==2, "corrected attack pose retains explicit human approval")
	check(doc.art.get("direction_coverage") == ["S"] and doc.art.get("flattened"), "candidate declares south-only and flattened artwork")
	var absent_are_empty := true
	for d in 8:
		if d == 4: continue
		for f in 18: absent_are_empty = absent_are_empty and doc.composite(d,f).get_used_rect().size == Vector2i.ZERO
	check(absent_are_empty, "missing directions are empty rather than duplicated or mirrored")
	var resources := SpriteFrames.new()
	resources.remove_animation("default")
	for clip in doc.animation.clips:
		resources.add_animation(clip.name)
		resources.set_animation_speed(clip.name,1.0)
		resources.set_animation_loop(clip.name,clip.loop)
		var distinct := {}
		var visible := true
		for f in clip.frames:
			var im: Image = doc.composite(4,int(f))
			visible = visible and im.get_used_rect().size != Vector2i.ZERO
			distinct[im.get_data().hex_encode().sha256_text()] = true
			resources.add_frame(clip.name,ImageTexture.create_from_image(im),float(clip.durations_ms[str(f)])/1000.0)
		check(visible and distinct.size()==6, "%s contains six visible distinct poses" % clip.name)
	check(ResourceSaver.save(resources,asset_root+"south_animations.res")==OK,"three south animations saved as native Godot resource")
	var loaded: SpriteFrames = load(asset_root+"south_animations.res")
	check(loaded != null and loaded.get_animation_names().size()==3,"native animation resource reloads")
	var sprite := AnimatedSprite2D.new()
	root.add_child(sprite)
	sprite.sprite_frames = loaded
	sprite.frame_changed.connect(func(): changes += 1)
	for clip in doc.animation.clips:
		changes = 0
		sprite.play(clip.name)
		await create_timer(0.5).timeout
		check(changes>0,"Godot actually advances %s" % clip.name)
	var gate: Dictionary = Audit.new().evaluate(doc)
	check(not gate.technical_passed,"full eight-direction character gate correctly remains incomplete")
	sprite.queue_free()
	if version == "3":
		var preview: Node = load(asset_root+"preview.tscn").instantiate()
		root.add_child(preview)
		await process_frame
		check(preview.actors.size()==3 and preview.actors.all(func(actor): return actor.is_playing()),"comparison scene starts all three native animations")
		var controls: HBoxContainer
		for child in preview.get_children():
			if child is HBoxContainer: controls=child
		controls.get_child(0).pressed.emit()
		var before: Array = preview.actors.map(func(actor): return actor.frame)
		await create_timer(0.3).timeout
		check(preview.actors.all(func(actor): return not actor.is_playing()) and before==preview.actors.map(func(actor): return actor.frame),"Pause freezes every clip without drifting frames")
		controls.get_child(1).pressed.emit()
		var advanced := true
		for i in 3: advanced=advanced and preview.actors[i].frame==(int(before[i])+1)%6
		check(advanced,"frame-step advances each paused clip once")
		controls.get_child(0).pressed.emit()
		check(preview.actors.all(func(actor): return actor.is_playing()),"Play resumes all clips after frame-step")
		preview.queue_free()
	var failed := checks.filter(func(item): return not item.passed).size()
	storage.atomic_json(asset_root+"validation.json",{"checks":checks,"passed":checks.size()-failed,"failed":failed,"directions":["S"],"whole_character_human_approved":false,"corrected_pose_human_approved":version=="3","full_character_gate":gate.technical_passed,"engine":Engine.get_version_info().string})
	quit(0 if failed==0 else 1)
