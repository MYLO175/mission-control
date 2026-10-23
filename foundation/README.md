# The small working foundation

A native SwiftUI macOS 26+ app with a supplied light/dark theme, chat, saved conversations, account connection and an on-demand daily brief. It has no native source collectors, external integrations, action tools or automatic inference jobs.

```sh
python3 build.py --run --preview
```

The fictional preview does not initialize ChatGPTConnection or WorkspaceStore. For your own app, use the starter's `scripts/create_app.py`; it copies this directory and assigns new stable identities. Then run that app's `build.py --run` and complete your own sign-in in Settings.

## Source map

| Area | Files | Responsibility |
| --- | --- | --- |
| Identity and build | `app.json`, `build.py` | Name/theme, stable bundle ID, generated identity, local app bundle and signing |
| Provider | `Sources/Provider/` | Adapted OAuth, callback, Keychain accounts, renewal, model catalogue and completed SSE transport |
| Local workspace | `Sources/Core/WorkspaceStore.swift` | Account-separated messages, drafts, priorities and briefs; atomic JSON persistence |
| Conversation | `Sources/Core/FoundationModel.swift` | Captured account/request ownership, explicit Send/Stop, transient streaming and manual brief generation |
| Appearance | `Sources/UI/Theme.swift`, `Sources/UI/WorkspaceView.swift` | Supplied palettes, sidebar, chat, Today and connection settings |
| Lifecycle | `Sources/MissionControlApp.swift` | Normal window or isolated fictional preview/render path |
| Checks | `Tests/` | Offline auth, stream and workspace acceptance cases |

Only recent completed messages are sent for chat continuity (up to 40 messages and 60,000 characters). Incomplete assistant output is labelled and excluded. Credentials use this app's own Keychain service; local workspace JSON is not encrypted by the app. Decoding or saving failures pause further workspace writes rather than replacing unreadable data. There is no automatic retry or paid fallback.

## Extending it

Follow a feature recipe in the starter. Add a dedicated service and explicit controls, then mount its UI/tools only if selected. The provider has a typed tool-response transport for future adapters, but the foundation exposes no tools. Keep source refresh separate from model work, and background scheduling separate from on-demand briefs.

See `PROVENANCE.json` for the original 3PO provider files and their adaptation notes. Updating the reference snapshot does not overwrite this foundation or a generated personal app.

## Verification

From the starter root, run `python3 scripts/check.py` for catalogue/reference/content checks and `python3 scripts/test_foundation.py` for offline Swift checks. To build this app directly, run `python3 build.py`. Live sign-in/inference needs the owner's own consent and is tested separately.
