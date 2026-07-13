[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory,

    [switch]$Simulation
)

$ErrorActionPreference = 'Stop'
$engineRoot = $PSScriptRoot
$startedAt = [datetimeoffset]::Now
$state = $null
$adapter = $null
$coreOwnsAdapter = $false
$exitCode = 1
$startupConfig = $null
$startupVersion = 0
$fullRunDirectory = $null

function Protect-AIFishBotEngineEntryMessage {
    param([AllowNull()][string]$Message)

    if ($null -eq $Message) {
        return $null
    }
    if ($null -ne (Get-Command -Name Protect-AIFishBotSecret -ErrorAction SilentlyContinue)) {
        return Protect-AIFishBotSecret -Text $Message
    }
    $pattern = '(?<prefix>https:(?:\\/|/){2}(?:(?:canary|ptb)\.)?discord(?:app)?\.com(?::[0-9]{1,5})?' +
        '(?:\\/|/)api(?:(?:\\/|/)v[0-9]+)?(?:\\/|/)webhooks(?:\\/|/))' +
        '[A-Za-z0-9_-]+(?:\\/|/)[A-Za-z0-9._-]+(?:\?[^\s<>"'']*)?'
    return [regex]::Replace(
        $Message,
        $pattern,
        '${prefix}***',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Invoke-AIFishBotEngineEntryDispose {
    param([AllowNull()][object]$TargetAdapter)

    if ($null -eq $TargetAdapter) {
        return
    }
    $property = $TargetAdapter.PSObject.Properties['Dispose']
    if ($null -ne $property -and $property.Value -is [scriptblock]) {
        & $property.Value | Out-Null
        return
    }
    $method = $TargetAdapter.PSObject.Methods['Dispose']
    if ($null -ne $method) {
        $method.Invoke(@()) | Out-Null
    }
}

function Write-AIFishBotEngineEntryError {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()][object]$Config,
        [int]$ConfigVersion = 0
    )

    if ([string]::IsNullOrWhiteSpace($fullRunDirectory) -or
        -not [System.IO.Directory]::Exists($fullRunDirectory)) {
        return
    }
    $safeMessage = Protect-AIFishBotEngineEntryMessage -Message $Message
    $profileName = 'Unknown Profile'
    if ($null -ne $Config) {
        $profileProperty = $Config.PSObject.Properties['profileName']
        if ($null -ne $profileProperty -and
            -not [string]::IsNullOrWhiteSpace([string]$profileProperty.Value)) {
            $profileName = [string]$profileProperty.Value
        }
    }
    $now = [datetimeoffset]::Now
    try {
        Write-AIFishBotStatus -RunDirectory $fullRunDirectory -Status ([pscustomobject][ordered]@{
                processId = [int]$PID
                state = 'error'
                hookCount = 0
                retryCount = 0
                profileName = $profileName
                startedAt = $startedAt
                remainingSeconds = $null
                lastError = $safeMessage
                heartbeatAt = $now
                configVersion = [math]::Max(0, $ConfigVersion)
            }) | Out-Null
    }
    catch {
    }
    try {
        Write-AIFishBotLog -RunDirectory $fullRunDirectory -Level Error `
            -Message ('Engine entry failed: {0}' -f $safeMessage) -Now $now | Out-Null
    }
    catch {
    }
}

try {
    $fullRunDirectory = [System.IO.Path]::GetFullPath($RunDirectory)
    if (-not [System.IO.Directory]::Exists($fullRunDirectory)) {
        throw 'The engine run directory does not exist.'
    }

    Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'AI-FishBot.Config.psm1') `
        -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
        -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'AI-FishBot.Adapters.psm1') `
        -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'AI-FishBot.EngineCore.psm1') `
        -Force -ErrorAction Stop

    $startConfigPath = Join-Path -Path $fullRunDirectory -ChildPath 'start-config.json'
    $liveConfigPath = Join-Path -Path $fullRunDirectory -ChildPath 'live-config.json'
    $startupConfig = Read-AIFishBotJson -Path $startConfigPath
    $versionProperty = $startupConfig.PSObject.Properties['configVersion']
    if ($null -ne $versionProperty) {
        $startupVersion = [int]$versionProperty.Value
    }

    $capturedRunDirectory = $fullRunDirectory
    $entryLogProvider = ({
            param($level, $message)
            Write-AIFishBotLog -RunDirectory $capturedRunDirectory -Level $level `
                -Message $message | Out-Null
        }.GetNewClosure())
    $adapter = New-AIFishBotEngineAdapter -Config $startupConfig `
        -RunDirectory $fullRunDirectory -Simulation:$Simulation -LogProvider $entryLogProvider
    Write-AIFishBotLog -RunDirectory $fullRunDirectory -Level Info `
        -Message 'Engine starting.' | Out-Null

    $capturedLiveConfigPath = $liveConfigPath
    $liveConfigLoader = ({
            param($engineState)
            if (-not [System.IO.File]::Exists($capturedLiveConfigPath)) {
                return $null
            }
            return Read-AIFishBotJson -Path $capturedLiveConfigPath
        }.GetNewClosure())
    $state = New-AIFishBotEngineState -Config $startupConfig `
        -RunDirectory $fullRunDirectory -Adapter $adapter -ConfigVersion $startupVersion `
        -LiveConfigLoader $liveConfigLoader -StartedAt $startedAt

    $coreOwnsAdapter = $true
    $state = Start-AIFishBotEngineLoop -State $state
    if ($state.State -eq 'error') {
        $exitCode = 1
    }
    else {
        Write-AIFishBotLog -RunDirectory $fullRunDirectory -Level Info `
            -Message ('Engine finished in state {0}.' -f $state.State) | Out-Null
        $exitCode = 0
    }
}
catch {
    $safeError = Protect-AIFishBotEngineEntryMessage -Message $_.Exception.Message
    Write-AIFishBotEngineEntryError -Message $safeError -Config $startupConfig `
        -ConfigVersion $startupVersion
    $exitCode = 1
}
finally {
    if (-not $coreOwnsAdapter -and $null -ne $adapter) {
        try {
            Invoke-AIFishBotEngineEntryDispose -TargetAdapter $adapter
        }
        catch {
        }
    }
}

exit $exitCode
