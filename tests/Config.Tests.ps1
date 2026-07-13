$script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$script:ConfigModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'AI-FishBot.Config.psm1'

if (Test-Path -LiteralPath $script:ConfigModulePath -PathType Leaf) {
    Import-Module -Name $script:ConfigModulePath -Force -ErrorAction Stop
}

function Assert-ConfigError {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result,

        [Parameter(Mandatory = $true)]
        [string]$Field
    )

    Assert-Equal -Expected $false -Actual $Result.IsValid
    Assert-True -Condition $Result.Errors.ContainsKey($Field)
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$Result.Errors[$Field]))
}

function New-TestBuff {
    param(
        [object]$Enabled = $true,
        [object]$Keybind = 'F9',
        [object]$CastTimeSeconds = 1,
        [object]$DurationMinutes = 10,
        [AllowNull()]
        [object]$Name = ''
    )

    return [pscustomobject]@{
        enabled = $Enabled
        keybind = $Keybind
        castTimeSeconds = $CastTimeSeconds
        durationMinutes = $DurationMinutes
        name = $Name
    }
}

Test-Case 'default configuration contains every required value' {
    $config = New-AIFishBotDefaultConfig

    Assert-Equal -Expected 1 -Actual $config.schemaVersion
    Assert-Equal -Expected '新方案' -Actual $config.profileName
    Assert-Equal -Expected $false -Actual $config.retail
    Assert-Equal -Expected $true -Actual $config.autoStop
    Assert-Equal -Expected 60 -Actual $config.autoStopTime
    Assert-Equal -Expected $false -Actual $config.autoLogout
    Assert-Equal -Expected 3 -Actual $config.audioSensitivity
    Assert-Equal -Expected $true -Actual $config.useWindowFocus
    Assert-Equal -Expected $false -Actual $config.useWeakAura
    Assert-Equal -Expected 15 -Actual $config.fishingRetries
    Assert-Equal -Expected 'F6' -Actual $config.castKey
    Assert-Equal -Expected 'F7' -Actual $config.bobberKey
    Assert-Equal -Expected 'F8' -Actual $config.logoutKey
    Assert-Equal -Expected $false -Actual $config.usePi
    Assert-Equal -Expected '' -Actual $config.picoComPort
    Assert-Equal -Expected $false -Actual $config.enableNotifications
    Assert-Equal -Expected '' -Actual $config.discordWebhook
    Assert-Equal -Expected $true -Actual $config.notifyOnStart
    Assert-Equal -Expected $true -Actual $config.notifyOnStop
    Assert-Equal -Expected 0.3 -Actual $config.biteResponseMinSeconds
    Assert-Equal -Expected 0.7 -Actual $config.biteResponseMaxSeconds
    Assert-Equal -Expected 0.5 -Actual $config.preHookMinSeconds
    Assert-Equal -Expected 0.5 -Actual $config.preHookMaxSeconds
    Assert-Equal -Expected 1.1 -Actual $config.postHookMinSeconds
    Assert-Equal -Expected 1.5 -Actual $config.postHookMaxSeconds
    Assert-Equal -Expected 0.2 -Actual $config.preCastMinSeconds
    Assert-Equal -Expected 0.6 -Actual $config.preCastMaxSeconds
    Assert-True -Condition ($config.PSObject.Properties.Name -contains 'buffs')
    Assert-Equal -Expected 0 -Actual @($config.buffs).Count
}

Test-Case 'default configuration is valid' {
    $result = Test-AIFishBotConfig -Config (New-AIFishBotDefaultConfig)

    Assert-Equal -Expected $true -Actual $result.IsValid
    Assert-Equal -Expected 0 -Actual $result.Errors.Count
}

foreach ($case in @(
        @{ Name = 'below the minimum'; Value = 0 },
        @{ Name = 'above the maximum'; Value = 10 },
        @{ Name = 'text'; Value = 'loud' },
        @{ Name = 'an empty value'; Value = $null }
    )) {
    Test-Case ("audio sensitivity rejects {0}" -f $case.Name) {
        $config = New-AIFishBotDefaultConfig
        $config.audioSensitivity = $case.Value

        Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'audioSensitivity'
    }
}

foreach ($case in @(
        @{ Name = 'zero'; Value = 0 },
        @{ Name = 'text'; Value = 'later' },
        @{ Name = 'an empty value'; Value = $null }
    )) {
    Test-Case ("auto stop time rejects {0}" -f $case.Name) {
        $config = New-AIFishBotDefaultConfig
        $config.autoStopTime = $case.Value

        Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'autoStopTime'
    }
}

Test-Case 'fishing retries rejects a negative value' {
    $config = New-AIFishBotDefaultConfig
    $config.fishingRetries = -1

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'fishingRetries'
}

$waitRanges = @(
    @{ Name = 'bite response'; Min = 'biteResponseMinSeconds'; Max = 'biteResponseMaxSeconds' },
    @{ Name = 'pre hook'; Min = 'preHookMinSeconds'; Max = 'preHookMaxSeconds' },
    @{ Name = 'post hook'; Min = 'postHookMinSeconds'; Max = 'postHookMaxSeconds' },
    @{ Name = 'pre cast'; Min = 'preCastMinSeconds'; Max = 'preCastMaxSeconds' }
)

foreach ($range in $waitRanges) {
    Test-Case ("{0} wait rejects a negative value" -f $range.Name) {
        $config = New-AIFishBotDefaultConfig
        $config.($range.Min) = -0.1

        Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field $range.Min
    }

    Test-Case ("{0} wait rejects a reversed range" -f $range.Name) {
        $config = New-AIFishBotDefaultConfig
        $config.($range.Min) = 2
        $config.($range.Max) = 1

        Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field $range.Min
    }

    Test-Case ("{0} wait rejects text and empty values" -f $range.Name) {
        $config = New-AIFishBotDefaultConfig
        $config.($range.Min) = 'soon'
        $config.($range.Max) = $null

        $result = Test-AIFishBotConfig -Config $config
        Assert-ConfigError -Result $result -Field $range.Min
        Assert-True -Condition $result.Errors.ContainsKey($range.Max)
    }
}

foreach ($keyField in @('castKey', 'bobberKey', 'logoutKey')) {
    foreach ($invalidKey in @('F4', 'F13')) {
        Test-Case ("{0} rejects {1}" -f $keyField, $invalidKey) {
            $config = New-AIFishBotDefaultConfig
            $config.$keyField = $invalidKey

            Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field $keyField
        }
    }
}

Test-Case 'Pico rejects a port that is not currently available' {
    $config = New-AIFishBotDefaultConfig
    $config.usePi = $true
    $config.picoComPort = 'COM7'

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config -AvailablePorts @('COM3')) -Field 'picoComPort'
}

Test-Case 'Pico accepts a port that is currently available' {
    $config = New-AIFishBotDefaultConfig
    $config.usePi = $true
    $config.picoComPort = 'COM7'

    $result = Test-AIFishBotConfig -Config $config -AvailablePorts @('COM3', 'COM7')
    Assert-Equal -Expected $true -Actual $result.IsValid
    Assert-Equal -Expected 0 -Actual $result.Errors.Count
}

Test-Case 'a valid buff with an empty name is accepted' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -Name $null)

    $result = Test-AIFishBotConfig -Config $config
    Assert-Equal -Expected $true -Actual $result.IsValid
    Assert-Equal -Expected 0 -Actual $result.Errors.Count
}

Test-Case 'buff cast time rejects zero' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -CastTimeSeconds 0)

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].castTimeSeconds'
}

Test-Case 'buff duration rejects zero' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -DurationMinutes 0)

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].durationMinutes'
}

foreach ($invalidKey in @('F4', 'F13')) {
    Test-Case ("buff key rejects {0}" -f $invalidKey) {
        $config = New-AIFishBotDefaultConfig
        $config.buffs = @(New-TestBuff -Keybind $invalidKey)

        Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].keybind'
    }
}

Test-Case 'buff cast time rejects text without throwing' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -CastTimeSeconds 'slow')

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].castTimeSeconds'
}

Test-Case 'buff duration rejects an empty value without throwing' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -DurationMinutes $null)

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].durationMinutes'
}

Test-Case 'buff enabled rejects text without throwing' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = @(New-TestBuff -Enabled 'yes')

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0].enabled'
}

Test-Case 'an empty configuration returns keyed errors without throwing' {
    $result = Test-AIFishBotConfig -Config $null

    Assert-ConfigError -Result $result -Field 'config'
}
