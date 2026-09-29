# Godot MCP and Cursor setup

Chat ID: a67a7ef1-13d8-411d-ac2f-4289c0e0395f

## User

what all do i need to do to set up my cursor ide with my godot project? is there an MCP server i can use?

## Assistant

**Exploring project setup**

I need to figure out the guidance for the user regarding the Godot project and its existing files. They mentioned needing help with the setup and MCP. Since MCP is continuously evolving, it would be best to gather the latest information, possibly through a web search. I'm thinking we might only find Supabase instead of Godot tools, but I could also inspect the relevant files for more context.
- Tool call: `Glob` {"target_directory": "/home/bazzite/odm-test", "glob_pattern": "*"}
- Tool call: `rg` {"pattern": "godot|project.godot|mcp", "path": "/home/bazzite/odm-test", "output_mode": "files_with_matches", "head_limit": 50}
- Tool call: `WebSearch` {"search_term": "Cursor IDE Godot MCP server setup 2026", "explanation": "Check current Cursor and Godot MCP integration options."}

**Inspecting project setup**

I need to tailor my answer specifically to the current repo. It makes sense to inspect the project.godot file, so I’ll look into that. I might need to check if Godot is installed or if the node is available. Additionally, reading the file and checking the shell version could provide useful context. I'm considering how all these elements fit together to give an accurate and helpful response!
- Tool call: `ReadFile` {"path": "/home/bazzite/odm-test/project.godot"}
- Tool call: `ReadFile` {"path": "/home/bazzite/odm-test/node_3d.tscn"}
- Tool call: `Shell` {"command": "pwd && godot --version 2>/dev/null || true && node --version 2>/dev/null || true", "working_directory": "/home/bazzite/odm-test", "block_until_ms": 10000, "description": "Check Godot and Node versions"}

**Explaining setup details**

I need to clarify the setup, specifically regarding the project located at the /var/home path alias. It’s crucial to exercise caution with third-party MCP servers since there isn't a single official one to rely on. I'll recommend a particular option. To find the best information on this, I'll search for the official Cursor documentation, which should provide more context and guidance on the project setup. I just want to make sure everything’s clear!
- Tool call: `WebSearch` {"search_term": "site:docs.cursor.com MCP mcp.json project configuration Cursor"}
- Tool call: `WebSearch` {"search_term": "Godot 4.7 official external editor Cursor GDScript language server"}
- Tool call: `WebFetch` {"url": "https://github.com/yanhuifair/Godot-MCP"}

Yes. For your project, you need three layers:

1. Godot project
2. Cursor’s GDScript/editor integration
3. Optional MCP connection for live Godot context and actions

Your project is already a Godot 4.7 project (`project.godot`), with a basic `Node3D` scene.

## Recommended setup

### 1. Open the correct folder in Cursor

Open:

```text
/var/home/bazzite/odm-test
```

The `/home/bazzite/odm-test` path appears to resolve to the same project.

Cursor should see `project.godot` at the workspace root—not one directory above or below it.

### 2. Install the Godot extension

In Cursor’s Extensions panel, install:

```text
godot-tools
```

This provides GDScript syntax support, completion, diagnostics, navigation, and integration with Godot’s language server.

### 3. Configure Godot to use Cursor

In Godot:

`Editor → Editor Settings → Text Editor → External`

Enable **Use External Editor** and select Cursor’s executable.

On Linux, it is commonly one of:

```text
/usr/bin/cursor
```

or:

```text
~/.local/bin/cursor
```

Use these external-editor flags:

```text
{project} --goto {file}:{line}:{col}
```

Keep Godot open with this project loaded. Godot’s language server normally runs on port `6005`.

Godot’s official documentation covers this integration:

[Godot external editor documentation](https://docs.godotengine.org/en/4.7/tutorials/editor/external_editor.html)

### 4. Verify Godot itself is available

Your project targets Godot 4.7. Verify that the executable is installed and on your PATH:

```bash
godot --version
```

The earlier check found Node.js `v25.9.0`, but did not find a `godot` command. If Godot is installed through Flatpak, the executable may instead be:

```bash
flatpak run org.godotengine.Godot --version
```

## MCP options

There is no official Godot MCP server maintained by Godot. There are several community servers.

### Easiest option: `yanhuifair/Godot-MCP`

This is a Node-based MCP server that Cursor can launch automatically.

In Cursor, use:

`Settings → Tools & Integrations → Add Custom MCP`

The configuration is approximately:

```json
{
  "mcpServers": {
    "godot-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@yanhuifair/godot-mcp", "-p", "."]
    }
  }
}
```

Alternatively, create:

```text
.cursor/mcp.json
```

in the project root.

Then:

1. Open the project in Godot.
2. Open Cursor’s MCP settings.
3. Confirm `godot-mcp` is connected.
4. Use Cursor Agent mode.
5. Test with a request such as:  
   “Inspect the current Godot project and describe the scene tree.”

Repository: [yanhuifair/Godot-MCP](https://github.com/yanhuifair/Godot-MCP)

### More integrated option: `vberai/godot-mcp`

This installs as a Godot addon and runs an HTTP MCP server inside the Godot editor, usually on `127.0.0.1:3000`.

Its workflow is:

1. Copy the addon into `res://addons/`.
2. Enable it under `Project → Project Settings → Plugins`.
3. Open its Godot panel.
4. Start the local MCP server.
5. Use its one-click Cursor configuration.

Repository: [vberai/godot-mcp](https://github.com/vberai/godot-mcp)

This option may provide better live editor/scene interaction, but it requires installing a third-party addon into the project.

## What MCP adds

Without MCP, Cursor can:

- Read and edit `.gd`, `.tscn`, and project files
- Use GDScript completion and diagnostics
- Help write scripts and scenes

With MCP, Cursor may additionally be able to:

- Inspect the live scene tree
- Query nodes and properties
- Run Godot-related operations
- Interact with the open editor, depending on the server
- Get more accurate project context than file scanning alone

Start with one MCP server only. MCP servers can execute tools on your machine, so review their permissions and keep any Godot HTTP server bound to localhost.

### Suggested order

1. Confirm `godot --version`.
2. Install `godot-tools` in Cursor.
3. Configure Cursor as Godot’s external editor.
4. Open and run the project once.
5. Add the Node-based MCP server.
6. Only add the Godot addon-based server if you need deeper live-editor control.

**Clarifying setup steps**

I need to address a directory mismatch, specifically between /var/home and /home symlink. Since the user asks what they need, I'll provide guidance without edits. Including exact config might be too detailed, but illustrative guidance seems okay. I'll differentiate MCP options: stdio npx is the easiest, while the Godot plugin offers richer control but requires more trust. I should recommend starting with yanhuifair or vberai based on findings. I need to verify if Godot's command is installed or in path. Lastly, I’ll mention that the project config includes Jolt and a checklist for setup.
**Detailing MCP configuration**

The MCP config JSON may need to be exact. For plugin-based use, I should note that vberai requires downloading an addon and enabling it in the project on the localhost server. However, it's crucial not to set both options simultaneously to avoid conflicts or duplicates. I also need to emphasize security, ensuring that localhost is the only point of access and that users inspect their tools. Including concise source links would be helpful too!

## User

i downloaded godot via the website and have the executable stored

## Assistant

Great. Since the earlier check did not find `godot` on your PATH, do this:

1. Make the downloaded executable runnable:

```bash
chmod +x /path/to/Godot_v4.7-stable_linux.x86_64
```

2. Launch your project:

```bash
/path/to/Godot_v4.7-stable_linux.x86_64 --editor --path /var/home/bazzite/odm-test
```

3. Optional: make `godot` available globally:

```bash
mkdir -p ~/.local/bin
ln -s /path/to/Godot_v4.7-stable_linux.x86_64 ~/.local/bin/godot
```

If needed, add this to your shell PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then verify:

```bash
godot --version
```

In Godot, configure Cursor under:

`Editor → Editor Settings → Text Editor → External`

Set the editor executable to your Cursor executable, commonly:

```text
/usr/bin/cursor
```

Use:

```text
{project} --goto {file}:{line}:{col}
```

Then open `/var/home/bazzite/odm-test` in Cursor and install the `godot-tools` extension.

If you tell me the exact path and filename of the Godot executable, I can give you the exact commands and Cursor editor path.

## User

i added it to path but godot --version doesn't work, the executable is in the Documents/Godot folder, i already created the link to ~/.local/bin

## Assistant

The most likely issue is that your current terminal has not reloaded `PATH`, or the symlink points to the wrong file.

Run these commands:

```bash
ls -la ~/Documents/Godot
ls -l ~/.local/bin/godot
readlink -f ~/.local/bin/godot
~/.local/bin/godot --version
```

If the direct command works, refresh your current shell:

```bash
export PATH="$HOME/.local/bin:$PATH"
hash -r
godot --version
```

To make it permanent for Bash:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

If `~/.local/bin/godot --version` fails, recreate the link using the executable’s exact filename. For example:

```bash
chmod +x ~/Documents/Godot/Godot_v4.7-stable_linux.x86_64
ln -sfn "$HOME/Documents/Godot/Godot_v4.7-stable_linux.x86_64" "$HOME/.local/bin/godot"
```

Then run:

```bash
~/.local/bin/godot --version
```

If it still fails, paste the output of the four diagnostic commands above.

## User

direct command doesn't work even though the symlink is there in the bin folder

## Assistant

A symlink can exist while being broken, pointing to a directory, or pointing to a non-executable file. Run these and paste the output:

```bash
ls -l ~/.local/bin/godot
readlink -f ~/.local/bin/godot
file ~/.local/bin/godot
~/.local/bin/godot --version
```

The error usually means:

- `No such file or directory` → broken symlink
- `Permission denied` → executable permission missing
- `Is a directory` → link points to the folder, not the Godot binary
- `Exec format error` → wrong download, such as Windows instead of Linux

If the result is `Permission denied`, run:

```bash
chmod +x "$(readlink -f ~/.local/bin/godot)"
~/.local/bin/godot --version
```

The symlink must point to the actual Linux executable inside `~/Documents/Godot`, not merely the `Godot` folder.

**Diagnosing symlink issues**

I need to diagnose this problem more precisely. Simply explaining the existence of the symlink isn’t enough; I should ask for output too. It’s possible that the symlink points to a path with spaces. The direct command `/.local/bin/godot` should invoke the program if there is execute permission on the target. It might help to check Documents for casing issues on Linux. I should ask the user to run some commands, like:  

```  
ls -l /.local/bin/godot  
readlink -e...  
file...  
stat -c...  
```  

It's crucial to get the exact error messages to troubleshoot effectively.
**Recreating file robustly**

I should suggest recreating the symlink using the actual file through shell globbing if there’s just one executable. I can set the executable like this:  

```  
GODOT_BIN=$(find "$HOME/Documents/Godot" -maxdepth 1 -type f -name 'Godot*linux*' -print -quit)  
chmod u+x "$GODOT_BIN"  
ln -sfn "$GODOT_BIN" "$HOME/.local/bin/godot"  
"$HOME/.local/bin/godot" --version  
```  

However, a developer mentioned not to use shell for file operations. We might need the exact filename, so I can recommend using `ls -l` for checking the symlink structure, followed by `readlink -f`, and then testing the executable with `file`. If there’s a `Permission denied` issue, I can suggest changing permissions, and `No such file` indicates a broken link. If there’s an `Exec format error`, it could be the wrong architecture—make sure the download matches the x86_64 format.

The symlink is broken because it contains a relative target:

```text
godot -> Godot_v4.7.2-stable_linux.x86_64
```

Since the link lives in `~/.local/bin`, it looks for the executable there instead of in `Documents/Godot`.

From your current directory, run:

```bash
chmod +x Godot_v4.7.2-stable_linux.x86_64
ln -sfn "$PWD/Godot_v4.7.2-stable_linux.x86_64" "$HOME/.local/bin/godot"
```

Then verify:

```bash
readlink -f ~/.local/bin/godot
~/.local/bin/godot --version
```

You should see:

```text
Godot Engine v4.7.2...
```

After that, `godot --version` should work if `~/.local/bin` is in your `PATH`.

## User

im triyng to set up the mcp server and its not working

## Assistant

**Inspecting the JSON file**

I need to examine the mcp.json file since the user mentioned troubleshooting. It's important to check what’s inside this file to address any issues. I'll read through its contents carefully to identify potential problems or errors that might need fixing. This step feels critical, as understanding this file will help me assist the user better. Let’s see what I can find!
- Tool call: `ReadFile` {"path": "/home/bazzite/odm-test/.cursor/mcp.json"}

**Diagnosing package issues**

I need to figure out if the current package issues are caused by Node 25, maybe related to npx not working. I might need to ask about the error, but I can inspect the MCP using the Cursor. However, we don’t have a dynamic tool for that. I should consider running the npx package in the terminal, possibly checking network settings. I don't need to edit anything unless requested, and I’m aiming to help with their setup.
- Tool call: `Shell` {"command": "npx -y @yanhuifair/godot-mcp -p . --help", "working_directory": "/var/home/bazzite/odm-test", "block_until_ms": 30000, "description": "Test the configured Godot MCP command"}

Your JSON is syntactically valid, and the MCP package itself launches successfully from this project. The likely issue is that Cursor starts MCP with a different working directory and may not inherit your shell’s PATH, so `-p "."` and automatic Godot detection are fragile.
- Tool call: `Shell` {"command": "command -v npx; command -v godot; readlink -f ~/.local/bin/godot; godot --version", "working_directory": "/var/home/bazzite/odm-test", "block_until_ms": 10000, "description": "Check MCP executable paths"}
- Tool call: `ReadLints` {"paths": ["/home/bazzite/odm-test/.cursor/mcp.json"]}

Your shell setup is working:

- `npx`: `/home/linuxbrew/.linuxbrew/bin/npx`
- Godot: `/home/bazzite/.local/bin/godot`
- Godot version: `4.7.2`

Cursor likely cannot see your shell PATH. Update `.cursor/mcp.json` to use absolute paths:

```json
{
  "mcpServers": {
    "godot-mcp": {
      "type": "stdio",
      "command": "/home/linuxbrew/.linuxbrew/bin/npx",
      "args": [
        "-y",
        "@yanhuifair/godot-mcp",
        "-p",
        "/var/home/bazzite/odm-test",
        "-g",
        "/home/bazzite/.local/bin/godot"
      ]
    }
  }
}
```

Then reload or restart the MCP server in Cursor.

You may also need to install the Godot-side addon once:

```bash
/home/linuxbrew/.linuxbrew/bin/npx -y @yanhuifair/godot-mcp \
  --enable-plugin \
  -p /var/home/bazzite/odm-test \
  -g /home/bazzite/.local/bin/godot
```

After that:

1. Open the project in Godot.
2. Enable the Godot MCP plugin under `Project → Project Settings → Plugins`.
3. Keep Godot open.
4. Restart `godot-mcp` in Cursor.
5. Test it in Agent mode with:  
   `Inspect the current Godot scene tree.`

**Troubleshooting user requests**

The user is saying something isn’t working, and it seems like they want to fix an issue but haven’t explicitly asked for help editing. I think I should provide clear guidance on troubleshooting instead. Since they have a file already, I’ll suggest an exact configuration without making edits myself. I’ll mention the correct paths and check if Cursor supports certain features before advising them to look at logs if there's still an issue.

## User

inspect the current Godot scene tree

## Assistant

The current scene tree is:

```text
Node3D
```

It is the root node in `node_3d.tscn`, with no child nodes yet.
