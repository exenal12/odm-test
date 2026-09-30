# Remove unused assets

Chat ID: 2f47d487-fe4a-48b1-b122-9d0cd982c5f8

## User

remove all unused assets

## Assistant

- Tool call: `GetDynamicTools` {"namespace": "project-0-odm-test-godot-mcp", "toolName": "find_unused_assets"}

- Tool call: `CallDynamicTool` {"namespace": "project-0-odm-test-godot-mcp", "toolName": "find_unused_assets", "arguments": {}}

Several of these look like false positives - main_menu.tscn, forest_world, plugin.gd, game_settings autoload, default_bus_layout. I need to be careful and verify the non-addon candidates with a grep before treating them as real hits.
- Tool call: `Shell` {"command": "cd /home/bazzite/odm-test && for n in node_3d debug_kill titan_features hand_grip head_stabilizer limp_body gas_refill map_bounds build_humanf_library build_humanm_library verify_rebuilt_player noise.gdshaderinc; do echo \"== $n\"; rg -l --glob '!prompts/**' --glob '!.godot/**' --glob '...

I've confirmed head_stabilizer is referenced in player_animation. Now I want to check map_bounds and whether gas_refill.gd is attached through a class_name, so I'll grep for class_name usage.
- Tool call: `Shell` {"command": "cd /home/bazzite/odm-test && for f in scripts/debug/debug_kill scripts/enemies/titan_features scripts/player/hand_grip scripts/player/head_stabilizer scripts/player/limp_body scripts/world/gas_refill scripts/world/map_bounds; do echo \"== $f\"; rg -n '^class_name' $f.gd; done; rg -n -i ...

- Tool call: `Shell` {"command": "cd /home/bazzite/odm-test && rg -n -w 'TitanFeatures|HandGrip|LimpBody|MapBounds' --glob '*.{gd,tscn,tres}' --glob '!addons/**' . | grep -v 'class_name'; rg -n 'debug_kill|gas_refill.gd|node_3d' project.godot scenes scripts | head"}

I'm identifying which files are genuinely unused versus intentional dev tools — node_3d.tscn, debug_kill.gd, and gas_refill.gd look safe to remove, while the tools scripts are documented and should stay. For the addon, I'll leave the phantom_camera core alone but remove its example directory, and double-check gas_refill.gd along with the associated uid files before finalizing.
- Tool call: `Shell` {"command": "cd /home/bazzite/odm-test && rg -l 'gas_refill\\.gd|debug_kill|node_3d\\.tscn' --glob '!prompts/**' --glob '!.godot/**' . ; ls node_3d.tscn* scripts/debug/ scripts/world/gas_refill.gd* addons/phantom_camera/examples"}

- Tool call: `Shell` {"command": "cd /home/bazzite/odm-test && rm -rf node_3d.tscn node_3d.tscn.* scripts/debug scripts/world/gas_refill.gd scripts/world/gas_refill.gd.uid addons/phantom_camera/examples && git status --short | grep -E '^ ?D' | grep -v -E 'traversal|world.tscn|map_switcher' | wc -l"}

I removed the assets that nothing in the project references. I didn't run the project or the Godot editor afterward, so nothing has been tested.

**Deleted**
- `node_3d.tscn`
- `scripts/debug/` (`debug_kill.gd`)
- `scripts/world/gas_refill.gd`
- `addons/phantom_camera/examples/`, which held the demo scenes, models, textures and scripts.

**Kept**
`find_unused_assets` listed 54 files, but many of those are false positives:
- **Loaded in code or registered elsewhere:** the `class_name` scripts (`TitanFeatures`, `HandGrip`, `HeadStabilizer`, `LimpBody`, `MapBounds`) are used in code, `noise.gdshaderinc` is included by the shaders, and `main_menu.tscn`, `forest_world.tscn`, `game_settings.gd` and `default_bus_layout.tres` are loaded by name or registered as autoloads.
- **Other addon files:** the Phantom Camera plugin, manager and C# scripts are the addon itself, so I left them.
- **`tools/build_human*_library.gd` and `tools/verify_rebuilt_player.gd`:** these are dev scripts documented in `tools/README.md`.

Godot may still rebuild its import cache, and the addon deletion will show up in `git status`.
