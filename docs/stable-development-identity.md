# Stable Development Identity

Observer's daily development build must keep the same macOS identity between rebuilds so TCC permissions and Keychain ACLs stay attached to the same app.

## Fixed Contract

- `DEVELOPMENT_TEAM`: `4TRT463PSU`
- `PRODUCT_BUNDLE_IDENTIFIER`: `local.observer.dev`
- `PRODUCT_NAME`: `Observer`
- `EXECUTABLE_NAME`: `ObserverApp`
- `CODE_SIGN_IDENTITY`: `Apple Development`
- `CODE_SIGN_ENTITLEMENTS`: `config/Observer.entitlements`
- Install path: `/Applications/Observer.app`

These values live in `scripts/stable-signing-config.sh` and must not be changed per branch, date, commit, build mode, or Codex session.

## Current Audit Snapshot

Before this pass, the installed app at `/Applications/Observer.app` was signed as:

- Bundle id: `local.observer.dev`
- Executable: `ObserverApp`
- Authority: `Observer Local Development`
- TeamIdentifier: not set
- Designated requirement: `identifier "local.observer.dev" and certificate leaf = H"fe693b1e00391b8c720b355248F8B394BF57B229"`
- Entitlements: `com.apple.security.get-task-allow = true`

The packaging script also built and launched from `build/Observer.app` and silently fell back to a local self-signed certificate. That path is now disabled for the daily app.

## Apple Development Certificate Status

At the time of this change, `security find-identity -v -p codesigning` did not expose an `Apple Development` certificate for team `4TRT463PSU`; it only exposed `Observer Local Development`.

The packaging script now fails if that Apple Development identity is missing. It does not fall back to ad-hoc signing, self-signed signing, or a different team.

To make the build runnable, install/create one Apple Development certificate for team `4TRT463PSU` in Xcode, then run:

```bash
scripts/package-dev-app.sh
scripts/verify-stable-signing.sh
```

## Daily Rule

Use only:

```bash
scripts/run-dev.sh
```

This builds, signs, installs, and opens `/Applications/Observer.app`.
