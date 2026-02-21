#!/usr/bin/env bash
set -euo pipefail

PUBLISHER="local-mdbeauty"
NAME="open-with-mdbeauty"
VERSION="0.1.0"
EXT_ID="${PUBLISHER}.${NAME}"
TARGET_BASE="${HOME}/.vscode/extensions"
TARGET_DIR="${TARGET_BASE}/${EXT_ID}-${VERSION}"

mkdir -p "${TARGET_BASE}"

# Remove older local versions of the same extension id.
find "${TARGET_BASE}" -maxdepth 1 -type d -name "${EXT_ID}-*" -exec rm -rf {} +

mkdir -p "${TARGET_DIR}"

cat > "${TARGET_DIR}/package.json" <<'JSON'
{
  "name": "open-with-mdbeauty",
  "displayName": "Open with MDBeauty",
  "description": "Adds 'Open with MDBeauty' for Markdown files in Source Control context menu.",
  "version": "0.1.0",
  "publisher": "local-mdbeauty",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [
    "onCommand:mdbeauty.openWithMDBeauty"
  ],
  "main": "./extension.js",
  "contributes": {
    "commands": [
      {
        "command": "mdbeauty.openWithMDBeauty",
        "title": "Open with MDBeauty"
      }
    ],
    "menus": {
      "scm/resourceState/context": [
        {
          "command": "mdbeauty.openWithMDBeauty",
          "group": "navigation@100",
          "when": "resourceExtname == .md || resourceExtname == .markdown || resourceExtname == .mdown"
        }
      ],
      "explorer/context": [
        {
          "command": "mdbeauty.openWithMDBeauty",
          "group": "navigation@100",
          "when": "resourceExtname == .md || resourceExtname == .markdown || resourceExtname == .mdown"
        }
      ]
    },
    "configuration": {
      "title": "MDBeauty",
      "properties": {
        "mdbeauty.appName": {
          "type": "string",
          "default": "MDbeaty",
          "description": "Application name for 'open -a'. Example: MDbeaty"
        },
        "mdbeauty.appPath": {
          "type": "string",
          "default": "",
          "description": "Optional full path to .app bundle. If set, overrides mdbeauty.appName."
        }
      }
    }
  }
}
JSON

cat > "${TARGET_DIR}/extension.js" <<'JS'
const vscode = require("vscode");
const { execFile } = require("child_process");

function resolveUri(input) {
  if (Array.isArray(input)) {
    for (const item of input) {
      const resolved = resolveUri(item);
      if (resolved) return resolved;
    }
    return undefined;
  }

  if (!input) return undefined;
  if (input instanceof vscode.Uri) return input;
  if (input.resourceUri instanceof vscode.Uri) return input.resourceUri;
  if (input.sourceUri instanceof vscode.Uri) return input.sourceUri;
  if (typeof input.fsPath === "string") return vscode.Uri.file(input.fsPath);
  return undefined;
}

function isMarkdownFile(fsPath) {
  return /\.(md|markdown|mdown)$/i.test(fsPath);
}

function runOpen(appTarget, fsPath) {
  return new Promise((resolve, reject) => {
    execFile("/usr/bin/open", ["-a", appTarget, fsPath], (error) => {
      if (error) reject(error);
      else resolve();
    });
  });
}

function activate(context) {
  const disposable = vscode.commands.registerCommand(
    "mdbeauty.openWithMDBeauty",
    async (arg) => {
      const candidate = resolveUri(arg) || vscode.window.activeTextEditor?.document?.uri;
      if (!candidate || candidate.scheme !== "file") {
        vscode.window.showErrorMessage("MDBeauty: file path is not available.");
        return;
      }

      const fsPath = candidate.fsPath;
      if (!isMarkdownFile(fsPath)) {
        vscode.window.showWarningMessage("MDBeauty: this command supports only Markdown files.");
        return;
      }

      const cfg = vscode.workspace.getConfiguration("mdbeauty");
      const appPath = (cfg.get("appPath") || "").trim();
      const appName = (cfg.get("appName") || "MDbeaty").trim() || "MDbeaty";
      const appTarget = appPath || appName;

      try {
        await runOpen(appTarget, fsPath);
      } catch (error) {
        const details = error && error.message ? ` (${error.message})` : "";
        vscode.window.showErrorMessage(
          `MDBeauty: failed to open '${fsPath}' with '${appTarget}'${details}`
        );
      }
    }
  );

  context.subscriptions.push(disposable);
}

function deactivate() {}

module.exports = {
  activate,
  deactivate
};
JS

cat > "${TARGET_DIR}/README.md" <<'MD'
# Open with MDBeauty (local extension)

Adds `Open with MDBeauty` for Markdown files in:

- Source Control context menu
- Explorer context menu

Settings:

- `mdbeauty.appName` (default: `MDbeaty`)
- `mdbeauty.appPath` (optional absolute path to `MDbeaty.app`)
MD

echo "Installed local VS Code extension at:"
echo "  ${TARGET_DIR}"
echo
echo "Next steps:"
echo "  1) Restart VS Code or run: Developer: Reload Window"
echo "  2) In Source Control, right-click a .md file -> Open with MDBeauty"
echo
echo "Optional:"
echo "  Set 'mdbeauty.appPath' in VS Code settings if app name lookup fails."
