# Grapple momentum retention

Chat ID: c1c42feb-8955-4987-9ac6-bff70f5d7927

## User

the player needs to be able to gain and keep momentum when grappling. right now, it feels like if the player is going too fast, they lose speed when grappling. obviouslythere needs to be an upper limit, but this feels bad

## Assistant

- Tool call: `Grep` {"pattern": "grapple|hook", "glob": "*.gd", "-i": true, "output_mode": "count"}

- Tool call: `Grep` {"pattern": "speed|velocity|max_|drag|damp", "path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "-n": true, "-i": true}

- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "offset": 15, "limit": 50}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "offset": 250, "limit": 140}

I realize entering reel mode currently overwrites velocity outright, losing momentum from before—I should instead preserve current speed magnitude up to a capped maximum and steer direction gradually rather than resetting it. I also need to double check the distance times seven limiter and the single hook logic.
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "old_string": "\t\t_reel_boost_bonus = move_toward(_reel_boost_bonus, 0.0, reel_boost_decay * delta)\n\t\tvar speed := minf(_effective_reel_speed() + _reel_boost_bonus,", "new_string": "\t\tvar base_speed := _effective_reel_speed()\...
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "old_string": "## How quickly extra speed from boosting fades while reeling.\n@export_range(0.0, 20.0, 0.1, \"or_greater\") var reel_boost_decay: float = 1.0", "new_string": "## How quickly extra speed (boost or carried momentum) fa...

I'm realizing the boost speed cap could clip velocity too low if the player is already carrying more speed than the cap allows, so I need to adjust it to use the larger of the current cap or the existing grapple length, letting reel boosting actually accelerate up toward the max grapple speed instead of getting artificially capped at 28.
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "old_string": "\t\tspeed_cap = maxf(speed_cap, _effective_reel_speed() + 4.0)", "new_string": "\t\tspeed_cap = maxf(speed_cap, maxf(_effective_reel_speed() + 4.0, max_grapple_speed))"}

I changed `scripts/player/odm_controller.gd` so the player keeps their speed when they start grappling. I haven't run the game, so this is untested.

**Cause:** while reeling, the code set `velocity = direction * (reel_speed + boost bonus)` every frame. If you were going faster than that, for example 30 against a reel speed of 14, you dropped to the reel speed the moment the hook attached. The boost was also capped at 28.

**Changes:**
- **Momentum carry:** while reeling, any speed above the base reel speed is now kept. It fades slowly through the existing `reel_boost_decay`, which defaults to 1 unit/s.
- **New upper limit:** `max_grapple_speed` (default 45) is an exported value you can tune in the inspector.
- **Boost cap:** while reeling, boost can now push you up to `max_grapple_speed`, instead of stopping at 28. So you can gain speed while grappling, not just keep it.

**Tuning:**
- Lower `reel_boost_decay` if you want speed to last longer. Setting it to 0 keeps it until you release the hook.
- Raise `max_grapple_speed` for a higher ceiling.

Momentum is only carried while reel mode is on. With reel off, the swing code already keeps your velocity, apart from a small horizontal damping. If swinging still feels slow, tell me and I'll look at `swing_damping`.
