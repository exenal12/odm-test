"""Retarget the third Mixamo One Hand Sword Combo strike to native HumanF.

Preserve the source timing and joint motion. Rest-space rotation transfer and
fixed target bone offsets preserve HumanF proportions. Root travel is removed
for an in-place action; hips height and body rotation remain for planted swings.
Left is a skeleton-space mirror of the same right-hand performance.
"""
import bpy
from mathutils import Matrix, Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets/Human Melee Animations/Models/HumanF_Model.fbx'
SOURCE = ROOT / 'assets/anims/One Hand Sword Combo.fbx'
OUT = ROOT / 'scenes/player/animations/HumanF_SwordSwings.glb'
FIRST, LAST = 65, 121

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(MODEL))
rig = next(o for o in bpy.context.selected_objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
rig.animation_data_create()
rig.animation_data.action = None
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)

before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=str(SOURCE))
source_objects = set(bpy.data.objects) - before
source = next(o for o in source_objects if o.type == 'ARMATURE')
source.animation_data_create()
for track in source.animation_data.nla_tracks:
    track.mute = True
source.animation_data.action = next(a for a in bpy.data.actions if 'mixamo.com' in a.name)
bpy.context.scene.render.fps = 30

mapping = {'B-hips': 'Hips', 'B-spine': 'Spine', 'B-chest': 'Spine2',
           'B-neck': 'Neck', 'B-head': 'Head'}
parts = {'shoulder': 'Shoulder', 'upperArm': 'Arm', 'forearm': 'ForeArm',
         'hand': 'Hand', 'thigh': 'UpLeg', 'shin': 'Leg', 'foot': 'Foot', 'toe': 'ToeBase'}
for suffix, side in [('L', 'Left'), ('R', 'Right')]:
    for dst, src in parts.items():
        mapping[f'B-{dst}.{suffix}'] = side + src
    for dst, src in [('thumb', 'Thumb'), ('index', 'Index'), ('middle', 'Middle'), ('ring', 'Ring'), ('pinky', 'Pinky')]:
        for n in range(1, 4):
            mapping[f'B-{dst}Finger0{n}.{suffix}'] = f'{side}Hand{src}{n}'
mapping = {dst: 'mixamorig:' + src for dst, src in mapping.items()}
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
source_rest = {n: source.matrix_world @ source.data.bones[n].matrix_local for n in mapping.values()}
ordered = sorted(rest, key=lambda name: len(rig.data.bones[name].parent_recursive))
mirror = Matrix.Diagonal((-1., 1., 1., 1.))
height_scale = rest['B-hips'].translation.z / source_rest[mapping['B-hips']].translation.z
assert 0.7 < height_scale < 1.3, 'Unexpected source/target unit conversion'


def counterpart(name):
    if name.endswith('.L'): return name[:-1] + 'R'
    if name.endswith('.R'): return name[:-1] + 'L'
    return name


for clip, mirrored in [('SwingRight', False), ('SwingLeft', True)]:
    action = bpy.data.actions.new(clip)
    rig.animation_data.action = action
    previous = {}
    for frame in range(FIRST, LAST + 1):
        bpy.context.scene.frame_set(frame)
        evaluated = source.evaluated_get(bpy.context.evaluated_depsgraph_get())
        desired = {}
        for name in ordered:
            parent = rig.data.bones[name].parent
            parent_rest = rest[parent.name] if parent else Matrix.Identity(4)
            parent_pose = desired[parent.name] if parent else Matrix.Identity(4)
            local_rest = parent_rest.inverted() @ rest[name]
            position = (parent_pose @ local_rest).translation
            if name in mapping:
                src = mapping[name]
                pose = source.matrix_world @ evaluated.pose.bones[src].matrix
                delta = pose.to_quaternion() @ source_rest[src].to_quaternion().inverted()
                rotation = delta @ rest[name].to_quaternion()
                if name == 'B-hips':
                    position = rest[name].translation.copy()
                    position.z += (pose.translation.z - source_rest[src].translation.z) * height_scale
                desired[name] = Matrix.LocRotScale(position, rotation, Vector((1, 1, 1)))
            else:
                desired[name] = parent_pose @ local_rest
        if mirrored:
            desired = {name: mirror @ desired[counterpart(name)] @ mirror for name in ordered}
        for name in ordered:
            parent = rig.data.bones[name].parent
            parent_rest = rest[parent.name] if parent else Matrix.Identity(4)
            parent_pose = desired[parent.name] if parent else Matrix.Identity(4)
            basis = (parent_rest.inverted() @ rest[name]).inverted() @ parent_pose.inverted() @ desired[name]
            bone = rig.pose.bones[name]
            bone.rotation_mode = 'QUATERNION'
            rotation = basis.to_quaternion()
            if name in previous and previous[name].dot(rotation) < 0:
                rotation.negate()
            previous[name] = rotation.copy()
            bone.rotation_quaternion = rotation
            # Preserve native lengths and scales. Only the hips may move vertically.
            bone.location = basis.translation if name == 'B-hips' else Vector((0, 0, 0))
            bone.scale = (1, 1, 1)
            out_frame = frame - FIRST + 1
            bone.keyframe_insert(data_path='rotation_quaternion', frame=out_frame, group=name)
            bone.keyframe_insert(data_path='location', frame=out_frame, group=name)
        assert abs(desired['B-hips'].translation.x) < 1e-4
    rig.animation_data.action = None
    track = rig.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    track.mute = True
    print('RETARGETED', clip, FIRST, LAST, 'at 30 fps; preserved target bone lengths')

for o in source_objects:
    bpy.data.objects.remove(o, do_unlink=True)
for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True); mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='NLA_TRACKS', export_nla_strips=True,
    export_frame_range=False, export_yup=True)
print('EXPORTED', OUT)
