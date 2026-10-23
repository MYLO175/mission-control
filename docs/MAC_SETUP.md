# Get your Mission Control running on a Mac

Your coding assistant can do the file and build work. You choose the name, features and your own account access.

## Prepare the Mac

Use macOS 26 or later, full Xcode at `/Applications/Xcode.app`, and Python 3. Open Xcode once to complete any first-launch components. No Node installation is needed for the foundation. Optional features can introduce their own requirements.

Check the tools:

```sh
xcodebuild -version
python3 --version
```

The build script chooses Xcode for its own process and never changes the Mac's global developer setting.

## Look around with fictional information

From this repository:

```sh
python3 foundation/build.py --run --preview
```

This builds a standalone native app with local ad-hoc signing and opens its preview. The preview is a separate early path: no saved accounts, Keychain access, disk store loading, network requests or real sources. It does not sign you in. Optional feature illustrations are in [the catalogue](FEATURES.md).

## Create your own app

After the short [setup interview](INTERVIEW.md), choose a new destination. The example below uses Atlas; you can use any display name.

```sh
python3 scripts/create_app.py --name "Atlas" --destination "$HOME/Developer/Atlas"
python3 "$HOME/Developer/Atlas/build.py" --run --preview
```

The generator refuses to overwrite an existing folder. It copies only the foundation and writes a fresh bundle/storage/Keychain identity. Keep that identity for future updates. To choose your own reverse-DNS bundle identifier, pass `--bundle-id com.example.atlas` when creating it.

`app.json` holds the display name, stable bundle ID and theme. Supported supplied themes are `sage` (default), `ocean`, `graphite`, `rose` and `gold`. Your coding assistant can adapt the design further.

## Connect your own account

Open the app normally:

```sh
python3 "$HOME/Developer/Atlas/build.py" --run
```

Go to Settings, select Continue with ChatGPT and finish sign-in in your browser. Then refresh available models, choose one and run the explicit one-request connection check. [ChatGPT setup](CHATGPT.md) explains this flow and usage.

You can now chat, save priorities and generate a daily brief. Nothing runs automatically. Calendar, Reminders and other source permissions are not requested by the foundation.

## Build outputs and signing

`build.py` writes the app under `.build/<app name>.app` by default. `--output /private/tmp/my-build` chooses another build directory. The app can be built with no third-party packages. It uses `swiftc`, creates its own bundle and applies ad-hoc signing for local development.

A stable Apple signing identity is a later implementation step for distribution or native permission-sensitive integrations; the Calendar and Reminders recipes cover that. Do not copy the creator's signing team. Do not replace an existing app while it is running: quit it and preserve its complete data before installing a new build.

## Where your information lives

The generated bundle ID names its own preferences, Keychain service and Application Support folder. Chats, drafts, priorities and briefs are local JSON; they are not all encrypted. Credentials live separately in macOS Keychain. Account conversations are kept separate. Content you explicitly submit is sent to the connected model; there are no source collectors in the foundation.

Initialize a separate private Git repository in your app folder if you want version control. Never commit account data or credentials. The generated app includes its own ignore rules and a short README.
