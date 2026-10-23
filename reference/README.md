# A worked example: 3PO

The creator's personal Mission Control is called **3PO**. Its committed application source, tests, build helpers and published documentation are copied into [3po/](3po/README.md) so recipes work without depending on a moving branch or another repository's visibility.

[manifest.json](manifest.json) records the exact source commit and SHA-256 of every imported file. The source repository is [MYLO175/3PO](https://github.com/MYLO175/3PO). This is a file snapshot with fresh starter history. Personal planning files, ignored local files, app data and old Git history are not imported.

The reference is an integrated, larger app. It is not installed by creating a foundation app. Start from the relevant recipe, inspect its named components and adapt only what your own app needs. The original bundle ID, storage, OAuth name and signing team describe the creator's app and must be replaced when adapting code. Some documents describe the original system rather than the smaller foundation.

Do not edit this copy as if it were the customer's app. [Maintenance](../docs/MAINTAINING.md) explains how to refresh it deliberately and then update the affected recipes. New upstream code does not silently change anyone's app.
