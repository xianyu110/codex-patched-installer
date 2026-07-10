# Codex Patched 安装器

这是一个 Windows 和 macOS 上使用的非官方 Codex Patched 安装器。

本仓库 **不重新分发 Codex App 官方二进制文件**。安装器会在用户自己的电脑上定位已经安装的官方 Codex App，把完整应用复制到独立目录，再对副本打补丁。Windows 会创建 `.lnk` 快捷方式；macOS 会创建独立的 `.app` 副本和启动器。

## 下载

请从项目主页或 GitHub Releases 下载最新版安装包：

<https://xianyu110.github.io/codex-patched-installer/>

## Windows

### 环境要求

- Windows
- 已经安装官方 Codex 桌面应用
- 已安装 Node.js LTS，并且 `node`、`npx` 能在 PowerShell 中运行
- 安装时需要网络访问，因为补丁脚本会下载 `@electron/asar`，并从 OpenAI 官方 `openai/codex` 仓库读取最新模型目录

### 安装方法

1. 下载 `CodexPatched-Installer.zip`。
2. 解压 ZIP。
3. 在解压后的文件夹中打开 PowerShell。
4. 运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-CodexPatched.ps1
```

默认安装目录：

```text
%LOCALAPPDATA%\Programs\CodexPatched
```

安装完成后会创建桌面快捷方式 `Codex Patched.lnk`。

### 更新

官方 Codex App 更新不会自动更新补丁副本。官方 App 更新后，请重新运行：

```powershell
%LOCALAPPDATA%\Programs\CodexPatched\Patch-CodexApp.ps1
```

## macOS

### 环境要求

- macOS 12 或更高版本。
- 已安装官方 Codex 桌面应用。当前官方 macOS 包可能显示为 `ChatGPT.app`，但其 bundle identifier 是 `com.openai.codex`，安装器会同时识别 `Codex.app` 和 `ChatGPT.app`。
- Node.js LTS，且 `node`、`npx` 可在 Terminal 中运行。
- 网络访问，用于下载 `@electron/asar` 并读取 OpenAI 官方 Codex 模型目录。

不需要管理员权限。安装器只会在 `~/Applications`、`~/Library/Application Support/CodexPatched`、`~/.codex` 下写入文件。

### 安装方法

从仓库根目录运行：

```bash
chmod +x installer/macos/*.sh installer/macos/*.command
./installer/macos/Install-CodexPatched-macos.sh
```

默认位置：

```text
~/Applications/Codex Patched.app
~/Library/Application Support/CodexPatched
```

安装后会在桌面创建 `Open Codex Patched.command`。请通过该启动器打开副本，它会传入独立的 `--user-data-dir`，避免与官方 App 复用 Electron 用户数据。也可手动运行：

```bash
~/Library/Application\ Support/CodexPatched/macos/Open-CodexPatched.command
```

若自定义模型 provider 的运行时列表没有返回 GPT-5.6，macOS 菜单仍会显示官方目录中的 GPT-5.6 Sol、Terra、Luna 备用条目。显示条目不代表 provider 一定支持请求；实际对话仍由 provider 的服务端能力决定。

若官方 App 不在默认位置，请显式指定：

```bash
./installer/macos/Install-CodexPatched-macos.sh \
  --source-app "/path/to/Codex.app"
```

安装器会复制已安装 App 的当前架构，因此同时支持 Apple Silicon 和 Intel Mac；它不会下载或重新分发任何官方 App 二进制文件。

macOS 会验证 `app.asar` 的 Electron integrity 哈希，并对副本执行 ad-hoc signing。副本不再具备 OpenAI 原始 Developer ID 签名，系统首次启动时可能仍要求在“系统设置 > 隐私与安全性”中确认打开。

下载官方模型目录时，安装器会先验证 JSON。网络暂时不可用而本机已有有效模型目录时，会自动使用该缓存；也可使用 `CODEX_PATCHED_OFFLINE=1` 在更新脚本中明确启用缓存模式。

### 更新

官方 Codex App 更新不会自动更新补丁副本。官方 App 更新后，运行：

```bash
~/Library/Application\ Support/CodexPatched/macos/Patch-CodexApp-macos.sh
```

## 补丁内容

- Fast/service tier UI 同时允许 `chatgpt` 与 `apikey` 登录方式，但不会放开 Copilot、Bedrock 等其他模式。
- 保留模型自身的 service tier 支持检查，不会让不支持 Fast 的模型伪装支持。
- 从 OpenAI 官方 Codex 模型目录添加/保留 GPT-5.6 Sol、Terra、Luna。
- 按模型支持情况显示 `low`、`medium`、`high`、`xhigh`、`max`、`ultra` reasoning effort。
- Sol 的 Ultra 在 Responses 请求线上仍按官方设计规范化为 `reasoning.effort = "max"`，并带 `context = "all_turns"`。
- 附带可选的远程插件本地 marketplace 同步脚本，不改变 App 的 API Key 登录状态。

补丁依赖当前 Codex App 的资源文件名和压缩后的代码片段。若官方版本发生变化，安装器会在匹配失败时停止，不会静默生成半完成的 App 副本。

## 远程插件

安装包包含 `sync-remote-plugins.ps1`、`sync-remote-plugins-macos.sh` 和 `plugin-account.json`。

如果 `plugin-account.json` 留空，脚本只会使用本机已有的插件 bundle 缓存。若填写 `authFile` 或 `accessToken`，必须使用 ChatGPT/Codex OAuth token，不能使用 OpenAI API Key。以 `sk-` 开头的值会被拒绝，脚本不会打印 token。

插件出现在列表中不代表外部服务已经授权。GitHub、Figma、Google、Slack 等连接器仍可能需要各自的 OAuth 或工作区授权。

Windows：

```powershell
.\sync-remote-plugins.ps1
```

macOS：

```bash
~/Library/Application\ Support/CodexPatched/macos/sync-remote-plugins-macos.sh
```

## 免责声明

这是非官方补丁工具，不隶属于 OpenAI，也不代表 OpenAI 官方支持。请自行判断风险后使用。
