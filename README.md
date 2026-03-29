# MDbeaty

Lightweight, fast and clean macOS Markdown viewer.

## Features

- fast launch and rendering
- full Markdown formatting (headings, lists, tables, code blocks, quotes)
- embedded images, including relative paths from the opened file
- startup auto-scroll to `#fragment` from file URLs
- built-in table of contents with active section highlight while scrolling
- auto-expanded window on launch (fills available screen area, not macOS Full Screen)
- multi-tab workflow with parallel Markdown files
- opening a new `.md` from Finder while app is running opens a new tab
- drag-and-drop `.md` files
- `File -> Open` and `File -> Recent` menu items (`Cmd+O`, `Cmd+R` for reload)
- auto-reload when the file changes on disk

## Run

```bash
swift run MDbeaty
```

Open a specific file right away:

```bash
swift run MDbeaty /absolute/path/to/file.md
```

## Build

```bash
swift build
```

## Build `.app` bundle

```bash
./scripts/build-app.sh
```

Bundle path:

```text
dist/MDbeaty.app
```

Optional debug bundle:

```bash
./scripts/build-app.sh debug
```

Sign with Developer ID during build:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

## Share App So It Launches on Another Mac

For "double-click and run" on your friend's Mac, you need:

1. Apple Developer membership (Developer ID certificate).
2. Notarization via Apple.

One-command release pipeline (signed + notarized + stapled + ZIP):

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mdbeauty-notary" \
./scripts/release-notarized.sh
```

Output:

- `dist/MDbeaty.app` (stapled)
- `dist/release/MDbeaty-<version>-macOS.zip` (share this file)

Create the notary profile once:

```bash
xcrun notarytool store-credentials "mdbeauty-notary" \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

## Free Share (Unsigned DMG)

If you do not want to pay for Apple Developer membership, create an unsigned DMG:

```bash
./scripts/make-dmg.sh
```

Output:

- `dist/release/MDbeaty-<version>-unsigned.dmg`

Friend flow:

1. Open DMG.
2. Drag `MDbeaty.app` to `Applications`.
3. First launch: right-click `MDbeaty.app` -> `Open` -> `Open`.

Generate app icon (`Resources/AppIcon.icns`) from script:

```bash
./scripts/make-app-icon.sh
```

## Register in Finder / LaunchServices

```bash
./scripts/register-app.sh
```

After registration, assign it as default for `.md`:

1. Select any `.md` file in Finder.
2. `Get Info` -> `Open with` -> `MDbeaty`.
3. Click `Change All...`.

## VS Code Source Control Menu (Open with MDBeauty)

Install a local VS Code extension that adds `Open with MDBeauty` for `.md` files in:

- Source Control context menu
- Explorer context menu

Run:

```bash
./scripts/install-vscode-mdbeauty-menu.sh
```

Then reload VS Code (`Developer: Reload Window`).

If VS Code cannot find the app by name, set `mdbeauty.appPath` in settings to the full `.app` path.
