<#
.SYNOPSIS
  只读预检：为一次计划中的写入生成「路径 / 是否已存在 / 现有占用 / 预计新增 / 卷空间」报告。

.DESCRIPTION
  对应 D 盘优先约定的 R5。脚本只读：不创建、不修改、不删除任何文件。
  默认退出码始终为 0；加 -FailIfC 时，目标落在 C 盘则以退出码 3 结束，便于编排判断。

.PARAMETER Path
  计划写入的完整路径，目录或文件均可，允许尚不存在。

.PARAMETER ExpectedBytes
  预计新增容量。接受字节数，或 '250MB' / '1.5GB' 这类写法。默认 0。

.PARAMETER Json
  输出 JSON 对象，而不是 Markdown 表格。

.PARAMETER FailIfC
  目标在 C 盘时以退出码 3 结束。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\preflight-c-write.ps1 -Path 'C:\Users\me\AppData\Local\Temp\build' -ExpectedBytes 250MB -Json

.NOTES
  文件保存为 UTF-8 with BOM，Windows PowerShell 5.1 才能正确解析其中的中文。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Path,
  [Parameter(Position = 1)][string]$ExpectedBytes = '0',
  [switch]$Json,
  [switch]$FailIfC
)

$ErrorActionPreference = 'Stop'

function ConvertTo-ByteCount {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return [long]0 }
  $m = [regex]::Match($Text.Trim(), '^(?<n>\d+(?:\.\d+)?)\s*(?<u>B|KB|MB|GB|TB)?$', 'IgnoreCase')
  if (-not $m.Success) { throw "无法解析容量 '$Text'；可用示例：1024、250MB、1.5GB" }
  $n = [double]$m.Groups['n'].Value
  $unit = $m.Groups['u'].Value
  if ([string]::IsNullOrEmpty($unit)) { $unit = 'B' }
  $mult = switch ($unit.ToUpperInvariant()) {
    'B' { 1 }
    'KB' { 1KB }
    'MB' { 1MB }
    'GB' { 1GB }
    'TB' { 1TB }
    default { 1 }
  }
  return [long]($n * $mult)
}

function Format-ByteCount {
  param([long]$Bytes)
  if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
  if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
  return ('{0} B' -f $Bytes)
}

function Resolve-FullPath {
  param([string]$Candidate)
  if (-not [System.IO.Path]::IsPathRooted($Candidate)) {
    $Candidate = Join-Path -Path (Get-Location).ProviderPath -ChildPath $Candidate
  }
  try { return [System.IO.Path]::GetFullPath($Candidate) }
  catch { return $Candidate }
}

function Test-IsOnC {
  param([string]$FullPath)
  $letter = $null
  try { $letter = [System.IO.Path]::GetPathRoot($FullPath) }
  catch { $letter = Split-Path -Qualifier $FullPath }
  if ([string]::IsNullOrWhiteSpace($letter)) { return $false }
  return ($letter.TrimEnd('\').TrimEnd(':').ToUpperInvariant() -eq 'C')
}

function Get-DriveLetter {
  param([string]$FullPath)
  $letter = $null
  try { $letter = [System.IO.Path]::GetPathRoot($FullPath) }
  catch { $letter = Split-Path -Qualifier $FullPath }
  if ([string]::IsNullOrWhiteSpace($letter)) { return $null }
  $clean = $letter.TrimEnd('\').TrimEnd(':')
  if ($clean.Length -eq 1) { return $clean.ToUpperInvariant() }
  return $null
}

$target = Resolve-FullPath -Candidate $Path
$expected = ConvertTo-ByteCount -Text $ExpectedBytes
$isC = Test-IsOnC -FullPath $target
$driveLetter = Get-DriveLetter -FullPath $target

$exists = Test-Path -LiteralPath $target
$occupiedBytes = $null
$occupiedHuman = '—'
if ($exists) {
  try {
    $item = Get-Item -LiteralPath $target -Force
    if ($item.PSIsContainer) {
      $sum = (Get-ChildItem -LiteralPath $target -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
      if ($null -eq $sum) { $sum = 0 }
      $occupiedBytes = [long]$sum
    }
    else {
      $occupiedBytes = [long]$item.Length
    }
    $occupiedHuman = '{0}（{1:N0} 字节）' -f (Format-ByteCount -Bytes $occupiedBytes), $occupiedBytes
  }
  catch {
    $occupiedHuman = '无法读取（权限不足或路径不可访问）'
  }
}

$nearest = $target
while ($nearest -and -not (Test-Path -LiteralPath $nearest)) {
  $parent = Split-Path -Parent $nearest
  if ([string]::IsNullOrEmpty($parent) -or $parent -eq $nearest) { break }
  $nearest = $parent
}

function Get-VolumeSpace {
  param([string]$Letter)
  # 依次尝试：DriveInfo → Get-Volume → Get-PSDrive → CIM。
  # 某些受限/沙箱环境里前几种会返回空，因此逐个兜底，全部失败时返回 $null 而不是 0。
  try {
    $di = New-Object System.IO.DriveInfo("${Letter}:\")
    if ($di.IsReady) {
      return @{ Free = [long]$di.AvailableFreeSpace; Size = [long]$di.TotalSize }
    }
  }
  catch { }
  try {
    $vol = Get-Volume -DriveLetter $Letter -ErrorAction Stop
    if ($null -ne $vol) {
      return @{ Free = [long]$vol.SizeRemaining; Size = [long]$vol.Size }
    }
  }
  catch { }
  try {
    $psd = Get-PSDrive -Name $Letter -ErrorAction Stop
    if ($null -ne $psd -and $null -ne $psd.Free) {
      return @{ Free = [long]$psd.Free; Size = $null }
    }
  }
  catch { }
  try {
    $cim = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${Letter}:'" -ErrorAction Stop
    if ($null -ne $cim) {
      return @{ Free = [long]$cim.FreeSpace; Size = [long]$cim.Size }
    }
  }
  catch { }
  return $null
}

$freeBytes = $null
$volumeSize = $null
if ($driveLetter) {
  $space = Get-VolumeSpace -Letter $driveLetter
  if ($null -ne $space -and $null -ne $space.Free) {
    $freeBytes = [long]$space.Free
    $volumeSize = $space.Size
  }
}

$freeHuman = if ($null -ne $freeBytes) { Format-ByteCount -Bytes $freeBytes } else { '未知' }
$volumeHuman = if ($null -ne $volumeSize) {
  '{0}:（剩余 {1} / 共 {2}）' -f $driveLetter, (Format-ByteCount -Bytes $freeBytes), (Format-ByteCount -Bytes $volumeSize)
}
else {
  '{0}:（剩余 {1}）' -f $driveLetter, $freeHuman
}

$verdict = if ($isC) { '必须先按 R5 向用户报告并取得同意，再写入 C 盘' } else { '无需报告：目标不在 C 盘' }

$warnings = @()
if ($null -ne $freeBytes -and $expected -gt $freeBytes) {
  $warnings += ('预计新增 {0} 超过卷剩余空间 {1}' -f (Format-ByteCount -Bytes $expected), $freeHuman)
}
if ($isC -and -not $exists) {
  $warnings += '目标尚不存在，其父目录会在首次写入时被创建（也属于 C 盘新增）'
}

if ($Json) {
  [pscustomobject]@{
    target               = $target
    drive                = $driveLetter
    isC                  = $isC
    exists               = $exists
    nearestExistingParent = $nearest
    occupiedBytes        = $occupiedBytes
    occupiedHuman        = $occupiedHuman
    expectedBytes        = $expected
    expectedHuman        = (Format-ByteCount -Bytes $expected)
    freeBytes            = $freeBytes
    freeHuman            = $freeHuman
    volume               = $volumeHuman
    verdict              = $verdict
    warnings             = $warnings
  } | ConvertTo-Json -Depth 4
}
else {
  Write-Output '### 写入预检（只读）'
  Write-Output ''
  Write-Output '| 项目 | 值 |'
  Write-Output '|---|---|'
  Write-Output ('| 目标路径 | `{0}` |' -f $target)
  Write-Output ('| 所在卷 | {0} |' -f $volumeHuman)
  if ($exists) {
    Write-Output '| 原来是否存在 | 是 |'
  }
  else {
    Write-Output ('| 原来是否存在 | 否（最近的已存在父目录：`{0}`） |' -f $nearest)
  }
  Write-Output ('| 现有占用 | {0} |' -f $occupiedHuman)
  Write-Output ('| 预计新增 | {0}（{1:N0} 字节） |' -f (Format-ByteCount -Bytes $expected), $expected)
  Write-Output ('| 结论 | {0} |' -f $verdict)
  if ($isC) {
    Write-Output '| 需要补充 | 为什么该内容必须放在 C 盘、不能安全地放到 D 盘 |'
  }
  if ($warnings.Count -gt 0) {
    Write-Output ''
    foreach ($w in $warnings) { Write-Output ('> 注意：{0}' -f $w) }
  }
  Write-Output ''
  Write-Output '> 本报告由只读脚本生成，未创建、修改或删除任何文件。'
}

if ($FailIfC -and $isC) { exit 3 }
exit 0
