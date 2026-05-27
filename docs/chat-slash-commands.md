# LuminaVaultClient — Chat Slash Commands

The Think tab treats any composer message beginning with `/` as a deterministic skill command.

Flow:

1. `ChatViewModel.send()` appends the user command bubble locally.
2. The command is sent to `POST /v1/skills/slash` through `SkillsHTTPClient.runSlash(command:)`.
3. The returned markdown is appended as an assistant bubble.
4. Normal non-slash messages continue through the existing memory-grounded SSE or fresh chat-completions transports.

The iOS client does not own alias semantics. The server parser maps commands such as `/kb-ingest`, `/kb-compile`, `/patterns`, `/contradict`, and `/beliefs` to the correct backend service or skill manifest.

For command discovery, use `GET /v1/skills` to show enabled skill names. Built-in aliases are documented in `LuminaVaultServer/docs/skills-slash-commands.md`.
