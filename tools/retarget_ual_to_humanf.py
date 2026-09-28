"""Bake selected UAL actions onto HumanF_Model's native FBX armature.

This applies the FBX armature's centimetre object scale before baking
rest-pose world deltas in metres. The project only imports clips whose exported bind
pose matches HumanF_Model.fbx in Godot.
"""
import bpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'assets/Human Melee Animations/Models/HumanF_Model.fbx'
OUT = ROOT / 'scenes/player/animations/HumanF_UAL_Retarget.glb'

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(MODEL))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
assert all(abs(x - .01) < 1e-5 for x in rig.scale), 'Expected centimetre FBX armature'
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
assert all(abs(x - 1.0) < 1e-5 for x in rig.scale)
rig.animation_data_create()
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action = None

mapping = {'B-root': 'root', 'B-hips': 'pelvis', 'B-spine': 'spine_01',
           'B-chest': 'spine_02', 'B-neck': 'neck_01', 'B-head': 'Head'}
parts = {'shoulder': 'clavicle', 'upperArm': 'upperarm', 'forearm': 'lowerarm',
         'hand': 'hand', 'thigh': 'thigh', 'shin': 'calf', 'foot': 'foot', 'toe': 'ball'}
for side in ('L', 'R'):
    suffix = '_l' if side == 'L' else '_r'
    for humanf, ual in parts.items():
        mapping[f'B-{humanf}.{side}'] = ual + suffix

target_rest = {name: rig.data.bones[name].matrix_local.copy() for name in mapping}
pairs = sorted(mapping.items(), key=lambda item: len(rig.data.bones[item[0]].parent_recursive))
sets = [
    ('UAL1_Standard.glb', {
        'Walk': 'Walk_Loop',
        'Crouch_Idle': 'Crouch_Idle_Loop',
        'Crouch_Fwd': 'Crouch_Fwd_Loop',
        'Jump_Start': 'Jump_Start',
        'Jump': 'Jump_Loop',
        'Jump_Land': 'Jump_Land',
    }),
    ('UAL2_Standard.glb', {
        'Slide_Start': 'Slide_Start',
        'Slide': 'Slide_Loop',
        'Slide_Exit': 'Slide_Exit',
    }),
]

for filename, clips in sets:
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/anims' / filename))
    source = next(o for o in bpy.context.selected_objects if o.type == 'ARMATURE')
    source.animation_data_create()
    for track in source.animation_data.nla_tracks:
        track.mute = True
    source_rest = {name: source.data.bones[name].matrix_local.copy() for name in mapping.values()}
    for dest_name, action_name in clips.items():
        action = bpy.data.actions.get(action_name)
        assert action is not None, f'Missing {action_name}'
        source.animation_data.action = action
        start, end = int(action.frame_range[0]), int(action.frame_range[1])
        for bone in rig.pose.bones:
            bone.matrix_basis.identity()
        baked = bpy.data.actions.new(dest_name)
        rig.animation_data.action = baked
        for frame in range(start, end + 1):
            bpy.context.scene.frame_set(frame)
            evaluated = source.evaluated_get(bpy.context.evaluated_depsgraph_get())
            desired = {}
            for target_name, source_name in pairs:
                delta = evaluated.pose.bones[source_name].matrix @ source_rest[source_name].inverted()
                desired[target_name] = delta @ target_rest[target_name]
            for target_name, _ in pairs:
                pose = rig.pose.bones[target_name]
                rest_bone = rig.data.bones[target_name]
                parent = rest_bone.parent
                if parent and parent.name in desired:
                    relative_rest = target_rest[parent.name].inverted() @ target_rest[target_name]
                    basis = relative_rest.inverted() @ desired[parent.name].inverted() @ desired[target_name]
                else:
                    basis = target_rest[target_name].inverted() @ desired[target_name]
                pose.rotation_mode = 'QUATERNION'
                pose.matrix_basis = basis
                pose.keyframe_insert(data_path='location', frame=frame, group=target_name)
                pose.keyframe_insert(data_path='rotation_quaternion', frame=frame, group=target_name)
                pose.keyframe_insert(data_path='scale', frame=frame, group=target_name)
        rig.animation_data.action = None
        strip_track = rig.animation_data.nla_tracks.new()
        strip_track.name = dest_name
        strip = strip_track.strips.new(dest_name, start, baked)
        strip.action_frame_start = start
        strip.action_frame_end = end
        strip_track.mute = True
        print('BAKED', dest_name, start, end)
    bpy.data.objects.remove(source, do_unlink=True)
    for obj in list(bpy.context.selected_objects):
        if obj not in (rig, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)

for track in rig.animation_data.nla_tracks:
    track.mute = False
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT), export_format='GLB', use_selection=True,
    export_animations=True, export_animation_mode='NLA_TRACKS', export_nla_strips=True,
    export_frame_range=False, export_yup=True)
print('EXPORTED', OUT)
