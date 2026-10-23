# Terms used in 3PO

[Documentation](../README.md) · [Features](FEATURES.md) · [Architecture](../architecture/ARCHITECTURE.md)

| Term | Meaning |
| --- | --- |
| **3PO / Mission Control** | Current product name / codebase and stable storage identity. |
| **PA** | The personal assistant: saved conversation, context preparation and tools around a connected language model. |
| **Source** | An original system such as Apple Calendar, Reminders, Mail or a selected WhatsApp chat. |
| **Collection** | Permitted source reads into local caches. It makes no model calls. |
| **Inference** | A model request to interpret input or generate an answer. Separate from source collection. |
| **Heartbeat** | One due or explicitly requested background review cycle: context, queued feedback, email review, eligible learning/organisation, suggestions/drafts and current brief. |
| **Focus / Life area** | Selected topics that help relevance. They do not grant permissions or turn unrelated facts into relevant context. |
| **Fact / belief** | A saved preference, context or commitment, with origin, evidence, certainty, dates and version lineage. |
| **Source memory** | A separately permitted interpretation attributed to exact source evidence; not a human assertion or write authority. |
| **Current / usable / selected** | Latest belief / passes permission, scope, age and evidence gates / relevant enough to include in this request. These are different states. |
| **Notebook / Life map** | Derived views of usable memories and exact workspace anchors, rather than another independent facts database. |
| **Recall** | Local selection of relevant usable facts. Currently lexical with typed/human-reviewed connections, not embeddings. |
| **Canonical identity** | The stable exact record identity used across views, memory and Projects so a rename or move does not create a different entity. |
| **Space / Task** | A local folder with optional notes / local project work. A Task is separate from Apple Reminders. |
| **Anchor / binding** | An exact reference connecting memory organisation to an existing workspace/source record. |
| **Evidence / dependency** | Original quote/identity/version supporting a record / saved support that must remain valid before new reasoning/advice is reused. Saved Review display and concrete creation approval follow their own access/payload/receipt checks. |
| **Revision** | Version marker or snapshot used to detect a change between read, review and save. |
| **Occurrence / series** | One instance of a repeating native event / its repeating sequence. Write scope must be explicit. |
| **Receipt** | Persisted identity and status of an operation or completed result. A pending receipt can represent an uncertain outcome. |
| **Review conversation / Done** | Saved source discussion with editable checkboxes / approval of checked captured actions without AI, preserving an unsent draft. |
| **AI Activity / pill** | Five recent task slots and current action work / live work, unresolved attention or a six-second verified green success. |
| **Queued feedback / Process now** | Explicit email interpretation at the next heartbeat, one per cycle / immediate priority through the same coordinator. |
| **Dismiss / Feedback** | Acknowledgement of that displayed concern / an explicit editable preference about attention. Neither implies completion. |
| **Context details** | A saved reply trace of supplied IDs/counts, model, Focus and attempted tools; not model attention or private reasoning. |
| **Runtime port / adapter** | A narrow injected capability / the desktop bridge that supplies it. Lets services run with fictional dependencies in tests. |
| **Worktree** | An isolated code checkout. It still shares app data, accounts, Keychain and installation on this Mac. |
| **Source-free / candidate / live acceptance** | Fictional deterministic checks / checks of a signed compiled app / evidence from actual UI, sources and ordinary use. |
