# Adaptive Environment Loop

Observer should eventually learn which ambient conditions help or hurt work without pretending to read emotions directly.

Useful signal pattern:

- stimulus: music track, playlist, notification style, app state, time of day
- before: input rhythm, focus duration, app switching, camera stability
- during: typing cadence, mouse interruptions, face presence, head direction, pauses
- after: return to task, skipping track, manual note, sustained focus, visible friction

Initial interpretation rules:

- Do not infer "likes music" from a single face frame.
- Treat a song as helpful only after repeated association with longer focus intervals or lower switching.
- Treat a song as disruptive only after repeated skips, abrupt app switching, or work stalls.
- Always leave automation reversible and visible.

First useful product behavior:

- Observe currently playing track locally when a media integration exists.
- Label candidate reactions: `settled`, `energized`, `distracted`, `neutral`.
- Suggest changes before taking control.
- Only auto-switch music after an explicit user opt-in.
