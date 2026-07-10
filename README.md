# Codex Patched Installer

Unofficial Windows installer for a local patched copy of the Codex desktop app.

This repository does **not** redistribute the Codex App binaries. The installer locates the official Codex App already installed on the user's computer, copies it to a separate local directory, patches the copy, and creates a `Codex Patched.lnk` shortcut.

## Download

Download the latest installer ZIP from the project page or GitHub Releases:

<https://xianyu110.github.io/codex-patched-installer/>

## Requirements

- Windows
- Official Codex desktop app already installed
- Node.js LTS with `node` and `npx` available in `PATH`
- Network access during install, because the patcher downloads `@electron/asar` and the current official model catalog from OpenAI's `openai/codex` repository

## Install

1. Download `CodexPatched-Installer.zip`.
2. Extract it.
3. Open PowerShell in the extracted folder.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-CodexPatched.ps1
```

By default the patched copy is installed to:

```text
%LOCALAPPDATA%\Programs\CodexPatched
```

The installer creates a desktop shortcut named `Codex Patched.lnk`.

## What It Patches

- Enables Fast/service tier UI for both `chatgpt` and `apikey` auth methods only.
- Keeps model-level service tier support checks intact.
- Adds/keeps GPT-5.6 Sol, Terra, and Luna from the official Codex model catalog.
- Enables `low`, `medium`, `high`, `xhigh`, `max`, and `ultra` reasoning visibility where supported.
- Keeps Sol Ultra normalized to Responses wire `reasoning.effort = "max"` with `context = "all_turns"`.
- Adds optional remote-plugin local marketplace sync scripts without changing API key login state.

## Remote Plugins

The package includes `sync-remote-plugins.ps1` and `plugin-account.json`.

Leave `plugin-account.json` blank to use local bundle cache only. If you use `authFile` or `accessToken`, it must be a ChatGPT/Codex OAuth token, not an OpenAI API key. Tokens starting with `sk-` are rejected and are not logged.

Plugin visibility does not grant external service authorization. Connectors such as GitHub or Figma may still require their own OAuth.

## Update

Official App updates do not update the patched copy. After updating the official Codex App, rerun:

```powershell
%LOCALAPPDATA%\Programs\CodexPatched\Patch-CodexApp.ps1
```

## Disclaimer

This is an unofficial patcher. It is not affiliated with or endorsed by OpenAI. Use at your own risk.
