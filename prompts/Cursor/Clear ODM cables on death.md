# Clear ODM cables on death

Chat ID: 58c5e749-b952-4c2a-b056-464f17f0a21f

## User

when a player/soldier dies, the cables/hooks from their odm need to be instantly removed

## Assistant

I'll find how ODM cables/hooks are managed on death and make them clear instantly when a player or soldier dies.
- Tool call: `GetDynamicTools` {"namespace": "cursor-app-control", "toolName": "rename_chat"}
- Tool call: `CallDynamicTool` {"namespace": "cursor-ide-browser", "toolName": "browser_tabs", "arguments": {"action": "list"}}
- Tool call: `Grep` {"pattern": "die|death|dead|on_death|is_dead", "glob": "**/*.{gd,tscn}", "-i": true}
- Tool call: `Grep` {"pattern": "cable|hook|odm|reel|grapple", "glob": "**/*.{gd,tscn}", "-i": true}

- Tool call: `CallDynamicTool` {"namespace": "cursor-app-control", "toolName": "rename_chat", "arguments": {"title": "Clear ODM cables on death"}}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/npc/soldier.gd", "offset": 100, "limit": 80}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scenes/player/player.gd", "offset": 180, "limit": 70}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "offset": 260, "limit": 50}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_hook.gd"}

Death already calls `release_hooks()`, but detach only starts a retract animation—I'll make death clear cables and hooks instantly.
- Tool call: `Grep` {"glob": "**/*.{gd}", "pattern": "release_hooks|detach\\(|_update_cable_visuals"}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "offset": 297, "limit": 80}
- Tool call: `Grep` {"path": "/home/bazzite/odm-test/tools/export_cursor_transcript.py", "pattern": "TITLES|export_cursor_transcript"}

- Tool call: `Read` {"limit": 50, "offset": 270, "path": "/home/bazzite/odm-test/scenes/player/player.gd"}
- Tool call: `Read` {"path": "/home/bazzite/odm-test/tools/export_cursor_transcript.py", "limit": 80}
- Tool call: `GetDynamicTools` {"namespace": "cursor", "toolName": "TodoWrite"}

Death already calls `release_hooks()`, but that only starts the retract animation. I'll add an instant clear path and use it on death.
- Tool call: `Shell` {"command": "ls -t /home/bazzite/.cursor/projects/home-bazzite-odm-test/agent-transcripts | head -5", "description": "Find current chat transcript ID"}
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/player/odm_hook.gd", "old_string": "## Returns the hook to its idle state and reels the anchor back in. Emits detach\n## only when it was previously attached.\nfunc detach() -> void:\n\tif state == State.IDLE:\n\t\treturn\n\tstate = State.IDLE\n\t_anchor_body...
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/player/odm_controller.gd", "old_string": "## Detaches both hooks and hides the cables.\nfunc release_hooks() -> void:\n\t_ai_fire = [false, false]\n\tfor pair in [[_left_hook, true], [_right_hook, false]]:\n\t\tvar hook: ODMHook = pair[0]\n\t\tif hook != null...
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scenes/player/player.gd", "old_string": "## Stops player control: hooks released, swords and ODM input disabled.\nfunc _on_died() -> void:\n\t_dead = true\n\tvar was_grabbed := grabbed\n\ton_released(Vector3.ZERO)\n\todm.release_hooks()\n", "new_string": "## Stops pl...
- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/scripts/npc/soldier.gd", "old_string": "func _die() -> void:\n\tvar airborne := not is_on_floor() or odm.is_hooked() or _climbing\n\t_climbing = false\n\talive = false\n\tmotion_mode = CharacterBody3D.MOTION_MODE_GROUNDED\n\todm.release_hooks()\n\todm.ai_steer = Vect...

- Tool call: `StrReplace` {"path": "/home/bazzite/odm-test/tools/export_cursor_transcript.py", "old_string": "    \"e0d67b01-e4b6-45d8-aa23-e82c32d649c6\": \"GitHub repository setup\",\n}", "new_string": "    \"e0d67b01-e4b6-45d8-aa23-e82c32d649c6\": \"GitHub repository setup\",\n    \"58c5e749-b952-4c2a-b056-464f17f0a21f\":...
- Tool call: `Shell` {"command": "python3 tools/export_cursor_transcript.py 58c5e749-b952-4c2a-b056-464f17f0a21f --title \"Clear ODM cables on death\"", "description": "Export Cursor chat transcript"}

Death already called `release_hooks()`, but that only started the retract animation, so cables stayed visible for a bit.

**What changed**
- `ODMHook.detach(instant)` can skip retract and hide the cable/anchor immediately
- `ODMController.release_hooks(instant)` uses that, and also clears in-flight miss cables
- Player and soldier death call `release_hooks(true)`

Normal releases (grab, manual unhook, AI) still use the retract animation.
