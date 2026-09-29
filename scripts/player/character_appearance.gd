class_name CharacterAppearance
extends Node
## Dresses a HumanF-rigged character in a Survey Corps uniform and gives it hair.
## Clothing and skin are cut from the body mesh itself and pushed out along its
## normals, so they keep the body's skin weights and deform with every animation.
## Hair is a shell grown around the head's shape and skinned rigidly to the head bone.
## Generated meshes are cached, so characters sharing a look share one mesh.

@export var model_path: NodePath = ^"../Model"
@export var dress_outfit: bool = true
@export var skin_tone: Color = Color(0.98, 0.84, 0.74)
@export_group("Hair")
@export var hair_enabled: bool = true
@export var hair_color: Color = Color(0.9, 0.74, 0.44)
## Rest-pose height where the hair ends at the back; the shoulders sit near 1.42.
@export var hair_back_end: float = 1.4
## Rest-pose height where the hair ends at the sides, unless the shoulders stop it first.
@export var hair_side_end: float = 1.43
## Rest-pose height of the fringe over the forehead; above 1.77 means no fringe.
@export var fringe_height: float = 1.672

enum Garment { NONE, SKIN, SHIRT, JACKET, PANTS, BOOTS, STRAP }

const GARMENT_COLORS := {
	Garment.SHIRT: Color(0.9, 0.89, 0.85),
	Garment.JACKET: Color(0.46, 0.31, 0.17),
	Garment.PANTS: Color(0.93, 0.92, 0.88),
	Garment.BOOTS: Color(0.2, 0.12, 0.07),
	Garment.STRAP: Color(0.3, 0.18, 0.09),
}
## How far each layer stands off the body; the jacket is thickest so its hem reads.
const GARMENT_OFFSETS := {
	Garment.SKIN: 0.0012,
	Garment.SHIRT: 0.004,
	Garment.JACKET: 0.012,
	Garment.PANTS: 0.005,
	Garment.BOOTS: 0.009,
	Garment.STRAP: 0.009,
}
## Under every layer; slivers visible between garments read as seam shadow.
const BODY_UNDERLAY := Color(0.2, 0.16, 0.13)
## Triangles straddling a garment edge are split this many times, so hems are straight.
const EDGE_SUBDIVISIONS := 2
## Rest-pose landmarks of the HumanF body (T-pose, facing +Z, left side is +X).
const JACKET_HEM := 1.18
const COLLAR := 1.47
const CUFF := 0.565
const WAIST := 1.0
const BOOT_TOP := 0.47
const ARM_START := 0.19
## Wings of Freedom patches: centre (x, y), size, and whether the patch faces the back.
const PATCHES := [[0.0, 1.3, 0.15, true], [0.085, 1.335, 0.05, false]]

## Hair grid: columns around the head's vertical axis, rows down from the crown.
const HAIR_AXIS_Z := 0.035
## Just above the skull's top (1.766), so the crown ring already has width.
const HAIR_TOP := 1.772
const HAIR_BOTTOM := 1.34
const HAIR_STEP := 0.01
const HAIR_COLUMNS := 64
const HAIR_THICKNESS := 0.012
## Columns this far from the back (radians) frame the face and end at the fringe.
const FACE_ANGLE := 2.23

static var _mesh_cache: Dictionary = {}
static var _emblem: ImageTexture


func _ready() -> void:
	var model := get_node_or_null(model_path)
	if model == null:
		return
	apply(model.find_child("HumanF_BodyMesh", true, false) as MeshInstance3D)


## Adds the outfit and hair to a body mesh that is a child of its Skeleton3D.
func apply(body: MeshInstance3D) -> void:
	if body == null or body.mesh == null:
		return
	var skeleton := body.get_parent() as Skeleton3D
	if skeleton == null:
		return
	if dress_outfit:
		var underlay := StandardMaterial3D.new()
		underlay.albedo_color = BODY_UNDERLAY
		underlay.roughness = 1.0
		body.set_surface_override_material(0, underlay)
	var source_id := body.mesh.get_rid().get_id()
	if dress_outfit:
		var key := "outfit|%d|%s" % [source_id, skin_tone.to_html()]
		if not _mesh_cache.has(key):
			_mesh_cache[key] = _outfit_mesh(body)
		_add_skinned(skeleton, body, "Outfit", _mesh_cache[key])
	if hair_enabled:
		var key := "hair|%d|%s|%s|%s|%s" % [source_id, hair_color.to_html(), hair_back_end,
			hair_side_end, fringe_height]
		if not _mesh_cache.has(key):
			_mesh_cache[key] = _hair_mesh(body, skeleton)
		if _mesh_cache[key] != null:
			_add_skinned(skeleton, body, "Hair", _mesh_cache[key])


static func _add_skinned(skeleton: Skeleton3D, body: MeshInstance3D, node_name: String, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.skin = body.skin
	skeleton.add_child(instance)
	instance.skeleton = instance.get_path_to(skeleton)


static func _bone_flags(source: Array) -> Array:
	var per_vertex: int = (source[Mesh.ARRAY_BONES] as PackedInt32Array).size() \
			/ (source[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return [per_vertex, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per_vertex == 8 else 0]


func _outfit_mesh(body: MeshInstance3D) -> ArrayMesh:
	var source := body.mesh.surface_get_arrays(0)
	var bone_info := _bone_flags(source)
	var layers := _build_outfit(source, bone_info[0])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, layers[0], [], {}, bone_info[1])
	mesh.surface_set_material(0, _cloth_material())
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, layers[1], [], {}, bone_info[1])
	mesh.surface_set_material(1, _emblem_material())
	return mesh


func _hair_mesh(body: MeshInstance3D, skeleton: Skeleton3D) -> ArrayMesh:
	var head_bind := _bind_index(body.skin, skeleton, "B-head")
	if head_bind < 0:
		return null
	var source := body.mesh.surface_get_arrays(0)
	var bone_info := _bone_flags(source)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_build_hair(source[Mesh.ARRAY_VERTEX], head_bind, bone_info[0]), [], {}, bone_info[1])
	mesh.surface_set_material(0, _hair_material())
	return mesh


## Skin bind slot that drives the named bone; mesh bone indices refer to these slots.
static func _bind_index(skin: Skin, skeleton: Skeleton3D, bone_name: String) -> int:
	var bone := skeleton.find_bone(bone_name)
	for i in skin.get_bind_count():
		var bound := skin.get_bind_bone(i)
		if bound < 0:
			bound = skeleton.find_bone(skin.get_bind_name(i))
		if bound == bone:
			return i
	return -1


# --- Outfit -------------------------------------------------------------------

## Returns [cloth and skin arrays, emblem patch arrays].
func _build_outfit(source: Array, bones_per_vertex: int) -> Array:
	var verts: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
	var cloth := _SurfaceBuilder.new(source, bones_per_vertex)
	var patches := _SurfaceBuilder.new(source, bones_per_vertex)
	for t in range(0, indices.size(), 3):
		var tri := [indices[t], indices[t + 1], indices[t + 2]]
		var centroid: Vector3 = (verts[tri[0]] + verts[tri[1]] + verts[tri[2]]) / 3.0
		var garment := _garment(centroid)
		if _is_uniform(garment, verts[tri[0]], verts[tri[1]], verts[tri[2]]):
			if garment == Garment.NONE:
				continue
			for i in tri:
				cloth.add(i, garment, verts[i] + normals[i] * GARMENT_OFFSETS[garment], _color(garment, verts[i]))
			cloth.close_triangle()
		else:
			_split(cloth, [cloth.corner(tri[0]), cloth.corner(tri[1]), cloth.corner(tri[2])], EDGE_SUBDIVISIONS)
		if garment == Garment.JACKET:
			_add_patch(patches, tri, centroid, verts, normals)
	return [cloth.arrays(), patches.arrays()]


## Samples corners and edge midpoints too, since straps are narrower than some triangles.
static func _is_uniform(garment: Garment, a: Vector3, b: Vector3, c: Vector3) -> bool:
	for p in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5]:
		if _garment(p) != garment:
			return false
	return true


## Subdivides a triangle that crosses a garment edge until each piece lies in one garment.
func _split(builder: _SurfaceBuilder, corners: Array, depth: int) -> void:
	var centroid: Vector3 = (corners[0].p + corners[1].p + corners[2].p) / 3.0
	var garment := _garment(centroid)
	if depth > 0 and not _is_uniform(garment, corners[0].p, corners[1].p, corners[2].p):
		var ab := builder.mix(corners[0], corners[1])
		var bc := builder.mix(corners[1], corners[2])
		var ca := builder.mix(corners[2], corners[0])
		_split(builder, [corners[0], ab, ca], depth - 1)
		_split(builder, [ab, corners[1], bc], depth - 1)
		_split(builder, [ca, bc, corners[2]], depth - 1)
		_split(builder, [ab, bc, ca], depth - 1)
		return
	if garment == Garment.NONE:
		return
	for corner in corners:
		builder.add_corner(corner, GARMENT_OFFSETS[garment], _color(garment, corner.p))
	builder.close_triangle()


static func _garment(c: Vector3) -> Garment:
	var ax := absf(c.x)
	if c.y > 1.3 and ax > ARM_START:
		return Garment.JACKET if ax < CUFF else Garment.SKIN
	if c.y >= COLLAR:
		return Garment.SKIN
	if c.y >= JACKET_HEM:
		# The jacket is worn open, showing the shirt down the front.
		if c.z > 0.05 and ax < 0.045:
			return Garment.SHIRT
		return Garment.JACKET
	if c.y >= WAIST:
		# Chest band under the hem and two straps down to the belt.
		if c.y > 1.14 or absf(ax - 0.075) < 0.011:
			return Garment.STRAP
		return Garment.SHIRT
	if c.y >= BOOT_TOP:
		if absf(c.y - 0.752) < 0.013:
			return Garment.STRAP
		# Strap down the outside of each thigh, from under the blade box to the thigh band.
		if c.y > 0.752 and c.y < 0.9 and ax > 0.12 and absf(c.z - 0.02) < 0.012:
			return Garment.STRAP
		return Garment.PANTS
	return Garment.BOOTS


func _color(garment: Garment, point: Vector3) -> Color:
	if garment == Garment.SKIN:
		return skin_tone
	# Slight per-vertex variation so large panels of cloth don't look flat.
	var n := fposmod(sin(point.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453, 1.0)
	return GARMENT_COLORS[garment] * (0.96 + 0.06 * n)


func _add_patch(builder: _SurfaceBuilder, tri: Array, centroid: Vector3,
		verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	var offset: float = GARMENT_OFFSETS[Garment.JACKET] + 0.002
	for patch in PATCHES:
		var center := Vector2(patch[0], patch[1])
		var size: float = patch[2]
		var back: bool = patch[3]
		var face_normal := (normals[tri[0]] + normals[tri[1]] + normals[tri[2]]).normalized()
		if (face_normal.z < 0.0) != back:
			continue
		if absf(centroid.x - center.x) > size * 0.5 + 0.02 or absf(centroid.y - center.y) > size * 0.5 + 0.02:
			continue
		for i in tri:
			var p: Vector3 = verts[i]
			# Viewed from behind, +X is on the viewer's left, so the back patch mirrors U.
			var u := ((center.x - p.x) if back else (p.x - center.x)) / size + 0.5
			var v := 0.5 - (p.y - center.y) / size
			builder.add(i, 100, p + normals[i] * offset, Color.WHITE, Vector2(u, v))
		builder.close_triangle()
		return


static func _cloth_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	return mat


static func _emblem_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _emblem_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_repeat = false
	mat.roughness = 0.8
	return mat


## Survey Corps "Wings of Freedom": white and blue wings crossed on a dark-edged shield.
static func _emblem_texture() -> ImageTexture:
	if _emblem != null:
		return _emblem
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for py in size:
		for px in size:
			var p := Vector2((px + 0.5) / size * 2.0 - 1.0, 1.0 - (py + 0.5) / size * 2.0)
			image.set_pixel(px, py, _emblem_pixel(p))
	image.generate_mipmaps()
	_emblem = ImageTexture.create_from_image(image)
	return _emblem


static func _emblem_pixel(p: Vector2) -> Color:
	var half_width := 0.82 if p.y >= 0.0 else 0.82 * pow(maxf(1.0 + p.y, 0.0), 0.55)
	if p.y > 0.92 or absf(p.x) > half_width:
		return Color(0, 0, 0, 0)
	if minf(half_width - absf(p.x), 0.92 - p.y) < 0.09:
		return Color(0.1, 0.1, 0.12)
	var color := Color(0.3, 0.26, 0.22)
	var white := _wing(p, Vector2(0.2, -0.5), deg_to_rad(95.0), deg_to_rad(150.0))
	if white > 0:
		color = Color(0.95, 0.95, 0.95) if white == 1 else Color(0.12, 0.12, 0.15)
	var blue := _wing(p, Vector2(-0.2, -0.5), deg_to_rad(85.0), deg_to_rad(30.0))
	if blue > 0:
		color = Color(0.2, 0.36, 0.78) if blue == 1 else Color(0.12, 0.12, 0.15)
	return color


## 0 = outside, 1 = feather, 2 = feather outline. Feathers fan out from root.
static func _wing(p: Vector2, root: Vector2, from_angle: float, to_angle: float) -> int:
	var result := 0
	var lengths := [1.15, 1.0, 0.85, 0.7]
	for i in 4:
		var angle := lerpf(from_angle, to_angle, i / 3.0)
		var along_dir := Vector2(cos(angle), sin(angle))
		var q := p - root
		var half: float = lengths[i] * 0.5
		var along := (q.dot(along_dir) - half) / half
		var across := q.dot(Vector2(-along_dir.y, along_dir.x)) / 0.13
		var e := along * along + across * across
		if e <= 1.0:
			result = 1 if e < 0.72 else 2
	return result


# --- Hair ---------------------------------------------------------------------

## Hair shell: each column follows the skull, then falls from its widest point with a
## slight taper toward the neck and a flick outward at the ends. It stops at the fringe
## over the face, and otherwise at shoulder length or where it would meet the shoulders.
func _build_hair(verts: PackedVector3Array, head_bind: int, bones_per_vertex: int) -> Array:
	var rows := int(round((HAIR_TOP - HAIR_BOTTOM) / HAIR_STEP)) + 1
	var head := PackedFloat32Array()
	head.resize(rows * HAIR_COLUMNS)
	var body := PackedFloat32Array()
	body.resize(rows * HAIR_COLUMNS)
	for v in verts:
		if v.y < HAIR_BOTTOM - HAIR_STEP or v.y > HAIR_TOP or absf(v.x) > 0.32:
			continue
		var dz := v.z - HAIR_AXIS_Z
		var cell := _hair_row(v.y, rows) * HAIR_COLUMNS + _hair_column(atan2(v.x, -dz))
		var radius := sqrt(v.x * v.x + dz * dz)
		if v.y >= 1.5:
			head[cell] = maxf(head[cell], radius)
		else:
			body[cell] = maxf(body[cell], radius)

	# Radius per (column, row); columns end where their hair ends.
	var profiles: Array[PackedFloat32Array] = []
	for c in HAIR_COLUMNS:
		var theta := _column_angle(c)
		var jag := 0.012 * fposmod(sin(c * 78.233) * 12345.678, 1.0)
		var end_y := fringe_height + jag * 0.5
		if absf(theta) < FACE_ANGLE:
			end_y = lerpf(hair_side_end, hair_back_end, clampf(cos(theta), 0.0, 1.0)) - jag
		var profile := PackedFloat32Array()
		var hang := 0.0
		var widest_y := HAIR_TOP
		for j in rows:
			var y := HAIR_TOP - j * HAIR_STEP
			var here := _sample(head, c, j, rows)
			if here > hang:
				hang = here
				widest_y = y
			var fall := widest_y - y
			var thickness := HAIR_THICKNESS + 0.01 * clampf((y - 1.68) / 0.1, 0.0, 1.0)
			var radius := maxf(here, hang - 0.12 * fall) + thickness + 0.08 * maxf(0.0, 1.5 - y)
			var shoulder := _sample(body, c, j, rows) + 0.008
			if shoulder > radius:
				if shoulder - radius > 0.025:
					break
				radius = shoulder
			profile.append(radius)
			if y <= end_y:
				break
		profiles.append(profile)
	# Smooth down each column, then around the head, so the sampled radii don't read as steps.
	for c in HAIR_COLUMNS:
		var profile := profiles[c]
		for _pass in 3:
			var copy := profile.duplicate()
			for j in range(1, profile.size() - 1):
				profile[j] = (copy[j - 1] + copy[j] * 2.0 + copy[j + 1]) * 0.25
		profiles[c] = profile
	var smoothed: Array[PackedFloat32Array] = []
	for c in HAIR_COLUMNS:
		var profile := profiles[c].duplicate()
		for j in profile.size():
			var total := 0.0
			var weight := 0.0
			for dc in range(-2, 3):
				var other := profiles[posmod(c + dc, HAIR_COLUMNS)]
				if j < other.size():
					var w := 3.0 - absf(dc)
					total += other[j] * w
					weight += w
			profile[j] = total / weight
		smoothed.append(profile)

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var grid: Array[PackedInt32Array] = []
	var crown := Vector3(0.0, 1.62, HAIR_AXIS_Z)
	for c in HAIR_COLUMNS:
		var theta := _column_angle(c)
		var dir := Vector3(sin(theta), 0.0, -cos(theta))
		var streak := 0.9 + 0.2 * fposmod(sin(c * 12.9898) * 43758.5453, 1.0)
		var column := PackedInt32Array()
		var profile := smoothed[c]
		for j in profile.size():
			var y := HAIR_TOP - j * HAIR_STEP
			var point := Vector3(0.0, y, HAIR_AXIS_Z) + dir * (profile[j] + 0.0025 * sin(theta * 16.0 + j * 0.35))
			column.append(positions.size())
			positions.append(point)
			normals.append((point - crown).normalized() if y > crown.y else dir)
			colors.append(hair_color * streak * lerpf(1.0, 0.88, float(j) / rows))
		grid.append(column)

	var tris := PackedInt32Array()
	var cap := positions.size()
	positions.append(Vector3(0.0, HAIR_TOP + 0.016, HAIR_AXIS_Z))
	normals.append(Vector3.UP)
	colors.append(hair_color * 1.05)
	for c in HAIR_COLUMNS:
		var left := grid[c]
		var right := grid[(c + 1) % HAIR_COLUMNS]
		if left.is_empty() or right.is_empty():
			continue
		tris.append_array(PackedInt32Array([cap, left[0], right[0]]))
		for j in mini(left.size(), right.size()) - 1:
			tris.append_array(PackedInt32Array([left[j], right[j + 1], right[j],
				left[j], left[j + 1], right[j + 1]]))

	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in positions.size():
		for k in bones_per_vertex:
			bones.append(head_bind if k == 0 else 0)
			weights.append(1.0 if k == 0 else 0.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = tris
	return arrays


## Angle around the head axis: 0 at the back of the head, +PI/2 on the character's left.
static func _column_angle(column: int) -> float:
	return -PI + (column + 0.5) / HAIR_COLUMNS * TAU


static func _hair_row(y: float, rows: int) -> int:
	return clampi(int(round((HAIR_TOP - y) / HAIR_STEP)), 0, rows - 1)


static func _hair_column(theta: float) -> int:
	return posmod(int(floor((theta + PI) / TAU * HAIR_COLUMNS)), HAIR_COLUMNS)


## Largest radius near a grid cell, so gaps between the body's vertices don't dent the hair.
static func _sample(table: PackedFloat32Array, column: int, row: int, rows: int) -> float:
	var best := 0.0
	for dj in range(-2, 3):
		var j := row + dj
		if j < 0 or j >= rows:
			continue
		for dc in range(-2, 3):
			best = maxf(best, table[j * HAIR_COLUMNS + posmod(column + dc, HAIR_COLUMNS)])
	return best


static func _hair_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.55
	mat.metallic_specular = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Collects triangles copied from the body. Vertices are duplicated per garment so each
## garment sits at its own offset; split edges get vertices with blended bone weights.
class _SurfaceBuilder:
	var _verts_src: PackedVector3Array
	var _bones_src: PackedInt32Array
	var _weights_src: PackedFloat32Array
	var _normals_src: PackedVector3Array
	var _per_vertex: int
	var _remap := {}
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var _pending := PackedInt32Array()

	func _init(source: Array, per_vertex: int) -> void:
		_verts_src = source[Mesh.ARRAY_VERTEX]
		_bones_src = source[Mesh.ARRAY_BONES]
		_weights_src = source[Mesh.ARRAY_WEIGHTS]
		_normals_src = source[Mesh.ARRAY_NORMAL]
		_per_vertex = per_vertex

	## Adds a copy of a source vertex, shared between triangles of the same group.
	func add(source_index: int, group: int, position: Vector3, color: Color, uv := Vector2.ZERO) -> void:
		var key := source_index * 128 + group
		if not _remap.has(key):
			_remap[key] = positions.size()
			positions.append(position)
			normals.append(_normals_src[source_index])
			colors.append(color)
			uvs.append(uv)
			for k in _per_vertex:
				bones.append(_bones_src[source_index * _per_vertex + k])
				weights.append(_weights_src[source_index * _per_vertex + k])
		_pending.append(_remap[key])

	## A free-standing vertex description used while subdividing.
	func corner(source_index: int) -> Dictionary:
		var skin := {}
		for k in _per_vertex:
			var w := _weights_src[source_index * _per_vertex + k]
			if w > 0.0:
				var b := _bones_src[source_index * _per_vertex + k]
				skin[b] = skin.get(b, 0.0) + w
		return {"p": _verts_src[source_index], "n": _normals_src[source_index], "skin": skin}

	func mix(a: Dictionary, b: Dictionary) -> Dictionary:
		var skin := {}
		for bone in a.skin:
			skin[bone] = a.skin[bone] * 0.5
		for bone in b.skin:
			skin[bone] = skin.get(bone, 0.0) + b.skin[bone] * 0.5
		return {"p": (a.p + b.p) * 0.5, "n": (a.n + b.n).normalized(), "skin": skin}

	func add_corner(c: Dictionary, offset: float, color: Color) -> void:
		_pending.append(positions.size())
		positions.append(c.p + c.n * offset)
		normals.append(c.n)
		colors.append(color)
		uvs.append(Vector2.ZERO)
		# Keep the strongest influences that fit, renormalised.
		var ranked: Array = c.skin.keys()
		ranked.sort_custom(func(x, y): return c.skin[x] > c.skin[y])
		var total := 0.0
		for k in mini(ranked.size(), _per_vertex):
			total += c.skin[ranked[k]]
		for k in _per_vertex:
			if k < ranked.size():
				bones.append(ranked[k])
				weights.append(c.skin[ranked[k]] / maxf(total, 0.00001))
			else:
				bones.append(0)
				weights.append(0.0)

	func close_triangle() -> void:
		indices.append_array(_pending)
		_pending.clear()

	func arrays() -> Array:
		var result := []
		result.resize(Mesh.ARRAY_MAX)
		result[Mesh.ARRAY_VERTEX] = positions
		result[Mesh.ARRAY_NORMAL] = normals
		result[Mesh.ARRAY_COLOR] = colors
		result[Mesh.ARRAY_TEX_UV] = uvs
		result[Mesh.ARRAY_BONES] = bones
		result[Mesh.ARRAY_WEIGHTS] = weights
		result[Mesh.ARRAY_INDEX] = indices
		return result
