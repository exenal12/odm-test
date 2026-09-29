#!/usr/bin/env python3
"""Export user prompts and assistant replies from local Codex session records."""

import argparse
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "prompts" / "Codex"


def text_of(message):
    return "\n".join(
        part["text"] for part in message.get("content", []) if isinstance(part, dict) and "text" in part
    ).strip()


def export(thread_id, title):
    if not title or title in {".", ".."} or "/" in title or "\\" in title:
        raise ValueError("The chat title must be a safe file name")
    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    records = sorted((codex_home / "sessions").rglob(f"*{thread_id}*.jsonl"))
    if not records:
        raise FileNotFoundError(f"No local session records found for {thread_id}")

    turns = {}
    seen = set()
    for record in records:
        with record.open(encoding="utf-8") as stream:
            for line in stream:
                entry = json.loads(line)
                item = entry.get("payload", {})
                if entry.get("type") != "response_item" or item.get("type") != "message":
                    continue
                message_id = item.get("id")
                if message_id in seen:
                    continue
                seen.add(message_id)
                turn_id = item.get("internal_chat_message_metadata_passthrough", {}).get("turn_id")
                if not turn_id:
                    continue
                role = item.get("role")
                phase = item.get("phase")
                body = text_of(item)
                if not body:
                    continue
                if role == "user":
                    if body.startswith(("<recommended_plugins>", "# AGENTS.md instructions", "<environment_context>")):
                        continue
                    if body.startswith("<send_user_message_question_reply>"):
                        try:
                            answers = json.loads(body.split("\n", 1)[1].rsplit("\n", 1)[0])
                            body = "\n".join(answer["answer"] for answer in answers)
                        except (ValueError, KeyError, IndexError):
                            pass
                    bucket = turns.setdefault(turn_id, {"user": [], "final": [], "commentary": []})["user"]
                    if body not in bucket:
                        bucket.append(body)
                elif role == "assistant" and phase in ("final_answer", "commentary"):
                    key = "final" if phase == "final_answer" else "commentary"
                    bucket = turns.setdefault(turn_id, {"user": [], "final": [], "commentary": []})[key]
                    if body not in bucket:
                        bucket.append(body)

    lines = [f"# {title}", "", f"Codex chat ID: `{thread_id}`", ""]
    included = 0
    for turn in turns.values():
        if not turn["user"]:
            continue
        included += 1
        for prompt in turn["user"]:
            lines.extend(["## User", "", prompt, ""])
        replies = turn["final"] or turn["commentary"]
        for reply in replies:
            lines.extend(["## Assistant", "", reply, ""])
        if not replies:
            lines.extend(["## Assistant", "", "_(No response recorded.)_", ""])
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    target = ARCHIVE / f"{title}.md"
    target.write_text("\n".join(lines), encoding="utf-8")
    print(f"{target}: {included} turns")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("thread_id")
    parser.add_argument("title")
    args = parser.parse_args()
    export(args.thread_id, args.title)
