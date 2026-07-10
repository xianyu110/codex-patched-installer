# Remote plugin sync for Codex Patched

This directory exposes account-visible remote plugin bundles as a local Codex marketplace named `openai-curated-remote-local`.

Files:

- `plugin-account.json`: optional OAuth/account input. Leave it blank to use only the local bundle cache already present on this machine.
- `sync-remote-plugins.mjs`: builds `plugin-marketplace/.agents/plugins/marketplace.json` and copies available local plugin bundles.
- `sync-remote-plugins.ps1`: runs the sync script and registers the marketplace with `codex plugin marketplace add`.
- `plugin-marketplace/`: generated local marketplace root.

Token rules:

- `accessToken` must be a ChatGPT/Codex OAuth access token, not an OpenAI API key.
- Any value starting with `sk-` is rejected.
- Tokens are never printed by the scripts.
- Prefer `authFile` if you have a separate ChatGPT-login `auth.json`; this keeps the Codex App API Key login unchanged.

Behavior:

- If `include` is empty, the script exposes every account-visible plugin that has an available bundle.
- If no OAuth token/auth file is configured, it exposes all plugins found in the local bundle cache.
- Missing remote bundles are not faked. Set `downloadMissing` to `true` to try downloading remote bundles that include `bundle_download_url`.
- Plugin visibility does not authorize the external service. GitHub, Figma, Google, Slack, and other connectors can still require their own OAuth or workspace approval.

Run:

```powershell
.\sync-remote-plugins.ps1
```
