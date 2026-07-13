$script:AIFishBotPortProvider = {
    return @([IO.Ports.SerialPort]::GetPortNames())
}

function Get-AIFishBotAvailablePorts {
    return @(& $script:AIFishBotPortProvider)
}

function Get-AIFishBotConfigValue {
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-AIFishBotNumber {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $false
    }

    $isNumber = $Value -is [sbyte] -or
        $Value -is [byte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal]

    if (-not $isNumber) {
        return $false
    }

    if ($Value -is [single] -or $Value -is [double]) {
        $doubleValue = [double]$Value
        return -not ([double]::IsNaN($doubleValue) -or [double]::IsInfinity($doubleValue))
    }

    return $true
}

function Add-AIFishBotConfigError {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Errors,

        [Parameter(Mandatory = $true)]
        [string]$Field,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Errors[$Field] = $Message
}

function Test-AIFishBotFunctionKey {
    param(
        [AllowNull()]
        [object]$Value
    )

    return $null -ne $Value -and ([string]$Value -match '^F(?:[5-9]|1[0-2])$')
}

function New-AIFishBotDefaultConfig {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        profileName = '新方案'
        retail = $false
        autoStop = $true
        autoStopTime = 60
        autoLogout = $false
        audioSensitivity = 3
        useWindowFocus = $true
        useWeakAura = $false
        fishingRetries = 15
        castKey = 'F6'
        bobberKey = 'F7'
        logoutKey = 'F8'
        usePi = $false
        picoComPort = ''
        enableNotifications = $false
        discordWebhook = ''
        notifyOnStart = $true
        notifyOnStop = $true
        biteResponseMinSeconds = 0.3
        biteResponseMaxSeconds = 0.7
        preHookMinSeconds = 0.5
        preHookMaxSeconds = 0.5
        postHookMinSeconds = 1.1
        postHookMaxSeconds = 1.5
        preCastMinSeconds = 0.2
        preCastMaxSeconds = 0.6
        buffs = @()
    }
}

function Test-AIFishBotConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Config,

        [AllowNull()]
        [object[]]$AvailablePorts = @()
    )

    $errors = @{}

    if ($null -eq $Config) {
        Add-AIFishBotConfigError -Errors $errors -Field 'config' -Message '配置不能为空。'
        return [pscustomobject]@{
            IsValid = $false
            Errors = $errors
        }
    }

    $audioSensitivity = Get-AIFishBotConfigValue -InputObject $Config -Name 'audioSensitivity'
    if (-not (Test-AIFishBotNumber -Value $audioSensitivity)) {
        Add-AIFishBotConfigError -Errors $errors -Field 'audioSensitivity' -Message '灵敏度必须是1到9之间的有效数字。'
    }
    elseif ([double]$audioSensitivity -lt 1 -or [double]$audioSensitivity -gt 9) {
        Add-AIFishBotConfigError -Errors $errors -Field 'audioSensitivity' -Message '灵敏度必须在1到9之间。'
    }

    $autoStopTime = Get-AIFishBotConfigValue -InputObject $Config -Name 'autoStopTime'
    if (-not (Test-AIFishBotNumber -Value $autoStopTime)) {
        Add-AIFishBotConfigError -Errors $errors -Field 'autoStopTime' -Message '自动停止分钟必须是有效数字。'
    }
    elseif ([double]$autoStopTime -le 0) {
        Add-AIFishBotConfigError -Errors $errors -Field 'autoStopTime' -Message '自动停止分钟必须大于0。'
    }

    $fishingRetries = Get-AIFishBotConfigValue -InputObject $Config -Name 'fishingRetries'
    if (-not (Test-AIFishBotNumber -Value $fishingRetries)) {
        Add-AIFishBotConfigError -Errors $errors -Field 'fishingRetries' -Message '抛竿重试次数必须是有效数字。'
    }
    elseif ([double]$fishingRetries -lt 0) {
        Add-AIFishBotConfigError -Errors $errors -Field 'fishingRetries' -Message '抛竿重试次数不得小于0。'
    }

    $waitRanges = @(
        @{ Min = 'biteResponseMinSeconds'; Max = 'biteResponseMaxSeconds' },
        @{ Min = 'preHookMinSeconds'; Max = 'preHookMaxSeconds' },
        @{ Min = 'postHookMinSeconds'; Max = 'postHookMaxSeconds' },
        @{ Min = 'preCastMinSeconds'; Max = 'preCastMaxSeconds' }
    )

    foreach ($range in $waitRanges) {
        $minimum = Get-AIFishBotConfigValue -InputObject $Config -Name $range.Min
        $maximum = Get-AIFishBotConfigValue -InputObject $Config -Name $range.Max
        $minimumIsNumber = Test-AIFishBotNumber -Value $minimum
        $maximumIsNumber = Test-AIFishBotNumber -Value $maximum

        if (-not $minimumIsNumber) {
            Add-AIFishBotConfigError -Errors $errors -Field $range.Min -Message '最小等待时间必须是有效数字。'
        }
        elseif ([double]$minimum -lt 0) {
            Add-AIFishBotConfigError -Errors $errors -Field $range.Min -Message '最小等待时间不得小于0。'
        }

        if (-not $maximumIsNumber) {
            Add-AIFishBotConfigError -Errors $errors -Field $range.Max -Message '最大等待时间必须是有效数字。'
        }
        elseif ([double]$maximum -lt 0) {
            Add-AIFishBotConfigError -Errors $errors -Field $range.Max -Message '最大等待时间不得小于0。'
        }

        if ($minimumIsNumber -and $maximumIsNumber -and [double]$minimum -gt [double]$maximum) {
            Add-AIFishBotConfigError -Errors $errors -Field $range.Min -Message '最小等待时间不得大于最大等待时间。'
        }
    }

    foreach ($keyField in @('castKey', 'bobberKey', 'logoutKey')) {
        $keyValue = Get-AIFishBotConfigValue -InputObject $Config -Name $keyField
        if (-not (Test-AIFishBotFunctionKey -Value $keyValue)) {
            Add-AIFishBotConfigError -Errors $errors -Field $keyField -Message '按键必须是F5到F12。'
        }
    }

    $usePi = Get-AIFishBotConfigValue -InputObject $Config -Name 'usePi'
    if ($usePi -is [bool] -and $usePi) {
        $picoComPort = Get-AIFishBotConfigValue -InputObject $Config -Name 'picoComPort'
        $effectiveAvailablePorts = $AvailablePorts
        if (-not $PSBoundParameters.ContainsKey('AvailablePorts')) {
            $effectiveAvailablePorts = @(Get-AIFishBotAvailablePorts)
        }

        if ([string]::IsNullOrWhiteSpace([string]$picoComPort) -or $effectiveAvailablePorts -notcontains [string]$picoComPort) {
            Add-AIFishBotConfigError -Errors $errors -Field 'picoComPort' -Message '必须选择当前可用的Pico串口。'
        }
    }

    $buffValues = Get-AIFishBotConfigValue -InputObject $Config -Name 'buffs'
    if ($null -ne $buffValues) {
        $buffs = @($buffValues)
        for ($index = 0; $index -lt $buffs.Count; $index += 1) {
            $buff = $buffs[$index]
            $enabledField = 'buffs[{0}].enabled' -f $index
            $keybindField = 'buffs[{0}].keybind' -f $index
            $castTimeField = 'buffs[{0}].castTimeSeconds' -f $index
            $durationField = 'buffs[{0}].durationMinutes' -f $index

            $enabled = Get-AIFishBotConfigValue -InputObject $buff -Name 'enabled'
            if ($enabled -isnot [bool]) {
                Add-AIFishBotConfigError -Errors $errors -Field $enabledField -Message '增益启用状态必须是布尔值。'
            }

            $keybind = Get-AIFishBotConfigValue -InputObject $buff -Name 'keybind'
            if (-not (Test-AIFishBotFunctionKey -Value $keybind)) {
                Add-AIFishBotConfigError -Errors $errors -Field $keybindField -Message '增益按键必须是F5到F12。'
            }

            $castTime = Get-AIFishBotConfigValue -InputObject $buff -Name 'castTimeSeconds'
            if (-not (Test-AIFishBotNumber -Value $castTime)) {
                Add-AIFishBotConfigError -Errors $errors -Field $castTimeField -Message '增益施放时间必须是有效数字。'
            }
            elseif ([double]$castTime -lt 1) {
                Add-AIFishBotConfigError -Errors $errors -Field $castTimeField -Message '增益施放时间不得少于1秒。'
            }

            $duration = Get-AIFishBotConfigValue -InputObject $buff -Name 'durationMinutes'
            if (-not (Test-AIFishBotNumber -Value $duration)) {
                Add-AIFishBotConfigError -Errors $errors -Field $durationField -Message '增益持续分钟必须是有效数字。'
            }
            elseif ([double]$duration -le 0) {
                Add-AIFishBotConfigError -Errors $errors -Field $durationField -Message '增益持续分钟必须大于0。'
            }
        }
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = $errors
    }
}

Export-ModuleMember -Function New-AIFishBotDefaultConfig, Test-AIFishBotConfig
