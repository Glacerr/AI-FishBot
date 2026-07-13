# AI-FishBot 图形控制台 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改动用户当前 `AI-FishBot.ps1` 的前提下，交付一个可调参数、多配置、带托盘和独立后台进程的深海科技风格 Windows 图形控制台。

**Architecture:** 保留现有脚本作为回退入口，新建配置、运行时、引擎核心、真实设备适配、界面和控制器等小型模块。GUI 与后台引擎通过每次运行目录中的启动快照、实时配置、控制、状态和日志文件通信；所有引擎测试使用模拟适配器，不向游戏发送按键。

**Tech Stack:** Windows PowerShell 5.1、WinForms、PowerShell 模块、JSON 文件通信、项目内置轻量测试运行器、Git。

---

## 文件结构与边界

### 保留且禁止修改

- `AI-FishBot.ps1`：用户已在时光服调试可用的回退入口。
- `code.py`、`adafruit_hid/`、`AudioModule/`：现有设备与声音资源。

### 新建的程序文件

- `AI-FishBot.Config.psm1`：默认配置、旧脚本导入、校验、多方案与原子保存。
- `AI-FishBot.Runtime.psm1`：随机等待、原子JSON、状态、心跳、命令、日志和敏感信息遮盖。
- `AI-FishBot.EngineCore.psm1`：可测试的钓鱼状态机，只调用注入的声音、按键、时钟和通知适配器。
- `AI-FishBot.Adapters.psm1`：Windows真实声音监听、SendKeys、窗口聚焦、Pico串口和Discord通知。
- `AI-FishBot.Engine.ps1`：读取运行目录并把真实适配器装配到引擎核心。
- `AI-FishBot.UI.psm1`：深海科技主题、五个分页、托盘和控件清单。
- `AI-FishBot.Controller.psm1`：配置与控件绑定、校验、运行锁定、进程启动/停止和状态轮询。
- `AI-FishBot.Dependencies.psm1`：声音组件检查与用户明确触发的安装。
- `AI-FishBot.GUI.ps1`：STA入口、单实例、首次导入、窗口事件循环和异常提示。
- `启动_AI-FishBot-界面.cmd`：从正确目录启动界面。

### 新建的测试文件

- `tests/TestHarness.ps1`：断言、临时目录和测试汇总。
- `tests/Run-Tests.ps1`：统一测试入口。
- `tests/Smoke.Tests.ps1`：测试运行器自身验证。
- `tests/Config.Tests.ps1`：默认值、校验、旧脚本导入和多方案。
- `tests/Runtime.Tests.ps1`：随机等待、状态、命令、日志和遮盖。
- `tests/Engine.Tests.ps1`：全模拟状态机、四段节奏和停止行为。
- `tests/Adapters.Tests.ps1`：真实适配器的参数校验，禁止实际发送按键或网络请求。
- `tests/Dependencies.Tests.ps1`：声音组件检查和显式安装的注入测试。
- `tests/UI.Tests.ps1`：STA窗口、分页、控件、锁定和托盘。
- `tests/Controller.Tests.ps1`：方案绑定、保存、启动、停止、恢复和错误状态。
- `tests/Integration.Tests.ps1`：模拟引擎子进程与GUI文件协议。

### 运行时生成且不提交

- `profiles/*.json`
- `runtime/**`
- `logs/*.log`

### 规格覆盖索引

| 已确认要求 | 负责任务 |
|---|---|
| 保留用户当前脚本与现有文件 | Task 1、Task 12 |
| 首次导入“时光服”与全部原参数 | Task 3、Task 4、Task 11 |
| 四组最小/最大随机等待及运行中生效 | Task 5、Task 6、Task 10 |
| 多方案、原子保存与输入校验 | Task 3、Task 4、Task 10 |
| 独立后台、单实例、状态、心跳、停止与恢复 | Task 5、Task 6、Task 7、Task 10、Task 11 |
| WeakAura、增益、Pico、聚焦与Discord | Task 6、Task 7、Task 9、Task 10 |
| 五分页深海科技界面与托盘 | Task 9、Task 10、Task 11 |
| 声音组件显式安装 | Task 8、Task 11 |
| 无真实按键测试、可见检查与说明书 | Task 2、Task 6、Task 7、Task 9、Task 12 |

---

### Task 1: 隔离开发环境与保护基线

**Files:**
- Modify: `.gitignore`
- Test: `AI-FishBot.ps1`（只读校验）

- [ ] **Step 1: 使用隔离工作区技能创建分支和工作区**

在执行阶段先调用 `using-git-worktrees`，创建 `codex/ai-fishbot-gui`。记录主工作区绝对路径与当前脚本哈希：

```powershell
$PrimaryRoot = 'C:\Users\zhuyi\Documents\魔兽世界 3\AI-FishBot'
$ProtectedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$PrimaryRoot\AI-FishBot.ps1").Hash
$ProtectedHash
```

Expected: 输出一个64位十六进制SHA-256；执行期间不得对主工作区该文件调用写入命令。

- [ ] **Step 2: 验证隔离工作区基线**

```powershell
git status --short
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path '.\AI-FishBot.ps1'),
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) { throw ($errors | Out-String) }
}
```

Expected: 工作区只包含计划内文档变化；语法检查退出码为0。

- [ ] **Step 3: 添加运行数据忽略规则**

```gitignore
profiles/*.json
runtime/
logs/
tests/.tmp/
```

保留目录时由程序自动创建，不提交空目录占位文件。

- [ ] **Step 4: 检查并提交隔离准备**

Run:

```powershell
git diff --check
git add .gitignore
git commit -m "chore: ignore AI FishBot runtime data"
```

Expected: `git diff --check` 无输出，提交仅包含 `.gitignore`。

---

### Task 2: 建立零外部依赖的测试入口

**Files:**
- Create: `tests/TestHarness.ps1`
- Create: `tests/Run-Tests.ps1`
- Create: `tests/Smoke.Tests.ps1`

- [ ] **Step 1: 写测试运行器的失败测试**

`tests/Smoke.Tests.ps1`：

```powershell
Test-Case 'Assert-Equal 能识别相同值' {
    Assert-Equal -Expected 3 -Actual (1 + 2)
}

Test-Case 'Assert-Throws 能识别异常' {
    Assert-Throws -ScriptBlock { throw 'expected' } -MessageLike '*expected*'
}
```

- [ ] **Step 2: 运行并确认失败原因是测试函数尚不存在**

Run:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File .\tests\Run-Tests.ps1
```

Expected: FAIL，提示 `Test-Case` 或 `Assert-Equal` 未定义。

- [ ] **Step 3: 实现最小测试框架**

`tests/TestHarness.ps1` 提供这些完整接口：

```powershell
$script:TestResults = New-Object System.Collections.Generic.List[object]

function Test-Case {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Body)
    try {
        & $Body
        $script:TestResults.Add([pscustomobject]@{ Name = $Name; Passed = $true; Error = $null })
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:TestResults.Add([pscustomobject]@{ Name = $Name; Passed = $false; Error = $_.Exception.Message })
        Write-Host "FAIL $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual)
    if ($Expected -ne $Actual) { throw "Expected [$Expected] but got [$Actual]" }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = 'Expected true')
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, [string]$MessageLike = '*')
    try { & $ScriptBlock; throw 'Expected script to throw' }
    catch {
        if ($_.Exception.Message -eq 'Expected script to throw') { throw }
        if ($_.Exception.Message -notlike $MessageLike) {
            throw "Exception [$($_.Exception.Message)] did not match [$MessageLike]"
        }
    }
}

function New-TestDirectory {
    $root = Join-Path $PSScriptRoot '.tmp'
    if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root | Out-Null }
    $path = Join-Path $root ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}
```

`tests/Run-Tests.ps1`：

```powershell
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\TestHarness.ps1"
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' |
    Where-Object Name -ne 'Run-Tests.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
$failed = @($script:TestResults | Where-Object { -not $_.Passed })
Write-Host "`nTotal: $($script:TestResults.Count), Failed: $($failed.Count)"
if ($failed.Count -gt 0) { exit 1 }
exit 0
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: `Total: 2, Failed: 0`，退出码0。

- [ ] **Step 5: 提交测试入口**

```powershell
git add tests/TestHarness.ps1 tests/Run-Tests.ps1 tests/Smoke.Tests.ps1
git commit -m "test: add self contained PowerShell test runner"
```

---

### Task 3: 默认配置与完整校验

**Files:**
- Create: `AI-FishBot.Config.psm1`
- Create: `tests/Config.Tests.ps1`

- [ ] **Step 1: 写默认配置和边界失败测试**

测试必须逐项断言：

```powershell
Import-Module "$PSScriptRoot\..\AI-FishBot.Config.psm1" -Force

Test-Case '默认配置包含四组节奏范围' {
    $c = New-AIFishBotDefaultConfig
    Assert-Equal 0.3 $c.biteResponseMinSeconds
    Assert-Equal 0.7 $c.biteResponseMaxSeconds
    Assert-Equal 0.5 $c.preHookMinSeconds
    Assert-Equal 0.5 $c.preHookMaxSeconds
    Assert-Equal 1.1 $c.postHookMinSeconds
    Assert-Equal 1.5 $c.postHookMaxSeconds
    Assert-Equal 0.2 $c.preCastMinSeconds
    Assert-Equal 0.6 $c.preCastMaxSeconds
}

Test-Case '最小值大于最大值时校验失败' {
    $c = New-AIFishBotDefaultConfig
    $c.preCastMinSeconds = 0.7
    $c.preCastMaxSeconds = 0.2
    $result = Test-AIFishBotConfig -Config $c
    Assert-True (-not $result.IsValid)
    Assert-True (@($result.Errors.preCastMinSeconds).Count -eq 1)
}

Test-Case 'Pico启用但端口不存在时校验失败' {
    $c = New-AIFishBotDefaultConfig
    $c.usePi = $true
    $c.picoComPort = 'COM999'
    $result = Test-AIFishBotConfig -Config $c -AvailablePorts @('COM3')
    Assert-True (-not $result.IsValid)
}
```

- [ ] **Step 2: 运行并确认模块缺失导致失败**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.Config.psm1`。

- [ ] **Step 3: 实现默认配置与校验接口**

模块导出：

```powershell
function New-AIFishBotDefaultConfig {
    [pscustomobject][ordered]@{
        schemaVersion = 1; profileName = '新方案'; retail = $false
        autoStop = $true; autoStopTime = 60.0; autoLogout = $false
        audioSensitivity = 3; useWindowFocus = $true; useWeakAura = $false
        fishingRetries = 15; castKey = 'F6'; bobberKey = 'F7'; logoutKey = 'F8'
        usePi = $false; picoComPort = ''
        enableNotifications = $false; discordWebhook = ''
        notifyOnStart = $true; notifyOnStop = $true
        biteResponseMinSeconds = 0.3; biteResponseMaxSeconds = 0.7
        preHookMinSeconds = 0.5; preHookMaxSeconds = 0.5
        postHookMinSeconds = 1.1; postHookMaxSeconds = 1.5
        preCastMinSeconds = 0.2; preCastMaxSeconds = 0.6
        buffs = @()
    }
}

function Test-AIFishBotConfig {
    param([Parameter(Mandatory)]$Config, [string[]]$AvailablePorts = [IO.Ports.SerialPort]::GetPortNames())
    $errors = @{}
    function Add-FieldError([string]$Field, [string]$Message) { $errors[$Field] = $Message }
    if ([int]$Config.audioSensitivity -lt 1 -or [int]$Config.audioSensitivity -gt 9) { Add-FieldError 'audioSensitivity' '声音灵敏度必须为1到9。' }
    if ([double]$Config.autoStopTime -le 0) { Add-FieldError 'autoStopTime' '运行分钟必须大于0。' }
    if ([int]$Config.fishingRetries -lt 0) { Add-FieldError 'fishingRetries' '重试次数不能为负数。' }
    foreach ($prefix in 'biteResponse','preHook','postHook','preCast') {
        $minName = "${prefix}MinSeconds"; $maxName = "${prefix}MaxSeconds"
        $min = [double]$Config.$minName; $max = [double]$Config.$maxName
        if ($min -lt 0) { Add-FieldError $minName '最小等待不能为负数。' }
        elseif ($max -lt 0) { Add-FieldError $maxName '最大等待不能为负数。' }
        elseif ($min -gt $max) { Add-FieldError $minName '最小等待不能大于最大等待。' }
    }
    foreach ($keyName in 'castKey','bobberKey','logoutKey') {
        if ([string]$Config.$keyName -notmatch '^F(?:[5-9]|1[0-2])$') { Add-FieldError $keyName '按键必须为F5到F12。' }
    }
    if ($Config.usePi -and $Config.picoComPort -notin $AvailablePorts) { Add-FieldError 'picoComPort' '请选择当前存在的串口。' }
    for ($i = 0; $i -lt @($Config.buffs).Count; $i++) {
        $b = @($Config.buffs)[$i]
        if ($b.keybind -notmatch '^F(?:[5-9]|1[0-2])$') { Add-FieldError "buffs[$i].keybind" '增益按键必须为F5到F12。' }
        if ([double]$b.castTimeSeconds -lt 1) { Add-FieldError "buffs[$i].castTimeSeconds" '施放时间至少为1秒。' }
        if ([double]$b.durationMinutes -le 0) { Add-FieldError "buffs[$i].durationMinutes" '持续分钟必须大于0。' }
    }
    [pscustomobject]@{ IsValid = ($errors.Count -eq 0); Errors = $errors }
}

Export-ModuleMember -Function New-AIFishBotDefaultConfig,Test-AIFishBotConfig
```

实现时把数值转换异常捕获为对应字段的中文错误，不能让GUI因用户输入文本而崩溃。

- [ ] **Step 4: 补齐全部边界测试并运行**

增加：灵敏度0/10、分钟0、负重试、四组负数、F4/F13、增益施放0、持续0、合法默认值。Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`。

Expected: 全部PASS，退出码0。

- [ ] **Step 5: 提交配置模型**

```powershell
git add AI-FishBot.Config.psm1 tests/Config.Tests.ps1
git commit -m "feat: add validated AI FishBot configuration model"
```

---

### Task 4: 安全导入旧脚本与多方案存储

**Files:**
- Modify: `AI-FishBot.Config.psm1`
- Modify: `tests/Config.Tests.ps1`

- [ ] **Step 1: 写安全导入与方案操作失败测试**

在临时目录写一个只包含赋值和恶意命令文本的旧脚本，断言命令没有执行：

```powershell
Test-Case '导入器只读取字面量赋值且不会执行脚本' {
    $d = New-TestDirectory
    $legacy = Join-Path $d 'legacy.ps1'
    @'
$retail = $False
$audioSensitivity = 2
$enableBuffs = (1..2)
$cast = "F6"
$bobber = "F7"
$logout = "F8"
$onStart = $True
$onStop = $False
$buffKeybind1 = "F9"
$buffCastTime1 = 5
$buffDuration1 = 10
$buffKeybind2 = "F10"
$buffCastTime2 = 4
$buffDuration2 = 30
throw "导入器不得执行到这里"
'@ | Set-Content -LiteralPath $legacy -Encoding UTF8
    $c = Import-AIFishBotLegacyConfig -ScriptPath $legacy -ProfileName '时光服'
    Assert-Equal '时光服' $c.profileName
    Assert-Equal 2 $c.audioSensitivity
    Assert-True $c.buffs[0].enabled
    Assert-True (-not $c.notifyOnStop)
}
```

另写保存、读取、复制、重命名、删除、非法名称和损坏JSON恢复测试。

- [ ] **Step 2: 运行并确认缺少导入/存储函数而失败**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示 `Import-AIFishBotLegacyConfig` 未定义。

- [ ] **Step 3: 用语法树安全读取赋值**

核心读取方式必须是解析而不是执行：

```powershell
function Get-LegacyLiteralAssignments {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "旧脚本无法解析：$($parseErrors[0].Message)" }
    $values = @{}
    $assignments = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] }, $true)
    foreach ($assignment in $assignments) {
        if ($assignment.Left -isnot [Management.Automation.Language.VariableExpressionAst]) { continue }
        $name = $assignment.Left.VariablePath.UserPath
        try {
            $values[$name] = $assignment.Right.SafeGetValue()
        } catch {
            if ($name -ne 'enableBuffs') { continue }
            $text = $assignment.Right.Extent.Text.Trim()
            if ($text -match '^\(\s*(\d+)\s*\.\.\s*(\d+)\s*\)$') {
                $first = [int]$Matches[1]; $last = [int]$Matches[2]
                $items = New-Object System.Collections.Generic.List[int]
                if ($first -le $last) { for ($i = $first; $i -le $last; $i++) { $items.Add($i) } }
                else { for ($i = $first; $i -ge $last; $i--) { $items.Add($i) } }
                $values[$name] = @($items)
            } elseif ($text -match '^\(\s*(\d+)\s*\)$') {
                $values[$name] = @([int]$Matches[1])
            }
        }
    }
    return $values
}
```

`Import-AIFishBotLegacyConfig` 从默认配置开始，仅映射白名单字段；按 `buffKeybindN`、`buffCastTimeN`、`buffDurationN` 的共同编号建立增益列表，并以 `$enableBuffs` 决定 `enabled`。原脚本中的编号 `0` 表示不启用任何增益，不能建立编号0的增益行。

- [ ] **Step 4: 实现原子方案存储**

导出以下接口：

```powershell
Get-AIFishBotProfilePath
Get-AIFishBotProfiles
Read-AIFishBotProfile
Save-AIFishBotProfile
Copy-AIFishBotProfile
Rename-AIFishBotProfile
Remove-AIFishBotProfile
Initialize-AIFishBotProfiles
Import-AIFishBotLegacyConfig
```

方案名称只允许去除首尾空白后的普通文件名，并拒绝 `[IO.Path]::GetInvalidFileNameChars()`、`.`、`..`。保存使用同目录临时文件：

```powershell
$temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
$Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
$roundTrip = Get-Content -Raw -LiteralPath $temp -Encoding UTF8 | ConvertFrom-Json
$valid = Test-AIFishBotConfig -Config $roundTrip
if (-not $valid.IsValid) { Remove-Item -LiteralPath $temp -Force; throw '配置校验失败。' }
if (Test-Path -LiteralPath $Path) {
    $backup = "$Path.backup"
    [IO.File]::Replace($temp, $Path, $backup, $true)
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
} else {
    [IO.File]::Move($temp, $Path)
}
```

- [ ] **Step 5: 运行配置测试并提交**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 导入、往返、复制、重命名、删除、损坏JSON与非法名称测试全部PASS。

```powershell
git add AI-FishBot.Config.psm1 tests/Config.Tests.ps1
git commit -m "feat: import legacy settings and manage profiles"
```

---

### Task 5: 随机时间与文件通信基础

**Files:**
- Create: `AI-FishBot.Runtime.psm1`
- Create: `tests/Runtime.Tests.ps1`

- [ ] **Step 1: 写包含端点、固定值和非法范围失败测试**

```powershell
Import-Module "$PSScriptRoot\..\AI-FishBot.Runtime.psm1" -Force

Test-Case '随机毫秒包含最大端点' {
    $value = Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.2 -MaximumSeconds 0.6 -RandomIntProvider { param($min,$max) $max }
    Assert-Equal 600 $value
}

Test-Case '相同端点返回固定毫秒' {
    Assert-Equal 500 (Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.5 -MaximumSeconds 0.5)
}

Test-Case '反向范围被拒绝' {
    Assert-Throws { Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.7 -MaximumSeconds 0.2 } '*最小*最大*'
}
```

再写原子JSON往返、配置版本更新、停止命令、心跳新鲜/过期、日志分级和Webhook遮盖测试。

- [ ] **Step 2: 运行并确认模块缺失导致失败**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.Runtime.psm1`。

- [ ] **Step 3: 实现随机等待与原子JSON**

```powershell
$script:AIFishBotRandom = New-Object Random

function Get-AIFishBotDelayMilliseconds {
    param([double]$MinimumSeconds,[double]$MaximumSeconds,[scriptblock]$RandomIntProvider)
    if ($MinimumSeconds -lt 0 -or $MaximumSeconds -lt 0) { throw '等待时间不能为负数。' }
    if ($MinimumSeconds -gt $MaximumSeconds) { throw '最小等待不能大于最大等待。' }
    $min = [int][Math]::Round($MinimumSeconds * 1000,[MidpointRounding]::AwayFromZero)
    $max = [int][Math]::Round($MaximumSeconds * 1000,[MidpointRounding]::AwayFromZero)
    if ($min -eq $max) { return $min }
    if ($RandomIntProvider) { return [int](& $RandomIntProvider $min $max) }
    return $script:AIFishBotRandom.Next($min, $max + 1)
}

function Write-AIFishBotAtomicJson {
    param([string]$Path,[Parameter(Mandatory)]$Value)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
    Get-Content -Raw -LiteralPath $temp -Encoding UTF8 | ConvertFrom-Json | Out-Null
    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.backup"
        [IO.File]::Replace($temp, $Path, $backup, $true)
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    } else {
        [IO.File]::Move($temp, $Path)
    }
}
```

- [ ] **Step 4: 实现状态、命令、版本和日志接口**

导出：

```powershell
New-AIFishBotRunDirectory
Write-AIFishBotAtomicJson
Read-AIFishBotJson
Write-AIFishBotStatus
Read-AIFishBotStatus
Write-AIFishBotControlCommand
Read-AIFishBotControlCommand
Test-AIFishBotHeartbeatFresh
Write-AIFishBotLog
Protect-AIFishBotSecret
Get-AIFishBotDelayMilliseconds
```

`Protect-AIFishBotSecret` 将 `https://discord.com/api/webhooks/<id>/<token>` 变成 `https://discord.com/api/webhooks/***`。状态对象固定包含 `processId,state,hookCount,retryCount,profileName,startedAt,remainingSeconds,lastError,heartbeatAt,configVersion`。

- [ ] **Step 5: 运行测试并提交**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 随机、JSON、状态、命令、心跳和遮盖测试全部PASS。

```powershell
git add AI-FishBot.Runtime.psm1 tests/Runtime.Tests.ps1
git commit -m "feat: add runtime timing and file protocol"
```

---

### Task 6: 可模拟的钓鱼引擎核心

**Files:**
- Create: `AI-FishBot.EngineCore.psm1`
- Create: `tests/Engine.Tests.ps1`

- [ ] **Step 1: 写四段节奏顺序失败测试**

模拟器记录事件，不调用 `Start-Sleep` 或真实按键：

```powershell
$events = New-Object System.Collections.Generic.List[string]
$adapter = [pscustomobject]@{
    Sleep = { param($ms) $events.Add("sleep:$ms") }
    SendKey = { param($key) $events.Add("key:$key") }
    FocusGame = { $events.Add('focus') }
    ReadPeak = { 90 }
    Notify = { param($message) $events.Add('notify') }
    Now = { Get-Date '2026-07-13T12:00:00' }
}
$config = New-AIFishBotDefaultConfig
$config.biteResponseMinSeconds = 0.3; $config.biteResponseMaxSeconds = 0.3
$config.preHookMinSeconds = 0.5; $config.preHookMaxSeconds = 0.5
$config.postHookMinSeconds = 1.1; $config.postHookMaxSeconds = 1.1
$config.preCastMinSeconds = 0.2; $config.preCastMaxSeconds = 0.2
$state = New-AIFishBotEngineState -Config $config -Adapter $adapter -Simulation
Invoke-AIFishBotBiteSequence -State $state
Assert-Equal 'sleep:300,key:F7' (($events | Where-Object { $_ -in 'sleep:300','key:F7' }) -join ',')
Assert-True (($events -join ',') -like '*sleep:300*sleep:500*key:F7*sleep:1100*sleep:200*key:F6*')
```

这里明确顺序为：咬钩响应 → 收杆前等待 → F7 → 收杆后等待 → 甩杆前等待 → F6。

- [ ] **Step 2: 写实时配置版本与停止失败测试**

测试状态机在下一动作前调用 `ReloadLiveConfig`，新版本只替换允许实时修改的字段；`stop` 命令在安全检查点令状态依次变为 `停止中`、`已停止`，并执行清理。

- [ ] **Step 3: 运行并确认引擎模块缺失导致失败**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.EngineCore.psm1`。

- [ ] **Step 4: 实现状态对象与动作函数**

模块导出：

```powershell
New-AIFishBotEngineState
Update-AIFishBotLiveConfig
Invoke-AIFishBotCast
Invoke-AIFishBotBiteSequence
Invoke-AIFishBotBuffCheck
Invoke-AIFishBotStop
Start-AIFishBotEngineLoop
```

`Invoke-AIFishBotBiteSequence` 的核心实现必须直接对应测试顺序：

```powershell
function Invoke-AIFishBotBiteSequence {
    param([Parameter(Mandatory)]$State)
    Update-AIFishBotLiveConfig -State $State
    & $State.Adapter.Sleep (Get-AIFishBotDelayMilliseconds $State.Config.biteResponseMinSeconds $State.Config.biteResponseMaxSeconds $State.RandomIntProvider)
    Update-AIFishBotLiveConfig -State $State
    & $State.Adapter.Sleep (Get-AIFishBotDelayMilliseconds $State.Config.preHookMinSeconds $State.Config.preHookMaxSeconds $State.RandomIntProvider)
    if ($State.Config.useWindowFocus) { & $State.Adapter.FocusGame }
    & $State.Adapter.SendKey $State.Config.bobberKey
    $State.HookCount++
    Update-AIFishBotLiveConfig -State $State
    & $State.Adapter.Sleep (Get-AIFishBotDelayMilliseconds $State.Config.postHookMinSeconds $State.Config.postHookMaxSeconds $State.RandomIntProvider)
    Invoke-AIFishBotCast -State $State
}
```

`Invoke-AIFishBotCast` 在每次发送抛竿键前读取实时配置并应用 `preCastMinSeconds/preCastMaxSeconds`。WeakAura 模式保留最多 `fishingRetries` 次尝试和原有1.0–1.5秒判定间隔；Classic/正式服保留30/22秒计时和抛竿后4秒静默期。

- [ ] **Step 5: 实现增益、自动停止、通知与清理**

增益以列表和下一次到期时间字典管理；自动停止时间随实时配置重算，但已过期时立即走正常停止；Discord失败只写警告；Pico错误进入 `错误` 并停止。所有退出路径在 `finally` 中调用适配器的 `Dispose`。

- [ ] **Step 6: 运行全模拟测试并提交**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 四段顺序、0.2–0.6边界、实时更新、WeakAura重试、无咬钩、增益、自动停止、通知失败和正常清理全部PASS；事件中没有真实设备调用。

```powershell
git add AI-FishBot.EngineCore.psm1 tests/Engine.Tests.ps1
git commit -m "feat: add simulated fishing engine state machine"
```

---

### Task 7: 真实Windows适配器与后台入口

**Files:**
- Create: `AI-FishBot.Adapters.psm1`
- Create: `AI-FishBot.Engine.ps1`
- Create: `tests/Adapters.Tests.ps1`
- Modify: `tests/Engine.Tests.ps1`

- [ ] **Step 1: 写适配器参数验证失败测试**

测试只注入记录器：

```powershell
Test-Case '软件按键格式被包成SendKeys功能键' {
    $sent = $null
    $sender = New-AIFishBotKeySender -UsePi:$false -SendKeysProvider { param($text) $script:sent = $text }
    & $sender 'F7'
    Assert-Equal '{F7}' $script:sent
}

Test-Case '通知发送前不把Webhook写入日志' {
    $log = New-Object System.Collections.Generic.List[string]
    $notify = New-AIFishBotNotifier -Webhook 'https://discord.com/api/webhooks/123/secret' -HttpProvider { throw 'network down' } -LogProvider { param($m) $log.Add($m) }
    & $notify 'hello'
    Assert-True (($log -join '') -notmatch 'secret')
}
```

- [ ] **Step 2: 运行并确认适配器模块缺失导致失败**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.Adapters.psm1`。

- [ ] **Step 3: 实现真实适配器工厂**

导出：

```powershell
New-AIFishBotAudioMonitor
New-AIFishBotKeySender
New-AIFishBotGameFocuser
New-AIFishBotNotifier
New-AIFishBotEngineAdapter
```

软件按键使用 `[Windows.Forms.SendKeys]::SendWait("{$Key}")`；Pico使用 `IO.Ports.SerialPort` 115200/N/8/1；自动聚焦使用 `WScript.Shell.AppActivate('World of Warcraft')`；通知使用 `Invoke-RestMethod` 并捕获异常。声音监听封装现有 `Write-AudioDevice -PlaybackStream`，只向引擎返回0–100峰值。

- [ ] **Step 4: 实现后台入口和退出码**

`AI-FishBot.Engine.ps1` 参数与入口：

```powershell
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [switch]$Simulation
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\AI-FishBot.Config.psm1" -Force
Import-Module "$PSScriptRoot\AI-FishBot.Runtime.psm1" -Force
Import-Module "$PSScriptRoot\AI-FishBot.EngineCore.psm1" -Force
Import-Module "$PSScriptRoot\AI-FishBot.Adapters.psm1" -Force
try {
    $snapshot = Read-AIFishBotJson (Join-Path $RunDirectory 'start-config.json')
    $adapter = New-AIFishBotEngineAdapter -Config $snapshot -Simulation:$Simulation
    $state = New-AIFishBotEngineState -Config $snapshot -Adapter $adapter -RunDirectory $RunDirectory -Simulation:$Simulation
    Start-AIFishBotEngineLoop -State $state
    exit 0
} catch {
    Write-AIFishBotStatus -RunDirectory $RunDirectory -State '错误' -LastError $_.Exception.Message
    Write-AIFishBotLog -RunDirectory $RunDirectory -Level ERROR -Message $_.Exception.Message
    exit 1
}
```

- [ ] **Step 5: 以模拟模式启动子进程验证文件协议**

测试创建运行目录和配置快照，启动 `powershell.exe -File AI-FishBot.Engine.ps1 -RunDirectory <temp> -Simulation`，等待状态文件出现，写入stop命令，断言退出码0且最终状态为 `已停止`。

- [ ] **Step 6: 运行测试并提交**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 所有测试PASS，测试日志中不出现完整Webhook，机器不收到按键。

```powershell
git add AI-FishBot.Adapters.psm1 AI-FishBot.Engine.ps1 tests/Adapters.Tests.ps1 tests/Engine.Tests.ps1
git commit -m "feat: connect engine to Windows adapters"
```

---

### Task 8: 声音依赖检查与显式安装

**Files:**
- Create: `AI-FishBot.Dependencies.psm1`
- Create: `tests/Dependencies.Tests.ps1`

- [ ] **Step 1: 写检查和安装失败测试**

注入 `CommandFinder`、`CopyProvider` 和 `ModuleInstaller`，断言缺少组件时只返回 `Missing`，不会自动安装；只有调用 `Install-AIFishBotAudioDependency` 才执行复制和安装。

- [ ] **Step 2: 实现接口**

```powershell
Test-AIFishBotAudioDependency
Install-AIFishBotAudioDependency
```

安装路径固定为当前用户模块目录 `$(Split-Path $PROFILE)\Modules\AudioDeviceCmdlets`，源文件固定为 `AudioModule\AudioDeviceCmdlets.dll` 与 `.psd1`。返回对象包含 `Success,Summary,Details`；界面显示Summary，Details只进入日志。

- [ ] **Step 3: 运行测试并提交**

Run: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 缺失、已存在、复制失败和安装失败测试全部PASS；测试不修改用户模块目录。

```powershell
git add AI-FishBot.Dependencies.psm1 tests/Dependencies.Tests.ps1
git commit -m "feat: add explicit audio dependency setup"
```

---

### Task 9: 深海科技主题与五分页窗口

**Files:**
- Create: `AI-FishBot.UI.psm1`
- Create: `tests/UI.Tests.ps1`

- [ ] **Step 1: 写STA窗口结构失败测试**

测试从新的STA PowerShell进程运行并断言：

```powershell
$view = New-AIFishBotMainView
Assert-Equal 5 $view.Controls.TabControl.TabPages.Count
Assert-Equal '基础' $view.Controls.TabControl.TabPages[0].Text
Assert-Equal '按键与设备' $view.Controls.TabControl.TabPages[1].Text
Assert-Equal '增益' $view.Controls.TabControl.TabPages[2].Text
Assert-Equal '通知' $view.Controls.TabControl.TabPages[3].Text
Assert-Equal '日志' $view.Controls.TabControl.TabPages[4].Text
foreach ($name in 'ProfileSelector','SaveButton','StartStopButton','AudioPeakBar','BiteResponseMin','BiteResponseMax','PreHookMin','PreHookMax','PostHookMin','PostHookMax','PreCastMin','PreCastMax','BuffGrid','WebhookText','LogBox') {
    Assert-True ($view.Controls.ContainsKey($name)) "缺少控件：$name"
}
$view.Form.Dispose()
```

- [ ] **Step 2: 运行并确认UI模块缺失导致失败**

Run: `powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.UI.psm1`。

- [ ] **Step 3: 实现主题和主框架**

主题常量固定为：背景 `#071522`、卡片 `#0D2233`、输入 `#102B40`、青色 `#2DD4BF`、主文字 `#D9F3FF`、次文字 `#82A9BC`、成功 `#45D483`、警告 `#F4A340`、错误 `#F05A67`。窗口初始 `760×620`、最小 `720×580`、居中、`AutoScaleMode=Dpi`。

`New-AIFishBotMainView` 返回：

```powershell
[pscustomobject]@{
    Form = $form
    Controls = $controls
    TrayIcon = $trayIcon
    TrayMenu = $trayMenu
    Timers = [pscustomobject]@{ Status = $statusTimer; Log = $logTimer }
}
```

- [ ] **Step 4: 实现五页控件清单**

控件字典至少包含这些稳定名称：

```text
ProfileSelector NewProfileButton CopyProfileButton RenameProfileButton DeleteProfileButton
StatusBadge SaveStateLabel SaveButton StartStopButton
Retail AutoStop AutoStopTime AutoLogout AudioSensitivity AudioPeakBar HookCount RemainingTime
BiteResponseMin BiteResponseMax PreHookMin PreHookMax PostHookMin PostHookMax PreCastMin PreCastMax
CastKey BobberKey LogoutKey UseWindowFocus UseWeakAura FishingRetries UsePi PicoComPort
BuffGrid AddBuffButton RemoveBuffButton MoveBuffUpButton MoveBuffDownButton
EnableNotifications NotifyOnStart NotifyOnStop WebhookText ShowWebhookButton
LogLevel LogBox ClearLogButton OpenLogButton InstallAudioButton
```

四组节奏使用小数输入框，步长0.1，显示1位小数。Webhook使用密码字符，按住显示按钮时临时取消遮盖。

- [ ] **Step 5: 实现托盘与视觉状态**

托盘菜单固定包含只读状态、打开主窗口、开始、停止、退出控制台。窗口最小化和关闭事件只发出控制器可订阅的事件，不在UI模块中直接结束后台。

- [ ] **Step 6: 运行UI结构测试并提交**

Run: `powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 五分页、全部控件、颜色、窗口尺寸、托盘菜单和Dispose测试PASS。

```powershell
git add AI-FishBot.UI.psm1 tests/UI.Tests.ps1
git commit -m "feat: build deep ocean WinForms console"
```

---

### Task 10: GUI控制器、运行锁定和多方案交互

**Files:**
- Create: `AI-FishBot.Controller.psm1`
- Create: `tests/Controller.Tests.ps1`
- Modify: `AI-FishBot.UI.psm1`
- Modify: `tests/UI.Tests.ps1`

- [ ] **Step 1: 写绑定、校验和锁定失败测试**

测试控制器使用伪View和临时方案目录：加载配置后控件值一致；非法值使 `StartStopButton.Enabled=$false` 并产生字段错误；运行状态下锁定字段变灰而四组节奏仍可编辑。GUI重新打开时，恢复逻辑必须重新取得仍然有效的后台状态。

运行锁定集合固定为：

```powershell
$LockedWhileRunning = @('Retail','UseWindowFocus','UseWeakAura','FishingRetries','CastKey','BobberKey','LogoutKey','UsePi','PicoComPort','ProfileSelector','RenameProfileButton','DeleteProfileButton')
$LiveWhileRunning = @('AudioSensitivity','AutoStop','AutoStopTime','AutoLogout','BiteResponseMin','BiteResponseMax','PreHookMin','PreHookMax','PostHookMin','PostHookMax','PreCastMin','PreCastMax','BuffGrid','EnableNotifications','NotifyOnStop')
```

- [ ] **Step 2: 写启动、停止与恢复失败测试**

断言启动时依次完成：校验 → 保存方案 → 创建运行目录 → 写启动快照/实时配置 → 启动隐藏进程 → 更新按钮。停止先写正常stop命令；超时只返回 `RequiresForceConfirmation=$true`，不自行强杀。恢复必须同时验证PID存在和心跳新鲜。

- [ ] **Step 3: 运行并确认控制器模块缺失导致失败**

Run: `powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1`

Expected: FAIL，提示找不到 `AI-FishBot.Controller.psm1`。

- [ ] **Step 4: 实现控制器公开接口**

```powershell
New-AIFishBotController
Set-AIFishBotViewFromConfig
Get-AIFishBotConfigFromView
Test-AIFishBotView
Set-AIFishBotRunningState
Save-AIFishBotCurrentProfile
Start-AIFishBotRun
Stop-AIFishBotRun
Resume-AIFishBotRun
Update-AIFishBotViewStatus
Update-AIFishBotViewLog
```

`Start-AIFishBotRun` 只通过注入的 `ProcessStarter` 启动：

```powershell
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$EnginePath`"",'-RunDirectory',"`"$runDirectory`"")
& $ProcessStarter -FilePath $WindowsPowerShellPath -ArgumentList $args -WindowStyle Hidden
```

实时保存只把设计允许的字段写入 `live-config.json`，并递增 `configVersion`。锁定字段仍保存到方案，但不写入当前运行的实时文件。

- [ ] **Step 5: 实现方案按钮与托盘行为**

新建使用内置默认值；复制命名为“原名 - 副本”并避免重名；重命名和删除运行方案被拒绝；切换前若未保存则询问。关闭控制台且后台运行时提供“继续后台运行”和“一并停止”两种明确选择。

- [ ] **Step 6: 运行控制器测试并提交**

Run: `powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1`

Expected: 绑定、错误提示、运行锁定、实时保存、方案操作、正常停止、超时确认、心跳恢复和托盘命令测试全部PASS。

```powershell
git add AI-FishBot.Controller.psm1 AI-FishBot.UI.psm1 tests/Controller.Tests.ps1 tests/UI.Tests.ps1
git commit -m "feat: control profiles and background runs from GUI"
```

---

### Task 11: GUI入口、单实例与启动器

**Files:**
- Create: `AI-FishBot.GUI.ps1`
- Create: `启动_AI-FishBot-界面.cmd`
- Create: `tests/Integration.Tests.ps1`

- [ ] **Step 1: 写GUI无显示自检失败测试**

GUI入口支持 `-SelfTest -NoShow`，返回0表示模块导入、首次方案初始化、窗口创建和释放成功。集成测试在临时根目录运行，不接触真实 `profiles/`。

- [ ] **Step 2: 实现单实例与首次导入**

入口参数：

```powershell
param(
    [string]$DataRoot = $PSScriptRoot,
    [switch]$SelfTest,
    [switch]$NoShow
)
```

用命名互斥量 `Local\AI-FishBot.GUI.<项目路径SHA256前16位>` 限制同一路径一个GUI。没有方案时调用 `Initialize-AIFishBotProfiles -LegacyScriptPath "$PSScriptRoot\AI-FishBot.ps1" -InitialProfileName '时光服'`。异常以中文消息框摘要显示，完整详情写日志。

- [ ] **Step 3: 装配UI、控制器、依赖按钮和轮询**

入口创建View与Controller，绑定所有按钮、字段变化、两个计时器、窗口最小化/关闭和托盘菜单。`-NoShow` 时创建后立即Dispose；正常模式使用 `[Windows.Forms.Application]::Run($view.Form)`。

- [ ] **Step 4: 实现启动器**

`启动_AI-FishBot-界面.cmd`：

```batch
@echo off
setlocal
cd /d "%~dp0"
start "AI-FishBot" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot.GUI.ps1"
endlocal
```

- [ ] **Step 5: 运行无显示自检和模拟子进程集成测试**

Run:

```powershell
powershell.exe -Sta -NoProfile -File .\AI-FishBot.GUI.ps1 -SelfTest -NoShow -DataRoot .\tests\.tmp\gui-selftest
powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1
```

Expected: 两条命令退出码0；首次导入生成“时光服”；模拟启动、状态轮询、实时参数版本更新、正常stop与GUI重开恢复全部PASS；无真实按键。

- [ ] **Step 6: 提交可启动界面**

```powershell
git add AI-FishBot.GUI.ps1 '启动_AI-FishBot-界面.cmd' tests/Integration.Tests.ps1
git commit -m "feat: add launchable AI FishBot GUI"
```

---

### Task 12: 使用说明、视觉检查与最终保护验证

**Files:**
- Modify after integration in primary workspace: `中文使用说明书.md`
- Modify: `README.md`
- Test: all program and test files

- [ ] **Step 1: 更新README入口和风险表述**

在README开头增加“图形界面版本”段，说明双击 `启动_AI-FishBot-界面.cmd`、首次导入“时光服”、原脚本仍可回退。删除或改写“完全无法检测”等承诺，明确自动化可能违反游戏规则并带来账号处罚风险。

- [ ] **Step 2: 在主工作区更新中文说明书**

由于该文件当前是用户工作区中的未跟踪成果，不让分支合并覆盖它。合并实现后，用 `apply_patch` 在现有内容中新增：五分页介绍、方案操作、四组等待、运行时锁定、托盘、日志、声音组件按钮、后台恢复和回退入口。保留原有时光服设置与故障排查内容。

- [ ] **Step 3: 运行全部自动验证**

```powershell
powershell.exe -Sta -NoProfile -File .\tests\Run-Tests.ps1
powershell.exe -Sta -NoProfile -File .\AI-FishBot.GUI.ps1 -SelfTest -NoShow -DataRoot .\tests\.tmp\final-selftest
git diff --check
```

Expected: 测试失败数0；GUI自检退出码0；格式检查无输出。

- [ ] **Step 4: 做可见GUI检查**

启动界面但不启动真实引擎，逐页检查760×620、100%与125%缩放：无文字裁切；四组最小/最大值完整；非法范围显示红框并禁用开始；运行模拟状态时锁定字段变灰；托盘恢复正常；Webhook默认隐藏；日志不会显示完整Webhook。保存截图到 `tests/artifacts/gui-100.png` 与 `tests/artifacts/gui-125.png`，检查后不提交临时运行数据。

- [ ] **Step 5: 对照规格逐项验收**

逐项核对设计说明第12节九条标准，并额外执行：

```powershell
$current = (Get-FileHash -Algorithm SHA256 -LiteralPath "$PrimaryRoot\AI-FishBot.ps1").Hash
if ($current -ne $ProtectedHash) { throw '用户当前AI-FishBot.ps1发生了变化。' }
git status --short
git log --oneline --decorate -12
```

Expected: 受保护脚本哈希与Task 1一致；用户原有删除、修改和未跟踪文件仍存在；计划实现形成清晰的小提交。

- [ ] **Step 6: 提交文档并请求代码审查**

```powershell
git add README.md
git commit -m "docs: explain AI FishBot graphical console"
```

调用 `requesting-code-review`，重点检查：无真实按键测试、原脚本保护、配置迁移完整、实时字段白名单、进程清理、Webhook遮盖、WinForms缩放和四段延迟顺序。修复审查问题后重新运行Step 3–5。

- [ ] **Step 7: 完成开发分支交付**

调用 `verification-before-completion` 复核最新命令输出，再调用 `finishing-a-development-branch` 提供合并、PR或保留分支选项。未经用户选择不推送远端、不创建PR。
