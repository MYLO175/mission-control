# What was checked, and what each check means

Run these from the starter root:

```sh
python3 scripts/check.py
python3 scripts/test_foundation.py
python3 foundation/build.py
```

`check.py` validates the catalogue, required files, local authored-document links, reference pointers and SHA-256 manifest. It also exercises the independent-app generator in a disposable temporary directory, including unique identities and refusing to overwrite existing apps.

`test_foundation.py` compiles and executes the real adapted OAuth/claims/signature and SSE/recovery checks, plus local workspace/account/context checks, using disposable paths. It never signs in, reads personal Keychain entries, opens Apple records or uses a subscription request.

The full build checks SwiftUI integration and creates a locally signed bundle. `--render-preview docs/assets/foundation.png` renders fictional foundation content with no credential/file loading. Optional illustrations are generated separately and labelled as illustrations; they do not prove module integration.

## Acceptance tiers

| Evidence | Establishes |
| --- | --- |
| Documentation/catalogue checks | Files, references and catalogue data agree |
| Offline Swift checks | Specific authentication, stream and persistence behaviours under controlled fixtures |
| Full native build and signature | The supplied code compiles and bundles on the tested Mac |
| Fictional preview/render | The illustrated foundation layout renders without personal sources |
| Owner's browser sign-in and explicit access check | That account can complete a request with the selected model at that time |
| Chosen native/source acceptance | The particular integration and approved operation work on that Mac |
| Sustained ordinary usage | Behaviour across real wake cycles, service failures and evolving personal data |

The last three tiers need the owner's selected access and are not claimed by building this starter. Each optional recipe lists its own acceptance work. See `docs/VALIDATION.json` for the actual initial verification results and `CHANGELOG.md` for later releases.
