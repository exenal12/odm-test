# Titan grab mechanic

Chat ID: 56af8281-2a05-4671-8076-25db710a5459

## User

what would it take to give titans the ability to grab players/npcs?

## Assistant

This is a conceptual question, so I should favor giving guidance over writing code, but I want to ground my answer by actually looking at the codebase first before responding.
- Tool call: `Grep` {"pattern": "titan|Titan", "output_mode": "files_with_matches", "path": "/home/bazzite/odm-test", "glob": "*.{gd,tscn}"}

- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/enemies/titan.gd"}
- Tool call: `Grep` {"pattern": "func |extends|class_name", "path": "/home/bazzite/odm-test/scripts/player/player_health.gd", "output_mode": "content"}

Grabbing is very doable. The existing attack state machine in `scripts/enemies/titan.gd` already has most of what you need. Here's the approach I'd take.

## What's already there
- `State` has `ATTACK`, and `_try_land_hit()` already checks whether a hand bone is within reach of the target. Grab detection can reuse that check.
- `_hand_bones` and `skeleton.get_bone_global_pose()` give you the hand position each frame, which is what the victim needs to follow.
- The player hooks into the titan through `take_damage` and `velocity`, so the titan already has a way to affect the player.

## What you'd add

**1. A new state and animation**
- Add `GRAB` (and maybe `EAT`/`THROW`) to the `State` enum, with a `match` branch in `_physics_process`.
- You need a grab animation in the titan's `AnimationPlayer`, next to `titan/Attack`. The animation library comes from `tools/build_humanm_library.gd`, so check whether a suitable clip exists or has to be made.
- Model the state on `_state_attack`: wind-up, a hit window (`hit_start_fraction`/`hit_end_fraction`), then either a successful grab or a recovery.

**2. Choosing grab or swipe**
- In `_state_chase`, pick the grab based on distance, a random roll, or a cooldown. A grab needs its own cooldown and range so it doesn't replace the swipe.

**3. Attaching the victim**
- On a successful hit, store a `_grabbed` reference.
- Each physics frame, set the victim's `global_position` to the hand bone's world position (skeleton transform times bone pose origin).
- While held, the victim's own movement has to be switched off, or it will fight you.

**4. Suspending the player's control**
- The player is a `CharacterBody3D` driven by `scripts/player/odm_controller.gd`. You need a "grabbed" flag or method on the player that makes the controller skip movement, gravity and gas boosting.
- Also disable collision with the titan's segment bodies while held. Those are `AnimatableBody3D`s on layers 1 and 2, so the player would otherwise be pushed around by the hand.
- Hooks and the sword should probably stay usable, since they're the escape mechanic.

**5. Escape and outcome**
- Escape options: mash a key, or cut the titan's hand or nape with the sword. Currently `on_sword_hit` only reacts to the nape, so a grabbing hand needs a valid hit target, or you allow the nape kill to release the victim.
- Outcomes: release after a timer, drain HP through `PlayerHealth.take_damage` while held, then throw or drop. On `_die()`, always release the victim.

**6. Edge cases**
- Clear `_grabbed` if the victim is freed (`is_instance_valid`).
- Release the victim if the titan enters `DEAD`.
- Make sure awareness and chase logic don't re-trigger an attack mid-grab.

## NPCs
The titan currently only targets whatever is in the `"player"` group (`_acquire_player`), and it stores a single `player` reference. Grabbing NPCs means:
- Generalizing the target to any node in something like a `"grabbable"` group.
- Giving NPCs a shared interface (for example `on_grabbed(titan)` and `on_released()`) that the titan calls instead of touching player internals.
- Deciding on target priority, since there's currently one target and NPCs would add more.

I'd build it for the player first, behind that shared interface, then add NPCs later. Do you want me to implement the player version? If so, tell me whether it should be grab-and-throw, grab-and-eat, or a damage-over-time hold with an escape mechanic.

That's enough context — I should just give guidance without writing code. I should note that the titan currently only targets the "player" group, so if NPCs exist they wouldn't be affected unless checked separately.
