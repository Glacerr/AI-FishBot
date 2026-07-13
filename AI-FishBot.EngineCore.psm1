$script:AIFishBotEngineModuleRoot = $PSScriptRoot
Import-Module -Name (Join-Path -Path $script:AIFishBotEngineModuleRoot -ChildPath 'AI-FishBot.Config.psm1') `
    -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:AIFishBotEngineModuleRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
    -ErrorAction Stop

$script:AIFishBotLiveConfigFields = @(
    'audioSensitivity',
    'autoStop',
    'autoStopTime',
    'autoLogout',
    'biteResponseMinSeconds',
    'biteResponseMaxSeconds',
    'preHookMinSeconds',
    'preHookMaxSeconds',
    'postHookMinSeconds',
    'postHookMaxSeconds',
    'preCastMinSeconds',
    'preCastMaxSeconds',
    'buffs',
    'enableNotifications',
    'discordWebhook',
    'notifyOnStop'
)

function Copy-AIFishBotEngineValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }
    return $Value | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json
}

function Get-AIFishBotEngineProperty {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ref]$Found
    )

    $Found.Value = $false
    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            $Found.Value = $true
            return $InputObject[$Name]
        }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $Found.Value = $true
        return $property.Value
    }
    return $null
}

function Invoke-AIFishBotAdapterMember {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Adapter,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object[]]$ArgumentList = @()
    )

    $property = $Adapter.PSObject.Properties[$Name]
    if ($null -ne $property) {
        if ($property.Value -is [scriptblock]) {
            return & $property.Value @ArgumentList
        }
        if ($property.Value -is [System.Delegate]) {
            return $property.Value.DynamicInvoke($ArgumentList)
        }
        if ($Name -eq 'Now' -and $ArgumentList.Count -eq 0) {
            return $property.Value
        }
    }
    $method = $Adapter.PSObject.Methods[$Name]
    if ($null -ne $method) {
        return $method.Invoke($ArgumentList)
    }
    throw ('The engine adapter does not provide {0}.' -f $Name)
}

function Get-AIFishBotEngineNow {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $values = @(Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'Now')
    if ($values.Count -ne 1 -or $null -eq $values[0]) {
        throw 'The engine adapter Now member must return exactly one timestamp.'
    }
    try {
        return [datetimeoffset]$values[0]
    }
    catch {
        throw ('The engine adapter returned an invalid timestamp: {0}' -f $_.Exception.Message)
    }
}

function Invoke-AIFishBotEngineSleep {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [int]$Milliseconds
    )

    Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'SleepMilliseconds' `
        -ArgumentList @($Milliseconds) | Out-Null
}

function Invoke-AIFishBotEngineFocus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'FocusWindow' | Out-Null
}

function Invoke-AIFishBotEngineKey {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'SendKey' -ArgumentList @($Key) | Out-Null
}

function Get-AIFishBotEnginePeak {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $values = @(Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'ReadPeak')
    if ($values.Count -ne 1 -or $null -eq $values[0]) {
        throw 'The engine adapter ReadPeak member must return exactly one number.'
    }
    try {
        $peak = [convert]::ToDouble($values[0], [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw ('The engine adapter returned an invalid audio peak: {0}' -f $_.Exception.Message)
    }
    if ([double]::IsNaN($peak) -or [double]::IsInfinity($peak)) {
        throw 'The engine adapter returned an invalid audio peak.'
    }
    return $peak
}

function Get-AIFishBotEngineDelay {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object]$MinimumSeconds,

        [Parameter(Mandatory = $true)]
        [object]$MaximumSeconds
    )

    if ($null -ne $State.RandomIntProvider) {
        return Get-AIFishBotDelayMilliseconds -MinimumSeconds $MinimumSeconds `
            -MaximumSeconds $MaximumSeconds -RandomIntProvider $State.RandomIntProvider
    }
    return Get-AIFishBotDelayMilliseconds -MinimumSeconds $MinimumSeconds `
        -MaximumSeconds $MaximumSeconds
}

function Write-AIFishBotEngineLog {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        Write-AIFishBotLog -RunDirectory $State.RunDirectory -Level $Level -Message $Message `
            -Now (Get-AIFishBotEngineNow -State $State) | Out-Null
    }
    catch {
    }
}

function Get-AIFishBotEngineRemainingSeconds {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [datetimeoffset]$Now
    )

    if (-not [bool]$State.LiveConfig.autoStop) {
        return $null
    }
    $deadline = $State.StartedAt.AddMinutes([double]$State.LiveConfig.autoStopTime)
    return [double][math]::Max(0, ($deadline - $Now).TotalSeconds)
}

function Write-AIFishBotEngineStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $now = Get-AIFishBotEngineNow -State $State
    $status = [pscustomobject][ordered]@{
        processId = [int]$PID
        state = [string]$State.State
        hookCount = [int]$State.HookCount
        retryCount = [int]$State.RetryCount
        profileName = [string]$State.LockedConfig.profileName
        startedAt = $State.StartedAt
        remainingSeconds = Get-AIFishBotEngineRemainingSeconds -State $State -Now $now
        lastError = $State.LastError
        heartbeatAt = $now
        configVersion = [int]$State.ConfigVersion
    }
    Write-AIFishBotStatus -RunDirectory $State.RunDirectory -Status $status | Out-Null
    if ($null -ne $State.PSObject.Properties['LastHeartbeatAt']) {
        $State.LastHeartbeatAt = $now
    }
}

function Set-AIFishBotEngineStateValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ready', 'casting', 'waiting-for-bite', 'hooking', 'stopping', 'stopped', 'error')]
        [string]$Value,

        [AllowNull()]
        [string]$LastError
    )

    $changed = $State.State -ne $Value
    $State.State = $Value
    if ($PSBoundParameters.ContainsKey('LastError')) {
        $State.LastError = $LastError
    }
    if ($changed) {
        [void]$State.StateHistory.Add($Value)
    }
    Write-AIFishBotEngineStatus -State $State
}

function Test-AIFishBotEngineConfig {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $availablePorts = @()
    if ($Config.usePi -is [bool] -and $Config.usePi -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.picoComPort)) {
        $availablePorts = @([string]$Config.picoComPort)
    }
    return Test-AIFishBotConfig -Config $Config -AvailablePorts $availablePorts
}

function New-AIFishBotEngineState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [string]$RunDirectory,

        [Parameter(Mandatory = $true)]
        [object]$Adapter,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ConfigVersion = 0,

        [scriptblock]$RandomIntProvider,

        [scriptblock]$LiveConfigLoader,

        [scriptblock]$ControlReader,

        [datetimeoffset]$StartedAt
    )

    $fullRunDirectory = [System.IO.Path]::GetFullPath($RunDirectory)
    if (-not [System.IO.Directory]::Exists($fullRunDirectory)) {
        throw 'The engine run directory does not exist.'
    }
    $validation = Test-AIFishBotEngineConfig -Config $Config
    if (-not $validation.IsValid) {
        throw ('The startup engine config is invalid: {0}' -f
            (@($validation.Errors.Keys | Sort-Object) -join ', '))
    }
    $lockedConfig = Copy-AIFishBotEngineValue -Value $Config
    $effectiveStartedAt = $StartedAt
    if (-not $PSBoundParameters.ContainsKey('StartedAt')) {
        $temporaryState = [pscustomobject]@{ Adapter = $Adapter }
        $effectiveStartedAt = Get-AIFishBotEngineNow -State $temporaryState
    }
    if (-not $PSBoundParameters.ContainsKey('LiveConfigLoader')) {
        $LiveConfigLoader = { param($state) return $null }
    }
    if (-not $PSBoundParameters.ContainsKey('ControlReader')) {
        $ControlReader = {
            param($state)
            return Read-AIFishBotControlCommand -RunDirectory $state.RunDirectory -Consume
        }
    }
    $history = New-Object 'System.Collections.Generic.List[string]'
    [void]$history.Add('ready')
    $state = [pscustomobject][ordered]@{
        LockedConfig = $lockedConfig
        LiveConfig = Copy-AIFishBotEngineValue -Value $lockedConfig
        ConfigVersion = [int]$ConfigVersion
        HookCount = 0
        RetryCount = 0
        StartedAt = [datetimeoffset]$effectiveStartedAt
        State = 'ready'
        RunDirectory = $fullRunDirectory
        Adapter = $Adapter
        BuffExpirations = @{}
        StopRequested = $false
        LastError = $null
        LastHeartbeatAt = $null
        RandomIntProvider = $RandomIntProvider
        LiveConfigLoader = $LiveConfigLoader
        ControlReader = $ControlReader
        StateHistory = $history
        Disposed = $false
        StartNotificationSent = $false
        StopNotificationSent = $false
    }
    Write-AIFishBotEngineStatus -State $state
    return $state
}

function Update-AIFishBotLiveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [AllowNull()]
        [object]$CandidateConfig,

        [AllowNull()]
        [object]$ConfigVersion
    )

    $candidateWasProvided = $PSBoundParameters.ContainsKey('CandidateConfig')
    $versionWasProvided = $PSBoundParameters.ContainsKey('ConfigVersion')
    if (-not $candidateWasProvided) {
        try {
            $loaderResults = @(& $State.LiveConfigLoader $State)
        }
        catch {
            Write-AIFishBotEngineLog -State $State -Level Warning `
                -Message ('Live config load failed: {0}' -f $_.Exception.Message)
            return $false
        }
        if ($loaderResults.Count -eq 0 -or $null -eq $loaderResults[0]) {
            return $false
        }
        if ($loaderResults.Count -ne 1) {
            Write-AIFishBotEngineLog -State $State -Level Warning `
                -Message 'Live config load failed: loader returned more than one value.'
            return $false
        }
        $loaded = $loaderResults[0]
        $configFound = $false
        $loadedConfig = Get-AIFishBotEngineProperty -InputObject $loaded -Name 'Config' -Found ([ref]$configFound)
        if ($configFound) {
            $CandidateConfig = $loadedConfig
        }
        else {
            $CandidateConfig = $loaded
        }
        $versionFound = $false
        $loadedVersion = Get-AIFishBotEngineProperty -InputObject $loaded -Name 'ConfigVersion' `
            -Found ([ref]$versionFound)
        if ($versionFound) {
            $ConfigVersion = $loadedVersion
            $versionWasProvided = $true
        }
    }
    if ($null -eq $CandidateConfig) {
        return $false
    }
    if (-not $versionWasProvided) {
        $versionFound = $false
        $ConfigVersion = Get-AIFishBotEngineProperty -InputObject $CandidateConfig `
            -Name 'ConfigVersion' -Found ([ref]$versionFound)
        if (-not $versionFound) {
            Write-AIFishBotEngineLog -State $State -Level Warning `
                -Message 'Live config rejected: config version is missing.'
            return $false
        }
    }
    try {
        $versionDecimal = [convert]::ToDecimal(
            $ConfigVersion,
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message 'Live config rejected: config version is invalid.'
        return $false
    }
    if ([decimal]::Truncate($versionDecimal) -ne $versionDecimal -or
        $versionDecimal -lt 0 -or $versionDecimal -gt [int]::MaxValue) {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message 'Live config rejected: config version is invalid.'
        return $false
    }
    $newVersion = [int]$versionDecimal
    if ($newVersion -le [int]$State.ConfigVersion) {
        return $false
    }

    $merged = Copy-AIFishBotEngineValue -Value $State.LiveConfig
    foreach ($field in $script:AIFishBotLiveConfigFields) {
        $found = $false
        $value = Get-AIFishBotEngineProperty -InputObject $CandidateConfig -Name $field -Found ([ref]$found)
        if ($found) {
            $merged.$field = Copy-AIFishBotEngineValue -Value $value
        }
    }
    $validation = Test-AIFishBotEngineConfig -Config $merged
    if (-not $validation.IsValid) {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message ('Live config rejected: {0}' -f
                (@($validation.Errors.Keys | Sort-Object) -join ', '))
        return $false
    }
    $State.LiveConfig = $merged
    $State.ConfigVersion = $newVersion
    Write-AIFishBotEngineStatus -State $State
    return $true
}

function Send-AIFishBotEngineNotification {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [ValidateSet('start', 'stop')]
        [string]$EventName
    )

    $flagName = if ($EventName -eq 'start') { 'StartNotificationSent' } else { 'StopNotificationSent' }
    if ($State.$flagName) {
        return
    }
    $State.$flagName = $true
    $enabledForEvent = if ($EventName -eq 'start') {
        [bool]$State.LockedConfig.notifyOnStart
    }
    else {
        [bool]$State.LiveConfig.notifyOnStop
    }
    if (-not [bool]$State.LiveConfig.enableNotifications -or -not $enabledForEvent) {
        return
    }
    try {
        Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'Notify' `
            -ArgumentList @($EventName, [string]$State.LiveConfig.discordWebhook) | Out-Null
    }
    catch {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message ('Notification {0} failed: {1}' -f $EventName, $_.Exception.Message)
    }
}

function Invoke-AIFishBotStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [switch]$Logout,

        [string]$Reason = 'stop requested'
    )

    if ($State.State -eq 'stopped') {
        return $State
    }
    $State.StopRequested = $true
    if ($State.State -ne 'error') {
        Set-AIFishBotEngineStateValue -State $State -Value 'stopping'
    }
    if ($Logout) {
        try {
            Invoke-AIFishBotEngineKey -State $State -Key ([string]$State.LockedConfig.logoutKey)
        }
        catch {
            Write-AIFishBotEngineLog -State $State -Level Warning `
                -Message ('Logout key failed: {0}' -f $_.Exception.Message)
        }
    }
    Send-AIFishBotEngineNotification -State $State -EventName stop
    if ($State.State -ne 'error') {
        Set-AIFishBotEngineStateValue -State $State -Value 'stopped'
    }
    return $State
}

function Test-AIFishBotEngineCheckpoint {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($State.StopRequested) {
        return $false
    }
    $checkpointNow = Get-AIFishBotEngineNow -State $State
    if ($null -eq $State.LastHeartbeatAt -or
        ($checkpointNow - [datetimeoffset]$State.LastHeartbeatAt).TotalSeconds -ge 1) {
        Write-AIFishBotEngineStatus -State $State
    }
    [void](Update-AIFishBotLiveConfig -State $State)
    if ($State.StopRequested) {
        return $false
    }
    try {
        $controlValues = @(& $State.ControlReader $State)
        if ($controlValues.Count -gt 0 -and $null -ne $controlValues[0]) {
            $commandFound = $false
            $command = Get-AIFishBotEngineProperty -InputObject $controlValues[0] -Name 'command' `
                -Found ([ref]$commandFound)
            if ($commandFound -and [string]$command -ieq 'stop') {
                Invoke-AIFishBotStop -State $State -Reason 'control command' | Out-Null
                return $false
            }
        }
    }
    catch {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message ('Control read failed: {0}' -f $_.Exception.Message)
    }
    if ([bool]$State.LiveConfig.autoStop) {
        $deadline = $State.StartedAt.AddMinutes([double]$State.LiveConfig.autoStopTime)
        if ((Get-AIFishBotEngineNow -State $State) -ge $deadline) {
            Invoke-AIFishBotStop -State $State -Logout:([bool]$State.LiveConfig.autoLogout) `
                -Reason 'auto stop' | Out-Null
            return $false
        }
    }
    return $true
}

function Invoke-AIFishBotCastAttempt {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    Set-AIFishBotEngineStateValue -State $State -Value 'casting'
    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    $delay = Get-AIFishBotEngineDelay -State $State `
        -MinimumSeconds $State.LiveConfig.preCastMinSeconds `
        -MaximumSeconds $State.LiveConfig.preCastMaxSeconds
    Invoke-AIFishBotEngineSleep -State $State -Milliseconds $delay

    if ([bool]$State.LockedConfig.useWindowFocus) {
        if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
            return $false
        }
        Invoke-AIFishBotEngineFocus -State $State
    }
    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    Invoke-AIFishBotEngineKey -State $State -Key ([string]$State.LockedConfig.castKey)
    return $true
}

function Stop-AIFishBotCastAtAttemptLimit {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $message = 'WeakAura cast retry limit reached.'
    $State.StopRequested = $true
    Set-AIFishBotEngineStateValue -State $State -Value 'error' -LastError $message
    Write-AIFishBotEngineLog -State $State -Level Error -Message $message
    throw $message
}

function Invoke-AIFishBotCast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    $maximumAttempts = [int]$State.LockedConfig.fishingRetries
    if ([bool]$State.LockedConfig.useWeakAura -and $maximumAttempts -eq 0) {
        Stop-AIFishBotCastAtAttemptLimit -State $State
    }
    $attempts = 0
    while (-not $State.StopRequested) {
        if (-not (Invoke-AIFishBotCastAttempt -State $State)) {
            return $false
        }
        $attempts += 1
        if (-not [bool]$State.LockedConfig.useWeakAura) {
            return $true
        }
        if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
            return $false
        }
        $retryDelay = Get-AIFishBotEngineDelay -State $State -MinimumSeconds 1.0 -MaximumSeconds 1.5
        Invoke-AIFishBotEngineSleep -State $State -Milliseconds $retryDelay
        if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
            return $false
        }
        $peak = Get-AIFishBotEnginePeak -State $State
        if ($peak -ge [double]$State.LiveConfig.audioSensitivity) {
            return $true
        }
        if ($attempts -ge $maximumAttempts) {
            Stop-AIFishBotCastAtAttemptLimit -State $State
        }
        $State.RetryCount += 1
        Write-AIFishBotEngineStatus -State $State
    }
    return $false
}

function Invoke-AIFishBotBiteSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    Set-AIFishBotEngineStateValue -State $State -Value 'hooking'
    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    $delay = Get-AIFishBotEngineDelay -State $State `
        -MinimumSeconds $State.LiveConfig.biteResponseMinSeconds `
        -MaximumSeconds $State.LiveConfig.biteResponseMaxSeconds
    Invoke-AIFishBotEngineSleep -State $State -Milliseconds $delay

    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    $delay = Get-AIFishBotEngineDelay -State $State `
        -MinimumSeconds $State.LiveConfig.preHookMinSeconds `
        -MaximumSeconds $State.LiveConfig.preHookMaxSeconds
    Invoke-AIFishBotEngineSleep -State $State -Milliseconds $delay

    if ([bool]$State.LockedConfig.useWindowFocus) {
        if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
            return $false
        }
        Invoke-AIFishBotEngineFocus -State $State
    }
    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    Invoke-AIFishBotEngineKey -State $State -Key ([string]$State.LockedConfig.bobberKey)
    $State.HookCount += 1
    Write-AIFishBotEngineStatus -State $State

    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    $delay = Get-AIFishBotEngineDelay -State $State `
        -MinimumSeconds $State.LiveConfig.postHookMinSeconds `
        -MaximumSeconds $State.LiveConfig.postHookMaxSeconds
    Invoke-AIFishBotEngineSleep -State $State -Milliseconds $delay
    return Invoke-AIFishBotCast -State $State
}

function Invoke-AIFishBotBuffCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
        return $false
    }
    $buffSnapshot = @(Copy-AIFishBotEngineValue -Value @($State.LiveConfig.buffs))
    $castAny = $false
    foreach ($buff in $buffSnapshot) {
        if ($null -eq $buff -or -not [bool]$buff.enabled -or
            [string]::IsNullOrWhiteSpace([string]$buff.keybind)) {
            continue
        }
        $key = [string]$buff.keybind
        $now = Get-AIFishBotEngineNow -State $State
        if ($State.BuffExpirations.ContainsKey($key) -and
            $now -lt [datetimeoffset]$State.BuffExpirations[$key]) {
            continue
        }
        Set-AIFishBotEngineStateValue -State $State -Value 'casting'
        if ([bool]$State.LockedConfig.useWindowFocus) {
            Invoke-AIFishBotEngineFocus -State $State
        }
        Invoke-AIFishBotEngineKey -State $State -Key $key
        $castMilliseconds = Get-AIFishBotEngineDelay -State $State `
            -MinimumSeconds $buff.castTimeSeconds -MaximumSeconds $buff.castTimeSeconds
        Invoke-AIFishBotEngineSleep -State $State -Milliseconds $castMilliseconds
        $State.BuffExpirations[$key] = (Get-AIFishBotEngineNow -State $State).AddMinutes(
            [double]$buff.durationMinutes)
        $castAny = $true
    }
    if ($castAny -and -not $State.StopRequested) {
        Set-AIFishBotEngineStateValue -State $State -Value 'ready'
    }
    return $true
}

function Close-AIFishBotEngineAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($State.Disposed) {
        return
    }
    $State.Disposed = $true
    try {
        Invoke-AIFishBotAdapterMember -Adapter $State.Adapter -Name 'Dispose' | Out-Null
    }
    catch {
        Write-AIFishBotEngineLog -State $State -Level Warning `
            -Message ('Adapter dispose failed: {0}' -f $_.Exception.Message)
    }
}

function Start-AIFishBotEngineLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    try {
        [void](Update-AIFishBotLiveConfig -State $State)
        Send-AIFishBotEngineNotification -State $State -EventName start
        :engineLoop while (-not $State.StopRequested) {
            if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
                break
            }
            if (-not (Invoke-AIFishBotBuffCheck -State $State)) {
                break
            }
            if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
                break
            }
            if (-not (Invoke-AIFishBotCast -State $State)) {
                break
            }

            $windowStart = Get-AIFishBotEngineNow -State $State
            if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
                break
            }
            Invoke-AIFishBotEngineSleep -State $State -Milliseconds 4000
            Set-AIFishBotEngineStateValue -State $State -Value 'waiting-for-bite'
            $windowSeconds = if ([bool]$State.LockedConfig.retail) { 22 } else { 30 }
            $deadline = $windowStart.AddSeconds($windowSeconds)
            $biteDetected = $false

            while ((Get-AIFishBotEngineNow -State $State) -lt $deadline) {
                if (-not (Test-AIFishBotEngineCheckpoint -State $State)) {
                    break engineLoop
                }
                $peak = Get-AIFishBotEnginePeak -State $State
                if ($peak -ge [double]$State.LiveConfig.audioSensitivity) {
                    $biteDetected = $true
                    if (-not (Invoke-AIFishBotBiteSequence -State $State)) {
                        break engineLoop
                    }
                    break
                }
                $remainingMilliseconds = [int][math]::Ceiling(
                    ($deadline - (Get-AIFishBotEngineNow -State $State)).TotalMilliseconds)
                if ($remainingMilliseconds -gt 0) {
                    Invoke-AIFishBotEngineSleep -State $State `
                        -Milliseconds ([math]::Min(100, $remainingMilliseconds))
                }
            }
            if ($State.StopRequested) {
                break
            }
            if ($biteDetected) {
                continue
            }
        }
    }
    catch {
        if ($State.State -ne 'error') {
            $State.StopRequested = $true
            Set-AIFishBotEngineStateValue -State $State -Value 'error' -LastError $_.Exception.Message
            Write-AIFishBotEngineLog -State $State -Level Error `
                -Message ('Engine failed: {0}' -f $_.Exception.Message)
        }
    }
    finally {
        try {
            Send-AIFishBotEngineNotification -State $State -EventName stop
        }
        finally {
            Close-AIFishBotEngineAdapter -State $State
        }
    }
    return $State
}

Export-ModuleMember -Function @(
    'New-AIFishBotEngineState',
    'Update-AIFishBotLiveConfig',
    'Invoke-AIFishBotCast',
    'Invoke-AIFishBotBiteSequence',
    'Invoke-AIFishBotBuffCheck',
    'Invoke-AIFishBotStop',
    'Start-AIFishBotEngineLoop'
)
