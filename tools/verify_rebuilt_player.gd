extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var floor := StaticBody3D.new()
	stage.add_child(floor)
	var floor_shape := CollisionShape3D.new()
	floor.add_child(floor_shape)
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	floor_shape.shape = box
	floor_shape.position.y = -0.1
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3(0, 1, 0))
	camera.current = true
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	stage.add_child(player)
	await create_timer(0.2).timeout
	var animation := player.get_node("PlayerAnimation") as PlayerAnimation
	var combat := player.get_node("SwordCombat") as SwordCombat
	assert(player.get_node("ODMController")._left_hook != null and player.get_node("ODMController")._right_hook != null)
	assert(player.get_node("ODMController")._left_socket != null and player.get_node("ODMController")._right_socket != null)
	assert(player.get_node("Model").scene_file_path.ends_with("HumanF_Model.fbx"))
	assert(animation.has_clip(&"Walk") and animation.has_clip(&"RunForward"))
	assert(animation.has_clip(&"SwingLeft") and animation.has_clip(&"SwingRight"))
	assert(animation.has_clip(&"Jump") and animation.has_clip(&"Slide"))
	assert(player.get_node("Model/Skeleton3D/LeftHandAttachment").bone_name == "B-handProp.L")
	assert(player.get_node("Model/Skeleton3D/RightHandAttachment").bone_name == "B-handProp.R")
	assert(player.get_node("Model/Skeleton3D/HipGearAttachment").bone_name == "B-hips")
	Input.action_press("move_forward")
	await create_timer(0.6).timeout
	var walk_speed := Vector2(player.velocity.x, player.velocity.z).length()
	assert(absf(walk_speed - 2.0) < 0.1, "Walking speed should be 2 m/s: %s" % walk_speed)
	assert(animation._base_clip == &"Walk", "Walk clip should be active")
	Input.action_press("sprint")
	await create_timer(0.6).timeout
	var sprint_speed := Vector2(player.velocity.x, player.velocity.z).length()
	assert(absf(sprint_speed - 4.0) < 0.1, "Sprint speed should be 4 m/s: %s" % sprint_speed)
	assert(animation._base_clip == &"RunForward", "HumanF run clip should be active")
	combat._start_attack(0)
	await create_timer(0.25).timeout
	assert(combat._attack_elapsed[0] >= 0.0, "Left attack should play while running")
	combat.swing_speed = 0.75
	var attack_time := combat._attack_elapsed[0]
	assert(is_equal_approx(animation.tree.get("parameters/LeftSpeed/scale"), 0.75))
	assert(is_equal_approx(animation.tree.get("parameters/RightSpeed/scale"), 0.75))
	combat.set_process(false)
	combat._process(0.1)
	assert(absf(combat._attack_elapsed[0] - attack_time - 0.075) < 0.001, "Hit timing must follow the edited speed")
	combat.set_process(true)
	combat.swing_speed = 2.0
	assert(is_equal_approx(animation.tree.get("parameters/LeftSpeed/scale"), 2.0))

	Input.action_release("move_forward")
	Input.action_release("sprint")
	await create_timer(1.5).timeout
	_mouse(MOUSE_BUTTON_LEFT, true)
	await create_timer(0.25).timeout
	assert(combat._attack_elapsed[0] >= 0.0 and not combat._holding[0], "Holding a ground button should be a single attack")
	_mouse(MOUSE_BUTTON_LEFT, false)
	await create_timer(1.4).timeout
	player.global_position.y = 3.0
	player.velocity = Vector3.ZERO
	await create_timer(0.1).timeout
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await create_timer(0.3).timeout
	assert(combat._holding[1] and combat._attack_elapsed[1] < 0.0, "Aerial hold must not trigger a swing")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await create_timer(0.1).timeout
	assert(not combat._holding[1], "Aerial hold should end on release")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await create_timer(0.05).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await create_timer(0.05).timeout
	assert(combat._attack_elapsed[0] >= 0.0, "Aerial tap should trigger a swing")
	var hook_left := InputMap.action_get_events("odm_hook_left")
	var hook_right := InputMap.action_get_events("odm_hook_right")
	assert(hook_left.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_Q))
	assert(hook_right.any(func(e: InputEvent) -> bool: return e is InputEventKey and e.physical_keycode == KEY_E))
	for event in hook_left + hook_right:
		assert(not event is InputEventMouseButton, "Mouse must not fire hooks")
	var callback_count := [0]
	var hit_handler := func(_left: bool, _target: Node3D, _damage: float) -> void: callback_count[0] += 1
	combat.sword_hit.connect(hit_handler)
	var target := Node3D.new()
	stage.add_child(target)
	combat._on_overlap(target, 0)
	combat._on_overlap(target, 0)
	assert(callback_count[0] == 1, "A sword hit should invoke the callback once per target")
	combat.sword_hit.disconnect(hit_handler)
	var slide_player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	slide_player.position = Vector3(10, 0, 0)
	stage.add_child(slide_player)
	await create_timer(0.25).timeout
	slide_player._start_slide()
	await create_timer(2.1).timeout
	assert(not slide_player._is_sliding, "Slide must progress through start, loop, and exit")
	# Standing swings affect the upper body while the locomotion layer owns the hips and legs.
	var slide_animation := slide_player.get_node("PlayerAnimation") as PlayerAnimation
	var blend_tree := slide_animation.tree.tree_root as AnimationNodeBlendTree
	assert(not blend_tree.has_node(&"LowerLeftSwing") and not blend_tree.has_node(&"LowerRightSwing"), "Standing swings must not apply the stepping layer")
	assert(slide_animation.clip_length(&"SwingLeft") > 1.8 and slide_animation.clip_length(&"SwingRight") > 1.8, "Mixamo swing clips should be imported")
	print("PASS: HumanF mesh, Mixamo swing clips, planted lower body, 2/4 m/s movement, aerial hold/tap, attached props, Q/E hooks")
	current_scene = null
	stage.queue_free()
	for i in 5:
		await process_frame
	quit()


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _arm_pose(skeleton: Skeleton3D, side: String) -> Vector2:
	var suffix := ".L" if side == "Left" else ".R"
	var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("B-upperArm" + suffix)).origin
	var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("B-forearm" + suffix)).origin
	var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("B-hand" + suffix)).origin
	return Vector2(rad_to_deg((elbow - shoulder).angle_to(wrist - elbow)), absf(wrist.x))
