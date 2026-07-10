# GitHub Brain Plan

Observer can use GitHub for its syncable brain, but not for private telemetry.

Recommended setup:

- private GitHub repository;
- keep app source code and `brain/` together at first;
- never commit `~/Library/Application Support/Observer`;
- never commit `observer.sqlite`;
- use `brain/` for prompts, schemas, detector definitions, policy, and product notes.

Possible later split:

- `observer-macos`: the app;
- `observer-brain`: shared prompts, schemas, detectors, policies.

Cloud-safe content:

- detector definitions;
- prompt templates;
- non-sensitive settings;
- sanitized examples;
- architecture docs.

Local-only content:

- raw event database;
- OCR text from real work;
- camera/attention event history;
- exported context packs unless manually sanitized.

If a GitHub remote is created, this project can push code and brain files there. A private repo is strongly recommended.

Local helper:

```bash
make github-private REPO=observer
```

This creates a private GitHub repo through `gh` and attaches it as `origin`. Review and commit intentionally before pushing.

Brain-only repo:

```bash
make github-brain REPO=observer-brain
```

This pushes only the `brain/` subtree to a separate private repository. It is the safer option if the app code and local runtime should stay on the Mac while shared product memory syncs through GitHub.
