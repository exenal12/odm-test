# Allied NPC combat AI

Chat ID: cd815041-13ae-494d-8132-41c471d3a589

## User

how complicated would it be to add NPCs to attack the titans? to keep it simple, their model/rig can reuse the player's model/rig

## Assistant

I'll look at how the titan and player are set up so the estimate is grounded.

This is a "how complicated" question, so I should favor giving guidance over writing code. Let me briefly look at the codebase first to ground my answer.
- Tool call: `Glob` {"glob_pattern": "scripts/**/*.gd", "target_directory": "/home/bazzite/odm-test"}
- Tool call: `Grep` {"pattern": "^(class_name|extends)|^func |^signal |add_to_group|take_damage|nape", "path": "/home/bazzite/odm-test/scripts/enemies/titan.gd", "output_mode": "content", "head_limit": 80}

- Tool call: `Grep` {"pattern": "^func |^class_name|^extends|get_first_node_in_group|\"player\"", "path": "/home/bazzite/odm-test/scripts/player", "output_mode": "content", "head_limit": 120}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/enemies/titan.gd", "offset": 170, "limit": 60}

**Short version:** a basic version is moderate. It's about a day of work if the NPCs are simple, and it grows quickly if you want them to look and fight like the player. The rig reuse isn't the hard part. The movement is.

**What helps**
- The titan already has a state machine (wander, chase, attack) and uses `NavigationAgent3D`. The player has a rig and animation tree, `PlayerAnimation`, that you can instance.
- `Titan.on_sword_hit(target, damage)` and the `Nape` `Area3D` are already the kill interface, so NPCs can use the same hit path as the player.
- The player's model is already rebuilt with an animation library (`humanf_native.tres`), so reusing it is mostly scene work.

**What makes it harder**

1. **Movement.** The player's ODM swinging is tied to input in `ODMController` (`_input`, hook actions, reel, boost). You can't reuse it for an AI without a big refactor. The cheapest option is to give NPCs ground navigation only, possibly with a simple "leap" toward the nape.
2. **Titan targeting.** `titan.gd` calls `get_first_node_in_group("player")` and passes `player` to `take_damage`. To make titans react to NPCs, you'd change that to pick the nearest target from a group like `"humans"`. This touches the sensing code (`_sense`, `_line_of_sight`, `_player_noise`), which assumes a single player.
3. **NPC damage.** NPCs need `take_damage`, health and death. `SwordCombat` is tied to the player's hitboxes and input, so the NPC would either get a slimmed-down version or just call `titan.on_sword_hit` directly.
4. **Attacking the nape.** The nape is high up, and the player reaches it by swinging. An NPC on the ground can't reach it, so you have to decide how it gets there. Options are a scripted jump/lunge, a teleport-to-nape "strike," or a probability roll when it gets close. A roll is the least realistic but the simplest.

**Suggested plan**
1. Create a `Soldier` scene (`CharacterBody3D`) that reuses the player's model and animation setup, minus the camera, input and `ODMController`.
2. Give it a small state machine and `NavigationAgent3D`, copying the shape of `titan.gd`: find nearest titan, path toward it, and attack.
3. Add the `"humans"` group. Update the titan's target selection to pick the nearest player or NPC, and call `take_damage` on whichever it hits.
4. Handle the nape strike with one of the options above.
5. Add a spawner in the world scripts (e.g. `giant_forest.gd`).

**Rough sizing**
- NPCs that walk to a titan, play an attack animation, and kill it by rolled chance: small.
- Titans that target NPCs too: small to medium, since the sensing code needs to become multi-target.
- NPCs that swing around with ODM and cut the nape: large. You'd need to refactor `ODMController` into something AI can drive.

I'd start with the first two levels and only go for AI-driven ODM if you want it. If you'd like, I can implement the `Soldier` scene and the titan multi-target change.

I've covered enough ground here — I'll give a guidance-level answer rather than going deeper.

## User

how hard would it be to make ODM logic for the NPCs?

## Assistant

I don't know enough about odm_controller yet, so I should quickly check its contents to give a grounded answer.
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "limit": 130}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "offset": 185, "limit": 260}

The ODM physics is easier to reuse than I said earlier. The AI decision logic on top of it is the hard part.

**Reusing the existing controller**

`ODMController` is a plain `Node` that takes any `CharacterBody3D` in `setup(player, camera, gear_root)`. The physics (reel, cable constraint, boost) works on that body's `velocity`, and `physics_tick(delta)` drives it. Only three parts are tied to the player:

1. **Input.** `_update_single_hook` reads `Input.is_action_just_pressed`, `_apply_boost` reads `odm_boost`, and `_apply_air_steer` reads `move_*`.
2. **Camera aim.** `_aim_origin` and `_aim_direction` use the camera, so hooks fire wherever the camera points.
3. **Signals and HUD.** They're fine to leave alone.

**Refactor (small to medium)**

- Replace the `Input.*` calls with a small "intent" layer, so the controller reads booleans like `want_fire_left`, `want_release_left`, `want_boost` and a `steer_dir`. The player script fills these from `Input`, and an NPC brain fills them from AI.
- Add an optional `aim_target: Vector3` or `aim_override` that replaces the camera-based origin and direction. For an NPC, that would be the hook origin at its socket and the direction toward a chosen anchor.
- Everything else stays as is. It's a contained edit to about four functions, with no rewrite.

**AI brain (medium to hard)**

This is where the difficulty is. Something has to decide when and where to do each of these:

- **Choose anchors.** Hooks only latch onto layer 2 (`grapple_collision_mask`), so the brain must find a point on a building, tree or titan that is in range and has line of sight. A raycast fan toward the titan plus a bit of upward bias is enough to start.
- **Approach the nape.** Reel toward the titan's neck using a chain of hook, reel, release and re-hook, staying in `max_cable_length` (45).
- **Time the strike.** Release near the nape, boost through it, then hit. The kill needs the nape `Area3D` overlap, so the brain fires the strike when it's within range and moving toward it.
- **Manage gas.** Return to `gas_refill.gd` points when low, or give NPCs generous gas to skip this.
- **Recover.** Handle falling, hooks with no valid anchor, and getting stuck.

Steering is the main problem. The player's reel mode moves straight along the cable to the anchor, which makes it deterministic and easy for AI to use. In reel-off swing mode it's a real pendulum, which is much harder. Restricting NPCs to reel mode (`reel_enabled = true`) is what makes this feasible.

**Other costs**

- `NavigationAgent3D` isn't useful while airborne, so NPCs need a ground/air mode switch: nav on the ground, hooking when they're within range of a titan.
- You'd need to tune whether NPCs kill titans too easily and make the player feel redundant.
- Multiple NPCs each running raycasts and physics are cheap at small counts, but the per-frame sensing in `titan.gd` isn't designed for many targets.

**Estimate**

| Piece | Effort |
|---|---|
| Intent-layer refactor of `ODMController` | small |
| Basic AI: ground nav, then hook the nearest titan, reel in, strike | medium |
| Polished AI: re-hooking chains, gas management, recovery, avoiding collisions with each other | large, and needs a lot of playtesting |

I'd do the refactor first, then a "dumb but works" brain: nav to within ~40 m of the titan, fire both hooks at the nape or body, reel in, then hit. You can build up smarter behaviour from that. I can start on the refactor if you want.
