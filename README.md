# Codex Patched 安装器

这是一个 Windows 上使用的非官方 Codex Patched 安装器。

本仓库 **不重新分发 Codex App 官方二进制文件**。安装器会在用户自己的电脑上自动定位已经安装的官方 Codex App，把完整应用复制到独立目录，再对副本打补丁，并创建 `Codex Patched.lnk` 快捷方式。

## 下载

请从项目主页或 GitHub Releases 下载最新版安装包：

<https://xianyu110.github.io/codex-patched-installer/>

## 环境要求

- Windows
- 已经安装官方 Codex 桌面应用
- 已安装 Node.js LTS，并且 `node`、`npx` 能在 PowerShell 中运行
- 安装时需要网络访问，因为补丁脚本会下载 `@electron/asar`，并从 OpenAI 官方 `openai/codex` 仓库读取最新模型目录

## 安装方法

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

## 补丁内容

- Fast/service tier UI 同时允许 `chatgpt` 与 `apikey` 登录方式，但不会放开 Copilot、Bedrock 等其他模式。
- 保留模型自身的 service tier 支持检查，不会让不支持 Fast 的模型伪装支持。
- 从 OpenAI 官方 Codex 模型目录添加/保留 GPT-5.6 Sol、Terra、Luna。
- 按模型支持情况显示 `low`、`medium`、`high`、`xhigh`、`max`、`ultra` reasoning effort。
- Sol 的 Ultra 在 Responses 请求线上仍按官方设计规范化为 `reasoning.effort = "max"`，并带 `context = "all_turns"`。
- 附带可选的远程插件本地 marketplace 同步脚本，不改变 App 的 API Key 登录状态。

## 远程插件

安装包包含 `sync-remote-plugins.ps1` 和 `plugin-account.json`。

如果 `plugin-account.json` 留空，脚本只会使用本机已有的插件 bundle 缓存。若填写 `authFile` 或 `accessToken`，必须使用 ChatGPT/Codex OAuth token，不能使用 OpenAI API Key。以 `sk-` 开头的值会被拒绝，脚本不会打印 token。

插件出现在列表中不代表外部服务已经授权。GitHub、Figma、Google、Slack 等连接器仍可能需要各自的 OAuth 或工作区授权。

## 更新

官方 Codex App 更新不会自动更新这个补丁副本。官方 App 更新后，请重新运行：

```powershell
%LOCALAPPDATA%\Programs\CodexPatched\Patch-CodexApp.ps1
```

## 免责声明

这是非官方补丁工具，不隶属于 OpenAI，也不代表 OpenAI 官方支持。请自行判断风险后使用。
