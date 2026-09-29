# Project chat transcripts

For every Codex chat about this project, keep a Markdown transcript in `prompts/Codex/` named exactly after the chat title (plus `.md`). Record each user prompt and the assistant's response in order under `## User` and `## Assistant` headings. Include the chat ID near the top so chats with similar titles can be distinguished. Do not include system/developer instructions, reasoning, tool calls, or secrets.

Before finishing each turn, update the transcript with the current user prompt and the exact final response you intend to send. If the chat has earlier turns missing from its file, backfill them first. For local Codex chats, `python3 tools/export_codex_transcript.py <chat-id> "<chat title>"` can reconstruct completed turns from session records; then add the current turn before sending the response. Preserve existing transcript content if local records are unavailable.

# Cursor chat transcripts

For every Cursor chat about this project, keep a Markdown transcript in `prompts/Cursor/` named after the chat title (plus `.md`), with `## User` and `## Assistant` headings and the chat ID near the top. Before finishing each turn, run `python3 tools/export_cursor_transcript.py <chat-id> --title "<chat title>"` to refresh it (omit the ID to re-export all chats). Exclude system instructions and secrets.
