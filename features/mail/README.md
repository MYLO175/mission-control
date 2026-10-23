# Read-only Mail

Bring relevant messages into view, with drafts you control.

![Illustrative Read-only Mail preview with fictional content](../../docs/assets/features/mail.png)

*Illustrative preview, not a live customer screenshot. Optional features require integration into the generated app.*

**Status:** Reference code available. **Implementation size:** advanced (a relative guide, not a time promise).

## Is this useful for me?

Useful if incoming messages influence your work. Start with selected accounts and read-only lookup. Assessment, drafts and Review are additional choices.

You can defer this and add it later. It is not included merely because its reference code is present in this repository.

## What it needs

Apple Mail Automation and selected account/purpose controls. Mail is read-only in the reference implementation.

The common foundation supplies account connection, app identity and basic storage. Optional dependencies are choices to explain, not reasons to install every 3PO subsystem.

## Implementation recipe

1. Choose Apple Mail accounts and whether the app may show headers, read bodies or send selected content to inference for the chosen purpose.
2. Adapt read-only collection and bounded lookup. Request Mail Automation only when connecting. Keep collection and model interpretation separate.
3. Use incremental per-account identity/cursor coverage and backoff; a body-read failure must not stop every account or imply there is no mail.
4. If drafts are selected, keep them local for review/edit/copy. Do not add sending, mark-read or other Mail writes. Add Review or heartbeat only if the owner chooses those features.

## Code to reuse or study

- [MailService.swift](../../reference/3po/MissionControl/Sources/Mail/MailService.swift)
- [MailReader.js](../../reference/3po/MissionControl/Sources/Mail/MailReader.js)
- [MailLookup.swift](../../reference/3po/MissionControl/Sources/Mail/MailLookup.swift)
- [EmailSummaryService.swift](../../reference/3po/MissionControl/Sources/Email/EmailSummaryService.swift)
- [ReviewFeedbackService.swift](../../reference/3po/MissionControl/Review/Feedback/ReviewFeedbackService.swift)

These files describe an integrated reference app at the commit in [the manifest](../../reference/manifest.json). Adapt the relevant behaviour and its tests; do not copy its complete service graph or original signing/storage identities. Some components depend on other 3PO types and will not compile when pasted alone.

## Check that it works

- Collection makes no inference requests and preserves Mail read/unread state.
- Unavailable accounts are labelled unavailable; partial history is not presented as complete.
- A selected lookup respects account boundaries, stops promptly and never sends a reply.
- Draft text stays local until the person copies or separately handles it.

Use fictional fixtures first, then the owner's explicitly selected source access where needed. Record build, fixture, live account/source and sustained-use results separately. Update the owner's private specification and handover notes.

[Back to the catalogue](../../docs/FEATURES.md) · [Setup workflow](../../START_HERE.md)
