# A tour of 3PO

**3PO brings your day, local project work and personal context into one native workspace.** Start with the dashboard, use the PA for a request, and use Review when a suggestion needs your attention or approval.

[Documentation](../README.md) · [Getting started](GETTING_STARTED.md) · [Architecture](../architecture/ARCHITECTURE.md) · [Detailed behaviour](../architecture/HOW_IT_WORKS.md)

Examples here are fictional. This is the committed 14 October feature baseline; current implementation and sustained model/reliability acceptance are different claims.

## Find a feature

| Feature | What it gives you |
| --- | --- |
| [Dashboard and appearance](#dashboard-and-appearance) | Pages, widgets, focused viewing and saved colours |
| [Calendar and Reminders](#calendar-and-reminders) | Native records, editors and supported verified changes |
| [Personal assistant](#personal-assistant) | Natural conversation, screenshots and explicit queued work |
| [Memory and setup](#memory-and-setup) | Saved facts, evidence, corrections and relevant recall |
| [Projects](#projects) | Spaces, notes, local tasks and progress |
| [Review inbox](#review-inbox) | Worthwhile email reading, action proposals and local drafts |
| [AI Activity](#ai-activity-and-the-toolbar-pill) | Live work, recent task outcomes and local attention |
| [Feedback](#feedback) | Editable preferences about what deserves attention |
| [Brief and weather](#brief-and-weather) | One current brief with readable evidence and an optional forecast |
| [Mail and WhatsApp](#mail-and-whatsapp) | Controlled, read-only source context |
| [Heartbeat and background work](#heartbeat-and-background-work) | Scheduled review, progress and honest recovery |

## Dashboard and appearance

Create saved pages and add widgets for the PA, Calendar, Reminders, Review, Projects/Life map, brief, weather or date/clock. Widgets preview continuously while you move or resize them, then snap and save on release. The dashboard fits the window; each widget's content can scroll. Focused view helps when the window is narrow.

The native customisable toolbar shares the window controls. Its arrangement is saved separately from page/widget layouts; Dashboard, View and Edit menus expose actions even when toolbar items are hidden.

Customise workspace colours separately for light and dark appearance. Individual widgets can override inherited colours. **Save as theme…** saves both palettes as a named local recipe; saved themes support Use, Update, Rename and Remove. The optional 3PO preset uses gold, ivory and bronze. Your PA's display name is also a local setting.

Layout, theme and name edits make no AI request. Native sheets, window chrome and Calendar/list source colours have their own appearance behaviour. [Detailed controls](../architecture/HOW_IT_WORKS.md#appearance-and-pa-name)

## AI Activity and the toolbar pill

The pill is vertically centred, with other controls on the right. Live action work or heartbeat wins; otherwise unresolved questions/failures retain attention. A verified green success, such as Reminder created, lasts six seconds before Ready. One local expiry wakeup avoids streaming-driven history/source reads.

Activity shows up to five task slots, with current action work first and recent outcomes after it with concise outcomes and conversation navigation. Heartbeat history, ordinary replies, context-only reads and queued feedback stay out. There are no acknowledgement controls; complete stored history and acknowledgement fields remain preserved. Exact later replies and verified same-job retry receipts can resolve attention locally without rewriting historical outcomes.

## Calendar and Reminders

Calendar reads the enabled native calendars, including supported iCloud/Exchange accounts. Browse dates, switch views, filter sources and open a record to edit it. Opening a widget returns to today; Day/Week **Now** refocuses the current time.

Drag a writable timed event to preview a new slot. Release saves a fifteen-minute-snapped occurrence edit while preserving duration and checking the current account, widget, source and revision. A click opens the editor. Supported last occurrence edits offer Undo.

Reminders keeps the native list identity, shows incomplete work and exposes list/date views. Click the name to edit; the circle completes the native reminder. Lists can be folded without excluding them from source access or AI context.

The editors expose supported dates, title, notes, URL, destination, repeats and alerts; Calendar also exposes timezone/availability and Reminders priority. Repeating events require the right occurrence/future scope. Native deletion and unsupported series changes have no app Undo. Provider-specific features such as invitations, attachments, tags and subtasks remain in Apple apps.

The PA uses the same guarded native operations for an understood current human request. For example: “Move tomorrow's design review to 14:00.” An ambiguous target/date/scope needs clarification. A save is reported successful only after readback. [Native editing detail](../architecture/HOW_IT_WORKS.md#calendar-and-reminder-customisation)

## Personal assistant

There is one ongoing general conversation, with optional multi-select **Life-area Focus**. Focus makes the request more relevant; it does not grant source access or action permission. Older topic conversations, drafts and tags remain saved.

Ask naturally, then follow up with references such as “do that” when the proposal is clear. The app supplies bounded recent dialogue, relevant usable memories and permitted context; the model can ask local tools for more details. Each job keeps its original account, conversation, Focus, model and permissions. A late result cannot move to a new account or draft.

Paste a screenshot for an explicit image request. Optional dictation depends on macOS permissions. **Stop** interrupts foreground work. Verified earlier changes retain their receipts. The PA continues a foreground request without a fixed tool-count cap, while read/input bounds, subscription limits and duplicate-loop detection remain.

The general delegated PA queue runs serially after explicit enqueue/Continue. Accepted never-started Review jobs instead run automatically when idle, including after reopening; Stop, failure or a question affects its own request. Work needing an answer, a failed request or interrupted recovery waits for human continuation. Reopening does not replay old uncertain writes.

Right-click a reply and choose **Context details…** to inspect supplied memory/notebook IDs, model, Focus and attempted tool names. This describes prepared input rather than what the model attended to. [Conversation detail](../architecture/HOW_IT_WORKS.md#a-pa-conversation)

## Memory and setup

Memory stores preferences, context and commitments with evidence, dates, certainty and version history. Human facts and separately permitted source interpretations remain distinguishable. Source text never overwrites a human fact or grants action authority.

Open **PA menu → Context** or **Settings → Context** for the everyday overview, project/topic pages, working changes and feature instructions. Each project has a direct Context shortcut. Pages update during heartbeats; an explicit Run heartbeat finishes the captured pending-page backlog. Original facts, evidence, correction history and learning controls are under **Supporting facts and controls**. Opening/searching/inspection makes no AI or source request.

Corrections retain earlier wording and evidence; Restore makes a new version. Retiring outdated human context removes it from current recall while preserving history. Forget is a separate operation. Memory resolution does not complete a project task or native Reminder.

The dedicated setup interview has its own draft and session. Opening does not start inference: **Start**, **Next**, **Skip** and **Continue** control progression. It uses memory-only tools and excludes a cached Apple/source snapshot.

Current recall uses lexical relevance, typed links and human-linked plans. A question can correctly retrieve no facts. It does not yet promise semantic matching for every paraphrase or automatic identity consolidation. [Full memory guide](../architecture/MEMORY_AND_CONTEXT.md)

## Projects

Projects creates two kinds of record: **Space** and **Task**. A space is a folder containing spaces/tasks with optional notes. A task is local work, separate from Apple Reminders. Use names and nesting to represent a project, course or life area.

Home shows top-level spaces; **Unfiled tasks** contains tasks without a folder. Opening a space shows direct contents. Folders & tasks is the default view, with List, Tree and Deadlines available. A board uses **To do / In progress / Done**. Progress measures actual saved tasks, not assumed attendance, mastery or unrecorded work.

Drag a task between columns to preview its stage, then release to save the local change. Notes use Save/Cancel with revision checks. Supported last edits have session Undo. Creation has no app Undo; recoverable Delete/Recently deleted retains original identities. A nonempty space cannot be converted into a task.

Browsing never changes the saved opening folder. Use **Open this folder by default** explicitly. You can also request changes naturally: “Create a Sensor Garden space with Research and Evaluation folders,” or “Mark Read paper as done.” Mentioning a project is context rather than an instruction to create it.

Projects and memory share exact identities/links. Filing supported anchors does not author human projects, and completing a local task does not complete a linked Apple Reminder. [Full project guide](../architecture/PROJECT_WORKSPACE.md)

## Review inbox

Review brings together outstanding email actions, genuinely worthwhile reading, source-linked proposals, questions and work needing an answer/outcome check. An email assessment and its supported suggestions share one card and one badge count. Individual actions retain separate approvals and receipts.

**Explore suggested actions** opens one saved source conversation with editable checkboxes for spaces, tasks, Calendar/Reminder creations, exact changes/removals and local reply copies. Evidence stays inside this sheet. Pending cards show Explore alone; after an action completes, the card shows its completed count and **View actions**, with remaining checkboxes inside. Background context, Feedback, View email and Dismiss remain separate. View email may fetch the current body without starting AI analysis.

**Done** approves the checked captured payloads without AI and keeps any unsent draft; Escape closes without approval. Conversation can revise suggestions or execute understood work through the same canonical operation identities. Saved display checks current source/account access rather than reconstructing evidence. Prepared creation approval checks concrete payload, account, destination, duplicate/uncertain receipts and readback. Existing-item edits/removals retain exact target, current-field and occurrence checks. New date suggestions need grounded evidence. Clear cancellation/postponement may support removal of one exact writable Calendar occurrence; repeating removal selects only the displayed occurrence and has no app deletion Undo. Unresolved dates or uncertain targets need clarification.

**Dismiss** acknowledges that exact displayed concern and supports Undo. It does not mean completion, disinterest or sender-wide blocking. Completed proposals and inferred addressed/planned history leave the main inbox; **Activity → Review history** retains supported history and **Keep in review**.

Prepared reply drafts are local: review, edit, save and copy them. There is no email or WhatsApp sending. Exact later same-account confirmation can quiet a fully resolved email request while keeping evidence and independent new/sibling actions. It never automatically completes native or project work.

Compound email actions and existing-project deadlines are implemented as separate reviewable suggestions. Complete extraction, natural-language plan quality and sustained native/provider reliability remain open acceptance. [Current Review detail](../architecture/HOW_IT_WORKS.md#14-october-current-review-and-ai-activity-behaviour)

## Feedback

Use **Feedback** to explain why an email should receive more or less attention. **Submit feedback** retains your words and closes the dialog immediately. It queues for the next heartbeat, one submission per cycle; **Process now** requests immediate priority. A bounded serial job interprets the exact email/comment into a learned preference, and page navigation does not cancel it.

Review preferences and Memory show the same canonical preference, original human words, editable About/scope and version history. Edit or Disable/Restore it. Interpretation is labelled as inferred; explicit sender-wide wording can set broader scope, while a vague comment is not automatically a blanket blacklist.

The card/preferences show progress and any failure. **Stop** targets one submission; foreground typing/sending interrupts active/queued feedback. **Retry learning** is explicit, and **Save only my words** is an explicit fallback. Never-started eligible submissions stay queued after reopening; attempted/interrupted submissions retain their words and require explicit retry. Interpretation checks captured source choices and exact email/account/assessment, model, memory and storage, with body readback. Unrelated Calendar/Reminders notifications do not invalidate it. A verified same-submission retry resolves its failure alert locally while retaining history. Pending submissions are not recall facts. [Feedback and memory detail](../architecture/MEMORY_AND_CONTEXT.md#feedback-about-what-deserves-review)

## Brief and weather

Today's brief shows one current update with its timestamp and **Sources and coverage**. It selects useful commitments, requests and updates rather than listing every message. Partial/disabled/unavailable source coverage remains explicit; “nothing stood out” refers only to checked material.

The header refresh explicitly prepares an AI update. The account's writing instructions are editable through **Edit brief prompt…**; editing alone does not regenerate saved output. The original morning record and its chat/notification delivery remain saved, while later manual/heartbeat updates change the widget without delivering another morning message.

Existing and new ordinary output uses readable source labels while preserving structured evidence and raw saved prose. Saved briefs and Review cards remain dated output under current source/account access; reuse for new reasoning/advice still requires current supporting dependencies.

Optional Weather uses one location fix rounded to 0.1 degrees and an Open-Meteo forecast. The Weather widget and brief weather visibility have separate presentation choices; today's forecast is selected after midnight. A local weather refresh makes no AI request. Coordinates are not retained in cache/context/logs. [Brief and weather detail](../architecture/HOW_IT_WORKS.md#local-weather-and-explicit-brief-refresh)

## Mail and WhatsApp

Mail uses Apple Mail Automation for read-only account/header/body access. Incremental arrival collection uses exact identities and per-account cursors/backoff; bounded historical PA search remains separate. It preserves unread state, reports partial coverage and retains successful cache when an account fails.

Optional WhatsApp links a standalone read-only device through a human-scanned QR code. The helper caches received linked-device text; selecting chats controls which cached conversations can be used by AI. **Selected** shows shared chats; **All chats** lets you choose more. Foreground context, brief and suggestions retain purpose-specific permissions. Source learning may inherit review permission or use an explicit opt-in under global memory controls; newly permitted scopes baseline existing content. Reception and name refresh make no AI call. New chats remain unselected, and local cached text is not complete history.

WhatsApp uses unofficial Baileys, encrypted local records and a Keychain-held key; linking can break or face restrictions. It sends no messages, read receipts or presence commands. [Privacy and source boundaries](PRIVACY.md)

## Heartbeat and background work

Settings → Background controls scheduled review and its interval. A due heartbeat prepares context, processes at most one queued feedback submission, reviews independently collected Mail, offers eligible memory/organisation work, prepares supported suggestions/local drafts, then updates the brief. It has persisted whole-run budgets and per-stage receipts. Settings → Background exposes the optional Daily AI call limit, defaulting to Off while retaining explicit saved numeric choices. **Run heartbeat** (⌘R) explicitly starts this AI work; **Refresh sources only** (⌥⌘R) collects sources without inference.

Scheduled work waits while the system sleeps, the laptop is closed or it is in dark wake. Full wake/launch checks once when due. Recoverable email, memory/organisation or suggestion failures retain separate outcomes and can still permit a supported brief. Ownership, Stop/sleep, foreground and usage guards end the run; completed receipts remain and the next interval starts a fresh cycle. It does not replay uncertain foreground saves or old queues. Quitting the app stops its work; closing the window leaves the menu bar app running.

**View heartbeat history** shows the latest 20 runs with stages, collection issues, failure details and AI usage. The PA header's last-completed time advances only on a completed run. Opening history makes no AI request.

Automatic learning retains global controls, review-permission inheritance or explicit source opt-ins, bounded deltas, shared allowance and persistent failure pauses. An eligible lane can run under exact heartbeat ownership; new permission baselines old content. Foreground typing/Stop wins. [Architecture flow](../architecture/ARCHITECTURE.md#collection-and-heartbeat-are-different-loops)

## Current limits and evidence

The app is a personal development project. Build/signature/installation, deterministic rules, fictional model checks and several days of real use prove different things. The latest candidate's sustained acceptance is still open. Semantic paraphrase recall, broader cross-source episode understanding, local offline inference and phone support remain future work.

The [developer guide](../development/DEVELOPMENT.md#choose-the-right-checks) explains the available checks and their limits. Passing a fixture or build does not establish sustained real-world reliability.
