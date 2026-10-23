# Grow the guide alongside 3PO

3PO is the creator's evolving personal app. Mission Control is the reusable setup guide. A new 3PO feature is a candidate for the guide, not an automatic addition to every customer's app.

## Import a deliberate reference update

Use a committed source state. The updater reads Git objects, so ignored files, local app records, unstaged changes and old Git history are not copied.

```sh
python3 scripts/refresh_reference.py --source /path/to/3PO --ref <commit-or-tag>
```

The default is a dry run. It reports changed files and affected recipes. Inspect the actual source changes, confirm they fit the reusable scope, then apply that same ref:

```sh
python3 scripts/refresh_reference.py --source /path/to/3PO --ref <same-commit-or-tag> --apply
```

Only the allowlisted reference snapshot and its manifest are replaced. The foundation, recipes, previews and personal apps are not overwritten. The manifest records the source commit, file digests and import date. Review provider changes for separate foundation backports.

## Promote a feature into a recipe

1. Decide what a new owner actually needs and the smallest independent version that helps. Identify shared dependencies; make optional feature dependencies explicit.
2. Add an entry to `catalog.json`: stable ID, user benefit, status, relative implementation size, preview path, source paths and source prefixes used to detect future changes.
3. Write `features/<id>/README.md` with the benefit, requirements, implementation steps, exact reference pointers and meaningful acceptance checks. Describe implemented behaviour separately from ideas.
4. Add a fictional visual example using `docs/preview-source.html` and capture it into the named PNG path, or render the actual feature in a rigorously isolated fictional preview. Label screenshots and illustrations truthfully. Never capture a normal personal-data app for this guide.
5. Run `python3 scripts/build_catalogue.py` to regenerate the Markdown catalogue and visual chooser. Run `python3 scripts/check.py`, the relevant source checks and any changed foundation checks.
6. Update `CHANGELOG.md` with the source commit, changed recipes, compatibility notes and what was verified. Commit reviewed files to this repository. Keep it private until the owner explicitly changes visibility.

The source prefix map can over-report affected features and cannot prove correctness. Review contracts and adapt the recipe; do not merely swap code and retain old acceptance claims.

## Backport improvements into the foundation

The foundation contains an adapted provider and a new minimal UI/storage layer. Compare provider changes against `foundation/PROVENANCE.json`, port relevant fixes deliberately and rerun auth/stream/workspace checks plus a full build. Account or transport support changes should be checked against current official OpenAI documentation. Bump the foundation version and note compatibility changes.

## How personal apps receive updates

Each generated app belongs to its owner. Record the starter/foundation origin and their own choices. Template changes do not flow into their repository automatically. On a requested update, compare the relevant recipe or foundation change, preserve their identities, data and design, apply it on a reviewable branch and verify their selected capabilities.

Keep a small upgrade note for important fixes. Consider extracting a shared package only after repeated real usage reveals a stable boundary; do not require every personalized app to keep the creator's service graph.

## Recreate the illustrations

The feature illustrations are authored in `docs/preview-source.html`; they contain only fictional information. To recapture them, serve this repository on loopback and use an isolated Playwright CLI session:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

In another terminal:

```sh
playwright-cli --session mission-control-guide open http://127.0.0.1:8765/docs/preview-source.html
python3 scripts/capture_previews.py --cli /path/to/playwright-cli
playwright-cli --session mission-control-guide close
```

A wrapper around Playwright CLI can also be passed to `--cli`. Stop the local server when finished. Review every changed PNG and keep its illustration disclosure visible. The actual foundation preview is generated separately:

```sh
python3 foundation/build.py --render-preview docs/assets/foundation.png
```

The chooser has no remote scripts, fonts or services. After cloning, opening `docs/chooser.html` directly in a normal browser works without serving or uploading it.
