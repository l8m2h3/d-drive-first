---
name: d-drive-first
description: "默认把新生成或下载的项目、源码、图片、视频、文档、构建产物、压缩包、导出文件、日志和可配置缓存放在 D 盘（工作根默认 D:\\APP，可用 D_WORK_ROOT 覆盖），尽量不向 C 盘写入；必须写 C 盘时先只读检查并报告完整路径、原来是否存在、现有占用、预计新增、以及为什么不能放 D 盘。Use when creating or scaffolding a project, downloading files/models/datasets/installers, choosing output, temp, cache, build or export directories, installing dependencies or tools, unzipping archives, or when the user says 放D盘、别占C盘、C盘满了、存储位置、下载目录、缓存目录、临时目录、输出路径、工作目录, D drive, avoid C drive, disk space."
license: MIT
metadata:
  version: "1.0"
  language: zh-CN
  platform: windows
---

# D 盘优先与 C 盘保护

把「新产物默认落 D 盘、写 C 盘前先报备」作为默认工作约定。适用于 Windows 上希望避免 C 盘被构建产物、依赖缓存、下载物逐步塞满的场景。除非系统或安全策略、或用户在当前任务中明确要求不同做法，否则始终遵守。

本 skill 目录：`%USERPROFILE%\.agents\skills\d-drive-first\`。下文所有相对路径都相对于它。

## 工作根

下文用 `$DROOT` 指代工作根，选择顺序：

1. 用户在当前任务里给出的 D 盘路径；
2. 环境变量 `D_WORK_ROOT`（若已设置且指向可写目录）；
3. 默认 `D:\APP`。

`$DROOT` 不存在时先创建，再在其中放东西。

## 硬规则

| # | 规则 |
|---|---|
| R1 | 新生成或下载的项目、源码、图片、视频、文档、构建产物、压缩包、导出文件、日志、可配置缓存，默认全部放 D 盘。 |
| R2 | 默认工作根为 `$DROOT`（默认 `D:\APP`）；新项目在其中建语义清晰的独立子目录。用户指定其他 D 盘目录时优先用用户的位置。 |
| R3 | 只要 D 盘可行，就不得把项目文件、素材副本、依赖目录、构建缓存、临时交付物写入 C 盘。 |
| R4 | 工具支持自定义缓存、临时、下载或输出目录时，显式指向 D 盘，不沿用 C 盘默认值。 |
| R5 | 任何新的 C 盘写入发生前，先做只读检查，并明确告诉用户五项：完整路径、原来是否存在、现有占用字节数或容量、本次预计新增、为什么必须放 C 盘而不能安全放 D 盘。 |

## 开工流程

1. **先定路径，再动手。** 不要把工作目录留在 C 盘默认位置（如 `C:\Users\<you>\Documents`）再用相对路径落盘。
2. 按下面的决策树选目录，`Test-Path` 确认，再 `New-Item -ItemType Directory -Force`。
3. **大任务先看空间**：`Get-Volume -DriveLetter D | Select-Object DriveLetter, SizeRemaining`；该命令在受限环境可能被拒绝，可退用 `[System.IO.DriveInfo]::new('D')` 读 `AvailableFreeSpace`。空间明显不够时先报告再开工。
4. 按[缓存与目录重定向](references/cache-redirects.md)把依赖缓存、临时目录、下载目录指到 D 盘。
5. 交付时给出产物的绝对路径和占用大小。
6. 只有走 R5 流程时才写 C 盘。

## 路径决策树

1. 用户给了 D 盘路径 → 直接用。
2. 任务属于某个已有项目 → 用项目根。项目根若在 C 盘，先按 R5 报告，并给出迁到 `$DROOT\<项目名>` 的方案让用户选，不要默不作声继续写 C 盘。
3. 新项目或一次性产物 → `$DROOT\<语义化名称>`（见名知意；同名已存在时追加日期或序号，不覆盖）。
4. 临时、缓存、下载、模型权重 → `$DROOT\.tmp`、`$DROOT\.cache\<tool>`、`$DROOT\downloads`、`$DROOT\.cache\models`。
5. D 盘不可用（不存在、只读、空间不足）→ 走 R5。不要静默回落到 C 盘。

## 不得不写 C 盘时（R5）

先跑只读预检，再按[报告模板](references/report-template.md)把五项发给用户：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.agents\skills\d-drive-first\scripts\preflight-c-write.ps1" -Path 'C:\Users\<you>\AppData\Local\Temp\build' -ExpectedBytes 250MB
```

（`powershell.exe` 在 Windows 上始终存在；`-ExecutionPolicy Bypass` 避免脚本被执行策略拦下。机器上有 PowerShell 7 时把 `powershell` 换成 `pwsh` 也可以，脚本两者都兼容。）

- 脚本只读：不创建、不修改、不删除任何东西。
- 报告后等待同意再写；能写临时目录就写完即删，把足迹压到最小。
- 工具硬编码 C 盘路径且没有配置项时，在报告里写明这一事实，以及已经尝试过的替代方案。
- 用户当前任务明确要求放 C 盘时，报告一次即可，不要反复劝阻。

## 边界

- **不绕过沙箱。** 当前会话文件策略只允许写工作区时，不要为守本约定去申请放宽权限；工作区内写不到 D 盘就如实报告，由用户决定。
- **不改系统设置。** 不迁移 `%LOCALAPPDATA%`、不改注册表重定向用户目录、不动系统盘文件；需要时只给建议。
- **不删除 C 盘既有内容。** 清理必须由用户明确要求，先列清单再动手。
- **原样保留用户措辞。** 用户已经给出的 D 盘路径、目录名、命名习惯优先于本文默认值。

## 覆盖范围

本 skill 只约束**新增内容写到哪里**，不改变程序的安装位置、不改变 Windows 的临时目录默认值（除非用户明确要求，见 `references/cache-redirects.md` 的持久化一节）。

## 检查清单

- [ ] 目标路径在 D 盘（或已按 R5 报告并获同意）
- [ ] 目录已创建且可写
- [ ] 缓存、临时、下载目录已重定向
- [ ] 交付信息含产物绝对路径
- [ ] 本次任务 C 盘新增 = 0 字节，或已按 R5 完成报告
