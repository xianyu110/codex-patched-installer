# Codex Patched 远程插件同步

此目录用于把账户可见的远程插件 bundle 暴露为本地 Codex marketplace，名称为 `openai-curated-remote-local`。

文件说明：

- `plugin-account.json`：可选的 OAuth/账户配置。留空时只使用本机已有插件 bundle 缓存。
- `sync-remote-plugins.mjs`：生成 `plugin-marketplace/.agents/plugins/marketplace.json`，并复制可用的本地插件 bundle。
- `sync-remote-plugins.ps1`：运行同步脚本，并执行 `codex plugin marketplace add` 注册 marketplace。
- `plugin-marketplace/`：生成的本地 marketplace 根目录。

Token 规则：

- `accessToken` 必须是 ChatGPT/Codex OAuth access token，不能是 OpenAI API Key。
- 任何以 `sk-` 开头的值都会被拒绝。
- 脚本不会打印 token。
- 推荐使用 `authFile` 指向另一份 ChatGPT 登录产生的 `auth.json`，这样不会改变 Codex App 当前的 API Key 登录状态。

行为说明：

- `include` 为空时，脚本会暴露所有账户可见且有可用 bundle 的插件。
- 未配置 OAuth token/auth file 时，只会暴露本机插件 bundle 缓存中已有的插件。
- 缺失 bundle 不会被伪造。把 `downloadMissing` 设为 `true` 后，脚本会尝试下载远端返回了 `bundle_download_url` 的插件 bundle。
- 插件显示不代表外部服务已经授权。GitHub、Figma、Google、Slack 等连接器仍可能需要各自的 OAuth 或工作区授权。

运行：

```powershell
.\sync-remote-plugins.ps1
```
