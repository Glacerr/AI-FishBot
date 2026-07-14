$script:EngineTestRoot = Split-Path -Path $PSScriptRoot -Parent
$script:EngineModulePath = Join-Path -Path $script:EngineTestRoot -ChildPath 'AI-FishBot.EngineCore.psm1'

if (-not (Test-Path -LiteralPath $script:EngineModulePath -PathType Leaf)) {
    Test-Case 'engine core module exists before its behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:EngineModulePath -PathType Leaf)
    }
    return
}

Import-Module -Name $script:EngineModulePath -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:EngineTestRoot -ChildPath 'AI-FishBot.Config.psm1') `
    -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:EngineTestRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
    -Force -ErrorAction Stop

Test-Case 'importing engine preserves already imported config and runtime commands' {
    $configPath = Join-Path -Path $script:EngineTestRoot -ChildPath 'AI-FishBot.Config.psm1'
    $runtimePath = Join-Path -Path $script:EngineTestRoot -ChildPath 'AI-FishBot.Runtime.psm1'
    $command = @"
Import-Module -Name '$configPath' -Force -ErrorAction Stop
Import-Module -Name '$runtimePath' -Force -ErrorAction Stop
Import-Module -Name '$script:EngineModulePath' -Force -ErrorAction Stop
if (`$null -eq (Get-Command New-AIFishBotDefaultConfig -ErrorAction SilentlyContinue) -or
    `$null -eq (Get-Command Read-AIFishBotStatus -ErrorAction SilentlyContinue)) {
    exit 1
}
exit 0
"@
    & powershell.exe -NoProfile -Command $command | Out-Null
    Assert-Equal -Expected 0 -Actual $LASTEXITCODE
}

function New-EngineConfig {
    param(
        [hashtable]$Values = @{}
    )

    $config = New-AIFishBotDefaultConfig
    $config.useWindowFocus = $false
    $config.autoStop = $false
    $config.enableNotifications = $false
    foreach ($name in $Values.Keys) {
        $config.$name = $Values[$name]
    }
    return $config
}

function Copy-EngineConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    return $Config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

function New-SimulatedAdapter {
    param(
        [datetimeoffset]$Now = [datetimeoffset]'2026-07-13T08:00:00+08:00',
        [object[]]$Peaks = @(),
        [switch]$ThrowOnNotify,
        [switch]$ThrowOnReadPeak,
        [scriptblock]$OnSleep
    )

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($peak in $Peaks) {
        $queue.Enqueue($peak)
    }
    $context = [pscustomobject]@{
        Now = $Now
        MonotonicMilliseconds = [double]0
        Peaks = $queue
        Events = New-Object 'System.Collections.Generic.List[string]'
        Notifications = New-Object 'System.Collections.Generic.List[object]'
        DisposeCount = 0
        ThrowOnNotify = [bool]$ThrowOnNotify
        ThrowOnReadPeak = [bool]$ThrowOnReadPeak
        OnSleep = $OnSleep
    }
    $captured = $context
    return [pscustomobject]@{
        Context = $context
        Now = ({ return $captured.Now }.GetNewClosure())
        MonotonicMilliseconds = ({ return $captured.MonotonicMilliseconds }.GetNewClosure())
        SleepMilliseconds = ({
                param($milliseconds)
                [void]$captured.Events.Add(('sleep:{0}' -f [int]$milliseconds))
                $captured.Now = $captured.Now.AddMilliseconds([double]$milliseconds)
                $captured.MonotonicMilliseconds += [double]$milliseconds
                if ($null -ne $captured.OnSleep) {
                    & $captured.OnSleep ([int]$milliseconds)
                }
            }.GetNewClosure())
        FocusWindow = ({ [void]$captured.Events.Add('focus') }.GetNewClosure())
        SendKey = ({
                param($key)
                [void]$captured.Events.Add(('key:{0}' -f $key))
            }.GetNewClosure())
        ReadPeak = ({
                [void]$captured.Events.Add('peak')
                if ($captured.ThrowOnReadPeak) {
                    throw 'simulated peak failure'
                }
                if ($captured.Peaks.Count -eq 0) {
                    return 0
                }
                return $captured.Peaks.Dequeue()
            }.GetNewClosure())
        Notify = ({
                param($eventName, $webhook)
                [void]$captured.Events.Add(('notify:{0}' -f $eventName))
                [void]$captured.Notifications.Add([pscustomobject]@{
                        EventName = [string]$eventName
                        Webhook = [string]$webhook
                    })
                if ($captured.ThrowOnNotify) {
                    throw ('simulated notification failure for {0}' -f $webhook)
                }
            }.GetNewClosure())
        Dispose = ({ $captured.DisposeCount += 1 }.GetNewClosure())
    }
}

function New-VersionedLoader {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Items
    )

    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($item in $Items) {
        $queue.Enqueue($item)
    }
    $captured = $queue
    return ({
            param($state)
            if ($captured.Count -eq 0) {
                return $null
            }
            return $captured.Dequeue()
        }.GetNewClosure())
}

function New-EngineTestState {
    param(
        [object]$Config = $(New-EngineConfig),
        [object]$Adapter = $(New-SimulatedAdapter),
        [scriptblock]$RandomIntProvider = { param($minimum, $maximum) return $minimum },
        [scriptblock]$LiveConfigLoader,
        [scriptblock]$ControlReader,
        [datetimeoffset]$StartedAt,
        [datetimeoffset]$ProcessStartedAt = [datetimeoffset]'2026-07-13T07:59:58+08:00'
    )

    $runDirectory = New-TestDirectory
    $parameters = @{
        Config = $Config
        RunDirectory = $runDirectory
        Adapter = $Adapter
        RandomIntProvider = $RandomIntProvider
        ProcessStartedAt = $ProcessStartedAt
    }
    if ($PSBoundParameters.ContainsKey('LiveConfigLoader')) {
        $parameters.LiveConfigLoader = $LiveConfigLoader
    }
    if ($PSBoundParameters.ContainsKey('ControlReader')) {
        $parameters.ControlReader = $ControlReader
    }
    if ($PSBoundParameters.ContainsKey('StartedAt')) {
        $parameters.StartedAt = $StartedAt
    }
    $state = New-AIFishBotEngineState @parameters
    $state | Add-Member -NotePropertyName TestRunDirectory -NotePropertyValue $runDirectory
    return $state
}

function Remove-EngineTestState {
    param(
        [AllowNull()]
        [object]$State
    )

    if ($null -ne $State -and
        $null -ne $State.PSObject.Properties['TestRunDirectory']) {
        Remove-Item -LiteralPath $State.TestRunDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-EventCount {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Adapter,

        [Parameter(Mandatory = $true)]
        [string]$Event
    )

    return @($Adapter.Context.Events | Where-Object { $_ -eq $Event }).Count
}

Test-Case 'engine state keeps locked and live snapshots with runtime counters' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ profileName = '测试方案'; castKey = 'F6' }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $config.castKey = 'F12'

        Assert-Equal -Expected 'F6' -Actual $state.LockedConfig.castKey
        Assert-Equal -Expected 'F6' -Actual $state.LiveConfig.castKey
        Assert-Equal -Expected 0 -Actual $state.ConfigVersion
        Assert-Equal -Expected 0 -Actual $state.HookCount
        Assert-Equal -Expected 0 -Actual $state.RetryCount
        Assert-Equal -Expected ([double]0) -Actual $state.AudioPeak
        Assert-Equal -Expected 'ready' -Actual $state.State
        Assert-Equal -Expected $false -Actual $state.StopRequested
        Assert-Equal -Expected $adapter -Actual $state.Adapter
        Assert-True -Condition ([System.IO.Path]::IsPathRooted($state.RunDirectory))
        Assert-True -Condition ($state.BuffExpirations -is [hashtable])
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'waiting-for-bite publishes a below-threshold peak only at the next periodic heartbeat' {
    $holder = @{ State = $null }
    $observation = @{
        WaitingHeartbeat = $null
        Before = $null
        EngineAtBefore = $null
        After = $null
        EngineAtAfter = $null
        StopReady = $false
    }
    $capturedHolder = $holder
    $capturedObservation = $observation
    $onSleep = {
        param($milliseconds)
        $state = $capturedHolder.State
        if ($null -eq $state -or $state.State -ne 'waiting-for-bite') {
            return
        }
        if ($null -eq $capturedObservation.WaitingHeartbeat) {
            $capturedObservation.WaitingHeartbeat =
                [double]$state.LastHeartbeatMonotonicMilliseconds
        }
        $heartbeatDue = [double]$capturedObservation.WaitingHeartbeat + 1000
        $monotonicNow = [double]$state.Adapter.Context.MonotonicMilliseconds
        if ($null -eq $capturedObservation.Before -and
            $monotonicNow -ge ($heartbeatDue - 100) -and $monotonicNow -lt $heartbeatDue) {
            $capturedObservation.Before = Read-AIFishBotStatus -RunDirectory $state.RunDirectory
            $capturedObservation.EngineAtBefore = [pscustomobject]@{
                MonotonicMilliseconds = $monotonicNow
                LastHeartbeatMonotonicMilliseconds =
                    [double]$state.LastHeartbeatMonotonicMilliseconds
            }
        }
        if ($null -eq $capturedObservation.After -and
            [double]$state.LastHeartbeatMonotonicMilliseconds -ge $heartbeatDue) {
            $capturedObservation.After = Read-AIFishBotStatus -RunDirectory $state.RunDirectory
            $capturedObservation.EngineAtAfter = [pscustomobject]@{
                MonotonicMilliseconds = $monotonicNow
                LastHeartbeatMonotonicMilliseconds =
                    [double]$state.LastHeartbeatMonotonicMilliseconds
                HookCount = [int]$state.HookCount
                RetryCount = [int]$state.RetryCount
                StopRequested = [bool]$state.StopRequested
                StateHistory = @($state.StateHistory)
            }
            $capturedObservation.StopReady = $true
        }
    }.GetNewClosure()
    $peaks = @(1..12 | ForEach-Object { [double]4.75 })
    $adapter = New-SimulatedAdapter -Peaks $peaks -OnSleep $onSleep
    $reader = {
        param($state)
        if ($capturedObservation.StopReady) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }.GetNewClosure()
    $config = New-EngineConfig -Values @{ useWeakAura = $false; audioSensitivity = 5 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        $holder.State = $state

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-True -Condition ($null -ne $observation.Before)
        Assert-True -Condition ($null -ne $observation.After)
        Assert-Equal -Expected ([double]0) -Actual $observation.Before.audioPeak
        Assert-Equal -Expected 'waiting-for-bite' -Actual $observation.Before.state
        Assert-True -Condition ($observation.EngineAtBefore.MonotonicMilliseconds -lt
            ([double]$observation.WaitingHeartbeat + 1000))
        Assert-Equal -Expected ([double]$observation.WaitingHeartbeat) `
            -Actual $observation.EngineAtBefore.LastHeartbeatMonotonicMilliseconds
        Assert-Equal -Expected ([double]4.75) -Actual $observation.After.audioPeak
        Assert-Equal -Expected 'waiting-for-bite' -Actual $observation.After.state
        Assert-Equal -Expected ([double]($observation.WaitingHeartbeat + 1000)) `
            -Actual $observation.EngineAtAfter.LastHeartbeatMonotonicMilliseconds
        Assert-Equal -Expected 0 -Actual $observation.EngineAtAfter.HookCount
        Assert-Equal -Expected 0 -Actual $observation.EngineAtAfter.RetryCount
        Assert-Equal -Expected $false -Actual $observation.EngineAtAfter.StopRequested
        Assert-Equal -Expected @('ready', 'casting', 'waiting-for-bite') `
            -Actual $observation.EngineAtAfter.StateHistory
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F7')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'adapter may expose its current time as a direct value' {
    $adapter = New-SimulatedAdapter
    $expectedNow = [datetimeoffset]'2026-07-13T09:15:00+08:00'
    $adapter.Now = $expectedNow
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Assert-Equal -Expected $expectedNow -Actual $state.StartedAt
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine uses an injected monotonic millisecond clock when available' {
    $adapter = New-SimulatedAdapter
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Assert-Equal -Expected 'Adapter.MonotonicMilliseconds' -Actual $state.MonotonicSource
        Assert-Equal -Expected ([double]0) -Actual $state.StartedMonotonicMilliseconds
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine accepts an injected monotonic timespan clock' {
    $adapter = New-SimulatedAdapter
    $adapter.PSObject.Properties.Remove('MonotonicMilliseconds')
    $capturedContext = $adapter.Context
    $adapter | Add-Member -NotePropertyName MonotonicNow -NotePropertyValue ({
            return [timespan]::FromMilliseconds($capturedContext.MonotonicMilliseconds)
        }.GetNewClosure())
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Assert-Equal -Expected 'Adapter.MonotonicNow' -Actual $state.MonotonicSource
        Assert-Equal -Expected ([double]0) -Actual $state.StartedMonotonicMilliseconds
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine falls back to a running stopwatch when no monotonic adapter clock exists' {
    $adapter = New-SimulatedAdapter
    $adapter.PSObject.Properties.Remove('MonotonicMilliseconds')
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Assert-Equal -Expected 'Stopwatch' -Actual $state.MonotonicSource
        Assert-True -Condition ($state.MonotonicStopwatch -is [System.Diagnostics.Stopwatch])
        Assert-True -Condition $state.MonotonicStopwatch.IsRunning
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'first ready status write is deferred until the owned engine loop starts' {
    $adapter = New-SimulatedAdapter
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Assert-Equal -Expected $false -Actual (Test-Path -LiteralPath `
                (Join-Path -Path $state.RunDirectory -ChildPath 'status.json'))
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine status carries the injected operating-system process start identity' {
    $adapter = New-SimulatedAdapter
    $runDirectory = New-TestDirectory
    $state = $null
    $processStartedAt = [datetimeoffset]'2026-07-13T07:59:58.1234567+08:00'
    try {
        $state = New-AIFishBotEngineState -Config (New-EngineConfig) `
            -RunDirectory $runDirectory -Adapter $adapter `
            -StartedAt ([datetimeoffset]'2026-07-13T08:00:00+08:00') `
            -ProcessStartedAt $processStartedAt `
            -ControlReader { param($engineState) [pscustomobject]@{ command = 'stop' } }

        Start-AIFishBotEngineLoop -State $state | Out-Null
        $status = Read-AIFishBotStatus -RunDirectory $runDirectory

        Assert-Equal -Expected $processStartedAt.ToString('o') -Actual $status.processStartedAt
    }
    finally {
        if (Test-Path -LiteralPath $runDirectory) {
            Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Test-Case 'initial status failure still disposes the adapter exactly once' {
    $adapter = New-SimulatedAdapter
    $adapter.Now = { throw 'simulated initial status failure' }
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter `
            -StartedAt ([datetimeoffset]'2026-07-13T08:00:00+08:00')
        Start-AIFishBotEngineLoop -State $state | Out-Null
        Assert-Equal -Expected 'error' -Actual $state.State
        Assert-True -Condition ($state.LastError -like '*initial status failure*')
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'bite sequence uses the exact simulated four-delay action order' {
    $adapter = New-SimulatedAdapter
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Invoke-AIFishBotBiteSequence -State $state | Out-Null

        Assert-Equal -Expected @(
            'sleep:300', 'sleep:500', 'key:F7', 'sleep:1000', 'sleep:100', 'sleep:200', 'key:F6'
        ) -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 1 -Actual $state.HookCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'focus is placed immediately before each simulated fishing key' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ useWindowFocus = $true }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBiteSequence -State $state | Out-Null

        Assert-Equal -Expected @(
            'sleep:300', 'sleep:500', 'focus', 'key:F7',
            'sleep:1000', 'sleep:100', 'sleep:200', 'focus', 'key:F6'
        ) -Actual @($adapter.Context.Events)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'random delay ranges include each configured upper boundary' {
    $adapter = New-SimulatedAdapter
    $ranges = New-Object 'System.Collections.Generic.List[string]'
    $capturedRanges = $ranges
    $provider = {
        param($minimum, $maximum)
        [void]$capturedRanges.Add(('{0}-{1}' -f $minimum, $maximum))
        return $maximum
    }.GetNewClosure()
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter -RandomIntProvider $provider
        Invoke-AIFishBotBiteSequence -State $state | Out-Null

        Assert-Equal -Expected @('300-700', '1100-1500', '200-600') -Actual @($ranges)
        Assert-Equal -Expected @(
            'sleep:700', 'sleep:500', 'key:F7', 'sleep:1000', 'sleep:500', 'sleep:600', 'key:F6'
        ) `
            -Actual @($adapter.Context.Events)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'live delay changes take effect on the very next fishing action' {
    $adapter = New-SimulatedAdapter
    $base = New-EngineConfig
    $items = @()
    foreach ($version in 1..6) {
        $candidate = Copy-EngineConfig -Config $base
        $candidate.biteResponseMinSeconds = 0.4
        $candidate.biteResponseMaxSeconds = 0.4
        if ($version -ge 2) {
            $candidate.preHookMinSeconds = 0.6
            $candidate.preHookMaxSeconds = 0.6
        }
        if ($version -ge 4) {
            $candidate.postHookMinSeconds = 1.2
            $candidate.postHookMaxSeconds = 1.2
        }
        if ($version -ge 5) {
            $candidate.preCastMinSeconds = 0.25
            $candidate.preCastMaxSeconds = 0.25
        }
        $items += [pscustomobject]@{ ConfigVersion = $version; Config = $candidate }
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $base -Adapter $adapter `
            -LiveConfigLoader (New-VersionedLoader -Items $items)
        Invoke-AIFishBotBiteSequence -State $state | Out-Null

        Assert-Equal -Expected @(
            'sleep:400', 'sleep:600', 'key:F7', 'sleep:1000', 'sleep:200', 'sleep:250', 'key:F6'
        ) `
            -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 6 -Actual $state.ConfigVersion
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'live updates accept only the whitelist and only a higher version' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{
        castKey = 'F6'; bobberKey = 'F7'; retail = $false; useWeakAura = $false
    }
    $candidate = Copy-EngineConfig -Config $config
    $candidate.audioSensitivity = 7
    $candidate.autoStop = $true
    $candidate.castKey = 'F12'
    $candidate.bobberKey = 'F11'
    $candidate.retail = $true
    $candidate.useWeakAura = $true
    $candidate.fishingRetries = 99
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $candidate -ConfigVersion 2)

        Assert-Equal -Expected 7 -Actual $state.LiveConfig.audioSensitivity
        Assert-Equal -Expected $true -Actual $state.LiveConfig.autoStop
        Assert-Equal -Expected 'F6' -Actual $state.LiveConfig.castKey
        Assert-Equal -Expected 'F7' -Actual $state.LiveConfig.bobberKey
        Assert-Equal -Expected $false -Actual $state.LiveConfig.retail
        Assert-Equal -Expected $false -Actual $state.LiveConfig.useWeakAura
        Assert-Equal -Expected 15 -Actual $state.LiveConfig.fishingRetries
        Assert-Equal -Expected 2 -Actual $state.ConfigVersion

        $candidate.audioSensitivity = 8
        Assert-Equal -Expected $false -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $candidate -ConfigVersion 2)
        Assert-Equal -Expected 7 -Actual $state.LiveConfig.audioSensitivity
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'invalid live config is logged and leaves the last valid snapshot intact' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig
    $candidate = Copy-EngineConfig -Config $config
    $candidate.audioSensitivity = 99
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Equal -Expected $false -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $candidate -ConfigVersion 1)
        Assert-Equal -Expected 3 -Actual $state.LiveConfig.audioSensitivity
        Assert-Equal -Expected 0 -Actual $state.ConfigVersion

        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*live config*rejected*')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'live config versions require bounded integer value types and recover afterward' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig
    $candidate = Copy-EngineConfig -Config $config
    $candidate.audioSensitivity = 4
    $invalidVersions = @(
        '1',
        $true,
        [decimal]1,
        [double]1,
        [single]1,
        [long]2147483648,
        [int]-1
    )
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        foreach ($invalidVersion in $invalidVersions) {
            Assert-Equal -Expected $false -Actual (Update-AIFishBotLiveConfig -State $state `
                    -CandidateConfig $candidate -ConfigVersion $invalidVersion)
            Assert-Equal -Expected 0 -Actual $state.ConfigVersion
            Assert-Equal -Expected 3 -Actual $state.LiveConfig.audioSensitivity
        }

        $candidate.audioSensitivity = 5
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $candidate -ConfigVersion ([long]1))
        Assert-Equal -Expected 1 -Actual $state.ConfigVersion
        Assert-Equal -Expected 5 -Actual $state.LiveConfig.audioSensitivity

        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-Equal -Expected $invalidVersions.Count -Actual `
            ([regex]::Matches($logText, 'Live config rejected: config version is invalid\.')).Count
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'WeakAura cast accepts a peak exactly at the sensitivity threshold' {
    $adapter = New-SimulatedAdapter -Peaks @(3)
    $config = New-EngineConfig -Values @{ useWeakAura = $true; fishingRetries = 2 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Equal -Expected $true -Actual (Invoke-AIFishBotCast -State $state)

        Assert-Equal -Expected @('sleep:200', 'key:F6', 'sleep:1000', 'peak') `
            -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 0 -Actual $state.RetryCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'WeakAura cast records retries and stops at its configured limit' {
    $adapter = New-SimulatedAdapter -Peaks @(0, 0)
    $config = New-EngineConfig -Values @{ useWeakAura = $true; fishingRetries = 2 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Throws -ScriptBlock { Invoke-AIFishBotCast -State $state } -MessageLike '*retry limit*'

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'sleep:1000')
        Assert-Equal -Expected 1 -Actual $state.RetryCount
        Assert-Equal -Expected $true -Actual $state.StopRequested
        Assert-Equal -Expected 'error' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'WeakAura zero-attempt limit errors immediately without sending a key' {
    $adapter = New-SimulatedAdapter -ThrowOnReadPeak
    $config = New-EngineConfig -Values @{ useWeakAura = $true; fishingRetries = 0 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Throws -ScriptBlock { Invoke-AIFishBotCast -State $state } -MessageLike '*retry limit*'

        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'peak')
        Assert-Equal -Expected 0 -Actual @($adapter.Context.Events).Count
        Assert-Equal -Expected 0 -Actual $state.RetryCount
        Assert-Equal -Expected $true -Actual $state.StopRequested
        Assert-Equal -Expected 'error' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'non-WeakAura cast sends one simulated key and never samples audio' {
    $adapter = New-SimulatedAdapter -ThrowOnReadPeak
    $config = New-EngineConfig -Values @{ useWeakAura = $false }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Equal -Expected $true -Actual (Invoke-AIFishBotCast -State $state)

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'peak')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

foreach ($invalidPeakCase in @(
        [pscustomobject]@{ Name = 'Boolean'; Value = $true },
        [pscustomobject]@{ Name = 'numeric text'; Value = '3' },
        [pscustomobject]@{ Name = 'NaN'; Value = [double]::NaN },
        [pscustomobject]@{ Name = 'infinity'; Value = [double]::PositiveInfinity },
        [pscustomobject]@{ Name = 'negative value'; Value = [double]-0.1 },
        [pscustomobject]@{ Name = 'value above one hundred'; Value = [double]100.1 }
    )) {
    Test-Case ('invalid {0} audio peak causes adapter error and safe disposal' -f $invalidPeakCase.Name) {
        $adapter = New-SimulatedAdapter -Peaks @($invalidPeakCase.Value)
        $reader = {
            param($state)
            $reads = @($state.Adapter.Context.Events | Where-Object { $_ -eq 'peak' }).Count
            if ($reads -ge 1) {
                return [pscustomobject]@{ command = 'stop' }
            }
            return $null
        }
        $state = $null
        try {
            $state = New-EngineTestState -Adapter $adapter -ControlReader $reader
            Start-AIFishBotEngineLoop -State $state | Out-Null

            Assert-Equal -Expected 'error' -Actual $state.State
            Assert-Equal -Expected $true -Actual $state.StopRequested
            Assert-True -Condition ($state.LastError -like '*invalid audio peak*')
            Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        }
        finally {
            Remove-EngineTestState -State $state
        }
    }
}

Test-Case 'no bite completes the classic window and starts the next round before stop' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ retail = $false; audioSensitivity = 3 }
    $reader = {
        param($state)
        $casts = @($state.Adapter.Context.Events | Where-Object { $_ -eq 'key:F6' }).Count
        if ($casts -ge 2) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 0 -Actual $state.HookCount
        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected @(
            'ready', 'casting', 'waiting-for-bite', 'casting', 'stopping', 'stopped'
        ) -Actual @($state.StateHistory)
        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        Assert-True -Condition ($adapter.Context.Now -ge $state.StartedAt.AddSeconds(30))
        $firstPeakIndex = $adapter.Context.Events.IndexOf('peak')
        $longWaitSlicesBeforePeak = @(
            $adapter.Context.Events[0..($firstPeakIndex - 1)] | Where-Object { $_ -eq 'sleep:1000' }
        ).Count
        Assert-True -Condition ($firstPeakIndex -ge 0 -and $longWaitSlicesBeforePeak -ge 4)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'retail no-bite window ends after twenty-two total seconds' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ retail = $true }
    $reader = {
        param($state)
        $casts = @($state.Adapter.Context.Events | Where-Object { $_ -eq 'key:F6' }).Count
        if ($casts -ge 2) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected @(
            'ready', 'casting', 'waiting-for-bite', 'casting', 'stopping', 'stopped'
        ) -Actual @($state.StateHistory)
        Assert-True -Condition ($adapter.Context.Now -ge $state.StartedAt.AddSeconds(22.2))
        Assert-True -Condition ($adapter.Context.Now -lt $state.StartedAt.AddSeconds(23))
        Assert-Equal -Expected 'stopped' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine loop treats an equal peak as a bite and completes the hook sequence' {
    $adapter = New-SimulatedAdapter -Peaks @(3)
    $config = New-EngineConfig -Values @{ audioSensitivity = 3 }
    $reader = {
        param($state)
        if ($state.HookCount -ge 1 -and
            $state.Adapter.Context.MonotonicMilliseconds -ge 12000) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual $state.HookCount
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F7')
        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-True -Condition ($adapter.Context.MonotonicMilliseconds -ge 12000)
        Assert-Equal -Expected 'stopped' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'waiting loop refreshes its runtime heartbeat while no bite is heard' {
    $holder = @{ State = $null }
    $observation = @{ HeartbeatAt = $null }
    $capturedHolder = $holder
    $capturedObservation = $observation
    $onSleep = {
        param($milliseconds)
        if ($null -ne $capturedHolder.State -and
            $null -eq $capturedObservation.HeartbeatAt -and
            $capturedHolder.State.Adapter.Context.Now -ge
                $capturedHolder.State.StartedAt.AddSeconds(5.5)) {
            $path = Join-Path -Path $capturedHolder.State.RunDirectory -ChildPath 'status.json'
            $status = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
            $capturedObservation.HeartbeatAt = [datetimeoffset]$status.heartbeatAt
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $reader = {
        param($state)
        if ($state.Adapter.Context.Now -ge $state.StartedAt.AddSeconds(6)) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter -ControlReader $reader
        $holder.State = $state
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-True -Condition ($null -ne $observation.HeartbeatAt)
        Assert-True -Condition ($observation.HeartbeatAt -ge $state.StartedAt.AddSeconds(5))
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'a configurable wait longer than five seconds refreshes heartbeat in bounded slices' {
    $holder = @{ State = $null; HeartbeatAt = $null; LargestSleep = 0 }
    $capturedHolder = $holder
    $onSleep = {
        param($milliseconds)
        $capturedHolder.LargestSleep = [math]::Max($capturedHolder.LargestSleep, $milliseconds)
        if ($null -ne $capturedHolder.State -and
            $capturedHolder.State.Adapter.Context.MonotonicMilliseconds -ge 5500) {
            $path = Join-Path -Path $capturedHolder.State.RunDirectory -ChildPath 'status.json'
            $status = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
            $capturedHolder.HeartbeatAt = [datetimeoffset]$status.heartbeatAt
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $config = New-EngineConfig -Values @{
        preCastMinSeconds = 6; preCastMaxSeconds = 6
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $holder.State = $state

        Assert-Equal -Expected $true -Actual (Invoke-AIFishBotCast -State $state)

        Assert-True -Condition ($holder.LargestSleep -le 1000)
        Assert-True -Condition ($null -ne $holder.HeartbeatAt)
        Assert-True -Condition ($holder.HeartbeatAt -ge $state.StartedAt.AddSeconds(5))
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop arriving during a configurable wait prevents the pending key' {
    $signal = @{ Stop = $false; Elapsed = 0 }
    $capturedSignal = $signal
    $onSleep = {
        param($milliseconds)
        $capturedSignal.Elapsed += $milliseconds
        if ($capturedSignal.Elapsed -ge 2000) {
            $capturedSignal.Stop = $true
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $reader = {
        param($state)
        if ($capturedSignal.Stop) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }.GetNewClosure()
    $config = New-EngineConfig -Values @{
        preCastMinSeconds = 6; preCastMaxSeconds = 6
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader

        Assert-Equal -Expected $false -Actual (Invoke-AIFishBotCast -State $state)

        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-True -Condition ($adapter.Context.MonotonicMilliseconds -lt 6000)
        Assert-Equal -Expected 'stopped' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'wall clock rollback does not delay the waiting window' {
    $holder = @{ Adapter = $null; Rewound = $false }
    $capturedHolder = $holder
    $onSleep = {
        param($milliseconds)
        if (-not $capturedHolder.Rewound -and $null -ne $capturedHolder.Adapter -and
            $capturedHolder.Adapter.Context.MonotonicMilliseconds -ge 5000) {
            $capturedHolder.Adapter.Context.Now =
                $capturedHolder.Adapter.Context.Now.AddHours(-1)
            $capturedHolder.Rewound = $true
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $holder.Adapter = $adapter
    $reader = {
        param($state)
        if ($state.Adapter.Context.MonotonicMilliseconds -ge 25000) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $config = New-EngineConfig -Values @{ retail = $true }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected $true -Actual $holder.Rewound
        Assert-True -Condition ($adapter.Context.Now -lt $state.StartedAt)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'wall clock rollback does not delay auto stop' {
    $holder = @{ Adapter = $null; Rewound = $false }
    $capturedHolder = $holder
    $onSleep = {
        param($milliseconds)
        if (-not $capturedHolder.Rewound -and $null -ne $capturedHolder.Adapter -and
            $capturedHolder.Adapter.Context.MonotonicMilliseconds -ge 1000) {
            $capturedHolder.Adapter.Context.Now =
                $capturedHolder.Adapter.Context.Now.AddHours(-1)
            $capturedHolder.Rewound = $true
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $holder.Adapter = $adapter
    $reader = {
        param($state)
        if ($state.Adapter.Context.MonotonicMilliseconds -ge 8000) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $config = New-EngineConfig -Values @{ autoStop = $true; autoStopTime = 0.1 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected $true -Actual $holder.Rewound
        Assert-True -Condition ($adapter.Context.MonotonicMilliseconds -ge 6000)
        Assert-True -Condition ($adapter.Context.MonotonicMilliseconds -lt 7000)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'wall clock rollback does not delay heartbeat refresh' {
    $holder = @{ State = $null; Rewound = $false; ObservedHeartbeat = $null }
    $capturedHolder = $holder
    $onSleep = {
        param($milliseconds)
        if ($null -eq $capturedHolder.State) {
            return
        }
        if (-not $capturedHolder.Rewound -and
            $capturedHolder.State.Adapter.Context.MonotonicMilliseconds -ge 4500) {
            $capturedHolder.State.Adapter.Context.Now =
                $capturedHolder.State.Adapter.Context.Now.AddHours(-1)
            $capturedHolder.Rewound = $true
        }
        if ($null -eq $capturedHolder.ObservedHeartbeat -and
            $capturedHolder.State.Adapter.Context.MonotonicMilliseconds -ge 6500 -and
            $null -ne $capturedHolder.State.PSObject.Properties['LastHeartbeatMonotonicMilliseconds']) {
            $capturedHolder.ObservedHeartbeat =
                $capturedHolder.State.LastHeartbeatMonotonicMilliseconds
        }
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $reader = {
        param($state)
        if ($state.Adapter.Context.MonotonicMilliseconds -ge 7000) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter -ControlReader $reader
        $holder.State = $state
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected $true -Actual $holder.Rewound
        Assert-True -Condition ($null -ne $holder.ObservedHeartbeat)
        Assert-True -Condition ([double]$holder.ObservedHeartbeat -ge 6000)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'wall clock rollback does not delay a scheduled buff' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $adapter.Context.MonotonicMilliseconds =
            [double]$state.BuffSchedule[0].NextDueMonotonicMilliseconds
        $adapter.Context.Now = $state.StartedAt.AddHours(-1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-True -Condition ($adapter.Context.Now -lt $state.StartedAt)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'multiple buff rows keep separate keys and cast durations' {
    $adapter = New-SimulatedAdapter
    $buffs = @(
        [pscustomobject]@{
            enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
        },
        [pscustomobject]@{
            enabled = $true; keybind = 'F10'; castTimeSeconds = 2; durationMinutes = 2
        }
    )
    $config = New-EngineConfig -Values @{ buffs = $buffs }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected @('key:F9', 'sleep:1000', 'key:F10', 'sleep:1000', 'sleep:1000') `
            -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 2 -Actual @($state.BuffSchedule).Count
        Assert-True -Condition ($state.BuffSchedule[0].Identity -ne $state.BuffSchedule[1].Identity)
        foreach ($scheduledBuff in $state.BuffSchedule) {
            Assert-True -Condition ($null -ne $scheduledBuff.LastAppliedAt)
            Assert-True -Condition ($null -ne $scheduledBuff.NextDue)
        }
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop arriving during one buff is honored before the next row sends a key' {
    $signal = @{ Stop = $false }
    $capturedSignal = $signal
    $onSleep = {
        param($milliseconds)
        $capturedSignal.Stop = $true
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $reader = {
        param($state)
        if ($capturedSignal.Stop) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }.GetNewClosure()
    $buffs = @(
        [pscustomobject]@{
            name = 'first'; enabled = $true; keybind = 'F9'
            castTimeSeconds = 1; durationMinutes = 10
        },
        [pscustomobject]@{
            name = 'second'; enabled = $true; keybind = 'F10'
            castTimeSeconds = 2; durationMinutes = 10
        }
    )
    $config = New-EngineConfig -Values @{ buffs = $buffs }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Assert-Equal -Expected $false -Actual (Invoke-AIFishBotBuffCheck -State $state)

        Assert-Equal -Expected @('key:F9', 'sleep:1000') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected @('ready', 'casting', 'stopping', 'stopped') `
            -Actual @($state.StateHistory)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop arriving in the final wait slice prevents buff completion bookkeeping' {
    $signal = @{ Stop = $false }
    $capturedSignal = $signal
    $onSleep = {
        param($milliseconds)
        $capturedSignal.Stop = $true
    }.GetNewClosure()
    $adapter = New-SimulatedAdapter -OnSleep $onSleep
    $reader = {
        param($state)
        if ($capturedSignal.Stop) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }.GetNewClosure()
    $buffs = @(
        [pscustomobject]@{
            name = 'first'; enabled = $true; keybind = 'F9'
            castTimeSeconds = 1; durationMinutes = 10
        },
        [pscustomobject]@{
            name = 'second'; enabled = $true; keybind = 'F10'
            castTimeSeconds = 1; durationMinutes = 10
        }
    )
    $config = New-EngineConfig -Values @{ buffs = $buffs }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader

        Assert-Equal -Expected $false -Actual (Invoke-AIFishBotBuffCheck -State $state)

        Assert-Equal -Expected @('key:F9', 'sleep:1000') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected $null -Actual $state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        Assert-Equal -Expected 'stopped' -Actual $state.State
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'duplicate buff keys remain two independent scheduled rows' {
    $adapter = New-SimulatedAdapter
    $buffs = @(
        [pscustomobject]@{
            enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
        },
        [pscustomobject]@{
            enabled = $true; keybind = 'F9'; castTimeSeconds = 2; durationMinutes = 2
        }
    )
    $config = New-EngineConfig -Values @{ buffs = $buffs }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected @('key:F9', 'sleep:1000', 'key:F9', 'sleep:1000', 'sleep:1000') `
            -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 2 -Actual @($state.BuffSchedule).Count
        Assert-True -Condition ($state.BuffSchedule[0].Identity -ne $state.BuffSchedule[1].Identity)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'enabled buff casts initially and again exactly at monotonic expiration' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $expiration = [double]$state.BuffSchedule[0].NextDueMonotonicMilliseconds
        $adapter.Context.MonotonicMilliseconds = $expiration - 1
        $adapter.Context.Now = $state.BuffSchedule[0].NextDue.AddMilliseconds(-1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $adapter.Context.MonotonicMilliseconds = $expiration
        $adapter.Context.Now = $state.BuffSchedule[0].NextDue
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'sleep:1000')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'buff duration live update recomputes next due from last application' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $lastApplied = [double]$state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        $originalIdentity = $state.BuffSchedule[0].Identity
        $adapter.Context.MonotonicMilliseconds = $lastApplied + 120000
        $adapter.Context.Now = $adapter.Context.Now.AddMinutes(2)

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs[0].durationMinutes = 1
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected $originalIdentity -Actual $state.BuffSchedule[0].Identity
        Assert-True -Condition ($state.BuffSchedule[0].LastAppliedMonotonicMilliseconds `
                -ge ($lastApplied + 120000))
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'legacy buff name live update preserves its schedule without replay' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        name = 'old name'; enabled = $true; keybind = 'F9'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $originalIdentity = $state.BuffSchedule[0].Identity
        $originalLastApplied = $state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        $originalNextDue = $state.BuffSchedule[0].NextDueMonotonicMilliseconds

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs[0].name = 'new name'
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected $originalIdentity -Actual $state.BuffSchedule[0].Identity
        Assert-Equal -Expected $originalLastApplied `
            -Actual $state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        Assert-Equal -Expected $originalNextDue `
            -Actual $state.BuffSchedule[0].NextDueMonotonicMilliseconds
        Assert-Equal -Expected 'new name' -Actual $state.BuffSchedule[0].Name
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'legacy buff cast time live update preserves its schedule without replay' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        name = 'buff'; enabled = $true; keybind = 'F9'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $originalIdentity = $state.BuffSchedule[0].Identity
        $originalLastApplied = $state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        $originalNextDue = $state.BuffSchedule[0].NextDueMonotonicMilliseconds

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs[0].castTimeSeconds = 3
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'sleep:1000')
        Assert-Equal -Expected $originalIdentity -Actual $state.BuffSchedule[0].Identity
        Assert-Equal -Expected $originalLastApplied `
            -Actual $state.BuffSchedule[0].LastAppliedMonotonicMilliseconds
        Assert-Equal -Expected $originalNextDue `
            -Actual $state.BuffSchedule[0].NextDueMonotonicMilliseconds
        Assert-Equal -Expected 3 -Actual $state.BuffSchedule[0].CastTimeSeconds
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'deleted then re-added buff key is treated as a new row' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $firstIdentity = $state.BuffSchedule[0].Identity

        $removed = Copy-EngineConfig -Config $config
        $removed.buffs = @()
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $removed -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        Assert-Equal -Expected 0 -Actual @($state.BuffSchedule).Count

        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $config -ConfigVersion 2)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-True -Condition ($state.BuffSchedule[0].Identity -ne $firstIdentity)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'inserting a legacy buff at the front preserves unchanged row schedules' {
    $adapter = New-SimulatedAdapter
    $first = [pscustomobject]@{
        name = 'first'; enabled = $true; keybind = 'F9'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $second = [pscustomobject]@{
        name = 'second'; enabled = $true; keybind = 'F10'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($first, $second) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $oldByKey = @{}
        foreach ($scheduled in $state.BuffSchedule) {
            $oldByKey[$scheduled.Keybind] = $scheduled.Identity
        }

        $updated = Copy-EngineConfig -Config $config
        $inserted = [pscustomobject]@{
            name = 'inserted'; enabled = $true; keybind = 'F8'
            castTimeSeconds = 1; durationMinutes = 10
        }
        $updated.buffs = @($inserted) + @($updated.buffs)
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F8')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F10')
        Assert-Equal -Expected $oldByKey['F9'] -Actual $state.BuffSchedule[1].Identity
        Assert-Equal -Expected $oldByKey['F10'] -Actual $state.BuffSchedule[2].Identity
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'deleting a legacy buff preserves every remaining row schedule' {
    $adapter = New-SimulatedAdapter
    $buffs = @(
        [pscustomobject]@{
            name = 'remove'; enabled = $true; keybind = 'F8'
            castTimeSeconds = 1; durationMinutes = 10
        },
        [pscustomobject]@{
            name = 'keep-one'; enabled = $true; keybind = 'F9'
            castTimeSeconds = 1; durationMinutes = 10
        },
        [pscustomobject]@{
            name = 'keep-two'; enabled = $true; keybind = 'F10'
            castTimeSeconds = 1; durationMinutes = 10
        }
    )
    $config = New-EngineConfig -Values @{ buffs = $buffs }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $oldByKey = @{}
        foreach ($scheduled in $state.BuffSchedule) {
            $oldByKey[$scheduled.Keybind] = $scheduled.Identity
        }

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs = @($updated.buffs[1], $updated.buffs[2])
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F10')
        Assert-Equal -Expected $oldByKey['F9'] -Actual $state.BuffSchedule[0].Identity
        Assert-Equal -Expected $oldByKey['F10'] -Actual $state.BuffSchedule[1].Identity
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'identical legacy rows match old schedules one-to-one without sharing' {
    $adapter = New-SimulatedAdapter
    $duplicate = [pscustomobject]@{
        name = 'same'; enabled = $true; keybind = 'F9'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{
        buffs = @((Copy-EngineConfig -Config $duplicate), (Copy-EngineConfig -Config $duplicate))
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $oldIdentities = @($state.BuffSchedule | ForEach-Object { $_.Identity })

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs = @($updated.buffs) + @((Copy-EngineConfig -Config $duplicate))
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 3 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        $newIdentities = @($state.BuffSchedule | ForEach-Object { $_.Identity })
        Assert-Equal -Expected 3 -Actual @($newIdentities | Select-Object -Unique).Count
        foreach ($oldIdentity in $oldIdentities) {
            Assert-Equal -Expected 1 -Actual @(
                $newIdentities | Where-Object { $_ -eq $oldIdentity }
            ).Count
        }
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stable buff ids preserve schedules across reorder before legacy matching' {
    $adapter = New-SimulatedAdapter
    $first = [pscustomobject]@{
        id = 'buff-a'; name = 'same'; enabled = $true; keybind = 'F9'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $second = [pscustomobject]@{
        id = 'buff-b'; name = 'same'; enabled = $true; keybind = 'F10'
        castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($first, $second) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $oldByStableId = @{
            'buff-a' = $state.BuffSchedule[0].Identity
            'buff-b' = $state.BuffSchedule[1].Identity
        }

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs = @($updated.buffs[1], $updated.buffs[0])
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F10')
        Assert-Equal -Expected $oldByStableId['buff-b'] -Actual $state.BuffSchedule[0].Identity
        Assert-Equal -Expected $oldByStableId['buff-a'] -Actual $state.BuffSchedule[1].Identity
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'reordered legacy buff rows preserve their schedules without replay' {
    $adapter = New-SimulatedAdapter
    $first = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 10
    }
    $second = [pscustomobject]@{
        enabled = $true; keybind = 'F10'; castTimeSeconds = 1; durationMinutes = 10
    }
    $config = New-EngineConfig -Values @{ buffs = @($first, $second) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $identityByKey = @{}
        foreach ($scheduled in $state.BuffSchedule) {
            $identityByKey[$scheduled.Keybind] = $scheduled.Identity
        }

        $updated = Copy-EngineConfig -Config $config
        $updated.buffs = @($updated.buffs[1], $updated.buffs[0])
        Assert-Equal -Expected $true -Actual (Update-AIFishBotLiveConfig -State $state `
                -CandidateConfig $updated -ConfigVersion 1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F10')
        Assert-Equal -Expected $identityByKey['F10'] -Actual $state.BuffSchedule[0].Identity
        Assert-Equal -Expected $identityByKey['F9'] -Actual $state.BuffSchedule[1].Identity
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'buff live update waits for the next check and does not interrupt the current cast' {
    $adapter = New-SimulatedAdapter
    $firstBuff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
    }
    $secondBuff = [pscustomobject]@{
        enabled = $true; keybind = 'F10'; castTimeSeconds = 2; durationMinutes = 2
    }
    $config = New-EngineConfig -Values @{ buffs = @($firstBuff) }
    $updated = Copy-EngineConfig -Config $config
    $updated.buffs = @($secondBuff)
    $loader = New-VersionedLoader -Items @(
        $null,
        [pscustomobject]@{ ConfigVersion = 1; Config = $updated }
    )
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -LiveConfigLoader $loader
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        Assert-Equal -Expected @('key:F9', 'sleep:1000') -Actual @($adapter.Context.Events)

        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        Assert-Equal -Expected @('key:F9', 'sleep:1000', 'key:F10', 'sleep:1000', 'sleep:1000') `
            -Actual @($adapter.Context.Events)
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'latest auto-stop settings stop immediately and send the locked logout key' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ autoStop = $false; autoLogout = $false; logoutKey = 'F8' }
    $updated = Copy-EngineConfig -Config $config
    $updated.autoStop = $true
    $updated.autoStopTime = 0.5
    $updated.autoLogout = $true
    $updated.enableNotifications = $true
    $updated.notifyOnStop = $true
    $updated.discordWebhook = 'https://discord.com/api/webhooks/123/test-token'
    $loader = New-VersionedLoader -Items @(
        [pscustomobject]@{ ConfigVersion = 1; Config = $updated }
    )
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter `
            -LiveConfigLoader $loader
        $adapter.Context.MonotonicMilliseconds = 60000
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('notify:start', 'key:F8', 'notify:stop') `
            -Actual @($adapter.Context.Events)
        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'auto logout focuses before sending the locked key when focus succeeds' {
    $adapter = New-SimulatedAdapter
    $capturedContext = $adapter.Context
    $adapter.FocusWindow = ({
            [void]$capturedContext.Events.Add('focus')
            return $true
        }.GetNewClosure())
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        useWindowFocus = $true
        logoutKey = 'F8'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('focus', 'key:F8') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'auto logout accepts a legacy focus adapter with no return value' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        useWindowFocus = $true
        logoutKey = 'F8'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('focus', 'key:F8') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'auto logout skips the key when focus explicitly returns false' {
    $adapter = New-SimulatedAdapter
    $capturedContext = $adapter.Context
    $adapter.FocusWindow = ({
            [void]$capturedContext.Events.Add('focus')
            return $false
        }.GetNewClosure())
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        useWindowFocus = $true
        enableNotifications = $true
        notifyOnStart = $false
        notifyOnStop = $true
        discordWebhook = 'https://discord.com/api/webhooks/123/focus-false-test-token'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('focus', 'notify:stop') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F8')
        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*Logout key skipped*focus*false*')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'auto logout skips the key and stops cleanly when focus throws' {
    $adapter = New-SimulatedAdapter
    $capturedContext = $adapter.Context
    $adapter.FocusWindow = ({
            [void]$capturedContext.Events.Add('focus')
            throw 'simulated focus failure'
        }.GetNewClosure())
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        useWindowFocus = $true
        enableNotifications = $true
        notifyOnStart = $false
        notifyOnStop = $true
        discordWebhook = 'https://discord.com/api/webhooks/123/focus-throw-test-token'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('focus', 'notify:stop') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F8')
        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*Logout key skipped*simulated focus failure*')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'auto logout sends the key directly when window focus is disabled' {
    $adapter = New-SimulatedAdapter
    $adapter.FocusWindow = { throw 'focus should not be called' }
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        useWindowFocus = $false
        logoutKey = 'F8'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('key:F8') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'a running webhook update changes only the later stop notification address' {
    $adapter = New-SimulatedAdapter
    $oldWebhook = 'https://discord.com/api/webhooks/123/old-secret-token'
    $newWebhook = 'https://discord.com/api/webhooks/456/new-secret-token'
    $config = New-EngineConfig -Values @{
        autoStop = $false
        enableNotifications = $true
        notifyOnStart = $true
        notifyOnStop = $true
        discordWebhook = $oldWebhook
    }
    $updated = Copy-EngineConfig -Config $config
    $updated.autoStop = $true
    $updated.autoStopTime = 0.5
    $updated.discordWebhook = $newWebhook
    $loader = New-VersionedLoader -Items @(
        $null,
        [pscustomobject]@{ ConfigVersion = 1; Config = $updated }
    )
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -LiveConfigLoader $loader
        $adapter.Context.MonotonicMilliseconds = 60000

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('start', 'stop') -Actual @($adapter.Context.Notifications.EventName)
        Assert-Equal -Expected @($oldWebhook, $newWebhook) -Actual @($adapter.Context.Notifications.Webhook)
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'notify:start')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'notify:stop')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop control reloads a live config written while the command is read' {
    $adapter = New-SimulatedAdapter
    $oldWebhook = 'https://discord.com/api/webhooks/123/old-control-token'
    $newWebhook = 'https://discord.com/api/webhooks/456/new-control-token'
    $config = New-EngineConfig -Values @{
        enableNotifications = $true
        notifyOnStart = $true
        notifyOnStop = $true
        discordWebhook = $oldWebhook
    }
    $updated = Copy-EngineConfig -Config $config
    $updated.discordWebhook = $newWebhook
    $updated | Add-Member -NotePropertyName configVersion -NotePropertyValue 1
    $loader = {
        param($state)
        $path = Join-Path -Path $state.RunDirectory -ChildPath 'live-config.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $live = Read-AIFishBotJson -Path $path
        return [pscustomobject]@{ ConfigVersion = $live.configVersion; Config = $live }
    }
    $reader = {
        param($state)
        Write-AIFishBotAtomicJson -Path (Join-Path $state.RunDirectory 'live-config.json') `
            -InputObject $updated | Out-Null
        return [pscustomobject]@{ command = 'stop' }
    }.GetNewClosure()
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter `
            -LiveConfigLoader $loader -ControlReader $reader

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('start', 'stop') -Actual @($adapter.Context.Notifications.EventName)
        Assert-Equal -Expected @($oldWebhook, $newWebhook) -Actual @($adapter.Context.Notifications.Webhook)
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'notify:start')
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'notify:stop')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'failed stop-time live reload keeps the last config and masks its warning' {
    $adapter = New-SimulatedAdapter
    $webhook = 'https://discord.com/api/webhooks/123/kept-control-token'
    $config = New-EngineConfig -Values @{
        enableNotifications = $true
        notifyOnStart = $true
        notifyOnStop = $true
        discordWebhook = $webhook
    }
    $loadState = @{ Fail = $false }
    $capturedLoadState = $loadState
    $loader = {
        param($state)
        if ($capturedLoadState.Fail) {
            throw 'failed to read https://discord.com/api/webhooks/999/private-load-token'
        }
        return $null
    }.GetNewClosure()
    $reader = {
        param($state)
        $capturedLoadState.Fail = $true
        return [pscustomobject]@{ command = 'stop' }
    }.GetNewClosure()
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter `
            -LiveConfigLoader $loader -ControlReader $reader

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @($webhook, $webhook) -Actual @($adapter.Context.Notifications.Webhook)
        Assert-Equal -Expected 0 -Actual $state.ConfigVersion
        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*Live config load failed*')
        Assert-True -Condition (-not $logText.Contains('private-load-token'))
        Assert-True -Condition ($logText -like '*https://discord.com/api/webhooks/***')
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop remains final when its live refresh status write fails once' {
    $holder = @{ State = $null }
    $refresh = @{ StopRead = $false; CandidateReturned = $false; StatusFailed = $false }
    $capturedHolder = $holder
    $capturedRefresh = $refresh
    $adapter = New-SimulatedAdapter -ThrowOnReadPeak
    $adapterContext = $adapter.Context
    $adapter.Now = {
        if ($null -ne $capturedHolder.State -and
            $capturedHolder.State.ConfigVersion -eq 1 -and
            -not $capturedRefresh.StatusFailed) {
            $capturedRefresh.StatusFailed = $true
            throw 'status failed for https://discord.com/api/webhooks/999/private-status-token'
        }
        return $adapterContext.Now
    }.GetNewClosure()
    $webhook = 'https://discord.com/api/webhooks/123/usable-stop-token'
    $config = New-EngineConfig -Values @{
        useWeakAura = $false
        enableNotifications = $true
        notifyOnStart = $false
        notifyOnStop = $true
        discordWebhook = $webhook
    }
    $loader = {
        param($state)
        if (-not $capturedRefresh.StopRead -or $capturedRefresh.CandidateReturned) {
            return $null
        }
        $capturedRefresh.CandidateReturned = $true
        return [pscustomobject]@{
            ConfigVersion = 1
            Config = [pscustomobject]@{ audioSensitivity = 9 }
        }
    }.GetNewClosure()
    $reader = {
        param($state)
        if ($capturedRefresh.StopRead) { return $null }
        $capturedRefresh.StopRead = $true
        return [pscustomobject]@{ command = 'stop' }
    }.GetNewClosure()
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter `
            -LiveConfigLoader $loader -ControlReader $reader
        $holder.State = $state

        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected $true -Actual $refresh.StatusFailed
        Assert-Equal -Expected $true -Actual $state.StopRequested
        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected @('stop') -Actual @($adapter.Context.Notifications.EventName)
        Assert-Equal -Expected @($webhook) -Actual @($adapter.Context.Notifications.Webhook)
        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*Stop-time live config refresh failed*')
        Assert-True -Condition (-not $logText.Contains('private-status-token'))
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'stop control follows stopping then stopped without logout' {
    $adapter = New-SimulatedAdapter
    $reader = { param($state) return [pscustomobject]@{ command = 'stop' } }
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('ready', 'stopping', 'stopped') -Actual @($state.StateHistory)
        Assert-Equal -Expected 0 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F8')
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'notification failures are logged and never prevent a clean stop or disposal' {
    $adapter = New-SimulatedAdapter -ThrowOnNotify
    $config = New-EngineConfig -Values @{
        autoStop = $true
        autoStopTime = 0.5
        autoLogout = $true
        enableNotifications = $true
        notifyOnStart = $true
        notifyOnStop = $true
        discordWebhook = 'https://discord.com/api/webhooks/123/secret-token'
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        $adapter.Context.MonotonicMilliseconds = 60000
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected @('notify:start', 'key:F8', 'notify:stop') -Actual @($adapter.Context.Events)
        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        $logPath = Join-Path -Path $state.RunDirectory -ChildPath 'logs\2026-07-13.log'
        $logText = [System.IO.File]::ReadAllText($logPath)
        Assert-True -Condition ($logText -like '*Notification*failed*')
        Assert-True -Condition (-not $logText.Contains('secret-token'))
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'unexpected audio failure ends in error and disposes the adapter exactly once' {
    $adapter = New-SimulatedAdapter -ThrowOnReadPeak
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 'error' -Actual $state.State
        Assert-True -Condition ($state.LastError -like '*simulated peak failure*')
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}

Test-Case 'engine source cannot contain real input audio network serial or sleep calls' {
    $source = [System.IO.File]::ReadAllText($script:EngineModulePath)
    Assert-Equal -Expected $false -Actual ([bool]($source -match `
            'SendKeys|System\.Windows\.Forms|WScript\.Shell|SerialPort|Start-Sleep|SoundPlayer|Invoke-RestMethod'))
}

Test-Case 'every recorded engine state uses the runtime status vocabulary' {
    $adapter = New-SimulatedAdapter
    $reader = { param($state) return [pscustomobject]@{ command = 'stop' } }
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null
        $allowed = @('ready', 'casting', 'waiting-for-bite', 'hooking', 'stopping', 'stopped', 'error')
        foreach ($value in $state.StateHistory) {
            Assert-True -Condition ($allowed -contains $value)
        }

        $status = Read-AIFishBotStatus -RunDirectory $state.RunDirectory
        Assert-Equal -Expected 'stopped' -Actual $status.state
        Assert-Equal -Expected $state.ConfigVersion -Actual $status.configVersion
        Assert-Equal -Expected $state.HookCount -Actual $status.hookCount
    }
    finally {
        Remove-EngineTestState -State $state
    }
}
