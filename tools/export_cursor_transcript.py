#!/usr/bin/env python3
"""Export Cursor agent transcripts to prompts/Cursor/<title>.md.

Usage: export_cursor_transcript.py [chat-id ...] [--title "Title"]
With no chat IDs, every chat is exported. Titles come from TITLES; add a topic-based entry for each new chat.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path.home() / ".cursor/projects/home-bazzite-odm-test/agent-transcripts"
OUT = ROOT / "prompts" / "Cursor"


TITLES = {
    "19fc615a-34b4-4631-9ac4-fe2f2b163026": "Procedural map design",
    "fda94d69-2811-4281-9127-3f1ffd97b4de": "ODM gear model refinement",
    "4739e573-4cfa-4dbd-acf8-4c15e8cc7fce": "Tree platform gas suppliers",
    "99c6085f-cdd5-4ae0-af1c-b8b81de5ccea": "HUD visual restyle",
    "69ea6a94-af8b-40ab-92fa-3134eaa9ad7f": "Game sound implementation",
    "56af8281-2a05-4671-8076-25db710a5459": "Titan grab mechanic",
    "357deda7-ff27-4dab-aa0c-5ed1a9af4b0b": "Free asset sourcing for ODM gear",
    "5a4d263f-b860-40ba-b17b-1d74ad01942c": "Game design planning",
    "81119004-a488-4777-a131-3a9a17b990f8": "Custom animation feasibility",
    "857831ba-dc67-4ce2-8b3c-112636922e6f": "Feature-complete scope planning",
    "9906c9ec-0bdc-4c8c-a5b3-77cba4aeaa7c": "Chat transcript archiving",
    "a67a7ef1-13d8-411d-ac2f-4289c0e0395f": "Godot MCP and Cursor setup",
    "af196328-78fc-4306-a622-3e35cf6e55f3": "Traversal animations",
    "c1c42feb-8955-4987-9ac6-bff70f5d7927": "Grapple momentum retention",
    "c4a7ce20-6d00-4c4b-988e-7884b3a51944": "Head tracking during attacks",
    "cd815041-13ae-494d-8132-41c471d3a589": "Allied NPC combat AI",
    "d1a8c542-4e17-46d6-beb0-934f454f7e25": "Prototype world architecture",
    "e0d67b01-e4b6-45d8-aa23-e82c32d649c6": "GitHub repository setup",
    "58c5e749-b952-4c2a-b056-464f17f0a21f": "Clear ODM cables on death",
    "88456fb5-7d2a-40d8-8234-a9ee7cd05f7e": "Spawn logic",
    "2db4892f-8059-4b52-b707-98fec49d5125": "Fix world playground refs",
    "f0846041-2997-4922-bc03-394cc943fb49": "Game title ideas",
    "dcc5fa7d-6212-4ffc-bf23-7c41fba14e49": "Main menu settings page",
    "d26a744c-6edf-4e9e-af56-0c0752c8d4ec": "Airborne movement control",
    "8a37df5e-f557-459e-ac28-8b6d8d3385ea": "Soldier spawn and retreat",
    "2f47d487-fe4a-48b1-b122-9d0cd982c5f8": "Remove unused assets",
    "38f3ccab-0693-4fde-9b0b-0f477b98b1c1": "Titan attack hitbox facing",
    "4c54ad76-dfca-4af4-8e33-2b756eb7c08f": "Soldier distract command",
    "6c08476a-31cb-49f3-a4f8-3072ad0fd9da": "Chat log titles",
    "aec55738-e19b-47c4-b888-1a8e58a5740d": "Gear outfits and world polish",
    "ca5caa3f-cf35-4ae5-80e1-1a9cf7f75a2c": "Main menu",
}


def tool_line(c):
    args = json.dumps(c.get("input", {}), ensure_ascii=False)
    if len(args) > 300:
        args = args[:300] + "..."
    return f"- Tool call: `{c.get('name')}` {args}"


def text_of(msg):
    out = []
    for c in msg["message"]["content"]:
        if c.get("type") == "text":
            out.append(c["text"].strip())
        elif c.get("type") == "tool_use":
            out.append(tool_line(c))
    return "\n".join(out).strip()


def clean_user(t):
    m = re.search(r"<user_query>\s*(.*?)\s*</user_query>", t, re.S)
    return m.group(1) if m else re.sub(r"<timestamp>.*?</timestamp>", "", t, flags=re.S).strip()


def make_title(chat_id):
    return f"Untitled chat {chat_id[:8]}"


def export(chat_id, title=None):
    lines = [json.loads(l) for l in (SRC / chat_id / f"{chat_id}.jsonl").read_text().splitlines() if l.strip()]
    turns = []  # (role, text); consecutive assistant chunks are merged
    for m in lines:
        if "role" not in m or "message" not in m:
            continue
        role = m["role"]
        t = clean_user(text_of(m)) if role == "user" else text_of(m)
        if not t:
            continue
        if turns and turns[-1][0] == role == "assistant":
            turns[-1] = (role, turns[-1][1] + "\n\n" + t)
        else:
            turns.append((role, t))
    first = next((t for r, t in turns if r == "user"), "")
    title = title or TITLES.get(chat_id) or make_title(chat_id)
    safe = re.sub(r'[\\/:*?"<>|]', "", title)
    out = [f"# {title}", "", f"Chat ID: {chat_id}", ""]
    for role, t in turns:
        out += [f"## {'User' if role == 'user' else 'Assistant'}", "", t, ""]
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{safe}.md"
    path.write_text("\n".join(out))
    print(path)


def main():
    args = sys.argv[1:]
    title = None
    if "--title" in args:
        i = args.index("--title")
        title = args[i + 1]
        del args[i : i + 2]
    for cid in args or sorted(p.name for p in SRC.iterdir() if p.is_dir()):
        export(cid, title)


if __name__ == "__main__":
    main()
