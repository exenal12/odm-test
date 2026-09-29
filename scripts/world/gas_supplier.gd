class_name GasSupplier
extends Node3D
## Friendly NPC kneeling on a tree platform. Press the interact key nearby to refill gas.

const MODEL_PATH := "res://assets/Human Melee Animations/Models/HumanF_Model.fbx"
const PALETTE_PATH := "res://scenes/player/animations/humanf_palette.tres"
const ACTION := &"interact"
## Height of the kneeling knee joint; about the knee mesh's radius so it rests on the deck.
const KNEE_HEIGHT := 0.06
const CANISTER_RADIUS := 0.11
## Straps stand slightly proud of the body, so stacked canisters rest on them.
const CANISTER_BAND_RADIUS := 0.116
const CANISTER_LENGTH := 0.58
const PILE_X := 0.3
const PILE_Z := 0.05
## Soldiers hook the trunk this far above the deck...
const CLIMB_ANCHOR_HEIGHT := 12.0
## ...from this far out past the trunk, so the straight reel line passes over the deck edge.
const CLIMB_START_DISTANCE := 16.0
const GRAPPLE_LAYER := 2
const WORLD_LAYER := 1

## Distance within which the player can interact.
@export var interact_radius: float = 5.0
## Soldiers standing this close are refilled over time.
@export var soldier_radius: float = 3.0
@export var soldier_refill_per_second: float = 40.0
## Deck and trunk collider radii, set by the level so soldier climb routes clear the deck edge.
var deck_radius: float = 5.0
var trunk_radius: float = 3.0

var _prompt: Label3D
var _skeleton: Skeleton3D
var _pile_top: Vector3
var _route: Dictionary = {}
var _flash_time: float = 0.0


func _ready() -> void:
	add_to_group("gas_supplier")
	ensure_input_action()
	_build_canisters()
	_build_model()
	_build_prompt()


## Registers the interact action on F if the project has not defined it.
static func ensure_input_action() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
	for event in InputMap.action_get_events(ACTION):
		if event is InputEventKey:
			return
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	InputMap.action_add_event(ACTION, key)


## Where a soldier stands to refuel, beside the NPC's free right side.
func landing_point() -> Vector3:
	return to_global(Vector3(-1.1, 0.0, 0.3))


## Center of the deck's top surface (on the tree's axis).
func deck_center() -> Vector3:
	return Vector3(get_parent().global_position.x, global_position.y, get_parent().global_position.z)


## Horizontal direction from the tree out toward this NPC.
func outward() -> Vector3:
	var out := global_position - deck_center()
	out.y = 0.0
	return out.normalized()


## Ground spot and trunk anchor for a straight reel up onto the deck: {start, anchor}.
## Empty when no clear route exists.
func climb_route() -> Dictionary:
	if _route.is_empty():
		_route = _find_route()
	return _route


## Tries directions around the tree, nearest to this NPC's side first.
func _find_route() -> Dictionary:
	var center := deck_center()
	var trunk := get_parent().get_parent().get_node_or_null("Trunk")
	var space := get_world_3d().direct_space_state
	var aim := center + Vector3.UP * CLIMB_ANCHOR_HEIGHT
	var base_angle := atan2(outward().z, outward().x)
	for i in 16:
		var step := ceili(i / 2.0) * (1 if i % 2 == 0 else -1)
		var angle := base_angle + float(step) * TAU / 16.0
		var spot := center + Vector3(cos(angle), 0.0, sin(angle)) * (trunk_radius + CLIMB_START_DISTANCE)
		var ground := _ray(space, Vector3(spot.x, center.y - 4.0, spot.z),
			Vector3(spot.x, -5.0, spot.z), WORLD_LAYER)
		if ground.is_empty() or ground.position.y > 1.0:
			continue
		var start: Vector3 = ground.position
		var eye := start + Vector3.UP * 1.4
		var hook := _ray(space, eye, eye + (aim - eye).normalized() * 45.0, GRAPPLE_LAYER)
		if hook.is_empty() or hook.collider != trunk:
			continue
		var anchor: Vector3 = hook.position
		var body := start + Vector3.UP * 0.9
		if not _ray(space, body, anchor - (anchor - body).normalized() * 1.5,
				WORLD_LAYER | GRAPPLE_LAYER).is_empty():
			continue
		return {"start": start, "anchor": anchor}
	return {}


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return space.intersect_ray(query)


func _physics_process(delta: float) -> void:
	for node in get_tree().get_nodes_in_group("soldier"):
		var soldier := node as Soldier
		if soldier != null and soldier.alive \
				and soldier.global_position.distance_to(global_position) <= soldier_radius:
			soldier.odm.refill_gas(soldier_refill_per_second * delta)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) <= interact_radius
	_flash_time = maxf(0.0, _flash_time - delta)
	_prompt.visible = near or _flash_time > 0.0
	if _flash_time > 0.0:
		_prompt.text = "Gas refilled"
	else:
		_prompt.text = "[F] Refill gas"
	if near and Input.is_action_just_pressed(ACTION):
		var odm := player.get_node_or_null("ODMController") as ODMController
		if odm != null:
			odm.refill_gas()
			_flash_time = 1.5


func _build_model() -> void:
	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var body := _skeleton.find_child("HumanF_BodyMesh", false, false) as MeshInstance3D
	if body != null:
		body.set_surface_override_material(0, load(PALETTE_PATH) as Material)
	_pose_kneeling()


## Takes a knee: left knee on the deck with toes tucked, right foot planted,
## right forearm draped over the right knee and left hand on the canister pile.
## Skeleton space here is the NPC's local space: +Z forward, +X left, y = 0 on the deck.
func _pose_kneeling() -> void:
	var thigh := _origin("B-thigh.L").distance_to(_origin("B-shin.L"))
	var shin := _origin("B-shin.L").distance_to(_origin("B-foot.L"))
	var knee_l := Vector3(0.09, KNEE_HEIGHT, -0.12)
	_turn("B-hips", Basis(Vector3.RIGHT, deg_to_rad(5.0)))
	var hips := _global("B-hips")
	hips.origin += knee_l + Vector3(0.0, sqrt(thigh * thigh - 0.0036), 0.06) - _origin("B-thigh.L")
	_set_global("B-hips", hips)

	var ankle_l := knee_l + Vector3(0.0, 0.14, -sqrt(shin * shin - 0.14 * 0.14))
	_aim("B-thigh.L", "B-shin.L", knee_l)
	_aim("B-shin.L", "B-foot.L", ankle_l)
	_aim("B-foot.L", "B-toe.L", Vector3(ankle_l.x, 0.03, ankle_l.z + 0.05))
	_match_rest("B-toe.L")

	var hip_r := _origin("B-thigh.R")
	_reach("B-thigh.R", "B-shin.R", "B-foot.R",
		Vector3(-0.11, _skeleton.get_bone_global_rest(_bone("B-foot.R")).origin.y, hip_r.z + 0.38),
		Vector3(0, 1, 1))
	_match_rest("B-foot.R")
	_match_rest("B-toe.R")

	_turn("B-spine", Basis(Vector3.RIGHT, deg_to_rad(12.0)))
	_turn("B-chest", Basis(Vector3.RIGHT, deg_to_rad(8.0)))
	_turn("B-neck", Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	_turn("B-head", Basis(Vector3.UP, deg_to_rad(25.0)))

	var knee_r := _origin("B-shin.R")
	_reach("B-upperArm.R", "B-forearm.R", "B-hand.R", knee_r + Vector3(0.02, 0.09, 0.03),
		Vector3(-1, 0, -0.6))
	_aim("B-hand.R", "B-middleFinger01.R", _origin("B-hand.R") + Vector3(0.03, -1.0, 0.35))

	_reach("B-upperArm.L", "B-forearm.L", "B-hand.L", _pile_top + Vector3(-0.08, 0.04, 0.0),
		Vector3(1, 0, -1))
	_aim("B-hand.L", "B-middleFinger01.L", _origin("B-hand.L") + Vector3(1.0, -0.3, 0.1))


func _bone(bone_name: String) -> int:
	return _skeleton.find_bone(bone_name)


func _global(bone_name: String) -> Transform3D:
	return _skeleton.get_bone_global_pose(_bone(bone_name))


func _origin(bone_name: String) -> Vector3:
	return _global(bone_name).origin


func _set_global(bone_name: String, pose: Transform3D) -> void:
	var i := _bone(bone_name)
	var parent := _skeleton.get_bone_parent(i)
	var parent_pose := _skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	_skeleton.set_bone_pose(i, parent_pose.affine_inverse() * pose)


## Rotates a bone in place; children follow.
func _turn(bone_name: String, rotation_delta: Basis) -> void:
	var pose := _global(bone_name)
	pose.basis = rotation_delta * pose.basis
	_set_global(bone_name, pose)


## Restores a bone's rest orientation in skeleton space (e.g. a foot flat on the ground).
func _match_rest(bone_name: String) -> void:
	var pose := _global(bone_name)
	pose.basis = _skeleton.get_bone_global_rest(_bone(bone_name)).basis
	_set_global(bone_name, pose)


## Swings a bone so its child joint points at target.
func _aim(bone_name: String, child_name: String, target: Vector3) -> void:
	var pose := _global(bone_name)
	var from := (_origin(child_name) - pose.origin).normalized()
	var to := (target - pose.origin).normalized()
	if from.cross(to).length_squared() < 1e-8:
		return
	pose.basis = Basis(Quaternion(from, to)) * pose.basis
	_set_global(bone_name, pose)


## Two-bone IK: places the end joint at target, bending the middle joint toward pole.
func _reach(upper: String, middle: String, end: String, target: Vector3, pole: Vector3) -> void:
	var root := _origin(upper)
	var a := root.distance_to(_origin(middle))
	var b := _origin(middle).distance_to(_origin(end))
	var dir := (target - root).normalized()
	var d := clampf(root.distance_to(target), absf(a - b) + 0.001, a + b - 0.001)
	# Law of cosines gives how far along the root-to-target line the middle joint sits.
	var along := (a * a + d * d - b * b) / (2.0 * d)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	_aim(upper, middle, root + dir * along + bend * sqrt(maxf(a * a - along * along, 0.0)))
	_aim(middle, end, root + dir * d)


## Stacks lying canisters in a 3-2-1 pyramid beside the NPC's left knee.
func _build_canisters() -> void:
	var pile := Node3D.new()
	pile.name = "GasCanisters"
	add_child(pile)
	var parts := _canister_parts()
	var step := CANISTER_BAND_RADIUS * 2.0
	# Row centers rise by r * sqrt(3) when each canister rests in the groove of two below.
	var rise := CANISTER_BAND_RADIUS * sqrt(3.0)
	var index := 0
	for row in 3:
		for i in 3 - row:
			var canister := _canister(parts)
			canister.position = Vector3(PILE_X + step * (float(i) + float(row) * 0.5),
				CANISTER_BAND_RADIUS + rise * float(row), PILE_Z + [0.0, 0.03, -0.025][index % 3])
			canister.rotation = Vector3(PI * 0.5, 0.0, 0.0)
			pile.add_child(canister)
			index += 1
	_pile_top = Vector3(PILE_X + step, CANISTER_BAND_RADIUS * 2.0 + rise * 2.0, PILE_Z)


## Shared meshes and materials: steel body with rounded ends, leather straps, brass neck, green valve.
func _canister_parts() -> Dictionary:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.58, 0.61, 0.63)
	steel.metallic = 0.45
	steel.roughness = 0.4
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.3, 0.2, 0.12)
	leather.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.57, 0.26)
	brass.metallic = 0.5
	brass.roughness = 0.35
	var valve := StandardMaterial3D.new()
	valve.albedo_color = Color(0.3, 0.75, 0.32)
	valve.emission_enabled = true
	valve.emission = Color(0.1, 0.6, 0.15)
	valve.emission_energy_multiplier = 0.8
	var body := CapsuleMesh.new()
	body.radius = CANISTER_RADIUS
	body.height = CANISTER_LENGTH
	body.radial_segments = 16
	body.rings = 4
	var band := CylinderMesh.new()
	band.top_radius = CANISTER_BAND_RADIUS
	band.bottom_radius = CANISTER_BAND_RADIUS
	band.height = 0.035
	band.radial_segments = 16
	var neck := CylinderMesh.new()
	neck.top_radius = 0.028
	neck.bottom_radius = 0.04
	neck.height = 0.06
	var cap := CylinderMesh.new()
	cap.top_radius = 0.034
	cap.bottom_radius = 0.034
	cap.height = 0.03
	return {"steel": steel, "leather": leather, "brass": brass, "valve": valve,
		"body": body, "band": band, "neck": neck, "cap": cap}


## One canister along its local Y axis; the valve end is +Y.
func _canister(parts: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Canister"
	_part(root, parts.body, parts.steel, 0.0)
	for y in [-0.11, 0.11]:
		_part(root, parts.band, parts.leather, y)
	var tip := CANISTER_LENGTH * 0.5
	_part(root, parts.neck, parts.brass, tip + 0.02)
	_part(root, parts.cap, parts.valve, tip + 0.065)
	return root


func _part(parent: Node3D, mesh: Mesh, material: Material, y: float) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position.y = y
	parent.add_child(part)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "Prompt"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0007
	_prompt.font_size = 32
	_prompt.outline_size = 8
	_prompt.modulate = Color(0.5, 1.0, 0.55)
	_prompt.position = Vector3(0, 1.5, 0)
	_prompt.visible = false
	add_child(_prompt)
