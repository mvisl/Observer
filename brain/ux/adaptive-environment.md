# Adaptive Environment Loop

Observer should eventually learn which ambient conditions help or hurt work without pretending to read emotions directly.

Useful signal pattern:

- stimulus: music track, YouTube video, playlist, notification style, app state, time of day
- before: input rhythm, focus duration, app switching, camera stability
- during: typing cadence, mouse interruptions, face presence, head direction, pauses
- after: return to task, skipping track, manual note, sustained focus, visible friction

Initial interpretation rules:

- Prefer evidence fusion over publishing single-channel candidates. Camera, text, media, input rhythm, and task context should accumulate evidence into a hypothesis; confidence rises when independent channels agree.
- Treat single-channel posture or camera reactions as internal evidence by default, not widget text.
- Give AI-chat writing context high weight for task understanding. Prompts written into Codex, ChatGPT, Claude, or Gemini are usually the user's own distilled description of the current task or blocker.
- Do not infer "likes music" from a single face frame.
- Do not infer a definitive emotion from the face. Use weak labels such as focus, friction, or strong reaction candidate.
- Treat "irritation" as a possible friction pattern only after repeated evidence: rapid switches, short skips, abrupt input rhythm, or user confirmation.
- Text can be a strong frustration signal when it contains explicit negative language, rule-violation language, uppercase emphasis, or repeated punctuation.
- When frustration text mentions design, visual chaos, broken layout, or unnecessary elements, treat it as cause evidence. Promote it to a cause only after confirmation or corroborating context.
- Treat surprise as a strong reaction candidate, not a fact, unless the user confirms it.
- Treat a song as helpful only after repeated association with longer focus intervals or lower switching.
- Treat a song as disruptive only after repeated skips, abrupt app switching, or work stalls.
- Build personal baselines by hour of day before treating typing speed, switching frequency, gaze stability, or pauses as abnormal.
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
- Ask for lightweight validation later: a few high-confidence candidates per day should be confirmable as yes/no/unsure, and detector weights should learn from that.
- Suggest changes before taking control.
- Only auto-switch music after an explicit user opt-in.

Privacy and protection behavior:

- If the user is away and a face appears near the computer, treat this as a local information-protection incident.
- Do not take hidden screenshots, hidden camera captures, or hidden microphone recordings of other people.
- Record safe metadata first: time, current allowed app/window metadata, presence signal, input idle duration, and whether identity is unverified.
- Any future screenshot/audio capture for security must be explicit, visible, local-first, and clearly labeled as protective monitoring.
- If sensitive content is open while the user is away, prefer reversible protective actions such as pausing media, hiding the widget detail, or suggesting/triggering lock-screen behavior.
