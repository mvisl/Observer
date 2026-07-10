# Observer

Local macOS work observer prototype.

Observer is a menu bar app that starts with MVP-0: workspace topology, active app/window observation, coarse input timing, local SQLite event logging, privacy allowlists, local summaries, and context pack generation.

It does not capture screenshots, camera frames, video, audio, or typed characters in MVP-0.
Text captured through allowlisted Accessibility/OCR paths is redacted before storage for obvious secrets, tokens, card-like numbers, and short verification codes.

## Run

Build a local development app:

```bash
scripts/package-dev-app.sh
```

The packaging script uses a stable local signing identity when possible. This helps macOS remember camera permission across development rebuilds instead of treating each ad-hoc build as a new app.

Open:

```bash
open build/Observer.app
```

The app appears only in the macOS menu bar.

It also shows a small floating widget above all windows. Drag it to reposition it.

Convenience commands:

```bash
make test
make app
make run
make inspect
make diagnose
make install-login
make uninstall-login
make github-private REPO=observer
make github-brain REPO=observer-brain
```

GitHub CI is included under `.github/workflows/ci.yml` and runs `swift test` on macOS.

## Menu Actions

- `Start Observing`: starts coarse local observation.
- `Pause`: stops observation.
- `Start Camera Attention`: starts local face-presence attention sampling. Frames are processed in memory and not stored.
- `Stop Camera Attention`: stops camera sampling.
- `Show Widget`: shows the floating widget.
- `Hide Widget`: hides the floating widget.
- `Reset Widget Position`: brings the widget back to the upper-right corner of the main screen.
- `Collect Context`: copies a context pack to the clipboard and prints it to the app log.
- `Generate Local Summary`: creates a deterministic local summary from recent events and copies it to the clipboard.
- `Generate Research Digest`: produces a quieter research digest from summaries, detector patterns, hints, and notes.
- `Export Context File`: saves the current context pack under `Exports`.
- `Export Research Digest`: saves the current research digest under `Exports`.
- `Export Events JSONL`: exports local events as JSONL under `Exports`.
- `Generate Local LLM Insight`: asks a local Ollama server for a concise insight, if Ollama is installed and running.
- `Set Gemini API Key`: stores a Gemini API key in macOS Keychain. The key is not written to settings, logs, exports, SQLite, or GitHub brain files.
- `Delete Gemini API Key`: removes the Gemini API key from Keychain.
- `Generate Gemini Insight`: sends a compact, user-triggered context packet to Gemini and copies the answer to the clipboard.
- `Show Timeline`: opens a local event timeline.
- `Add Note`: stores a local note linked to the current workspace context.
- `Capture OCR For Current App`: runs local Apple Vision OCR for the current app, only if that app is allowlisted.
- `Allow Current App Context`: allows Observer to read compact Accessibility context for the current app.
- `Private: Exclude Current App`: records the current app as excluded in privacy config.
- `Delete Last Hour`: deletes Observer events from the last hour after confirmation.
- `Reset Local Memory`: deletes all Observer events after confirmation.
- `Request Accessibility Access`: asks macOS for Accessibility permission so Observer can read active window titles.
- `Request Camera Access`: asks macOS for camera permission used by local attention sampling.
- `Open Camera Privacy Settings`: opens macOS camera privacy settings if the system prompt did not surface.
- `Request Screen Recording Access`: asks macOS for permission needed by OCR/window capture.
- `Current Setup`: prints the workspace topology.
- `Open Data Folder`: opens the local data directory.
- `Open Settings File`, `Open Privacy File`, `Open Exports Folder`: quick access to local configuration and exported context packs.

## Local Data

Observer stores data in:

```text
~/Library/Application Support/Observer
```

Files:

- `workspace-topology.json`: physical workspace profile.
- `observer-settings.json`: summary interval, retention, and detector thresholds.
- Hint delivery is quiet by default: candidates are logged, and the widget surfaces at most one soft hint per interval.
- Camera attention sampling is throttled by default to avoid filling the log with noisy per-frame data.
- Allowlisted screen context refreshes quietly on an interval and is deduplicated before storage.
- `privacy.json`: excluded app ids.
- `observer.sqlite`: local event database.
- `Exports/`: exported context packs.
- `brain/`: syncable product brain for GitHub, without private telemetry.
- Gemini API key: macOS Keychain only, under Observer's Gemini service.

While observing, Observer also writes quiet local summaries on a timer. The default interval is 15 minutes.
Local deterministic detectors run during summary generation and can add `detectorFired` events for frequent app switching, return loops, and reading/thinking pauses.
Observation and camera attention now start on launch by default for this prototype. Camera frames are still processed in memory only and are not stored.

## Current Limits

- Screen capture is manual-only for OCR and only for allowlisted current apps.
- OCR uses local Apple Vision and stores recognized text snippets, not images.
- Camera attention is coarse: face present/off-screen, face position in frame, confidence. It is not eye tracking.
- The floating widget translates camera/input signals into soft states such as `активно работает`, `думает / читает`, `не у экрана`, and shows camera startup/permission states.
- External model calls are manual-only. `Generate Gemini Insight` sends a compact context packet only when explicitly triggered.
- Optional local LLM insight uses local Ollama at `127.0.0.1:11434` only.
- SQLite is not encrypted yet; SQLCipher is the intended durable backend later.

Optional local LLM model:

```bash
OBSERVER_OLLAMA_MODEL=llama3.2 open build/Observer.app
```
