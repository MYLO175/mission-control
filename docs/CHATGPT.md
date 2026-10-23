# Connect your own ChatGPT subscription

The foundation uses the documented **Sign in with ChatGPT** flow for open-source apps. It connects the app owner's own eligible account. The coding assistant building your app can be Claude, Codex or another tool; that choice does not change this runtime connection.

## In the app

1. Open Settings and choose **Continue with ChatGPT**.
2. Complete the browser flow and review sign-in and ChatGPT plan-use permissions yourself.
3. Choose **Refresh models** and select a model offered to this account.
4. Choose **Check access · 1 request**. This sends a short source-free prompt and requires a completed response before chat is enabled.

Signing in, listing models and completing inference are different checks. An account may sign in without having plan-use permission or usable allowance. Availability and limits are set by OpenAI and the account/workspace. Using this connection draws from the owner's plan allowance; it does not provide free or unlimited inference.

## Reusable implementation

The foundation includes an adapted version of 3PO's provider code: loopback callback, fresh state/nonce/PKCE, ID-token signature and claims validation, account-bound issued client IDs, token renewal, Keychain persistence, dynamic model selection and completed-response SSE handling. The app name comes from the generated identity. No creator credentials or registration are supplied.

Transport uses the public Responses endpoint with `store: false` and `stream: true`, and locally supplies required conversation history. It has no API-key billing fallback and does not use another app's session. Stop cancels the request. Partial streams are not accepted as completed responses or replayed automatically.

The foundation does not register action tools. For optional tools, keep functions locally executed and appropriately scoped. Provider-hosted MCP/connectors are not automatically supported by this subscription route; see the current limitations before designing an integration.

## Current official references

Verified against official OpenAI documentation on **23 October 2026**:

- [Registration and sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Accounts and sessions](https://developers.openai.com/siwc/token-sharing-open-source/accounts-and-sessions)
- [Models and completed inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Preview limitations and supported tools](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Recheck these pages when updating the adapter. Endpoint requirements, supported accounts and model availability can change. The reference source records prior implementation; the current official contract governs new integration work.

## Acceptance

Offline auth and stream tests cover state/claims/signatures, framing, completion and failures. Building the app does not prove live access. A new owner completes their own browser consent, model selection and one-request check. Live access was not exercised while preparing this starter, and no personal ChatGPT credentials were borrowed for it.
