# Adaptive Environment Loop

Observer should eventually learn which ambient conditions help or hurt work without pretending to read emotions directly.

Useful signal pattern:

- stimulus: music track, YouTube video, playlist, notification style, app state, time of day
- before: input rhythm, focus duration, app switching, camera stability
- during: typing cadence, mouse interruptions, face presence, head direction, pauses
- after: return to task, skipping track, manual note, sustained focus, visible friction

Initial interpretation rules:

- Do not infer "likes music" from a single face frame.
- Do not infer a definitive emotion from the face. Use weak labels such as focus, friction, or strong reaction candidate.
- Treat "irritation" as a possible friction pattern only after repeated evidence: rapid switches, short skips, abrupt input rhythm, or user confirmation.
- Treat surprise as a strong reaction candidate, not a fact, unless the user confirms it.
- Treat a song as helpful only after repeated association with longer focus intervals or lower switching.
- Treat a song as disruptive only after repeated skips, abrupt app switching, or work stalls.
- Always leave automation reversible and visible.

First useful product behavior:

- Observe currently playing track locally from available media sources.
- Auto-pause known media sources when the user is repeatedly absent and input is idle.
- Auto-resume only sources that Observer itself paused, only shortly after return, and only when the output looks like headphones.
- Treat Apple Music as the primary music source for preference learning.
- Treat YouTube as a flexible media source: sometimes music, sometimes learning, sometimes entertainment.
- Record quick skips as weak negative candidates only when the user appears present.
- Record volume increases as weak positive candidates only when the user appears present.
- Keep source family and content type in events so later models can learn situation-specific preferences.
- If the active audio output stops looking like headphones, pause known playing media.
- For ordinary headphones, if media is playing and the listener is no longer visible while input is idle, pause quickly even if macOS still reports the same audio output.
- Direct visual detection of "headphones on head" is a future local vision layer; until then, use listener presence plus audio output as the reliable approximation.
- If music continues while the user is away, keep playback telemetry but do not treat it as taste feedback.
- Lower confidence when the active context is messaging; the reaction may belong to the message, not the song.
- Record strong posture changes and sustained focus as `behaviorCue` events, with low confidence unless repeated.
- Label candidate reactions: `settled`, `energized`, `distracted`, `neutral`.
- Suggest changes before taking control.
- Only auto-switch music after an explicit user opt-in.
