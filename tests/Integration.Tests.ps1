$script:IntegrationRoot = Split-Path -Path $PSScriptRoot -Parent
$script:GuiEntryPath = Join-Path -Path $script:IntegrationRoot -ChildPath 'AI-FishBot.GUI.ps1'
$script:LauncherPath = Join-Path -Path $script:IntegrationRoot -ChildPath '启动_AI-FishBot-界面.cmd'
$script:WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

foreach ($moduleName in @(
        'AI-FishBot.Config.psm1',
        'AI-FishBot.Runtime.psm1',
        'AI-FishBot.Adapters.psm1',
        'AI-FishBot.EngineCore.psm1',
        'AI-FishBot.Dependencies.psm1',
        'AI-FishBot.UI.psm1',
        'AI-FishBot.Controller.psm1'
    )) {
    Import-Module (Join-Path $script:IntegrationRoot $moduleName) -Force
}

function Remove-IntegrationDirectory {
    param([AllowNull()][string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Quote-IntegrationArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"{0}"' -f ($Value -replace '"', '\"')
}

function Invoke-GuiEntryProcess {
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [switch]$SelfTest,
        [switch]$NoShow,
        [switch]$Simulation,
        [int]$TimeoutMilliseconds = 30000
    )

    $captureRoot = New-TestDirectory
    $stdoutPath = Join-Path $captureRoot 'stdout.txt'
    $stderrPath = Join-Path $captureRoot 'stderr.txt'
    $arguments = @(
        '-NoProfile',
        '-Sta',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Quote-IntegrationArgument $script:GuiEntryPath),
        '-DataRoot',
        (Quote-IntegrationArgument $DataRoot)
    )
    if ($SelfTest) { $arguments += '-SelfTest' }
    if ($NoShow) { $arguments += '-NoShow' }
    if ($Simulation) { $arguments += '-Simulation' }

    $process = $null
    try {
        $process = Start-Process -FilePath $script:WindowsPowerShellPath `
            -ArgumentList ($arguments -join ' ') -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $null = $process.Handle
        $observedMainWindowHandle = [intptr]::Zero
        try {
            $process.Refresh()
            if ($null -ne $process.MainWindowHandle) {
                $observedMainWindowHandle = [intptr]$process.MainWindowHandle
            }
        }
        catch { }
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch { }
            throw ('GUI 子进程在 {0} 毫秒内没有退出。' -f $TimeoutMilliseconds)
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            StandardOutput = if (Test-Path $stdoutPath) { [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::Default) } else { '' }
            StandardError = if (Test-Path $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::Default) } else { '' }
            MainWindowHandle = $observedMainWindowHandle
            ProcessId = $process.Id
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
            try { $process.WaitForExit(5000) | Out-Null } catch { }
        }
        if ($null -ne $process) { $process.Dispose() }
        Remove-IntegrationDirectory $captureRoot
    }
}

function Get-GuiMutexNameForTest {
    $projectPath = [IO.Path]::GetFullPath($script:IntegrationRoot).TrimEnd('\', '/')
    $canonicalPath = $projectPath.ToUpperInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonicalPath))
    }
    finally { $sha.Dispose() }
    $prefix = -join @($hash[0..7] | ForEach-Object { $_.ToString('x2') })
    return 'Local\AI-FishBot.GUI.{0}' -f $prefix
}

function Wait-IntegrationCondition {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Condition,
        [int]$TimeoutMilliseconds = 15000,
        [int]$PollMilliseconds = 25,
        [string]$FailureMessage = '等待模拟状态超时。'
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
            $results = @(& $Condition)
            if ($results.Count -gt 0 -and $null -ne $results[-1] -and $results[-1] -ne $false) {
                return $results[-1]
            }
            Start-Sleep -Milliseconds $PollMilliseconds
        }
    }
    finally { $stopwatch.Stop() }
    throw $FailureMessage
}

function Set-InvalidIntegrationProfile {
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$Secret
    )

    $initial = Invoke-GuiEntryProcess -DataRoot $DataRoot -SelfTest -NoShow -Simulation
    if ($initial.ExitCode -ne 0) { throw '无法准备损坏配置测试目录。' }
    Remove-Item -LiteralPath (Join-Path $DataRoot 'profiles\时光服.json') -Force
    $bad = New-AIFishBotDefaultConfig
    $bad.profileName = $Secret
    [IO.File]::WriteAllText(
        (Join-Path $DataRoot 'profiles\坏方案.json'),
        ($bad | ConvertTo-Json -Depth 20),
        (New-Object Text.UTF8Encoding($false)))
}

function Invoke-GuiEntryWithInjectedErrorPresenter {
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [string]$GuiPath = $script:GuiEntryPath,
        [switch]$NoShow,
        [switch]$SelfTest,
        [int]$TimeoutMilliseconds = 30000
    )

    $captureRoot = New-TestDirectory
    $harnessPath = Join-Path $captureRoot 'presenter-harness.ps1'
    $stdoutPath = Join-Path $captureRoot 'stdout.txt'
    $stderrPath = Join-Path $captureRoot 'stderr.txt'
    $harness = @'
param(
    [string]$GuiPath,
    [string]$GuiDataRoot,
    [string]$PresenterMarker,
    [switch]$NoShow,
    [switch]$SelfTest
)
$capturedMarker = $PresenterMarker
$global:AIFishBotGuiErrorPresenter = ({
        param($Summary)
        [IO.File]::WriteAllText(
            $capturedMarker,
            [string]$Summary,
            (New-Object Text.UTF8Encoding($false)))
    }.GetNewClosure())
if ($SelfTest) {
    & $GuiPath -DataRoot $GuiDataRoot -SelfTest -Simulation
}
elseif ($NoShow) {
    & $GuiPath -DataRoot $GuiDataRoot -NoShow -Simulation
}
else {
    & $GuiPath -DataRoot $GuiDataRoot -Simulation
}
exit $LASTEXITCODE
'@
    [IO.File]::WriteAllText($harnessPath, $harness, (New-Object Text.UTF8Encoding($true)))
    $arguments = @(
        '-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass',
        '-File', (Quote-IntegrationArgument $harnessPath),
        '-GuiPath', (Quote-IntegrationArgument $GuiPath),
        '-GuiDataRoot', (Quote-IntegrationArgument $DataRoot),
        '-PresenterMarker', (Quote-IntegrationArgument $MarkerPath)
    )
    if ($NoShow) { $arguments += '-NoShow' }
    if ($SelfTest) { $arguments += '-SelfTest' }

    $process = $null
    try {
        $process = Start-Process -FilePath $script:WindowsPowerShellPath `
            -ArgumentList ($arguments -join ' ') -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch { }
            throw '注入错误提示器的 GUI 子进程没有按时退出。'
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            StandardOutput = if (Test-Path $stdoutPath) { [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::Default) } else { '' }
            StandardError = if (Test-Path $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::Default) } else { '' }
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            try { $process.Kill() } catch { }
            try { $process.WaitForExit(5000) | Out-Null } catch { }
        }
        if ($null -ne $process) { $process.Dispose() }
        Remove-IntegrationDirectory $captureRoot
    }
}

Test-Case 'injected simulation peak flows through engine status polling into the hidden WinForms meter' {
    $root = New-TestDirectory
    $state = $null
    $adapter = $null
    $view = $null
    $controller = $null
    try {
        $now = [datetimeoffset]'2026-07-14T12:00:00+08:00'
        $profilesDirectory = Join-Path $root 'profiles'
        $runtimeRoot = Join-Path $root 'runtime'
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '峰值链路模拟方案'
        $config.useWeakAura = $true
        $config.fishingRetries = 2
        $config.audioSensitivity = 3
        $config.useWindowFocus = $false
        $config.usePi = $false
        $config.enableNotifications = $false
        Save-AIFishBotProfile -ProfilesDirectory $profilesDirectory -Config $config | Out-Null
        $runDirectory = New-AIFishBotRunDirectory -RuntimeRoot $runtimeRoot `
            -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 1 })

        $adapter = New-AIFishBotEngineAdapter -Simulation `
            -SimulationPeaks @([double]47.25) -SimulationNow $now `
            -SimulationThrottleProvider { param($milliseconds) }
        $state = New-AIFishBotEngineState -Config $config -RunDirectory $runDirectory `
            -Adapter $adapter -ConfigVersion 1 -ProcessStartedAt $now.AddSeconds(-2)
        Assert-Equal -Expected $true -Actual (Invoke-AIFishBotCast -State $state)
        Invoke-AIFishBotStop -State $state | Out-Null

        $view = New-AIFishBotMainView
        $controller = New-AIFishBotController -View $view `
            -ProfilesDirectory $profilesDirectory -RuntimeRoot $runtimeRoot `
            -EngineScriptPath (Join-Path $script:IntegrationRoot 'AI-FishBot.Engine.ps1') `
            -DependencyChecker { [pscustomobject]@{ Status = 'Available'; IsAvailable = $true } } `
            -ProcessStarter { param($request) throw '链路测试禁止启动进程。' } `
            -ProcessLookup { param($id) return $null } `
            -AvailablePortsProvider { @() } -Clock { $now } -Simulation
        $controller.CurrentRunDirectory = $runDirectory
        Set-AIFishBotRunningState -Controller $controller -Running $true | Out-Null

        $onTick = $view.Timers.Status.GetType().GetMethod(
            'OnTick',
            [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic)
        Assert-True -Condition ($null -ne $onTick)
        $onTick.Invoke($view.Timers.Status, @([EventArgs]::Empty)) | Out-Null

        Assert-True -Condition ($view.Controls.AudioPeakBar -is [Windows.Forms.ProgressBar])
        Assert-Equal -Expected 47 -Actual $view.Controls.AudioPeakBar.Value
    }
    finally {
        if ($null -ne $controller) { $controller.Dispose() }
        if ($null -ne $view) { $view.Dispose() }
        if ($null -ne $adapter -and $null -ne $adapter.PSObject.Properties['Dispose']) {
            & $adapter.Dispose | Out-Null
        }
        Remove-IntegrationDirectory $root
    }
}

Test-Case 'first profile import uses the legacy fixture once and never overwrites an existing profile' {
    $root = New-TestDirectory
    try {
        $profiles = Join-Path $root 'profiles'
        $legacy = Join-Path $root 'legacy fixture.ps1'
        [IO.File]::WriteAllText($legacy, '$autoStopTime = 42', (New-Object Text.UTF8Encoding($false)))

        $first = @(Initialize-AIFishBotProfiles -ProfilesDirectory $profiles -LegacyScriptPath $legacy -InitialProfileName '时光服')
        [IO.File]::WriteAllText($legacy, '$autoStopTime = 99', (New-Object Text.UTF8Encoding($false)))
        $second = @(Initialize-AIFishBotProfiles -ProfilesDirectory $profiles -LegacyScriptPath $legacy -InitialProfileName '时光服')
        $loaded = Read-AIFishBotProfile -ProfilesDirectory $profiles -ProfileName '时光服'

        Assert-Equal -Expected @('时光服') -Actual $first
        Assert-Equal -Expected @('时光服') -Actual $second
        Assert-Equal -Expected 42 -Actual $loaded.autoStopTime
    }
    finally { Remove-IntegrationDirectory $root }
}

Test-Case 'self test creates and binds the hidden GUI under a Chinese path without starting a worker' {
    $root = Join-Path (New-TestDirectory) '中文 数据 目录'
    try {
        $result = Invoke-GuiEntryProcess -DataRoot $root -SelfTest -NoShow -Simulation
        $line = @($result.StandardOutput -split '[\r\n]+' | Where-Object { $_.Trim().StartsWith('{') })[-1]
        $report = if ([string]::IsNullOrWhiteSpace($line)) { $null } else { $line | ConvertFrom-Json }

        Assert-Equal -Expected 0 -Actual $result.ExitCode
        Assert-Equal -Expected '' -Actual $result.StandardError.Trim()
        Assert-True -Condition ($null -ne $report)
        Assert-Equal -Expected $true -Actual $report.success
        Assert-Equal -Expected 5 -Actual $report.pageCount
        Assert-True -Condition ($report.controlCount -ge 30)
        Assert-Equal -Expected 0 -Actual $result.MainWindowHandle
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $root 'profiles\时光服.json') -PathType Leaf)
        Assert-Equal -Expected 0 -Actual @((Get-ChildItem -LiteralPath (Join-Path $root 'runtime') -Directory -ErrorAction SilentlyContinue)).Count
    }
    finally { Remove-IntegrationDirectory (Split-Path $root -Parent) }
}

Test-Case 'a second GUI process for the same project is rejected with a clear result' {
    $root = New-TestDirectory
    $mutex = New-Object Threading.Mutex($false, (Get-GuiMutexNameForTest))
    $ownsMutex = $false
    try {
        $ownsMutex = $mutex.WaitOne(0)
        Assert-Equal -Expected $true -Actual $ownsMutex

        $result = Invoke-GuiEntryProcess -DataRoot $root -SelfTest -NoShow -Simulation

        if ($result.ExitCode -eq 0) { throw '第二实例错误地返回了成功。' }
        if (($result.StandardOutput + $result.StandardError) -notlike '*已经*运行*') {
            throw ('第二实例没有返回清晰提示。输出：{0}；错误：{1}' -f $result.StandardOutput, $result.StandardError)
        }
    }
    finally {
        if ($ownsMutex) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
        Remove-IntegrationDirectory $root
    }
}

Test-Case 'invalid stored configuration exits nonzero and masks webhook secrets in its GUI log' {
    $root = New-TestDirectory
    try {
        $secret = 'https://discord.com/api/webhooks/123456/private-token'
        Set-InvalidIntegrationProfile -DataRoot $root -Secret $secret

        $result = Invoke-GuiEntryProcess -DataRoot $root -SelfTest -NoShow -Simulation
        $logs = @(Get-ChildItem -LiteralPath (Join-Path $root 'logs') -Filter '*.log' -File -ErrorAction SilentlyContinue)
        $logText = @($logs | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"

        if ($result.ExitCode -eq 0) { throw '损坏配置错误地返回了成功。' }
        if (($result.StandardOutput + $result.StandardError) -notlike '*启动失败*') {
            throw ('损坏配置没有返回中文摘要。输出：{0}；错误：{1}' -f $result.StandardOutput, $result.StandardError)
        }
        if ($logs.Count -lt 1) { throw '损坏配置没有写入 GUI 日志。' }
        if ($logText -notlike '*webhooks/***') { throw ('GUI 日志没有遮盖密钥：{0}' -f $logText) }
        Assert-Equal -Expected $false -Actual $logText.Contains('private-token')
        Assert-Equal -Expected $false -Actual (($result.StandardOutput + $result.StandardError).Contains('private-token'))
    }
    finally { Remove-IntegrationDirectory $root }
}

Test-Case 'interactive startup failures use a safe Chinese presenter while hidden modes never present' {
    $root = New-TestDirectory
    try {
        $secret = 'https://discord.com/api/webhooks/123456/presenter-secret'
        Set-InvalidIntegrationProfile -DataRoot $root -Secret $secret
        $interactiveMarker = Join-Path $root 'interactive-presenter.txt'

        $interactive = Invoke-GuiEntryWithInjectedErrorPresenter `
            -DataRoot $root -MarkerPath $interactiveMarker

        if ($interactive.ExitCode -eq 0) {
            $markerText = if (Test-Path -LiteralPath $interactiveMarker) {
                [IO.File]::ReadAllText($interactiveMarker)
            }
            else { '<missing>' }
            throw ('交互启动错误地返回了成功。提示：{0}；输出：{1}；错误：{2}' -f
                $markerText, $interactive.StandardOutput, $interactive.StandardError)
        }
        if (-not (Test-Path -LiteralPath $interactiveMarker -PathType Leaf)) {
            throw ('交互启动没有调用注入的安全提示器。输出：{0}；错误：{1}' -f
                $interactive.StandardOutput, $interactive.StandardError)
        }
        $summary = [IO.File]::ReadAllText($interactiveMarker)
        Assert-True -Condition ($summary -like '*启动失败*')
        Assert-Equal -Expected $false -Actual $summary.Contains('presenter-secret')
        Assert-Equal -Expected $false -Actual $summary.Contains('webhooks')

        $hiddenMarker = Join-Path $root 'hidden-presenter.txt'
        $hidden = Invoke-GuiEntryWithInjectedErrorPresenter `
            -DataRoot $root -MarkerPath $hiddenMarker -NoShow
        Assert-True -Condition ($hidden.ExitCode -ne 0)
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $hiddenMarker)
        Assert-True -Condition (($hidden.StandardOutput + $hidden.StandardError) -like '*启动失败*')
    }
    finally { Remove-IntegrationDirectory $root }
}

Test-Case 'first legacy import failure presents its safe field and reason without secrets paths or stack details' {
    $root = New-TestDirectory
    try {
        $projectRoot = Join-Path $root 'isolated GUI project'
        [void][IO.Directory]::CreateDirectory($projectRoot)
        foreach ($fileName in @(
                'AI-FishBot.GUI.ps1',
                'AI-FishBot.Config.psm1',
                'AI-FishBot.Runtime.psm1',
                'AI-FishBot.Dependencies.psm1',
                'AI-FishBot.UI.psm1',
                'AI-FishBot.Controller.psm1'
            )) {
            Copy-Item -LiteralPath (Join-Path $script:IntegrationRoot $fileName) `
                -Destination (Join-Path $projectRoot $fileName)
        }

        $secret = 'first-import-secret-token'
        $userProfilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $legacyText = '$autoStopTime = "x" autoStopTime=https://discord.com/api/webhooks/123456/{0}+{1}\private+{2}' -f `
            $secret, $userProfilePath, ('A' * 700)
        [IO.File]::WriteAllText(
            (Join-Path $projectRoot 'AI-FishBot.ps1'),
            $legacyText,
            (New-Object Text.UTF8Encoding($false)))

        $dataRoot = Join-Path $root 'data'
        $interactiveMarker = Join-Path $root 'first-import-presenter.txt'
        $interactive = Invoke-GuiEntryWithInjectedErrorPresenter `
            -GuiPath (Join-Path $projectRoot 'AI-FishBot.GUI.ps1') `
            -DataRoot $dataRoot -MarkerPath $interactiveMarker

        Assert-True -Condition ($interactive.ExitCode -ne 0)
        Assert-True -Condition (Test-Path -LiteralPath $interactiveMarker -PathType Leaf)
        $summary = [IO.File]::ReadAllText($interactiveMarker)
        Assert-True -Condition ($summary -like '首次配置导入失败：*')
        Assert-True -Condition ($summary -like '*autoStopTime*')
        Assert-True -Condition ($summary -match '无法解析|Unexpected token')
        Assert-Equal -Expected $false -Actual $summary.Contains($secret)
        Assert-Equal -Expected $false -Actual $summary.Contains($userProfilePath)
        Assert-Equal -Expected $false -Actual ($summary -match '[\r\n\u2028\u2029]')
        Assert-Equal -Expected 500 -Actual $summary.Length
        Assert-True -Condition $summary.EndsWith('…')
        Assert-Equal -Expected $false -Actual ($summary -match 'ScriptStackTrace|AI-FishBot\.GUI\.ps1:\s*line')

        $selfTestMarker = Join-Path $root 'self-test-presenter.txt'
        $selfTest = Invoke-GuiEntryWithInjectedErrorPresenter `
            -GuiPath (Join-Path $projectRoot 'AI-FishBot.GUI.ps1') `
            -DataRoot $dataRoot -MarkerPath $selfTestMarker -SelfTest
        Assert-True -Condition ($selfTest.ExitCode -ne 0)
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath $selfTestMarker)
    }
    finally { Remove-IntegrationDirectory $root }
}

Test-Case 'simulation GUI controller completes start live update reopen resume and clean stop' {
    $root = New-TestDirectory
    $firstView = $null
    $firstController = $null
    $secondView = $null
    $secondController = $null
    $engineProcess = $null
    $enginePid = 0
    try {
        $profilesDirectory = Join-Path $root 'profiles'
        $runtimeRoot = Join-Path $root 'runtime'
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '完整模拟方案'
        $config.autoStop = $false
        $config.autoLogout = $false
        $config.useWindowFocus = $false
        $config.useWeakAura = $false
        $config.usePi = $false
        $config.enableNotifications = $false
        Save-AIFishBotProfile -ProfilesDirectory $profilesDirectory -Config $config | Out-Null

        $launchGuard = [pscustomobject]@{ Calls = 0 }
        $capturedLaunchGuard = $launchGuard
        $simulationOnlyStarter = ({
                param($Request)
                $capturedLaunchGuard.Calls += 1
                if ([string]$Request.ArgumentList -notmatch '(?:^|\s)-Simulation(?:\s|$)') {
                    throw '完整集成测试拒绝启动未标记为 Simulation 的后台。'
                }
                Start-Process -FilePath $Request.FilePath -ArgumentList $Request.ArgumentList `
                    -WindowStyle Hidden -PassThru
            }.GetNewClosure())

        $firstView = New-AIFishBotMainView
        $firstController = New-AIFishBotController -View $firstView `
            -ProfilesDirectory $profilesDirectory -RuntimeRoot $runtimeRoot `
            -EngineScriptPath (Join-Path $script:IntegrationRoot 'AI-FishBot.Engine.ps1') `
            -DependencyChecker { [pscustomobject]@{ Status = 'Available'; IsAvailable = $true } } `
            -ProcessStarter $simulationOnlyStarter `
            -Simulation -HeartbeatMaxAgeSeconds 10 -StopTimeoutSeconds 15
        Set-AIFishBotViewFromConfig -Controller $firstController -Config $config | Out-Null

        $started = Start-AIFishBotRun -Controller $firstController
        if (-not $started.Success) {
            throw ('完整模拟启动失败：{0}' -f ($started | ConvertTo-Json -Compress))
        }
        Assert-Equal -Expected 1 -Actual $launchGuard.Calls
        $enginePid = [int]$started.Pid
        $runDirectory = [string]$started.RunDirectory
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $runDirectory 'start-config.json') -PathType Leaf)
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $runDirectory 'live-config.json') -PathType Leaf)
        $engineProcess = Get-Process -Id $enginePid -ErrorAction Stop
        $null = $engineProcess.Handle

        $readyStatus = Wait-IntegrationCondition -FailureMessage '模拟后台没有写入可用状态和心跳。' -Condition {
            try {
                $candidate = Read-AIFishBotStatus -RunDirectory $runDirectory
                if ($candidate.processId -eq $enginePid -and
                    $candidate.state -in @('ready', 'casting', 'waiting-for-bite', 'hooking') -and
                    (Test-AIFishBotHeartbeatFresh -Status $candidate -MaxAgeSeconds 10)) {
                    return $candidate
                }
            }
            catch { }
            return $null
        }
        Assert-Equal -Expected $enginePid -Actual $readyStatus.processId
        Assert-Equal -Expected ([datetimeoffset]$engineProcess.StartTime).ToUniversalTime().ToString('o') `
            -Actual ([datetimeoffset]$readyStatus.processStartedAt).ToUniversalTime().ToString('o')

        $firstView.Controls.AudioSensitivity.Value = 8
        $firstView.Controls.WebhookText.Text = 'https://discord.com/api/webhooks/112233/integration-fake-token'
        $saved = Save-AIFishBotCurrentProfile -Controller $firstController
        if (-not $saved.Success) {
            throw ('完整模拟保存实时配置失败：{0}' -f ($saved | ConvertTo-Json -Compress))
        }
        Assert-Equal -Expected 2 -Actual $firstController.ConfigVersion
        $live = Read-AIFishBotJson -Path (Join-Path $runDirectory 'live-config.json')
        Assert-Equal -Expected 2 -Actual $live.configVersion
        Assert-Equal -Expected 8 -Actual $live.audioSensitivity
        Assert-Equal -Expected 'https://discord.com/api/webhooks/112233/integration-fake-token' -Actual $live.discordWebhook

        $appliedStatus = Wait-IntegrationCondition -FailureMessage '模拟后台没有读取新的实时配置版本。' -Condition {
            try {
                $candidate = Read-AIFishBotStatus -RunDirectory $runDirectory
                if ($candidate.configVersion -eq 2) { return $candidate }
            }
            catch { }
            return $null
        }
        Assert-Equal -Expected 2 -Actual $appliedStatus.configVersion

        $firstController.Dispose()
        $firstController = $null
        $firstView.Dispose()
        $firstView = $null
        Assert-Equal -Expected $false -Actual $engineProcess.HasExited

        $secondView = New-AIFishBotMainView
        $secondController = New-AIFishBotController -View $secondView `
            -ProfilesDirectory $profilesDirectory -RuntimeRoot $runtimeRoot `
            -EngineScriptPath (Join-Path $script:IntegrationRoot 'AI-FishBot.Engine.ps1') `
            -DependencyChecker { [pscustomobject]@{ Status = 'Available'; IsAvailable = $true } } `
            -ProcessStarter $simulationOnlyStarter `
            -Simulation -HeartbeatMaxAgeSeconds 10 -StopTimeoutSeconds 15
        $resumed = Resume-AIFishBotRun -Controller $secondController
        if (-not $resumed.Success) {
            throw ('完整模拟重开恢复失败：{0}' -f ($resumed | ConvertTo-Json -Compress))
        }
        Assert-Equal -Expected $enginePid -Actual $resumed.Pid
        Assert-Equal -Expected $runDirectory -Actual $resumed.RunDirectory

        $stopped = Stop-AIFishBotRun -Controller $secondController -TimeoutSeconds 15
        if (-not $stopped.Success) {
            $diagnosticStatus = $null
            try { $diagnosticStatus = Read-AIFishBotStatus -RunDirectory $runDirectory } catch { }
            $pendingControl = Test-Path -LiteralPath (Join-Path $runDirectory 'control.json')
            $diagnosticLog = @(
                Get-ChildItem -LiteralPath (Join-Path $runDirectory 'logs') -Filter '*.log' -File -ErrorAction SilentlyContinue |
                    ForEach-Object { [IO.File]::ReadAllText($_.FullName) }
            ) -join "`n"
            throw ('完整模拟停止失败：{0}；状态：{1}；命令仍待处理：{2}；进程已退出：{3}；日志：{4}' -f
                ($stopped | ConvertTo-Json -Compress),
                ($diagnosticStatus | ConvertTo-Json -Compress),
                $pendingControl,
                $engineProcess.HasExited,
                $diagnosticLog)
        }
        Assert-True -Condition $engineProcess.WaitForExit(15000)
        $finalStatus = Read-AIFishBotStatus -RunDirectory $runDirectory
        Assert-Equal -Expected 'stopped' -Actual $finalStatus.state
        Assert-Equal -Expected 0 -Actual $engineProcess.ExitCode
    }
    finally {
        if ($null -ne $secondController) { try { $secondController.Dispose() } catch { } }
        if ($null -ne $secondView) { try { $secondView.Dispose() } catch { } }
        if ($null -ne $firstController) { try { $firstController.Dispose() } catch { } }
        if ($null -ne $firstView) { try { $firstView.Dispose() } catch { } }
        if ($null -ne $engineProcess) {
            if (-not $engineProcess.HasExited) {
                try { $engineProcess.Kill() } catch { }
                try { $engineProcess.WaitForExit(5000) | Out-Null } catch { }
            }
            $engineProcess.Dispose()
        }
        elseif ($enginePid -gt 0) {
            $leftover = Get-Process -Id $enginePid -ErrorAction SilentlyContinue
            if ($null -ne $leftover) {
                try { Stop-Process -Id $enginePid -Force -ErrorAction SilentlyContinue } catch { }
                try { $leftover.WaitForExit(5000) | Out-Null } catch { }
                $leftover.Dispose()
            }
        }
        Remove-IntegrationDirectory $root
        if ($enginePid -gt 0 -and $null -ne (Get-Process -Id $enginePid -ErrorAction SilentlyContinue)) {
            throw '完整模拟测试遗留了后台进程。'
        }
        if (Test-Path -LiteralPath $root) { throw '完整模拟测试遗留了临时目录。' }
    }
}

Test-Case 'launcher uses its own directory and starts the quoted GUI entry in STA mode' {
    $lines = @([IO.File]::ReadAllLines($script:LauncherPath))
    Assert-Equal -Expected @(
        '@echo off',
        'setlocal',
        'cd /d "%~dp0"',
        'start "AI-FishBot" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot.GUI.ps1"',
        'endlocal'
    ) -Actual $lines
}

Test-Case 'GUI entry declares the supported public switches and does not alter the legacy script' {
    $text = [IO.File]::ReadAllText($script:GuiEntryPath)
    Assert-True -Condition ($text -match '\[string\]\s*\$DataRoot\s*=\s*\$PSScriptRoot')
    foreach ($switchName in @('SelfTest', 'NoShow', 'Simulation')) {
        Assert-True -Condition ($text -match ('\[switch\]\s*\${0}' -f $switchName))
    }
    Assert-True -Condition ($text -match 'AI-FishBot\.ps1')
    Assert-True -Condition ($text -match 'Application\]::Run')
}

Test-Case 'GUI confirmation provider gives reset profile an explicit warning' {
    $text = [IO.File]::ReadAllText($script:GuiEntryPath)
    Assert-True -Condition ($text -match "'ResetProfile'\s*\{\s*'确定将当前方案的所有设置恢复为默认值吗？'")
}
