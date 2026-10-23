# Getting started

**Build a fictional sample first, then configure the sources and AI context you want.** 3PO is currently a source-built macOS development app, rather than a downloadable public release.

[Documentation](../README.md) · [Features](FEATURES.md) · [Developer guide](../development/DEVELOPMENT.md) · [Privacy](PRIVACY.md)

## Requirements

| Requirement | Purpose |
| --- | --- |
| macOS 26 or later | Native SwiftUI/SwiftData application |
| Xcode at `/Applications/Xcode.app` | Compiler, macOS SDK and signing |
| Python 3 | Project/icon generation and check runner |
| npm and a development Node installation | WhatsApp dependency preparation; optional connector runtime packaging |
| Internet for initial preparation | Dependency and checksum-pinned runtime downloads |
| Suitable Apple Development signing identity | Current project generator contains the original developer's team |
| Eligible connected ChatGPT subscription, for AI | Inference uses the app's documented registration flow and available account models |

The native dashboard can be built independently of signing into ChatGPT. AI eligibility/model allowance depends on the connected account; a successful build does not prove inference.

## Build from source

Clone the repository with your existing GitHub access, then enter its root:

```sh
git clone https://github.com/MYLO175/3PO.git
cd 3PO
```

On another Mac, inspect the signing team/identity in [the project generator](../../scripts/project/generate-project.py) and configure your own before building. Keep `com.mylomichael.missioncontrol` when updating an existing installation, since permissions, registration and saved data depend on that identity.

```sh
MISSIONCONTROL_BUILD_ROOT=/private/tmp/3po-docs-example ./scripts/build.sh
```

The script selects `/Applications/Xcode.app/Contents/Developer` for that process, installs missing helper dependencies, packages the pinned Node runtime, regenerates the app icon/Xcode project and builds Debug. It does not change the global developer setting. Build output is:

```text
/private/tmp/3po-docs-example/derived-data/Build/Products/Debug/3PO.app
```

Without `MISSIONCONTROL_BUILD_ROOT`, each invocation prints its unique temporary build directory and log path. [Developer guide](../development/DEVELOPMENT.md#build-and-generated-files) explains the other supported overrides and concurrent build isolation.

## Explore with fictional data

```sh
open /private/tmp/3po-docs-example/derived-data/Build/Products/Debug/3PO.app --args --sample
```

This DEBUG sample dashboard bypasses normal source collection, helper connection and scheduling. It previews the layout without reading or writing Apple records, but still opens existing local app storage and loads saved credentials/settings. It is a presentation preview with shared data, not disposable storage. Audited signed app-memory modes provide disposable service checks. Do not run a normal second candidate alongside an existing personal-data instance; both use the same storage and permissions.

## Configure normal use

For an existing installation, follow [Updating an existing installation](../development/DEVELOPMENT.md#updating-an-existing-installation): quit the app, make a complete recoverable backup, and verify the signed replacement and saved records. For a first normal launch, open the built app without `--sample`.

1. **Choose native sources.** Grant Calendar/Reminders permissions and Mail Automation only for the integrations you want. Check source status and source filters. Denied/unavailable access is different from an empty source.
2. **Connect the assistant.** In Settings, use **Continue with ChatGPT** and the app's registration flow. Pick a model offered by the connected account, then choose **Check account access · 1 request** to verify inference. Sign-in/model discovery alone is not an inference check. Credentials stay in Keychain; there is no API-key fallback.
3. **Choose AI context.** Review Calendar/list/Mail account and optional WhatsApp controls before permitting personal content in inference. Brief/suggestion use and foreground use retain purpose-specific controls. Review-permitted sources may teach bounded source memory under the global memory controls, alongside explicit learning opt-ins.
4. **Set up memory deliberately.** The native setup interview starts only when you choose Start. Review memory-use and conversation/source-learning controls. New source-learning opt-ins baseline old content rather than indexing all history.
5. **Arrange the dashboard.** Add widgets/pages, choose colours and place project spaces. Browsing a Projects folder does not set its default opening folder; use that explicit menu action.
6. **Enable scheduled work if wanted.** Choose the heartbeat interval in Background settings. Check its stages/history, global learning controls and review-permission inheritance. The heartbeat can offer a bounded eligible learning lane; newly permitted sources baseline existing content.

Optional WhatsApp requires a human-scanned QR code and explicit chat selection. Optional Weather requests a location fix; dictation has separate macOS permissions. [Privacy](PRIVACY.md) describes what each source can expose.

## Your first useful actions

| Try | Expected behaviour |
| --- | --- |
| **Refresh sources only** · ⌥⌘R | Collect local sources; no AI request |
| “What should I focus on today?” | Explicit PA request with relevant permitted context |
| Create a space and a task | Local project work, separate from Apple Reminders |
| Inspect Memory or reply Context details | Local saved-record inspection; no new inference |
| **Run heartbeat** · ⌘R | Explicit AI review and brief update under current controls |
| Dismiss a Review card, then Undo | Reversible acknowledgement of that displayed concern |

## If something looks wrong

| Symptom | Check |
| --- | --- |
| Build signing fails | Your signing identity/team and full Xcode installation; regenerate after changing the generator |
| The app is not at an old `/tmp/missioncontrol-derived` path | Read the printed build directory, or set the explicit build root above |
| Calendar/Reminders/Mail appear unavailable | macOS permissions, app source controls, source status and the Apple account's availability |
| Source refresh did not generate a brief | Use the explicit brief refresh or Run heartbeat; source collection does not infer |
| Heartbeat says Retry or shows an old brief | Inspect the failed stage and next due time; completed receipts and the previous brief are retained |
| A memory is absent from recall | Inspect current version, age, scope, consent/source support and relevance; zero selected facts can be valid |
| A submitted preference is still pending | It normally waits for the next heartbeat; Process now requests priority. Never-started jobs remain queued after reopening; attempted/interrupted jobs need explicit retry |
| A native save has an uncertain outcome | Inspect the retained operation receipt and verify the outcome before another attempt |

Don't treat unavailable source coverage as proof that there is nothing to do. The [feature guide](FEATURES.md) explains source and behaviour limits; the [developer guide](../development/DEVELOPMENT.md#choose-the-right-checks) explains verification tiers.
