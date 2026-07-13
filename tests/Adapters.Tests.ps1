$script:AdaptersTestRoot = Split-Path -Path $PSScriptRoot -Parent
$script:AdaptersModulePath = Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Adapters.psm1'
$script:AdaptersEngineScriptPath = Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Engine.ps1'

if (-not (Test-Path -LiteralPath $script:AdaptersModulePath -PathType Leaf)) {
    Test-Case 'adapters module exists before its behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:AdaptersModulePath -PathType Leaf)
    }
    return
}

Import-Module -Name $script:AdaptersModulePath -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Config.psm1') `
    -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
    -Force -ErrorAction Stop

function Remove-AdaptersTestDirectory {
    param([AllowNull()][string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and
        [System.IO.Directory]::Exists($Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AdaptersMember {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Arguments = @()
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property -and $property.Value -is [scriptblock]) {
        return & $property.Value @Arguments
    }
    $method = $Object.PSObject.Methods[$Name]
    if ($null -ne $method) {
        return $method.Invoke($Arguments)
    }
    throw ('Missing test member: {0}' -f $Name)
}

Test-Case 'adapter module exports every public factory' {
    foreach ($name in @(
            'New-AIFishBotAudioMonitor',
            'New-AIFishBotKeySender',
            'New-AIFishBotGameFocuser',
            'New-AIFishBotNotifier',
            'New-AIFishBotEngineAdapter'
        )) {
        Assert-True -Condition ($null -ne (Get-Command -Name $name -ErrorAction SilentlyContinue))
    }
}

Test-Case 'software key sender validates and formats function keys for SendKeys' {
    $sent = New-Object 'System.Collections.Generic.List[string]'
    $captured = $sent
    $sender = New-AIFishBotKeySender -SendKeysProvider ({
            param($value)
            [void]$captured.Add([string]$value)
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F7') | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected @('{F7}') -Actual @($sent)
}

Test-Case 'key sender rejects keys outside F5 through F12' {
    $sender = New-AIFishBotKeySender -SendKeysProvider { param($value) }
    try {
        Assert-Throws -ScriptBlock {
            Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F4') | Out-Null
        } -MessageLike '*F5*F12*'
    }
    finally {
        Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    }
}

Test-Case 'Pico key sender opens with fixed serial settings sends lines and closes once' {
    $context = [pscustomobject]@{
        Arguments = @()
        OpenCount = 0
        CloseCount = 0
        DisposeCount = 0
        Lines = New-Object 'System.Collections.Generic.List[string]'
        IsOpen = $false
    }
    $captured = $context
    $serial = [pscustomobject]@{ IsOpen = $false }
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value {
        $captured.OpenCount += 1
        $this.IsOpen = $true
        $captured.IsOpen = $true
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name WriteLine -Value {
        param($line)
        [void]$captured.Lines.Add([string]$line)
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Close -Value {
        $captured.CloseCount += 1
        $this.IsOpen = $false
        $captured.IsOpen = $false
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = {
        param($portName, $baudRate, $parity, $dataBits, $stopBits)
        $captured.Arguments = @($portName, $baudRate, $parity, $dataBits, $stopBits)
        return $serial
    }.GetNewClosure()

    $sender = New-AIFishBotKeySender -UsePico -ComPort 'COM9' -SerialPortFactory $factory
    Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F12') | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected 'COM9' -Actual $context.Arguments[0]
    Assert-Equal -Expected 115200 -Actual $context.Arguments[1]
    Assert-Equal -Expected ([System.IO.Ports.Parity]::None) -Actual $context.Arguments[2]
    Assert-Equal -Expected 8 -Actual $context.Arguments[3]
    Assert-Equal -Expected ([System.IO.Ports.StopBits]::One) -Actual $context.Arguments[4]
    Assert-Equal -Expected @('F12') -Actual @($context.Lines)
    Assert-Equal -Expected 1 -Actual $context.OpenCount
    Assert-Equal -Expected 1 -Actual $context.CloseCount
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
}

Test-Case 'Pico key sender reports a clear open failure and disposes the failed port' {
    $context = [pscustomobject]@{ DisposeCount = 0 }
    $captured = $context
    $serial = [pscustomobject]@{}
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value { throw 'access denied' }
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = { param($portName, $baudRate, $parity, $dataBits, $stopBits) return $serial }.GetNewClosure()

    Assert-Throws -ScriptBlock {
        New-AIFishBotKeySender -UsePico -ComPort 'COM7' -SerialPortFactory $factory | Out-Null
    } -MessageLike '*COM7*access denied*'
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
}

Test-Case 'game focuser activates only World of Warcraft' {
    $targets = New-Object 'System.Collections.Generic.List[string]'
    $captured = $targets
    $focuser = New-AIFishBotGameFocuser -AppActivateProvider ({
            param($target)
            [void]$captured.Add([string]$target)
            return $true
        }.GetNewClosure()) -LogProvider { param($level, $message) }

    $result = Invoke-AdaptersMember -Object $focuser -Name Focus

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected @('World of Warcraft') -Actual @($targets)
}

Test-Case 'game focuser logs failure and returns false without choosing another window' {
    $targets = New-Object 'System.Collections.Generic.List[string]'
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedTargets = $targets
    $capturedLogs = $logs
    $focuser = New-AIFishBotGameFocuser -AppActivateProvider ({
            param($target)
            [void]$capturedTargets.Add([string]$target)
            throw 'window unavailable'
        }.GetNewClosure()) -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add(('{0}:{1}' -f $level, $message))
        }.GetNewClosure())

    $result = Invoke-AdaptersMember -Object $focuser -Name Focus

    Assert-Equal -Expected $false -Actual $result
    Assert-Equal -Expected @('World of Warcraft') -Actual @($targets)
    Assert-True -Condition (($logs -join "`n") -like '*window unavailable*')
}

Test-Case 'notifier posts JSON to a valid Discord webhook' {
    $requests = New-Object 'System.Collections.Generic.List[object]'
    $captured = $requests
    $rest = {
        param($Uri, $Method, $ContentType, $Body)
        [void]$captured.Add([pscustomobject]@{
                Uri = $Uri; Method = $Method; ContentType = $ContentType; Body = $Body
            })
        return [pscustomobject]@{ ok = $true }
    }.GetNewClosure()
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider $rest `
        -LogProvider { param($level, $message) } -ProtectProvider { param($text) return $text }
    $webhook = 'https://discord.com/api/webhooks/123456/secret-token'

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', $webhook)

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected 1 -Actual $requests.Count
    Assert-Equal -Expected $webhook -Actual $requests[0].Uri
    Assert-Equal -Expected 'Post' -Actual $requests[0].Method
    Assert-Equal -Expected 'application/json' -Actual $requests[0].ContentType
    Assert-Equal -Expected 'start' -Actual (($requests[0].Body | ConvertFrom-Json).event)
}

Test-Case 'notifier rejects empty and non-Discord webhook values without a request' {
    $context = [pscustomobject]@{ RequestCount = 0 }
    $captured = $context
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider ({
            param($Uri, $Method, $ContentType, $Body)
            $captured.RequestCount += 1
        }.GetNewClosure()) -LogProvider { param($level, $message) }

    $emptyResult = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', '')
    $invalidResult = Invoke-AdaptersMember -Object $notifier -Name Notify `
        -Arguments @('stop', 'https://example.com/webhooks/123/token')

    Assert-Equal -Expected $false -Actual $emptyResult
    Assert-Equal -Expected $false -Actual $invalidResult
    Assert-Equal -Expected 0 -Actual $context.RequestCount
}

Test-Case 'notifier contains network errors and masks webhook tokens in logs' {
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedLogs = $logs
    $webhook = 'https://discord.com/api/webhooks/123456/secret-token'
    $rest = { param($Uri, $Method, $ContentType, $Body) throw ('request failed: {0}' -f $Uri) }
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider $rest -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add([string]$message)
        }.GetNewClosure()) -ProtectProvider {
        param($text)
        return [regex]::Replace($text, '(webhooks/)[^/]+/[^\s]+', '${1}***')
    }

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('stop', $webhook)
    $logText = $logs -join "`n"

    Assert-Equal -Expected $false -Actual $result
    Assert-True -Condition ($logText -like '*webhooks/***')
    Assert-Equal -Expected $false -Actual $logText.Contains('secret-token')
}

Test-Case 'audio monitor returns one numeric peak clamped to zero through one hundred' {
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue(@('noise', 12, 105))
    $queue.Enqueue(-4)
    $captured = $queue
    $monitor = New-AIFishBotAudioMonitor -WriteAudioDeviceProvider ({
            if ($captured.Count -eq 0) { return $null }
            return $captured.Dequeue()
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $monitor -Name Start | Out-Null
    $high = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    $low = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]) -Actual $high.GetType()
    Assert-Equal -Expected ([double]100) -Actual $high
    Assert-Equal -Expected ([double]0) -Actual $low
}

Test-Case 'audio monitor owns and removes every playback job exactly once' {
    $context = [pscustomobject]@{
        StartCount = 0
        StopCount = 0
        RemoveCount = 0
        Job = $null
        ScriptText = ''
    }
    $captured = $context
    $startProvider = {
        param($scriptBlock)
        $captured.StartCount += 1
        $captured.ScriptText = [string]$scriptBlock
        $captured.Job = [pscustomobject]@{ State = 'Running'; Output = @(32) }
        return $captured.Job
    }.GetNewClosure()
    $receiveProvider = { param($job) return @($job.Output) }
    $stopProvider = {
        param($job)
        $captured.StopCount += 1
        $job.State = 'Stopped'
    }.GetNewClosure()
    $removeProvider = { param($job) $captured.RemoveCount += 1 }.GetNewClosure()
    $monitor = New-AIFishBotAudioMonitor -StartJobProvider $startProvider `
        -ReceiveJobProvider $receiveProvider -StopJobProvider $stopProvider `
        -RemoveJobProvider $removeProvider

    Invoke-AdaptersMember -Object $monitor -Name Start | Out-Null
    $peak = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]32) -Actual $peak
    Assert-True -Condition ($context.ScriptText -match 'Write-AudioDevice\s+-PlaybackStream')
    Assert-Equal -Expected 1 -Actual $context.StartCount
    Assert-Equal -Expected 1 -Actual $context.StopCount
    Assert-Equal -Expected 1 -Actual $context.RemoveCount
}

Test-Case 'engine adapter simulation is memory-only and records injected events' {
    $events = New-Object 'System.Collections.Generic.List[string]'
    $captured = $events
    $adapter = New-AIFishBotEngineAdapter -Simulation -SimulationPeaks @(37) `
        -SimulationEventSink ({ param($eventName) [void]$captured.Add([string]$eventName) }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name SleepMilliseconds -Arguments @(250) | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name SendKey -Arguments @('F7') | Out-Null
    $focused = Invoke-AdaptersMember -Object $adapter -Name FocusWindow
    $peak = Invoke-AdaptersMember -Object $adapter -Name ReadPeak
    $notified = Invoke-AdaptersMember -Object $adapter -Name Notify `
        -Arguments @('start', 'https://discord.com/api/webhooks/1/token')
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]250) -Actual (Invoke-AdaptersMember -Object $adapter -Name MonotonicMilliseconds)
    Assert-Equal -Expected $true -Actual $focused
    Assert-Equal -Expected ([double]37) -Actual $peak
    Assert-Equal -Expected $true -Actual $notified
    Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    Assert-Equal -Expected @('sleep:250', 'key:F7', 'focus', 'peak:37', 'notify:start', 'dispose') `
        -Actual @($events)
}

Test-Case 'engine adapter delegates every core operation through injected components' {
    $events = New-Object 'System.Collections.Generic.List[string]'
    $captured = $events
    $monitor = [pscustomobject]@{
        Start = ({ [void]$captured.Add('audio:start') }.GetNewClosure())
        ReadPeak = ({ [void]$captured.Add('audio:read'); return [double]44 }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('audio:dispose') }.GetNewClosure())
    }
    $sender = [pscustomobject]@{
        Send = ({ param($key) [void]$captured.Add(('key:{0}' -f $key)) }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('key:dispose') }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = ({ [void]$captured.Add('focus'); return $true }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('focus:dispose') }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = ({ param($eventName, $webhook) [void]$captured.Add(('notify:{0}' -f $eventName)); return $true }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('notify:dispose') }.GetNewClosure())
    }
    $adapter = New-AIFishBotEngineAdapter -AudioMonitor $monitor -KeySender $sender `
        -GameFocuser $focuser -Notifier $notifier `
        -SleepProvider ({ param($milliseconds) [void]$captured.Add(('sleep:{0}' -f $milliseconds)) }.GetNewClosure()) `
        -NowProvider { return [datetimeoffset]'2026-07-13T12:00:00+08:00' } `
        -MonotonicMillisecondsProvider { return [double]1234 } `
        -LogProvider ({ param($level, $message) [void]$captured.Add(('log:{0}:{1}' -f $level, $message)) }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name SleepMilliseconds -Arguments @(10) | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name SendKey -Arguments @('F6') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name FocusWindow | Out-Null
    $peak = Invoke-AdaptersMember -Object $adapter -Name ReadPeak
    Invoke-AdaptersMember -Object $adapter -Name Notify -Arguments @('stop', 'webhook') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Log -Arguments @('Info', 'message') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]44) -Actual $peak
    Assert-Equal -Expected ([double]1234) `
        -Actual (Invoke-AdaptersMember -Object $adapter -Name MonotonicMilliseconds)
    Assert-Equal -Expected @(
        'audio:start', 'sleep:10', 'key:F6', 'focus', 'audio:read', 'notify:stop',
        'log:Info:message', 'audio:dispose', 'key:dispose', 'focus:dispose', 'notify:dispose'
    ) -Actual @($events)
}

if (-not (Test-Path -LiteralPath $script:AdaptersEngineScriptPath -PathType Leaf)) {
    Test-Case 'engine entry script exists before integration behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:AdaptersEngineScriptPath -PathType Leaf)
    }
    return
}

Test-Case 'simulation engine process observes stop and exits with a final heartbeat and log' {
    $runDirectory = New-TestDirectory
    $process = $null
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = 'Simulation Integration'
        $config.autoStop = $false
        $config.useWindowFocus = $true
        $config | Add-Member -NotePropertyName configVersion -NotePropertyValue 1
        $startPath = Join-Path $runDirectory 'start-config.json'
        $livePath = Join-Path $runDirectory 'live-config.json'
        Write-AIFishBotAtomicJson -Path $startPath -InputObject $config | Out-Null
        Write-AIFishBotAtomicJson -Path $livePath -InputObject $config | Out-Null
        [System.IO.File]::SetAttributes(
            $startPath,
            ([System.IO.File]::GetAttributes($startPath) -bor [System.IO.FileAttributes]::ReadOnly))

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RunDirectory "{1}" -Simulation' -f `
            $script:AdaptersEngineScriptPath, $runDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)

        $deadline = [datetime]::UtcNow.AddSeconds(15)
        $status = $null
        while ([datetime]::UtcNow -lt $deadline) {
            try {
                $status = Read-AIFishBotStatus -RunDirectory $runDirectory
                if ($null -ne $status) { break }
            }
            catch {
            }
            Start-Sleep -Milliseconds 25
        }
        Assert-True -Condition ($null -ne $status)
        Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command stop | Out-Null
        Assert-True -Condition $process.WaitForExit(15000)

        $final = Read-AIFishBotStatus -RunDirectory $runDirectory
        $logFiles = @(Get-ChildItem -LiteralPath (Join-Path $runDirectory 'logs') -Filter '*.log' -File)
        Assert-Equal -Expected 0 -Actual $process.ExitCode
        Assert-Equal -Expected 'stopped' -Actual $final.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$final.heartbeatAt))
        Assert-True -Condition ($logFiles.Count -ge 1)
    }
    finally {
        if ($null -ne $process) {
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
        }
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}

Test-Case 'engine entry exits one and writes error status when start config is missing' {
    $runDirectory = New-TestDirectory
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:AdaptersEngineScriptPath `
            -RunDirectory $runDirectory -Simulation 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $status = Read-AIFishBotStatus -RunDirectory $runDirectory

        Assert-Equal -Expected 1 -Actual $exitCode
        Assert-Equal -Expected 'error' -Actual $status.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$status.lastError))
    }
    finally {
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}

Test-Case 'engine entry exits one and writes error status for malformed startup JSON' {
    $runDirectory = New-TestDirectory
    try {
        [System.IO.File]::WriteAllText((Join-Path $runDirectory 'start-config.json'), '{bad json')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:AdaptersEngineScriptPath `
            -RunDirectory $runDirectory -Simulation 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $status = Read-AIFishBotStatus -RunDirectory $runDirectory

        Assert-Equal -Expected 1 -Actual $exitCode
        Assert-Equal -Expected 'error' -Actual $status.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$status.lastError))
    }
    finally {
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}
