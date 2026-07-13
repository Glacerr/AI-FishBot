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
        Peaks = $queue
        Events = New-Object 'System.Collections.Generic.List[string]'
        DisposeCount = 0
        ThrowOnNotify = [bool]$ThrowOnNotify
        ThrowOnReadPeak = [bool]$ThrowOnReadPeak
        OnSleep = $OnSleep
    }
    $captured = $context
    return [pscustomobject]@{
        Context = $context
        Now = ({ return $captured.Now }.GetNewClosure())
        SleepMilliseconds = ({
                param($milliseconds)
                [void]$captured.Events.Add(('sleep:{0}' -f [int]$milliseconds))
                $captured.Now = $captured.Now.AddMilliseconds([double]$milliseconds)
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
                if ($captured.ThrowOnNotify) {
                    throw 'simulated notification failure'
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
        [datetimeoffset]$StartedAt
    )

    $runDirectory = New-TestDirectory
    $parameters = @{
        Config = $Config
        RunDirectory = $runDirectory
        Adapter = $Adapter
        RandomIntProvider = $RandomIntProvider
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

Test-Case 'bite sequence uses the exact simulated four-delay action order' {
    $adapter = New-SimulatedAdapter
    $state = $null
    try {
        $state = New-EngineTestState -Adapter $adapter
        Invoke-AIFishBotBiteSequence -State $state | Out-Null

        Assert-Equal -Expected @(
            'sleep:300', 'sleep:500', 'key:F7', 'sleep:1100', 'sleep:200', 'key:F6'
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
            'sleep:1100', 'sleep:200', 'focus', 'key:F6'
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
        Assert-Equal -Expected @('sleep:700', 'sleep:500', 'key:F7', 'sleep:1500', 'sleep:600', 'key:F6') `
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

        Assert-Equal -Expected @('sleep:400', 'sleep:600', 'key:F7', 'sleep:1200', 'sleep:250', 'key:F6') `
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
    $adapter = New-SimulatedAdapter -Peaks @(0, 0, 0)
    $config = New-EngineConfig -Values @{ useWeakAura = $true; fishingRetries = 2 }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Assert-Throws -ScriptBlock { Invoke-AIFishBotCast -State $state } -MessageLike '*retry limit*'

        Assert-Equal -Expected 3 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected 3 -Actual (Get-EventCount -Adapter $adapter -Event 'sleep:1000')
        Assert-Equal -Expected 2 -Actual $state.RetryCount
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

Test-Case 'no bite completes the classic window and starts the next round before stop' {
    $adapter = New-SimulatedAdapter
    $config = New-EngineConfig -Values @{ retail = $false; audioSensitivity = 3 }
    $reader = {
        param($state)
        if ($state.Adapter.Context.Now -ge $state.StartedAt.AddSeconds(30)) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 0 -Actual $state.HookCount
        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
        Assert-Equal -Expected 'stopped' -Actual $state.State
        Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
        Assert-True -Condition ($adapter.Context.Now -ge $state.StartedAt.AddSeconds(30))
        $silentIndex = $adapter.Context.Events.IndexOf('sleep:4000')
        $firstPeakIndex = $adapter.Context.Events.IndexOf('peak')
        Assert-True -Condition ($silentIndex -ge 0 -and $firstPeakIndex -gt $silentIndex)
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
        if ($state.Adapter.Context.Now -ge $state.StartedAt.AddSeconds(22.2)) {
            return [pscustomobject]@{ command = 'stop' }
        }
        return $null
    }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -ControlReader $reader
        Start-AIFishBotEngineLoop -State $state | Out-Null

        Assert-Equal -Expected 1 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F6')
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
        $casts = @($state.Adapter.Context.Events | Where-Object { $_ -eq 'key:F6' }).Count
        if ($state.HookCount -ge 1 -and $casts -ge 2) {
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

Test-Case 'enabled buff casts initially and again exactly at expiration' {
    $adapter = New-SimulatedAdapter
    $buff = [pscustomobject]@{
        enabled = $true; keybind = 'F9'; castTimeSeconds = 1; durationMinutes = 1
    }
    $config = New-EngineConfig -Values @{ buffs = @($buff) }
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $expiration = $state.BuffExpirations['F9']
        $adapter.Context.Now = $expiration.AddMilliseconds(-1)
        Invoke-AIFishBotBuffCheck -State $state | Out-Null
        $adapter.Context.Now = $expiration
        Invoke-AIFishBotBuffCheck -State $state | Out-Null

        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'key:F9')
        Assert-Equal -Expected 2 -Actual (Get-EventCount -Adapter $adapter -Event 'sleep:1000')
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
        Assert-Equal -Expected @('key:F9', 'sleep:1000', 'key:F10', 'sleep:2000') `
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
    $startedAt = $adapter.Context.Now.AddMinutes(-1)
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter `
            -LiveConfigLoader $loader -StartedAt $startedAt
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
    $startedAt = $adapter.Context.Now.AddMinutes(-1)
    $state = $null
    try {
        $state = New-EngineTestState -Config $config -Adapter $adapter -StartedAt $startedAt
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
