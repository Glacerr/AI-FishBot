$script:AIFishBotPortProvider = {
    return @([IO.Ports.SerialPort]::GetPortNames())
}

$script:AIFishBotUtf8Encoding = New-Object System.Text.UTF8Encoding($false, $true)

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

    foreach ($booleanField in $booleanFields) {
        $booleanValue = Get-AIFishBotConfigValue -InputObject $Config -Name $booleanField
        if ($booleanValue -isnot [bool]) {
            Add-AIFishBotConfigError -Errors $errors -Field $booleanField -Message '开关值必须是布尔值。'
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
    elseif ([double]$fishingRetries % 1 -ne 0) {
        Add-AIFishBotConfigError -Errors $errors -Field 'fishingRetries' -Message '抛竿重试次数必须是整数。'
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

    $buffProperty = $Config.PSObject.Properties['buffs']
    $buffs = @()
    if ($null -ne $buffProperty) {
        if ($buffProperty.Value -is [System.Array]) {
            $buffs = [object[]]$buffProperty.Value
        }
        elseif ($null -ne $buffProperty.Value) {
            $buffs = @($buffProperty.Value)
        }

        for ($index = 0; $index -lt $buffs.Count; $index += 1) {
            $buff = $buffs[$index]
            if ($null -eq $buff) {
                Add-AIFishBotConfigError -Errors $errors -Field ('buffs[{0}]' -f $index) -Message '增益项不能为空。'
                continue
            }

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

function ConvertTo-AIFishBotProfileName {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ProfileName
    )

    $normalizedName = ([string]$ProfileName).Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw '方案名称不能为空。'
    }

    if ($normalizedName -eq '.' -or $normalizedName -eq '..') {
        throw '方案名称不能是“.”或“..”。'
    }

    if ($normalizedName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $normalizedName.Contains([string][System.IO.Path]::DirectorySeparatorChar) -or
        $normalizedName.Contains([string][System.IO.Path]::AltDirectorySeparatorChar)) {
        throw '方案名称包含Windows文件名不允许使用的字符。'
    }

    if ($normalizedName.EndsWith('.', [System.StringComparison]::Ordinal) -or
        $normalizedName -match '^(?i:CON|PRN|AUX|NUL|COM(?:[1-9]|[¹²³])|LPT(?:[1-9]|[¹²³]))(?:\..*)?$') {
        throw '方案名称不是有效的Windows文件名。'
    }

    return $normalizedName
}

function Get-AIFishBotProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ProfileName
    )

    if ([string]::IsNullOrWhiteSpace($ProfilesDirectory)) {
        throw '方案目录不能为空。'
    }

    $normalizedName = ConvertTo-AIFishBotProfileName -ProfileName $ProfileName
    $directoryPath = [System.IO.Path]::GetFullPath($ProfilesDirectory)
    $profilePath = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine($directoryPath, ('{0}.json' -f $normalizedName)))
    $directoryPrefix = $directoryPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $profilePath.StartsWith($directoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw '方案名称不能指向方案目录之外。'
    }

    return $profilePath
}

function Get-AIFishBotProfilesMutexName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory
    )

    $directoryPath = [System.IO.Path]::GetFullPath($ProfilesDirectory)
    $rootPath = [System.IO.Path]::GetPathRoot($directoryPath)
    if ($directoryPath.Length -gt $rootPath.Length) {
        $directoryPath = $directoryPath.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
    }

    $canonicalPath = $directoryPath.ToUpperInvariant()
    $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $hashAlgorithm.ComputeHash($script:AIFishBotUtf8Encoding.GetBytes($canonicalPath))
    }
    finally {
        $hashAlgorithm.Dispose()
    }

    $hashText = [System.BitConverter]::ToString($hash).Replace('-', '').Substring(0, 32)
    return 'Local\AI-FishBot.Profiles.{0}' -f $hashText
}

function Invoke-AIFishBotProfilesLocked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $mutexName = Get-AIFishBotProfilesMutexName -ProfilesDirectory $ProfilesDirectory
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne()
        }
        catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }

        & $ScriptBlock
    }
    finally {
        if ($ownsMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Get-AIFishBotProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory
    )

    if (-not (Test-Path -LiteralPath $ProfilesDirectory -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $ProfilesDirectory -Filter '*.json' -File |
        ForEach-Object { $_.BaseName } |
        Sort-Object
}

function Get-AIFishBotPersistenceValidation {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Config
    )

    $availablePorts = @()
    if ((Get-AIFishBotConfigValue -InputObject $Config -Name 'usePi') -is [bool] -and
        (Get-AIFishBotConfigValue -InputObject $Config -Name 'usePi')) {
        $selectedPort = [string](Get-AIFishBotConfigValue -InputObject $Config -Name 'picoComPort')
        if (-not [string]::IsNullOrWhiteSpace($selectedPort)) {
            $availablePorts = @($selectedPort)
        }
    }

    return Test-AIFishBotConfig -Config $Config -AvailablePorts $availablePorts
}

function Assert-AIFishBotPersistableConfig {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Config
    )

    $validation = Get-AIFishBotPersistenceValidation -Config $Config
    if ($validation.IsValid) {
        return
    }

    $details = @($validation.Errors.GetEnumerator() |
            Sort-Object -Property Key |
            ForEach-Object { '{0}：{1}' -f $_.Key, $_.Value }) -join '；'
    throw ('方案配置无效：{0}' -f $details)
}

function Assert-AIFishBotObjectGraphNode {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [int]$Depth,

        [Parameter(Mandatory = $true)]
        [int]$MaximumDepth,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Ancestors
    )

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsValueType) {
        return
    }

    if ($Depth -gt $MaximumDepth) {
        throw ('方案配置对象层级超过安全上限（{0}层）。' -f $MaximumDepth)
    }

    foreach ($ancestor in $Ancestors) {
        if ([object]::ReferenceEquals($ancestor, $Value)) {
            throw '方案配置不能包含循环引用。'
        }
    }

    $Ancestors.Add($Value)
    try {
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in @($Value.Keys)) {
                Assert-AIFishBotObjectGraphNode -Value $Value[$key] -Depth ($Depth + 1) -MaximumDepth $MaximumDepth -Ancestors $Ancestors
            }
            return
        }

        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($item in $Value) {
                Assert-AIFishBotObjectGraphNode -Value $item -Depth ($Depth + 1) -MaximumDepth $MaximumDepth -Ancestors $Ancestors
            }
            return
        }

        foreach ($property in $Value.PSObject.Properties) {
            if ($property.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty -or
                $property.MemberType -eq [System.Management.Automation.PSMemberTypes]::Property) {
                Assert-AIFishBotObjectGraphNode -Value $property.Value -Depth ($Depth + 1) -MaximumDepth $MaximumDepth -Ancestors $Ancestors
            }
        }
    }
    finally {
        $Ancestors.RemoveAt($Ancestors.Count - 1)
    }
}

function Assert-AIFishBotObjectGraph {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,

        [int]$MaximumDepth = 20
    )

    $ancestors = New-Object 'System.Collections.Generic.List[object]'
    Assert-AIFishBotObjectGraphNode -Value $Value -Depth 0 -MaximumDepth $MaximumDepth -Ancestors $ancestors
}

function Read-AIFishBotUtf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    if ($bytes.Length -ge 4 -and
        (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) -or
            ($bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF))) {
        $invalidEncodingError = New-Object System.IO.InvalidDataException(
            ('{0}不能使用UTF-32编码，只允许UTF-8。' -f $Description))
        throw $invalidEncodingError
    }

    if ($bytes.Length -ge 2 -and
        (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
            ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        $invalidEncodingError = New-Object System.IO.InvalidDataException(
            ('{0}不能使用UTF-16编码，只允许UTF-8。' -f $Description))
        throw $invalidEncodingError
    }

    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $offset = 3
    }

    try {
        return $script:AIFishBotUtf8Encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch [System.Text.DecoderFallbackException] {
        $invalidEncodingError = New-Object System.IO.InvalidDataException(
            ('{0}不是有效的UTF-8文件。' -f $Description),
            $_.Exception)
        throw $invalidEncodingError
    }
}

function Read-AIFishBotConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedProfileName
    )

    $json = Read-AIFishBotUtf8Text -Path $Path -Description '方案JSON'
    try {
        $config = $json | ConvertFrom-Json -ErrorAction Stop
        Assert-AIFishBotPersistableConfig -Config $config
        $actualProfileName = Get-AIFishBotConfigValue -InputObject $config -Name 'profileName'
        if ($actualProfileName -isnot [string]) {
            throw 'JSON内的方案名称必须是字符串。'
        }
        if (-not [string]::Equals(
                $actualProfileName,
                $ExpectedProfileName,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('JSON内的方案名称“{0}”与文件名“{1}”不一致。' -f $actualProfileName, $ExpectedProfileName)
        }
        return $config
    }
    catch {
        $invalidDataError = New-Object System.IO.InvalidDataException(
            ('方案JSON内容无效：{0}' -f $_.Exception.Message),
            $_.Exception)
        throw $invalidDataError
    }
}

function Restore-AIFishBotProfileBackup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath
    )

    $operationId = [guid]::NewGuid().ToString('N')
    $restorePath = '{0}.{1}.tmp' -f $ProfilePath, $operationId
    $corruptPath = '{0}.{1}.corrupt' -f $ProfilePath, $operationId
    try {
        [System.IO.File]::Copy($BackupPath, $restorePath, $false)
        [System.IO.File]::Replace($restorePath, $ProfilePath, $corruptPath)
    }
    finally {
        if (Test-Path -LiteralPath $restorePath) {
            Remove-Item -LiteralPath $restorePath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $corruptPath) {
            Remove-Item -LiteralPath $corruptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-AIFishBotProfileCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $normalizedName = ConvertTo-AIFishBotProfileName -ProfileName $ProfileName
    $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $normalizedName
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw ('找不到方案“{0}”。' -f $normalizedName)
    }

    try {
        return Read-AIFishBotConfigFile -Path $profilePath -ExpectedProfileName $normalizedName
    }
    catch [System.IO.InvalidDataException] {
        $profileError = $_.Exception.Message
    }

    try {
        return Read-AIFishBotConfigFile -Path $profilePath -ExpectedProfileName $normalizedName
    }
    catch [System.IO.InvalidDataException] {
        $profileError = $_.Exception.Message
    }

    $backupPath = $profilePath + '.backup'
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        try {
            $backupConfig = Read-AIFishBotConfigFile -Path $backupPath -ExpectedProfileName $normalizedName
        }
        catch [System.IO.InvalidDataException] {
            throw ('方案“{0}”已损坏，备份也无法恢复。原错误：{1}' -f $normalizedName, $profileError)
        }

        try {
            Restore-AIFishBotProfileBackup -ProfilePath $profilePath -BackupPath $backupPath
        }
        catch {
            throw ('方案“{0}”的备份有效，但无法写回方案文件：{1}' -f $normalizedName, $_.Exception.Message)
        }
        return $backupConfig
    }

    throw ('方案“{0}”已损坏，且没有可用备份。原错误：{1}' -f $normalizedName, $profileError)
}

function Read-AIFishBotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    Invoke-AIFishBotProfilesLocked -ProfilesDirectory $ProfilesDirectory -ScriptBlock {
        Read-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -ProfileName $ProfileName
    }
}

function Save-AIFishBotProfileCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Config,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ProfileName,

        [switch]$CreateNew
    )

    if ($null -eq $Config) {
        throw '方案配置不能为空。'
    }

    $effectiveName = $ProfileName
    if (-not $PSBoundParameters.ContainsKey('ProfileName')) {
        $effectiveName = [string](Get-AIFishBotConfigValue -InputObject $Config -Name 'profileName')
    }
    $normalizedName = ConvertTo-AIFishBotProfileName -ProfileName $effectiveName

    Assert-AIFishBotObjectGraph -Value $Config -MaximumDepth 20

    try {
        $sourceJson = $Config | ConvertTo-Json -Depth 100 -Compress -ErrorAction Stop
        $workingConfig = $sourceJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ('方案配置无法转换为JSON：{0}' -f $_.Exception.Message)
    }

    if ($null -eq $workingConfig.PSObject.Properties['profileName']) {
        $workingConfig | Add-Member -MemberType NoteProperty -Name 'profileName' -Value $normalizedName
    }
    else {
        $workingConfig.profileName = $normalizedName
    }

    Assert-AIFishBotPersistableConfig -Config $workingConfig

    $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $normalizedName
    $directoryPath = Split-Path -Path $profilePath -Parent
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        New-Item -ItemType Directory -Path $directoryPath -Force -ErrorAction Stop | Out-Null
    }

    if ($CreateNew -and (Test-Path -LiteralPath $profilePath)) {
        throw ('方案“{0}”已存在。' -f $normalizedName)
    }

    $temporaryPath = '{0}.{1}.tmp' -f $profilePath, [guid]::NewGuid().ToString('N')
    try {
        $json = $workingConfig | ConvertTo-Json -Depth 100 -ErrorAction Stop
        [System.IO.File]::WriteAllText($temporaryPath, $json, $script:AIFishBotUtf8Encoding)
        $verifiedConfig = Read-AIFishBotConfigFile -Path $temporaryPath -ExpectedProfileName $normalizedName

        if ($CreateNew) {
            $staleBackupPath = $profilePath + '.backup'
            [System.IO.File]::Move($temporaryPath, $profilePath)
            if (Test-Path -LiteralPath $staleBackupPath -PathType Leaf -ErrorAction SilentlyContinue) {
                Remove-Item -LiteralPath $staleBackupPath -Force -ErrorAction SilentlyContinue
            }
        }
        elseif (Test-Path -LiteralPath $profilePath -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $profilePath, ($profilePath + '.backup'))
        }
        else {
            $staleBackupPath = $profilePath + '.backup'
            [System.IO.File]::Move($temporaryPath, $profilePath)
            if (Test-Path -LiteralPath $staleBackupPath -PathType Leaf -ErrorAction SilentlyContinue) {
                Remove-Item -LiteralPath $staleBackupPath -Force -ErrorAction SilentlyContinue
            }
        }

        return $verifiedConfig
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-AIFishBotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Config,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ProfileName,

        [switch]$CreateNew
    )

    $hasProfileName = $PSBoundParameters.ContainsKey('ProfileName')
    Invoke-AIFishBotProfilesLocked -ProfilesDirectory $ProfilesDirectory -ScriptBlock {
        $parameters = @{
            ProfilesDirectory = $ProfilesDirectory
            Config = $Config
            CreateNew = $CreateNew
        }
        if ($hasProfileName) {
            $parameters.ProfileName = $ProfileName
        }
        Save-AIFishBotProfileCore @parameters
    }
}

function Copy-AIFishBotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [Alias('SourceName')]
        [string]$SourceProfileName,

        [Parameter(Mandatory = $true)]
        [Alias('DestinationName', 'NewProfileName')]
        [string]$DestinationProfileName
    )

    Invoke-AIFishBotProfilesLocked -ProfilesDirectory $ProfilesDirectory -ScriptBlock {
        $destinationName = ConvertTo-AIFishBotProfileName -ProfileName $DestinationProfileName
        $destinationPath = Get-AIFishBotProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $destinationName
        if (Test-Path -LiteralPath $destinationPath) {
            throw ('方案“{0}”已存在。' -f $destinationName)
        }

        $sourceConfig = Read-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -ProfileName $SourceProfileName
        Save-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -Config $sourceConfig -ProfileName $destinationName -CreateNew
    }
}

function Rename-AIFishBotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('OldName', 'OldProfileName')]
        [string]$ProfileName,

        [Parameter(Mandatory = $true)]
        [Alias('NewName', 'DestinationProfileName')]
        [string]$NewProfileName,

        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory
    )

    Invoke-AIFishBotProfilesLocked -ProfilesDirectory $ProfilesDirectory -ScriptBlock {
        $oldName = ConvertTo-AIFishBotProfileName -ProfileName $ProfileName
        $newName = ConvertTo-AIFishBotProfileName -ProfileName $NewProfileName
        $newPath = Get-AIFishBotProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $newName
        if (Test-Path -LiteralPath $newPath) {
            throw ('方案“{0}”已存在。' -f $newName)
        }

        $config = Read-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -ProfileName $oldName
        $savedConfig = Save-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -Config $config -ProfileName $newName -CreateNew
        Remove-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -ProfileName $oldName
        return $savedConfig
    }
}

function Remove-AIFishBotProfileCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $normalizedName = ConvertTo-AIFishBotProfileName -ProfileName $ProfileName
    $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $normalizedName
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw ('找不到方案“{0}”。' -f $normalizedName)
    }

    Remove-Item -LiteralPath $profilePath -Force -ErrorAction Stop
    $backupPath = $profilePath + '.backup'
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
    }
}

function Remove-AIFishBotProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    Invoke-AIFishBotProfilesLocked -ProfilesDirectory $ProfilesDirectory -ScriptBlock {
        Remove-AIFishBotProfileCore -ProfilesDirectory $ProfilesDirectory -ProfileName $ProfileName
    }
}

function Get-AIFishBotLegacyAssignments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw ('找不到旧版配置脚本：{0}' -f $ScriptPath)
    }

    $scriptText = Read-AIFishBotUtf8Text -Path ([System.IO.Path]::GetFullPath($ScriptPath)) -Description '旧版配置脚本'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $scriptText,
        [ref]$tokens,
        [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ('旧版配置脚本无法解析：{0}' -f $parseErrors[0].Message)
    }

    $simpleNames = @(
        'retail', 'autoStop', 'autoStopTime', 'autoLogout', 'audioSensitivity',
        'UseWindowFocus', 'fishingRetries', 'usePi', 'picoComPort', 'useWeakAura',
        'cast', 'bobber', 'logout', 'enableNotifications', 'discordWebhook',
        'onStart', 'onStop'
    )
    $values = @{}
    $enableBuffsText = $null
    $assignments = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst]
        }, $true)

    foreach ($assignment in $assignments) {
        if ($assignment.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
            $assignment.Parent.Parent -ne $ast) {
            continue
        }

        $name = $assignment.Left.VariablePath.UserPath
        if ($name -eq 'enableBuffs') {
            if ($assignment.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals -and
                $null -ne $assignment.Right.Expression) {
                $enableBuffsText = $assignment.Right.Expression.Extent.Text
            }
            else {
                $enableBuffsText = $null
            }
            continue
        }

        if ($simpleNames -notcontains $name -and
            $name -notmatch '^buff(?:Keybind|CastTime|Duration)[0-9]+$') {
            continue
        }

        if ($assignment.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals) {
            [void]$values.Remove($name)
            continue
        }

        $expression = $assignment.Right.Expression
        $isLiteral = $expression -is [System.Management.Automation.Language.ConstantExpressionAst] -or
            $expression -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            ($expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $expression.VariablePath.UserPath -match '^(?i:true|false|null)$')
        if (-not $isLiteral) {
            [void]$values.Remove($name)
            continue
        }

        try {
            $values[$name] = $expression.SafeGetValue()
        }
        catch {
            [void]$values.Remove($name)
            continue
        }
    }

    return [pscustomobject]@{
        Values = $values
        EnableBuffsText = $enableBuffsText
    }
}

function Import-AIFishBotLegacyConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('LegacyScriptPath')]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $normalizedName = ConvertTo-AIFishBotProfileName -ProfileName $ProfileName
    $legacy = Get-AIFishBotLegacyAssignments -ScriptPath $ScriptPath
    $config = New-AIFishBotDefaultConfig
    $config.profileName = $normalizedName

    $fieldMap = [ordered]@{
        retail = 'retail'
        autoStop = 'autoStop'
        autoStopTime = 'autoStopTime'
        autoLogout = 'autoLogout'
        audioSensitivity = 'audioSensitivity'
        UseWindowFocus = 'useWindowFocus'
        fishingRetries = 'fishingRetries'
        usePi = 'usePi'
        picoComPort = 'picoComPort'
        useWeakAura = 'useWeakAura'
        cast = 'castKey'
        bobber = 'bobberKey'
        logout = 'logoutKey'
        enableNotifications = 'enableNotifications'
        discordWebhook = 'discordWebhook'
        onStart = 'notifyOnStart'
        onStop = 'notifyOnStop'
    }
    foreach ($sourceName in $fieldMap.Keys) {
        if ($legacy.Values.ContainsKey($sourceName)) {
            $config.($fieldMap[$sourceName]) = $legacy.Values[$sourceName]
        }
    }

    $enabledMode = 'None'
    $enabledNumber = 0
    $enableText = [string]$legacy.EnableBuffsText
    $rangeMatch = [regex]::Match($enableText, '^\(\s*1\s*\.\.\s*([1-9][0-9]*)\s*\)$')
    $singleMatch = [regex]::Match($enableText, '^\(\s*([1-9][0-9]*)\s*\)$')
    if ($rangeMatch.Success -and [int]::TryParse($rangeMatch.Groups[1].Value, [ref]$enabledNumber)) {
        $enabledMode = 'Range'
    }
    elseif ($singleMatch.Success -and [int]::TryParse($singleMatch.Groups[1].Value, [ref]$enabledNumber)) {
        $enabledMode = 'Single'
    }

    $keybinds = @{}
    $castTimes = @{}
    $durations = @{}
    foreach ($entry in $legacy.Values.GetEnumerator()) {
        if ($entry.Key -match '^buffKeybind([0-9]+)$') {
            $index = 0
            if ([int]::TryParse($Matches[1], [ref]$index) -and $index -gt 0) {
                $keybinds[$index] = $entry.Value
            }
        }
        elseif ($entry.Key -match '^buffCastTime([0-9]+)$') {
            $index = 0
            if ([int]::TryParse($Matches[1], [ref]$index) -and $index -gt 0) {
                $castTimes[$index] = $entry.Value
            }
        }
        elseif ($entry.Key -match '^buffDuration([0-9]+)$') {
            $index = 0
            if ([int]::TryParse($Matches[1], [ref]$index) -and $index -gt 0) {
                $durations[$index] = $entry.Value
            }
        }
    }

    $buffs = @()
    foreach ($index in @($keybinds.Keys | Sort-Object)) {
        if ($index -le 0 -or -not $castTimes.ContainsKey($index) -or -not $durations.ContainsKey($index)) {
            continue
        }

        $isEnabled = ($enabledMode -eq 'Range' -and $index -le $enabledNumber) -or
            ($enabledMode -eq 'Single' -and $index -eq $enabledNumber)
        $buffs += [pscustomobject][ordered]@{
            enabled = [bool]$isEnabled
            name = '增益 {0}' -f $index
            keybind = $keybinds[$index]
            castTimeSeconds = $castTimes[$index]
            durationMinutes = $durations[$index]
        }
    }
    $config.buffs = @($buffs)

    return $config
}

function Initialize-AIFishBotProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilesDirectory,

        [Parameter(Mandatory = $true)]
        [Alias('ScriptPath')]
        [string]$LegacyScriptPath,

        [string]$InitialProfileName = '时光服'
    )

    if (-not (Test-Path -LiteralPath $ProfilesDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $ProfilesDirectory -Force -ErrorAction Stop | Out-Null
    }

    $profiles = @(Get-AIFishBotProfiles -ProfilesDirectory $ProfilesDirectory)
    if ($profiles.Count -eq 0) {
        $config = Import-AIFishBotLegacyConfig -ScriptPath $LegacyScriptPath -ProfileName $InitialProfileName
        Save-AIFishBotProfile -ProfilesDirectory $ProfilesDirectory -Config $config | Out-Null
    }

    Get-AIFishBotProfiles -ProfilesDirectory $ProfilesDirectory
}

Export-ModuleMember -Function @(
    'New-AIFishBotDefaultConfig',
    'Test-AIFishBotConfig',
    'Get-AIFishBotProfilePath',
    'Get-AIFishBotProfiles',
    'Read-AIFishBotProfile',
    'Save-AIFishBotProfile',
    'Copy-AIFishBotProfile',
    'Rename-AIFishBotProfile',
    'Remove-AIFishBotProfile',
    'Initialize-AIFishBotProfiles',
    'Import-AIFishBotLegacyConfig'
)
