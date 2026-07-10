# MVP-0 Implementation Plan

Goal: create a local macOS observer that recovers work context without using camera data.

## Slice 1 - App Shell

- Swift menu bar app.
- Start, pause, and quit actions.
- Workspace topology config loaded from disk.
- Visible status in the menu bar.

## Slice 2 - Workspace Awareness

- Enumerate connected displays.
- Map displays to roles from the topology profile.
- Track active app and active window title.
- Record focus changes as events.

## Slice 3 - Event Store

- SQLite event log.
- Append-only event writes.
- Simple retention settings.
- Export recent events as readable JSON for debugging.

## Slice 4 - Privacy Allowlist

- Allow content extraction only for approved apps.
- Coarse focus events for everything else.
- One-click exclude current app.

## Slice 5 - Context Pack

- Generate a text block from recent events.
- Include current task guess, recent app/window changes, and notable loops.
- No external API required.

## Slice 6 - Local Summaries

- 15 minute summary from deterministic rules first.
- Add local model summarization only after the event stream is stable.

## Deferred To MVP-1

- Camera.
- Attention calibration.
- Gesture detection.
- Push hints.
- External LLM adapters.
