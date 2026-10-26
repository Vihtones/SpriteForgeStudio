extends SceneTree
const Storage = preload("res://core/storage.gd")
const Audit = preload("res://core/character_audit.gd")
const ROOT = "res://examples/animation_candidate_v5/"
var checks: Array[Dictionary] = []
var changes := 0

func check(value: bool, title: String) -> void:
	checks.append({"name":title,"passed":value}); print(("PASS " if value else "FAIL ")+title)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var storage := Storage.new()
	var doc = storage.load_document(ROOT+"sentinela-v5.sfs.json")
	var original = storage.load_document(ROOT+"south-source-v3.sfs.json")
	var static_doc = storage.load_document("res://examples/sentinela_turnaround_v4/sentinela-v4-static.sfs.json")
	check(doc!=null and original!=null and static_doc!=null,"directional assets load through SFS storage")
	if doc==null or original==null or static_doc==null: quit(1); return
	check(doc.validate().is_empty() and static_doc.validate().is_empty(),"animated and static documents satisfy integrity contracts")
	var static_hashes := {}; var static_visible := true
	for d in 8:
		var im: Image=static_doc.composite(d,0)
		static_visible=static_visible and im.get_used_rect().size!=Vector2i.ZERO
		static_hashes[im.get_data().hex_encode().sha256_text()]=true
	check(static_visible and static_hashes.size()==8 and static_doc.frames==1,"turnaround contains eight distinct visible static drawings")
	check(static_doc.manifest.approvals.is_empty() and static_doc.art.pose_approvals.is_empty(),"new static views inherit no human approval")
	check(doc.art.direction_coverage==["N","S"] and doc.frames==18,"animated coverage declares exactly North and South")
	var preserved := true; var missing_empty := true
	for f in 18:
		preserved=preserved and doc.composite(4,f).get_data()==original.composite(4,f).get_data()
		for d in [1,2,3,5,6,7]: missing_empty=missing_empty and doc.composite(d,f).get_used_rect().size==Vector2i.ZERO
	check(preserved,"all 18 South frames remain pixel-identical to v3")
	check(missing_empty,"six missing animated directions are not filled with duplicate views")
	check(doc.art.pose_approvals.size()==1 and doc.art.pose_approvals[0].direction=="S" and doc.art.pose_approvals[0].frame==2,"human approval remains scoped to corrected South attack pose")
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	for spec in [{"d":0,"name":"N"},{"d":4,"name":"S"}]:
		for clip in doc.animation.clips:
			var name: String=clip.name+"_"+spec.name
			frames.add_animation(name); frames.set_animation_speed(name,1.0); frames.set_animation_loop(name,clip.loop)
			var hashes := {}; var visible := true
			for f in clip.frames:
				var im: Image=doc.composite(spec.d,int(f))
				visible=visible and im.get_used_rect().size!=Vector2i.ZERO
				hashes[im.get_data().hex_encode().sha256_text()]=true
				frames.add_frame(name,ImageTexture.create_from_image(im),float(clip.durations_ms[str(f)])/1000.0)
			check(visible and hashes.size()==6,name+" contains six distinct visible poses")
	check(ResourceSaver.save(frames,ROOT+"directional_animations.res")==OK,"native six-animation resource saves")
	var loaded: SpriteFrames=load(ROOT+"directional_animations.res")
	check(loaded!=null and loaded.get_animation_names().size()==6,"native directional resource reloads")
	var sprite := AnimatedSprite2D.new(); sprite.sprite_frames=loaded; root.add_child(sprite)
	sprite.frame_changed.connect(func(): changes+=1)
	for name in loaded.get_animation_names():
		changes=0; sprite.play(name); await create_timer(0.45).timeout
		check(changes>0,"Godot advances "+name)
	check(not loaded.get_animation_loop("jump_N") and not loaded.get_animation_loop("attack_N") and loaded.get_animation_loop("idle_breathing_N"),"source North clips preserve one-shot and breathing-loop semantics")
	var preview: Node=load(ROOT+"preview.tscn").instantiate(); root.add_child(preview); await process_frame
	check(preview.actors.size()==3 and preview.actors.all(func(a): return a.animation.ends_with("_N")),"comparison scene starts three North clips")
	preview.direction_picker.select(1); preview.direction_picker.item_selected.emit(1)
	check(preview.actors.all(func(a): return a.animation.ends_with("_S")),"direction picker switches all actors to South artwork")
	var controls: HBoxContainer
	for child in preview.get_children():
		if child is HBoxContainer: controls=child
	controls.get_child(0).pressed.emit()
	var before: Array=preview.actors.map(func(a): return a.frame)
	await create_timer(0.3).timeout
	check(before==preview.actors.map(func(a): return a.frame),"Pause freezes directional clips")
	controls.get_child(1).pressed.emit()
	var stepped := true
	for i in 3: stepped=stepped and preview.actors[i].frame==(int(before[i])+1)%6
	check(stepped,"frame-step advances each selected-direction clip once")
	preview.direction_picker.select(0); preview.direction_picker.item_selected.emit(0)
	check(preview.actors.all(func(a): return a.animation.ends_with("_N") and not a.is_playing()),"changing direction while paused preserves pause")
	controls.get_child(0).pressed.emit()
	check(preview.actors.all(func(a): return a.is_playing()),"Play resumes all clips in the new direction")
	check(not Audit.new().evaluate(doc).technical_passed,"full character gate remains incomplete until eight directions and combat contacts exist")
	var failed := checks.filter(func(item): return not item.passed).size()
	storage.atomic_json(ROOT+"validation.json",{"checks":checks,"passed":checks.size()-failed,"failed":failed,"animated_directions":["N","S"],"static_directions":8,"whole_character_human_approved":false,"engine":Engine.get_version_info().string})
	preview.queue_free(); sprite.queue_free(); quit(0 if failed==0 else 1)
