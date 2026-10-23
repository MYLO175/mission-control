# Build this person's Mission Control

You are the coding assistant helping a person build their own macOS workspace. Treat this repository as a guide with reusable code. Your deliverable is their working app with their chosen features.

## 1. Learn what they need

Read [the interview guide](docs/INTERVIEW.md) and [the catalogue](docs/FEATURES.md). Ask two or three practical questions per round. Start with their routine and intended use, then recommend a small useful selection. Explain each suggested feature in plain language and show its local PNG preview using an absolute file path in a client that supports images, or link its feature page. Label illustrative previews honestly. Do not ask the person to understand technical terms or select every integration at once.

Ask what they want to call their app. Explain that the original creator calls his 3PO, but there is no requirement to use that name. Offer Mission Control if they have no preference.

Use the supplied Warm sage appearance automatically. Ask about visual changes only if they express a preference. Calendar, Reminders, Projects, Review, memory, heartbeat, Mail, WhatsApp, weather and MCP are all optional. Do not silently add features. Offer simple on-demand chat and a daily brief as the baseline; a request to omit the brief is also valid.

Distinguish the AI building the app from the model used inside the finished app. ChatGPT plan access requires the owner's own eligible account and explicit sign-in/plan permission. Never borrow the creator's registration or another app's credentials.

## 2. Save a short specification

Use [the example](examples/workspace-spec.example.json) as a shape, not the person's answers. Store their actual specification under `personal/workspace-spec.local.json` (ignored by Git), or in their own private app repository. Include name, identity, appearance, selected and deferred features, data sources, permitted actions and any desired schedule. Record their answers and assumptions explicitly. Never commit those answers to this starter.

Summarize the initial scope so they can correct it. Their feature selections authorize the routine reversible implementation and checks: proceed without asking the same permission again. Essential missing account access or a consequential ambiguity may need a concise question. Do all independent work while waiting.

## 3. Create their independent app

Read [Mac setup](docs/MAC_SETUP.md), [ChatGPT setup](docs/CHATGPT.md) and [the foundation](foundation/README.md). Run `scripts/create_app.py` with the chosen name and destination. This copies only the small foundation and creates fresh app, preferences, Keychain and storage identities. It does not copy the catalogue, 3PO snapshot or integrations into the app.

Build and launch its fictional preview first. Have the person complete their own ChatGPT sign-in when ready; never automate their consent or account selection. Discover models offered to that account, let them choose one, then use the explicit one-request connection check. Do not infer access from sign-in alone. No API billing fallback.

## 4. Add the chosen features, one at a time

Follow the matching `features/<id>/README.md`. Consult only relevant files in `reference/3po/`; this snapshot describes an integrated personal app, not a package manager. Adapt code into small services appropriate to this app. Review dependencies before implementation. If a recipe would require another user-facing feature, explain and offer a smaller implementation or ask about the dependency. Do not silently install the full application.

Mount UI, register tools, request permissions, start collectors and schedule inference only for selected features. Hiding a widget does not disable its service. Source refresh and AI analysis are separate. A daily brief must work with user-supplied priorities without native integrations; on-demand generation must work without heartbeat. Keep customer app names and account identities out of reference branding.

An MCP integration used by the coding assistant is not automatically available inside the app. Implement and verify a local client/adapter only if selected; keep provider-hosted tool limitations in view.

## 5. Verify and hand over

Follow each recipe's acceptance checks and [the verification guide](docs/VERIFICATION.md). Test Stop, unavailable access, reopen and account ownership where relevant. Use fictional fixtures before testing real sources. For native changes, test an explicitly approved disposable item and verify saved values by readback. Never replay an uncertain write.

Tell the owner what works, what was actually tested, what still needs their sign-in/permissions and which features were deferred. Give them a normal launch command or installed app location and a short maintenance guide. A successful build is not proof of live subscription access, native-source accuracy or sustained background reliability.

## Later changes

When they return, read their existing specification and code. Add or remove the requested feature without restarting the interview or replacing their customizations. Consult [maintenance](docs/MAINTAINING.md) for deliberate upstream updates; do not automatically overwrite their app from the template.
