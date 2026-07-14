$script:IntegrationRoot = Split-Path -Path $PSScriptRoot -Parent
$script:GuiEntryPath = Join-Path -Path $script:IntegrationRoot -ChildPath 'AI-FishBot.GUI.ps1'
$script:LauncherPath = Join-Path -Path $script:IntegrationRoot -ChildPath '启动_AI-FishBot-界面.cmd'
$script:WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

Import-Module (Join-Path $script:IntegrationRoot 'AI-FishBot.Config.psm1') -Force

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
        $first = Invoke-GuiEntryProcess -DataRoot $root -SelfTest -NoShow -Simulation
        Assert-Equal -Expected 0 -Actual $first.ExitCode
        Remove-Item -LiteralPath (Join-Path $root 'profiles\时光服.json') -Force

        $secret = 'https://discord.com/api/webhooks/123456/private-token'
        $bad = New-AIFishBotDefaultConfig
        $bad.profileName = $secret
        [IO.File]::WriteAllText(
            (Join-Path $root 'profiles\坏方案.json'),
            ($bad | ConvertTo-Json -Depth 20),
            (New-Object Text.UTF8Encoding($false)))

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

Test-Case 'launcher uses its own directory and starts the quoted GUI entry in STA mode' {
    $text = [IO.File]::ReadAllText($script:LauncherPath)
    Assert-True -Condition ($text -match '(?im)^cd /d "%~dp0"\s*$')
    Assert-True -Condition ($text -match '(?im)^powershell\.exe -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0AI-FishBot\.GUI\.ps1"\s*$')
    Assert-Equal -Expected $false -Actual ($text -match '(?im)>\s*nul|2>\s*nul|exit\s+/b\s+0')
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
