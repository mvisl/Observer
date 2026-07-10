# Workspace Inference

Observer should reason about the physical workspace, not only app names or camera frames.

Current cheap local signals:

- active app and coarse app intent
- focused window display, when Accessibility exposes window geometry
- mouse display role
- camera-mounted display role
- input recency
- face presence/head direction as weak supporting evidence
- generated `activityInsight` events for learning over time

Deferred signals:

- microphone/voice is a later opt-in layer because current work is mostly silent
- typed content remains out of scope unless explicitly captured through allowlisted UI context

Important rule:

- Pointer/display activity is often a stronger signal of where work is happening than a single camera frame.
- A missing face frame from a side-mounted camera is not absence.
- If the pointer is active on the main workbench, assume the user is working there unless repeated evidence says otherwise.
- Small laptop or camera-adjacent displays may be service/control surfaces.

Good widget output:

- `Дизайн: основной экран`
- `Диалог с ИИ: основной экран`
- `Код: устойчиво в задаче`
- `Поиск / сравнение: много переключений`

Bad widget output:

- `у экрана`
- `камера сбоку`
- `лицо в кадре`
- `активная работа`
