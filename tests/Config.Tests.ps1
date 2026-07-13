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
    Assert-True -Condition ([regex]::IsMatch([string]$Result.Errors[$Field], '[\u4e00-\u9fff]'))
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

$booleanFields = @(
    'retail',
    'autoStop',
    'autoLogout',
    'useWindowFocus',
    'useWeakAura',
    'usePi',
    'enableNotifications',
    'notifyOnStart',
    'notifyOnStop'
)

$invalidBooleanCases = @(
    @{ Name = 'text'; Value = 'true'; Missing = $false },
    @{ Name = 'an empty value'; Value = $null; Missing = $false },
    @{ Name = 'a missing property'; Missing = $true }
)

foreach ($booleanField in $booleanFields) {
    foreach ($invalidCase in $invalidBooleanCases) {
        Test-Case ("{0} rejects {1}" -f $booleanField, $invalidCase.Name) {
            $config = New-AIFishBotDefaultConfig
            if ($invalidCase.Missing) {
                $config.PSObject.Properties.Remove($booleanField)
            }
            else {
                $config.$booleanField = $invalidCase.Value
            }

            Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field $booleanField
        }
    }
}

Test-Case 'a text usePi value does not trigger port validation' {
    $config = New-AIFishBotDefaultConfig
    $config.usePi = 'true'
    $config.picoComPort = 'COM_MISSING'

    $result = Test-AIFishBotConfig -Config $config -AvailablePorts @()
    Assert-ConfigError -Result $result -Field 'usePi'
    Assert-True -Condition (-not $result.Errors.ContainsKey('picoComPort'))
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

Test-Case 'fishing retries rejects a fractional value' {
    $config = New-AIFishBotDefaultConfig
    $config.fishingRetries = 0.5

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

Test-Case 'default port provider reads the system serial ports' {
    $module = Get-Module -Name 'AI-FishBot.Config'
    $expectedPorts = @([IO.Ports.SerialPort]::GetPortNames())
    $actualPorts = @(& $module { Get-AIFishBotAvailablePorts })

    Assert-Equal -Expected $expectedPorts -Actual $actualPorts
}

Test-Case 'Pico discovers available ports when none are injected' {
    $module = Get-Module -Name 'AI-FishBot.Config'

    try {
        & $module {
            $script:AIFishBotPortProvider = { @('COM_TEST_DISCOVERED') }
        }

        $config = New-AIFishBotDefaultConfig
        $config.usePi = $true
        $config.picoComPort = 'COM_TEST_DISCOVERED'

        $result = Test-AIFishBotConfig -Config $config
        Assert-Equal -Expected $true -Actual $result.IsValid
        Assert-Equal -Expected 0 -Actual $result.Errors.Count
    }
    finally {
        Import-Module -Name $script:ConfigModulePath -Force -ErrorAction Stop
    }
}

Test-Case 'explicit available ports skip system discovery' {
    $module = Get-Module -Name 'AI-FishBot.Config'

    try {
        & $module {
            $script:AIFishBotPortProvider = { throw 'System discovery should not run.' }
        }

        $config = New-AIFishBotDefaultConfig
        $config.usePi = $true
        $config.picoComPort = 'COM_TEST_INJECTED'

        $result = Test-AIFishBotConfig -Config $config -AvailablePorts @('COM_TEST_INJECTED')
        Assert-Equal -Expected $true -Actual $result.IsValid
        Assert-Equal -Expected 0 -Actual $result.Errors.Count
    }
    finally {
        Import-Module -Name $script:ConfigModulePath -Force -ErrorAction Stop
    }
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

Test-Case 'a null buff returns an error at its original index' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = [object[]]@($null)

    Assert-ConfigError -Result (Test-AIFishBotConfig -Config $config) -Field 'buffs[0]'
}

Test-Case 'mixed buff lists preserve indexes after a null item' {
    $config = New-AIFishBotDefaultConfig
    $config.buffs = [object[]]@(
        (New-TestBuff -Keybind 'F9'),
        $null,
        (New-TestBuff -Keybind 'F4')
    )

    $result = Test-AIFishBotConfig -Config $config
    Assert-ConfigError -Result $result -Field 'buffs[1]'
    Assert-True -Condition $result.Errors.ContainsKey('buffs[2].keybind')
    Assert-True -Condition (-not $result.Errors.ContainsKey('buffs[1].keybind'))
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

function Write-TestTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Remove-TestDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

Test-Case 'legacy import maps every supported setting and numbered buffs' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$retail = $True
$autoStop = $False
$autoStopTime = 75
$autoLogout = $True
$audioSensitivity = 7
$UseWindowFocus = $False
$fishingRetries = 21
$usePi = $True
$picoComPort = "COM9"
$useWeakAura = $True
$cast = "F5"
$bobber = "F11"
$logout = "F12"
$enableNotifications = $True
$discordWebhook = "https://example.invalid/hook"
$onStart = $False
$onStop = $True
$enableBuffs = (1..2)
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
$buffKeybind2 = "F10"
$buffCastTime2 = 3
$buffDuration2 = 20
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName ' 时光服 '
        $defaults = New-AIFishBotDefaultConfig

        Assert-Equal -Expected '时光服' -Actual $config.profileName
        Assert-Equal -Expected $true -Actual $config.retail
        Assert-Equal -Expected $false -Actual $config.autoStop
        Assert-Equal -Expected 75 -Actual $config.autoStopTime
        Assert-Equal -Expected $true -Actual $config.autoLogout
        Assert-Equal -Expected 7 -Actual $config.audioSensitivity
        Assert-Equal -Expected $false -Actual $config.useWindowFocus
        Assert-Equal -Expected 21 -Actual $config.fishingRetries
        Assert-Equal -Expected $true -Actual $config.usePi
        Assert-Equal -Expected 'COM9' -Actual $config.picoComPort
        Assert-Equal -Expected $true -Actual $config.useWeakAura
        Assert-Equal -Expected 'F5' -Actual $config.castKey
        Assert-Equal -Expected 'F11' -Actual $config.bobberKey
        Assert-Equal -Expected 'F12' -Actual $config.logoutKey
        Assert-Equal -Expected $true -Actual $config.enableNotifications
        Assert-Equal -Expected 'https://example.invalid/hook' -Actual $config.discordWebhook
        Assert-Equal -Expected $false -Actual $config.notifyOnStart
        Assert-Equal -Expected $true -Actual $config.notifyOnStop
        foreach ($delayName in @(
                'biteResponseMinSeconds', 'biteResponseMaxSeconds',
                'preHookMinSeconds', 'preHookMaxSeconds',
                'postHookMinSeconds', 'postHookMaxSeconds',
                'preCastMinSeconds', 'preCastMaxSeconds'
            )) {
            Assert-Equal -Expected $defaults.$delayName -Actual $config.$delayName
        }

        Assert-Equal -Expected 2 -Actual @($config.buffs).Count
        Assert-Equal -Expected $true -Actual $config.buffs[0].enabled
        Assert-Equal -Expected '增益 1' -Actual $config.buffs[0].name
        Assert-Equal -Expected 'F9' -Actual $config.buffs[0].keybind
        Assert-Equal -Expected 2 -Actual $config.buffs[0].castTimeSeconds
        Assert-Equal -Expected 10 -Actual $config.buffs[0].durationMinutes
        Assert-Equal -Expected $true -Actual $config.buffs[1].enabled
        Assert-Equal -Expected '增益 2' -Actual $config.buffs[1].name
        Assert-Equal -Expected 'F10' -Actual $config.buffs[1].keybind
        Assert-Equal -Expected 3 -Actual $config.buffs[1].castTimeSeconds
        Assert-Equal -Expected 20 -Actual $config.buffs[1].durationMinutes
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import never executes script commands' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'malicious.ps1'
        $markerPath = Join-Path -Path $directory -ChildPath 'executed.txt'
        $escapedMarkerPath = $markerPath.Replace("'", "''")
        Write-TestTextFile -Path $legacyPath -Content @"
`$retail = `$False
throw 'legacy script must not run'
Set-Content -LiteralPath '$escapedMarkerPath' -Value 'executed'
`$cast = (Get-Process | Select-Object -First 1)
"@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '安全导入'

        Assert-Equal -Expected $false -Actual $config.retail
        Assert-Equal -Expected 'F6' -Actual $config.castKey
        Assert-True -Condition (-not (Test-Path -LiteralPath $markerPath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy zero buff marker creates no buff zero and disables configured buffs' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$enableBuffs = (0)
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
$buffKeybind2 = "F10"
$buffCastTime2 = 3
$buffDuration2 = 20
$buffKeybind0 = "F8"
$buffCastTime0 = 1
$buffDuration0 = 1
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '无增益'

        Assert-Equal -Expected 2 -Actual @($config.buffs).Count
        Assert-Equal -Expected $false -Actual $config.buffs[0].enabled
        Assert-Equal -Expected $false -Actual $config.buffs[1].enabled
        Assert-True -Condition (@($config.buffs | Where-Object { $_.name -eq '增益 0' }).Count -eq 0)
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import enables buff one from a parenthesized single value' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$enableBuffs = (1)
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '单个增益'

        Assert-Equal -Expected 1 -Actual @($config.buffs).Count
        Assert-Equal -Expected $true -Actual $config.buffs[0].enabled
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import supports any parenthesized positive buff number' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$enableBuffs = (2)
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
$buffKeybind2 = "F10"
$buffCastTime2 = 3
$buffDuration2 = 20
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '严格格式'

        Assert-Equal -Expected 2 -Actual @($config.buffs).Count
        Assert-Equal -Expected $false -Actual $config.buffs[0].enabled
        Assert-Equal -Expected $true -Actual $config.buffs[1].enabled
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import rejects an unparenthesized single buff number' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$enableBuffs = 1
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '非法格式'

        Assert-Equal -Expected 1 -Actual @($config.buffs).Count
        Assert-Equal -Expected $false -Actual $config.buffs[0].enabled
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import ignores oversized buff numbers without failing' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$enableBuffs = (1..1)
$buffKeybind1 = "F9"
$buffCastTime1 = 2
$buffDuration1 = 10
$buffKeybind999999999999999999999999 = "F10"
$buffCastTime999999999999999999999999 = 3
$buffDuration999999999999999999999999 = 20
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '超大编号'

        Assert-Equal -Expected 1 -Actual @($config.buffs).Count
        Assert-Equal -Expected '增益 1' -Actual $config.buffs[0].name
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import uses the final assignment even when it is unsafe' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content @'
$retail = $True
$retail = Get-Process
$autoStopTime = 10
$autoStopTime = 25
$enableBuffs = (1)
$enableBuffs = (1 + 1)
$buffKeybind1 = "F9"
$buffKeybind1 = Get-Process
$buffCastTime1 = 2
$buffDuration1 = 10
'@

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '重复赋值'

        Assert-Equal -Expected $false -Actual $config.retail
        Assert-Equal -Expected 25 -Actual $config.autoStopTime
        Assert-Equal -Expected 0 -Actual @($config.buffs).Count
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import reads UTF-8 Chinese text without a BOM' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content '$discordWebhook = "中文通知"'

        $config = Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '中文配置'

        Assert-Equal -Expected '中文通知' -Actual $config.discordWebhook
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'legacy import rejects invalid UTF-8 bytes' {
    $directory = New-TestDirectory
    try {
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        $prefix = [System.Text.Encoding]::ASCII.GetBytes('$discordWebhook = "')
        $suffix = [System.Text.Encoding]::ASCII.GetBytes('"')
        $bytes = [byte[]]@($prefix + [byte[]]@(0xFF) + $suffix)
        [System.IO.File]::WriteAllBytes($legacyPath, $bytes)

        Assert-Throws -ScriptBlock { Import-AIFishBotLegacyConfig -ScriptPath $legacyPath -ProfileName '非法编码' } -MessageLike '*UTF-8*'
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profiles save and read UTF-8 JSON without losing nested values' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = ' 钓鱼方案 '
        $config.discordWebhook = '中文通知'
        $config.buffs = @(New-TestBuff -Name '烹饪帽')

        $saved = Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config
        $loaded = Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '钓鱼方案'

        Assert-Equal -Expected '钓鱼方案' -Actual $saved.profileName
        Assert-Equal -Expected '钓鱼方案' -Actual $loaded.profileName
        Assert-Equal -Expected '中文通知' -Actual $loaded.discordWebhook
        Assert-Equal -Expected '烹饪帽' -Actual $loaded.buffs[0].name
        Assert-True -Condition (Test-Path -LiteralPath (Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '钓鱼方案'))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile read rejects a JSON profile name that differs from its file name' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '文件方案'
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null

        $wrongConfig = New-AIFishBotDefaultConfig
        $wrongConfig.profileName = '其他方案'
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '文件方案'
        Write-TestTextFile -Path $profilePath -Content ($wrongConfig | ConvertTo-Json -Depth 20)
        $originalText = [System.IO.File]::ReadAllText($profilePath)

        Assert-Throws -ScriptBlock { Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '文件方案' } -MessageLike '*名称*不一致*'
        Assert-Equal -Expected $originalText -Actual ([System.IO.File]::ReadAllText($profilePath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile read rejects invalid UTF-8 without changing the file' {
    $directory = New-TestDirectory
    try {
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '非法编码'
        $bytes = [byte[]]@(0x7B, 0x22, 0xFF, 0x22, 0x3A, 0x31, 0x7D)
        [System.IO.File]::WriteAllBytes($profilePath, $bytes)

        Assert-Throws -ScriptBlock { Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '非法编码' } -MessageLike '*UTF-8*'
        Assert-Equal -Expected $bytes -Actual ([System.IO.File]::ReadAllBytes($profilePath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile save rejects object graphs deeper than the safe limit' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '过深方案'
        $root = [pscustomobject]@{}
        $current = $root
        foreach ($level in 1..21) {
            $next = [pscustomobject]@{ level = $level }
            $current | Add-Member -MemberType NoteProperty -Name child -Value $next
            $current = $next
        }
        $config | Add-Member -MemberType NoteProperty -Name extra -Value $root

        Assert-Throws -ScriptBlock { Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config } -MessageLike '*层*'
        Assert-True -Condition (-not (Test-Path -LiteralPath (Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '过深方案')))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile save rejects circular object graphs' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '循环方案'
        $loop = @{}
        $loop['self'] = $loop
        $config | Add-Member -MemberType NoteProperty -Name extra -Value $loop

        Assert-Throws -ScriptBlock { Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config } -MessageLike '*循环*'
        Assert-True -Condition (-not (Test-Path -LiteralPath (Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '循环方案')))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile listing is sorted and excludes backup files' {
    $directory = New-TestDirectory
    try {
        foreach ($name in @('乙', '甲')) {
            $config = New-AIFishBotDefaultConfig
            $config.profileName = $name
            Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        }
        Write-TestTextFile -Path (Join-Path $directory '忽略.json.backup') -Content '{}'

        Assert-Equal -Expected @('甲', '乙') -Actual @(Get-AIFishBotProfiles -ProfilesDirectory $directory)
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profiles can be copied renamed and deleted' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '原方案'
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null

        $copy = Copy-AIFishBotProfile -ProfilesDirectory $directory -SourceProfileName '原方案' -DestinationProfileName '副本'
        Assert-Equal -Expected '副本' -Actual $copy.profileName

        $renamed = Rename-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '副本' -NewProfileName '新名称'
        Assert-Equal -Expected '新名称' -Actual $renamed.profileName
        Assert-True -Condition (-not (Test-Path -LiteralPath (Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '副本')))

        Remove-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '新名称'
        Assert-Equal -Expected @('原方案') -Actual @(Get-AIFishBotProfiles -ProfilesDirectory $directory)
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'copy and rename reject an existing destination' {
    $directory = New-TestDirectory
    try {
        foreach ($name in @('方案一', '方案二')) {
            $config = New-AIFishBotDefaultConfig
            $config.profileName = $name
            Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        }

        Assert-Throws -ScriptBlock { Copy-AIFishBotProfile -ProfilesDirectory $directory -SourceProfileName '方案一' -DestinationProfileName '方案二' } -MessageLike '*已存在*'
        Assert-Throws -ScriptBlock { Rename-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '方案一' -NewProfileName '方案二' } -MessageLike '*已存在*'
        $profiles = @(Get-AIFishBotProfiles -ProfilesDirectory $directory)
        Assert-Equal -Expected 2 -Actual $profiles.Count
        Assert-True -Condition ($profiles -contains '方案一')
        Assert-True -Condition ($profiles -contains '方案二')
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile names reject blanks traversal separators and invalid Windows characters' {
    $directory = New-TestDirectory
    try {
        foreach ($name in @('   ', '.', '..', '..\逃逸', '../逃逸', '坏:名字', '坏|名字', 'CON', 'COM¹', 'LPT²', '结尾.')) {
            Assert-Throws -ScriptBlock { Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName $name } -MessageLike '*方案名称*'
        }

        $outsidePath = Join-Path -Path (Split-Path -Path $directory -Parent) -ChildPath '逃逸.json'
        Assert-True -Condition (-not (Test-Path -LiteralPath $outsidePath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'corrupt JSON is restored from a valid backup' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '可恢复'
        $config.autoStopTime = 10
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $config.autoStopTime = 20
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null

        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '可恢复'
        Write-TestTextFile -Path $profilePath -Content '{ broken json'

        $restored = Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '可恢复'
        $readAgain = Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '可恢复'

        Assert-Equal -Expected 10 -Actual $restored.autoStopTime
        Assert-Equal -Expected 10 -Actual $readAgain.autoStopTime
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'corrupt JSON without a valid backup reports clearly and preserves the file' {
    $directory = New-TestDirectory
    try {
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '损坏方案'
        Write-TestTextFile -Path $profilePath -Content '{ broken json'
        Write-TestTextFile -Path ($profilePath + '.backup') -Content '{ also broken'

        Assert-Throws -ScriptBlock { Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '损坏方案' } -MessageLike '*损坏*'
        Assert-Equal -Expected '{ broken json' -Actual ([System.IO.File]::ReadAllText($profilePath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'a new profile discards a stale backup with the same name' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '重建方案'
        $config.autoStopTime = 10
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '重建方案'
        [System.IO.File]::Copy($profilePath, ($profilePath + '.backup'), $true)
        Remove-Item -LiteralPath $profilePath -Force

        $config.autoStopTime = 20
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null

        Assert-True -Condition (-not (Test-Path -LiteralPath ($profilePath + '.backup')))
        Write-TestTextFile -Path $profilePath -Content '{ broken json'
        Assert-Throws -ScriptBlock { Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '重建方案' } -MessageLike '*损坏*'
        Assert-Equal -Expected '{ broken json' -Actual ([System.IO.File]::ReadAllText($profilePath))
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'a temporary read failure never restores an older backup' {
    $directory = New-TestDirectory
    $lock = $null
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '读取占用'
        $config.autoStopTime = 10
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $config.autoStopTime = 20
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '读取占用'

        $lock = [System.IO.File]::Open(
            $profilePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Delete)
        Assert-Throws -ScriptBlock { Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '读取占用' }
        $lock.Dispose()
        $lock = $null

        Assert-Equal -Expected 20 -Actual (Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '读取占用').autoStopTime
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'failed atomic replacement preserves the previous profile and cleans temporary files' {
    $directory = New-TestDirectory
    $lock = $null
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '原子保存'
        $config.autoStopTime = 10
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $directory -ProfileName '原子保存'

        $lock = [System.IO.File]::Open($profilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $config.autoStopTime = 99
        Assert-Throws -ScriptBlock { Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config }
        $lock.Dispose()
        $lock = $null

        Assert-Equal -Expected 10 -Actual (Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '原子保存').autoStopTime
        Assert-Equal -Expected 0 -Actual @(Get-ChildItem -LiteralPath $directory -Filter '*.tmp' -File).Count
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
        }
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'profile reads wait for the cross-process directory mutex' {
    $directory = New-TestDirectory
    $mutex = $null
    $ownsMutex = $false
    $job = $null
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '互斥读取'
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null

        $module = Get-Module -Name 'AI-FishBot.Config'
        $mutexName = & $module {
            param($directoryPath)
            Get-AIFishBotProfilesMutexName -ProfilesDirectory $directoryPath
        } $directory
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $ownsMutex = $mutex.WaitOne()

        $markerPath = Join-Path -Path $directory -ChildPath 'reader.ready'
        $job = Start-Job -ScriptBlock {
            param($modulePath, $profilesDirectory, $marker)
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            [System.IO.File]::WriteAllText($marker, 'ready')
            (Read-AIFishBotProfile -ProfilesDirectory $profilesDirectory -ProfileName '互斥读取').autoStopTime
        } -ArgumentList $script:ConfigModulePath, $directory, $markerPath

        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $markerPath) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        Assert-True -Condition (Test-Path -LiteralPath $markerPath)
        Start-Sleep -Milliseconds 300
        Assert-Equal -Expected 'Running' -Actual ([string]$job.State)

        $mutex.ReleaseMutex()
        $ownsMutex = $false
        Wait-Job -Job $job -Timeout 10 | Out-Null
        Assert-Equal -Expected @(60) -Actual @(Receive-Job -Job $job -ErrorAction Stop)
    }
    finally {
        if ($ownsMutex -and $null -ne $mutex) {
            $mutex.ReleaseMutex()
        }
        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
        if ($null -ne $job) {
            if ($job.State -eq 'Running') {
                Stop-Job -Job $job
            }
            Remove-Job -Job $job -Force
        }
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'create-new profile saves never overwrite an existing target' {
    $directory = New-TestDirectory
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '不可覆盖'
        $config.autoStopTime = 10
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config -CreateNew | Out-Null

        $config.autoStopTime = 20
        Assert-Throws -ScriptBlock { Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config -CreateNew } -MessageLike '*已存在*'
        Assert-Equal -Expected 10 -Actual (Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '不可覆盖').autoStopTime
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'concurrent copies allow only one process to create the destination' {
    $directory = New-TestDirectory
    $jobs = @()
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = '并发源'
        Save-AIFishBotProfile -ProfilesDirectory $directory -Config $config | Out-Null
        $goPath = Join-Path -Path $directory -ChildPath 'copy.go'

        foreach ($number in 1..2) {
            $readyPath = Join-Path -Path $directory -ChildPath ('copy.{0}.ready' -f $number)
            $jobs += Start-Job -ScriptBlock {
                param($modulePath, $profilesDirectory, $ready, $go)
                Import-Module -Name $modulePath -Force -ErrorAction Stop
                [System.IO.File]::WriteAllText($ready, 'ready')
                while (-not (Test-Path -LiteralPath $go)) {
                    Start-Sleep -Milliseconds 20
                }
                try {
                    Copy-AIFishBotProfile -ProfilesDirectory $profilesDirectory -SourceProfileName '并发源' -DestinationProfileName '并发目标' | Out-Null
                    'SUCCESS'
                }
                catch {
                    'FAILED'
                }
            } -ArgumentList $script:ConfigModulePath, $directory, $readyPath, $goPath
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (@(Get-ChildItem -LiteralPath $directory -Filter 'copy.*.ready' -File).Count -lt 2 -and
            [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        Assert-Equal -Expected 2 -Actual @(Get-ChildItem -LiteralPath $directory -Filter 'copy.*.ready' -File).Count
        Write-TestTextFile -Path $goPath -Content 'go'

        Wait-Job -Job $jobs -Timeout 15 | Out-Null
        $results = @($jobs | Receive-Job -ErrorAction Stop)
        Assert-Equal -Expected 1 -Actual @($results | Where-Object { $_ -eq 'SUCCESS' }).Count
        Assert-Equal -Expected 1 -Actual @($results | Where-Object { $_ -eq 'FAILED' }).Count
        Assert-Equal -Expected '并发目标' -Actual (Read-AIFishBotProfile -ProfilesDirectory $directory -ProfileName '并发目标').profileName
    }
    finally {
        foreach ($job in $jobs) {
            if ($job.State -eq 'Running') {
                Stop-Job -Job $job
            }
            Remove-Job -Job $job -Force
        }
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'initialization imports legacy settings only when no profile exists' {
    $directory = New-TestDirectory
    try {
        $profilesDirectory = Join-Path -Path $directory -ChildPath 'profiles'
        $legacyPath = Join-Path -Path $directory -ChildPath 'legacy.ps1'
        Write-TestTextFile -Path $legacyPath -Content '$autoStopTime = 42'

        $first = @(Initialize-AIFishBotProfiles -ProfilesDirectory $profilesDirectory -LegacyScriptPath $legacyPath -InitialProfileName '时光服')
        Write-TestTextFile -Path $legacyPath -Content '$autoStopTime = 99'
        $second = @(Initialize-AIFishBotProfiles -ProfilesDirectory $profilesDirectory -LegacyScriptPath $legacyPath -InitialProfileName '时光服')

        Assert-Equal -Expected @('时光服') -Actual $first
        Assert-Equal -Expected @('时光服') -Actual $second
        Assert-Equal -Expected 42 -Actual (Read-AIFishBotProfile -ProfilesDirectory $profilesDirectory -ProfileName '时光服').autoStopTime
    }
    finally {
        Remove-TestDirectory -Path $directory
    }
}

Test-Case 'all profile management commands are exported' {
    foreach ($commandName in @(
            'Get-AIFishBotProfilePath',
            'Get-AIFishBotProfiles',
            'Read-AIFishBotProfile',
            'Save-AIFishBotProfile',
            'Copy-AIFishBotProfile',
            'Rename-AIFishBotProfile',
            'Remove-AIFishBotProfile',
            'Initialize-AIFishBotProfiles',
            'Import-AIFishBotLegacyConfig'
        )) {
        Assert-True -Condition ($null -ne (Get-Command -Name $commandName -ErrorAction SilentlyContinue))
    }
}
