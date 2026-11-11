# d-drive-first

一个给 AI 编码 Agent 用的 skill：**新产物默认落 D 盘，写 C 盘前先只读预检并报备五项事实**。

解决的是 Windows 上的一个具体痛点——构建产物、包管理器缓存、模型权重、下载物默认全堆在 `C:\Users\<you>\...`，C 盘不知不觉被吃掉几十 GB。这个 skill 把这套「D 盘优先」的判定规则写成 Agent 可执行的指令，并附一个只读预检脚本，让「要不要写 C 盘」变成可验证的报告，而不是凭感觉。

## 它做什么

| 能力 | 说明 |
|---|---|
| 路径决策 | 按「用户指定 → 项目根 → 新项目 → 缓存/临时/下载」的决策树选目录，避免散落到 C 盘默认位置 |
| 缓存重定向 | 20+ 常见工具（npm/pnpm/pip/uv/conda/HF/torch/cargo/go/gradle/maven/nuget/playwright/docker/WSL…）的缓存变量对照表 |
| C 盘写入预检 | 只读脚本输出「路径、是否已存在、现有占用、预计新增、卷剩余空间」，五项一次给全 |
| 边界约束 | 不绕过沙箱、不改注册表、不迁移 `%LOCALAPPDATA%`、不删 C 盘既有内容 |

## 安装

把整个目录放到 Agent 的 skills 目录下（Claude Code 等使用 `SKILL.md` + frontmatter 的生态通用）：

```powershell
# 用户级
git clone https://github.com/l8m2h3/d-drive-first "$env:USERPROFILE\.agents\skills\d-drive-first"
```

目录结构必须保持：

```
d-drive-first/
├── SKILL.md
├── references/
│   ├── cache-redirects.md
│   └── report-template.md
└── scripts/
    └── preflight-c-write.ps1
```

## 配置工作根

默认工作根是 `D:\APP`。要换位置，设一个用户级环境变量即可，不必改文件：

```powershell
[Environment]::SetEnvironmentVariable('D_WORK_ROOT', 'E:\WORK', 'User')
```

优先级：用户当前指令 > `D_WORK_ROOT` > `D:\APP`。

目录约定（`$DROOT` 指工作根）：

```
$DROOT\<项目名>\      长期项目：源码、素材、构建产物、导出文件、文档
$DROOT\.cache\<工具>\ 可重建的依赖、构建、包管理器缓存
$DROOT\.cache\models\ 模型权重、数据集分片
$DROOT\.tmp\          临时文件，可随时整体清空
$DROOT\downloads\     下载的安装包、压缩包、数据集
```

## 单独使用预检脚本

不需要 Agent 也能跑，脚本是纯只读的：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\preflight-c-write.ps1 `
  -Path 'C:\Users\me\AppData\Local\Temp\build' -ExpectedBytes 250MB
```

输出示例：

```
### 写入预检（只读）

| 项目 | 值 |
|---|---|
| 目标路径 | `C:\Users\me\AppData\Local\Temp\build` |
| 所在卷 | C:（剩余 53.8 GB / 共 222.7 GB） |
| 原来是否存在 | 否 |
| 现有占用 | — |
| 预计新增 | 250.00 MB（262,144,000 字节） |
| 结论 | 必须先按 R5 向用户报告并取得同意，再写入 C 盘 |
```

参数：

| 参数 | 说明 |
|---|---|
| `-Path` | 计划写入的完整路径（目录或文件，允许不存在） |
| `-ExpectedBytes` | 预计新增，接受 `1024`、`250MB`、`1.5GB` |
| `-Json` | 输出 JSON 而非 Markdown 表格，便于编排 |
| `-FailIfC` | 目标落在 C 盘时以退出码 3 结束 |

脚本只读：不创建、不修改、不删除任何文件。默认退出码 0。

## 平台

**Windows only。** 脚本依赖 `System.IO.DriveInfo`、`Get-Volume`、`Get-CimInstance` 等 Windows 专有接口，兼容 Windows PowerShell 5.1 与 PowerShell 7+。

**不适用于没有 D 盘的机器。** 规则里 D 盘不可用时要求走 R5 报告流程、不允许静默回落到 C 盘，因此在无 D 盘或 D 盘只读的环境里，Agent 会持续提示而无法自动落盘——这是刻意设计，不是故障；此时应改设 `D_WORK_ROOT` 指向另一块数据盘。

脚本文件是 UTF-8 **with BOM**，这是 Windows PowerShell 5.1 正确解析其中中文的必要条件，`.gitattributes` 已固定为不做换行转换，请勿「顺手」去掉 BOM 或改成 LF。

## 许可

[MIT](LICENSE)
