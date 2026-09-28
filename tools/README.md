# Player animation pipeline

The player instances `assets/Human Melee Animations/Models/HumanF_Model.fbx` directly. Its matching female FBX clips are assembled by `build_humanf_library.gd` into `scenes/player/animations/humanf_native.tres`. The builder checks the bone names and bind pose before copying animation tracks. The animation FBX files have one extra helper bone that is deliberately omitted because it is not part of the skinned model.

The katana swings come from the third strike in `assets/anims/One Hand Sword Combo.fbx`. `build_sword_swings.py` retargets source frames 65–121 at the original 30 fps onto the HumanF skeleton, preserves the source joint rotations and timing, and mirrors the result for the opposite hand. The clips remove horizontal root travel while retaining the source upper-body windup, cut, and recovery. Godot masks the clips to the torso, neck, head, and attacking arm, so the feet remain planted during standing attacks and locomotion owns the legs during movement. The original one-hand attack clips are used only to build the airborne sword-hold entry pose.

The UAL1/UAL2 walking, crouch, slide, and aerial clips are retargeted onto this same HumanF armature by Blender. The FBX armature imports at scale 0.01, so the Blender script applies that object scale before baking poses. The builder verifies the exported glTF bind pose against the source FBX (0.1 mm position and 0.0001 rad rotation tolerance) before adding these clips to the library.

To rebuild generated clips from the original files in `assets/`:

```sh
blender -b -t 2 --python tools/retarget_ual_to_humanf.py
blender -b -t 2 --python tools/build_sword_swings.py
godot --headless --path . --editor --quit
godot --headless --path . --script tools/build_humanf_library.gd
godot --headless --path . --script tools/verify_rebuilt_player.gd
```

The scripts were verified with Blender 4.5.14 and Godot 4.7.2. `assets/` is source material and is not modified by this pipeline. The player scene's `PlayerAnimation` component builds an AnimationTree with limb filters for left and right attacks and hold poses; `SwordCombat` owns input, timing, hitboxes, and the future hit callback. The ODM controller and hook scripts remain separate.

Swing speed is exposed on `Player/SwordCombat` under **Sword Attack → Swing Speed**. It is a playback multiplier (0.25–4.0), defaults to 2.0, and can be changed through the Remote Inspector during an active swing; the animation and hit window follow the same speed.
