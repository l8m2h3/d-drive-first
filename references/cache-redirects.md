# 缓存与目录重定向到 D 盘

按 R4：工具支持自定义目录时就显式改到 D 盘。先建好目标目录，再设置变量或配置。

下文用 `$DROOT` 指工作根，默认 `D:\APP`，可用环境变量 `D_WORK_ROOT` 覆盖（见 `SKILL.md` 的「工作根」）。

## 一次性：当前会话的进程级设置

只影响当前 shell 和它启动的子进程，不写任何持久配置，最安全：

```powershell
$DROOT = if ($env:D_WORK_ROOT) { $env:D_WORK_ROOT } else { 'D:\APP' }
New-Item -ItemType Directory -Force "$DROOT\.tmp", "$DROOT\.cache", "$DROOT\downloads" | Out-Null
$env:TEMP = "$DROOT\.tmp"
$env:TMP  = "$DROOT\.tmp"
```

## 持久化：用户级环境变量

会写入用户注册表（不是文件数据），换会话仍生效。若用户要求「绝对零 C 盘写入」，只用上面的进程级方式。

```powershell
[Environment]::SetEnvironmentVariable('TEMP', "$DROOT\.tmp", 'User')
[Environment]::SetEnvironmentVariable('TMP',  "$DROOT\.tmp", 'User')
```

## 常见工具对照表

| 工具 | 设置项 | 建议位置 |
|---|---|---|
| 临时文件 | `TEMP` / `TMP` | `$DROOT\.tmp` |
| 下载 | 浏览器、IDM、网盘客户端的下载目录 | `$DROOT\downloads` |
| 解压 / 导出 | 7-Zip、Office、剪辑软件的默认输出目录 | `$DROOT\<项目名>` |
| npm | `npm config set cache` | `$DROOT\.cache\npm` |
| pnpm | `pnpm config set store-dir` | `$DROOT\.cache\pnpm-store` |
| pip | `$env:PIP_CACHE_DIR`，或 `pip config set global.cache-dir ...` | `$DROOT\.cache\pip` |
| uv | `$env:UV_CACHE_DIR` | `$DROOT\.cache\uv` |
| conda / mamba | `.condarc` 里的 `pkgs_dirs:` | `$DROOT\.cache\conda` |
| Hugging Face | `$env:HF_HOME`（权重可用 `HF_HUB_CACHE`） | `$DROOT\.cache\hf` |
| PyTorch | `$env:TORCH_HOME` | `$DROOT\.cache\torch` |
| Cargo | `$env:CARGO_HOME` | `$DROOT\.cache\cargo` |
| Go | `$env:GOPATH`、`$env:GOMODCACHE` | `$DROOT\.cache\go` |
| Gradle | `$env:GRADLE_USER_HOME` | `$DROOT\.cache\gradle` |
| Maven | `-Dmaven.repo.local=...` | `$DROOT\.cache\m2` |
| NuGet | `$env:NUGET_PACKAGES` | `$DROOT\.cache\nuget` |
| Playwright | `$env:PLAYWRIGHT_BROWSERS_PATH` | `$DROOT\.cache\playwright` |
| Docker Desktop | Settings → Resources → Disk image location | `$DROOT\docker` |
| VS Code 扩展 | `--extensions-dir` / portable 模式 | `$DROOT\.vscode\extensions` |
| WSL 发行版 | `wsl --export` / `--import` 到 D 盘 | `$DROOT\wsl\<distro>` |

## 落地纪律

- 先建目录再设变量，否则部分工具会静默回落到默认位置。
- 设置完立刻验证一次，例如 `npm config get cache`、`pip cache dir`，把结果写进交付说明。
- 路径含空格时用引号包住；PowerShell 里优先 `-LiteralPath`。
- 工具没有配置项时不要硬改（例如改注册表或符号链接系统目录），按 R5 报告后由用户决定。
