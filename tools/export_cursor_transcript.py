#!/usr/bin/env python3
"""Export Cursor agent transcripts to prompts/Cursor/<title>.md.

Usage: export_cursor_transcript.py [chat-id ...] [--title "Title"]
With no chat IDs, every chat is exported. Titles default to the first prompt.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = Path.home() / ".cursor/projects/home-bazzite-odm-test/agent-transcripts"
OUT = ROOT / "prompts" / "Cursor"


TITLES = {
    "357deda7-ff27-4dab-aa0c-5ed1a9af4b0b": "Find free ODM gear and humanoid assets",
    "5a4d263f-b860-40ba-b17b-1d74ad01942c": "Plan the Attack on Titan game",
    "81119004-a488-4777-a131-3a9a17b990f8": "Custom animations for ODM gear",
    "857831ba-dc67-4ce2-8b3c-112636922e6f": "Plan missing crucial game features",
    "9906c9ec-0bdc-4c8c-a5b3-77cba4aeaa7c": "Create Cursor chat transcripts",
    "a67a7ef1-13d8-411d-ac2f-4289c0e0395f": "Set up Cursor IDE with Godot",
    "af196328-78fc-4306-a622-3e35cf6e55f3": "Climbing, hanging, and mantling animations",
    "c1c42feb-8955-4987-9ac6-bff70f5d7927": "Preserve grapple momentum",
    "c4a7ce20-6d00-4c4b-988e-7884b3a51944": "Fix head swinging during attacks",
    "cd815041-13ae-494d-8132-41c471d3a589": "Add NPCs that fight titans",
    "d1a8c542-4e17-46d6-beb0-934f454f7e25": "Why the prototype world is scripted",
    "e0d67b01-e4b6-45d8-aa23-e82c32d649c6": "Create a GitHub repo for the Godot game",
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


def make_title(prompt):
    words = re.sub(r"[^\w\s-]", "", prompt).split()[:6]
    return " ".join(words).capitalize() or "Untitled chat"


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
    title = title or TITLES.get(chat_id) or make_title(first)
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
