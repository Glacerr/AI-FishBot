Set-StrictMode -Version Latest

$script:AIFishBotRuntimeUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:AIFishBotRuntimeRandom = New-Object System.Random
$script:AIFishBotStatusFields = @(
    'processId',
    'state',
    'hookCount',
    'retryCount',
    'profileName',
    'startedAt',
    'remainingSeconds',
    'lastError',
    'heartbeatAt',
    'configVersion'
)

function Get-AIFishBotRuntimeHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $script:AIFishBotRuntimeUtf8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-AIFishBotRuntimeMutexName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($DirectoryPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar).ToUpperInvariant()
    return 'Local\AIFishBot.Runtime.{0}' -f (Get-AIFishBotRuntimeHash -Text $fullPath)
}

function Invoke-AIFishBotRuntimeLocked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $mutexName = Get-AIFishBotRuntimeMutexName -DirectoryPath $DirectoryPath
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne()
        }
        catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }

        if (-not $ownsMutex) {
            throw 'Unable to acquire the runtime directory lock.'
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

function Test-AIFishBotJsonObjectGraph {
    param(
        [AllowNull()]
        [object]$Value,

        [int]$Depth = 0,

        [System.Collections.ArrayList]$Ancestors = $(New-Object System.Collections.ArrayList)
    )

    if ($Depth -gt 50) {
        throw 'The JSON object graph is deeper than the supported limit.'
    }

    if ($null -eq $Value -or $Value -is [string] -or $Value -is [char] -or
        $Value -is [bool] -or $Value -is [datetime] -or $Value -is [datetimeoffset] -or
        $Value -is [guid] -or $Value -is [timespan] -or $Value -is [enum]) {
        return
    }

    if ($Value -is [double] -and ([double]::IsNaN($Value) -or [double]::IsInfinity($Value))) {
        throw 'JSON does not support non-finite numbers.'
    }
    if ($Value -is [single] -and ([single]::IsNaN($Value) -or [single]::IsInfinity($Value))) {
        throw 'JSON does not support non-finite numbers.'
    }
    if ($Value -is [System.ValueType]) {
        return
    }

    $isDictionary = $Value -is [System.Collections.IDictionary]
    $isEnumerable = $Value -is [System.Collections.IEnumerable]
    $isCustomObject = $Value -is [pscustomobject]
    if (-not ($isDictionary -or $isEnumerable -or $isCustomObject)) {
        return
    }

    foreach ($ancestor in $Ancestors) {
        if ([object]::ReferenceEquals($ancestor, $Value)) {
            throw 'The JSON object graph contains a circular reference.'
        }
    }

    [void]$Ancestors.Add($Value)
    try {
        if ($isDictionary) {
            foreach ($key in $Value.Keys) {
                Test-AIFishBotJsonObjectGraph -Value $Value[$key] -Depth ($Depth + 1) -Ancestors $Ancestors
            }
        }
        elseif ($isEnumerable) {
            foreach ($item in $Value) {
                Test-AIFishBotJsonObjectGraph -Value $item -Depth ($Depth + 1) -Ancestors $Ancestors
            }
        }
        else {
            foreach ($property in $Value.PSObject.Properties) {
                Test-AIFishBotJsonObjectGraph -Value $property.Value -Depth ($Depth + 1) -Ancestors $Ancestors
            }
        }
    }
    finally {
        $Ancestors.RemoveAt($Ancestors.Count - 1)
    }
}

function ConvertTo-AIFishBotJsonText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    Test-AIFishBotJsonObjectGraph -Value $InputObject
    try {
        $json = $InputObject | ConvertTo-Json -Depth 50 -ErrorAction Stop
        [void]($json | ConvertFrom-Json -ErrorAction Stop)
        return [string]$json
    }
    catch {
        throw (New-Object System.IO.InvalidDataException(
                ('The value cannot be represented as JSON: {0}' -f $_.Exception.Message),
                $_.Exception))
    }
}

function Read-AIFishBotJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw (New-Object System.IO.FileNotFoundException('The JSON file was not found.', $fullPath))
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $offset = 0
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $offset = 3
        }
        elseif (($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
                    ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) -or
            ($bytes.Length -ge 4 -and (($bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and
                        $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) -or
                    ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and
                        $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00)))) {
            throw 'The JSON file must use UTF-8 encoding.'
        }

        $json = $script:AIFishBotRuntimeUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
        if ([string]::IsNullOrWhiteSpace($json)) {
            throw 'The JSON file is empty.'
        }
        return ($json | ConvertFrom-Json -ErrorAction Stop)
    }
    catch [System.IO.FileNotFoundException] {
        throw
    }
    catch {
        throw (New-Object System.IO.InvalidDataException(
                ('The JSON file is invalid: {0}' -f $_.Exception.Message),
                $_.Exception))
    }
}

function Write-AIFishBotAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Alias('Value', 'Data')]
        [object]$InputObject,

        [Alias('NoOverwrite')]
        [switch]$CreateNew
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directoryPath = [System.IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($directoryPath) -or
        -not [System.IO.Directory]::Exists($directoryPath)) {
        throw (New-Object System.IO.DirectoryNotFoundException('The JSON target directory does not exist.'))
    }

    $json = ConvertTo-AIFishBotJsonText -InputObject $InputObject
    $temporaryPath = '{0}.{1}.tmp' -f $fullPath, [guid]::NewGuid().ToString('N')

    Invoke-AIFishBotRuntimeLocked -DirectoryPath $directoryPath -ScriptBlock {
        try {
            if ($CreateNew -and [System.IO.File]::Exists($fullPath)) {
                throw (New-Object System.IO.IOException('The JSON target already exists and cannot be overwritten.'))
            }
            if (-not $CreateNew -and [System.IO.File]::Exists($fullPath) -and
                (([System.IO.File]::GetAttributes($fullPath) -band [System.IO.FileAttributes]::ReadOnly) -ne 0)) {
                throw (New-Object System.UnauthorizedAccessException('The JSON target is read-only.'))
            }

            $bytes = $script:AIFishBotRuntimeUtf8.GetBytes($json)
            $stream = New-Object System.IO.FileStream(
                $temporaryPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush($true)
            }
            finally {
                $stream.Dispose()
            }

            $verified = Read-AIFishBotJson -Path $temporaryPath
            if ($CreateNew) {
                [System.IO.File]::Move($temporaryPath, $fullPath)
                $staleBackupPath = $fullPath + '.backup'
                if ([System.IO.File]::Exists($staleBackupPath)) {
                    Remove-Item -LiteralPath $staleBackupPath -Force -ErrorAction SilentlyContinue
                }
            }
            elseif ([System.IO.File]::Exists($fullPath)) {
                [System.IO.File]::Replace($temporaryPath, $fullPath, ($fullPath + '.backup'), $true)
            }
            else {
                [System.IO.File]::Move($temporaryPath, $fullPath)
                $staleBackupPath = $fullPath + '.backup'
                if ([System.IO.File]::Exists($staleBackupPath)) {
                    Remove-Item -LiteralPath $staleBackupPath -Force -ErrorAction SilentlyContinue
                }
            }

            return $verified
        }
        finally {
            if ([System.IO.File]::Exists($temporaryPath)) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function New-AIFishBotRunDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RootPath')]
        [string]$RuntimeRoot,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Alias('Config', 'InitialConfig')]
        [object]$StartConfig,

        [AllowNull()]
        [object]$LiveConfig
    )

    $rootPath = [System.IO.Path]::GetFullPath($RuntimeRoot)
    if (-not [System.IO.Directory]::Exists($rootPath)) {
        [void][System.IO.Directory]::CreateDirectory($rootPath)
    }

    $runPath = $null
    for ($attempt = 0; $attempt -lt 10 -and $null -eq $runPath; $attempt += 1) {
        $name = '{0:yyyyMMdd-HHmmssfff}-{1}-{2}' -f [datetime]::UtcNow, $PID, [guid]::NewGuid().ToString('N')
        $candidate = Join-Path -Path $rootPath -ChildPath $name
        try {
            [void][System.IO.Directory]::CreateDirectory($candidate)
            $runPath = $candidate
        }
        catch [System.IO.IOException] {
            $runPath = $null
        }
    }
    if ($null -eq $runPath) {
        throw 'Unable to create a unique runtime directory.'
    }

    try {
        $startPath = Join-Path -Path $runPath -ChildPath 'start-config.json'
        $livePath = Join-Path -Path $runPath -ChildPath 'live-config.json'
        Write-AIFishBotAtomicJson -Path $startPath -InputObject $StartConfig -CreateNew | Out-Null
        if ($PSBoundParameters.ContainsKey('LiveConfig')) {
            Write-AIFishBotAtomicJson -Path $livePath -InputObject $LiveConfig -CreateNew | Out-Null
        }
        else {
            Write-AIFishBotAtomicJson -Path $livePath -InputObject $StartConfig -CreateNew | Out-Null
        }
        [System.IO.File]::SetAttributes(
            $startPath,
            ([System.IO.File]::GetAttributes($startPath) -bor [System.IO.FileAttributes]::ReadOnly))
        return $runPath
    }
    catch {
        if ($null -ne $runPath -and [System.IO.Directory]::Exists($runPath)) {
            Remove-Item -LiteralPath $runPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Get-AIFishBotProtocolValue {
    param(
        [Parameter(Mandatory = $true)]
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

function Get-AIFishBotRequiredProtocolValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $found = $false
    $value = Get-AIFishBotProtocolValue -InputObject $InputObject -Name $Name -Found ([ref]$found)
    if (-not $found) {
        throw ('The protocol field "{0}" is required.' -f $Name)
    }
    return $value
}

function ConvertTo-AIFishBotDateTimeOffsetText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [switch]$AllowNull
    )

    if ($null -eq $Value) {
        if ($AllowNull) {
            return $null
        }
        throw ('The protocol field "{0}" cannot be null.' -f $FieldName)
    }

    $parsed = [datetimeoffset]::MinValue
    if ($Value -is [datetimeoffset]) {
        $parsed = $Value
    }
    elseif ($Value -is [datetime]) {
        $parsed = [datetimeoffset]$Value
    }
    elseif (-not [datetimeoffset]::TryParse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed)) {
        throw ('The protocol field "{0}" is not a valid timestamp.' -f $FieldName)
    }
    return $parsed.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-AIFishBotStatusObject {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Status
    )

    if ($null -eq $Status) {
        throw 'Status cannot be null.'
    }

    $lastError = Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'lastError'
    if ($null -ne $lastError -and $lastError -isnot [string]) {
        throw 'The protocol field "lastError" must be text or null.'
    }

    $remainingSeconds = Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'remainingSeconds'
    if ($null -ne $remainingSeconds) {
        try {
            $remainingSeconds = [convert]::ToDouble(
                $remainingSeconds,
                [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            throw 'The protocol field "remainingSeconds" must be numeric or null.'
        }
    }

    try {
        return [pscustomobject][ordered]@{
            processId = [convert]::ToInt32((Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'processId'))
            state = [string](Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'state')
            hookCount = [convert]::ToInt32((Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'hookCount'))
            retryCount = [convert]::ToInt32((Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'retryCount'))
            profileName = [string](Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'profileName')
            startedAt = ConvertTo-AIFishBotDateTimeOffsetText `
                -Value (Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'startedAt') `
                -FieldName 'startedAt'
            remainingSeconds = $remainingSeconds
            lastError = $lastError
            heartbeatAt = ConvertTo-AIFishBotDateTimeOffsetText `
                -Value (Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'heartbeatAt') `
                -FieldName 'heartbeatAt' -AllowNull
            configVersion = [convert]::ToInt32((Get-AIFishBotRequiredProtocolValue -InputObject $Status -Name 'configVersion'))
        }
    }
    catch {
        throw (New-Object System.IO.InvalidDataException(
                ('The status object is invalid: {0}' -f $_.Exception.Message),
                $_.Exception))
    }
}

function Write-AIFishBotStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RuntimeDirectory')]
        [string]$RunDirectory,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Status
    )

    $normalized = ConvertTo-AIFishBotStatusObject -Status $Status
    $path = Join-Path -Path ([System.IO.Path]::GetFullPath($RunDirectory)) -ChildPath 'status.json'
    Write-AIFishBotAtomicJson -Path $path -InputObject $normalized
}

function Read-AIFishBotStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RuntimeDirectory')]
        [string]$RunDirectory
    )

    $path = Join-Path -Path ([System.IO.Path]::GetFullPath($RunDirectory)) -ChildPath 'status.json'
    return ConvertTo-AIFishBotStatusObject -Status (Read-AIFishBotJson -Path $path)
}

function ConvertTo-AIFishBotControlObject {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Control
    )

    if ($null -eq $Control) {
        throw 'Control command cannot be null.'
    }
    $command = ([string](Get-AIFishBotRequiredProtocolValue -InputObject $Control -Name 'command')).ToLowerInvariant()
    if ($command -ne 'stop') {
        throw ('Unsupported control command: {0}' -f $command)
    }
    $commandId = [string](Get-AIFishBotRequiredProtocolValue -InputObject $Control -Name 'commandId')
    if ([string]::IsNullOrWhiteSpace($commandId)) {
        throw 'The control command identity cannot be blank.'
    }
    $createdAt = ConvertTo-AIFishBotDateTimeOffsetText `
        -Value (Get-AIFishBotRequiredProtocolValue -InputObject $Control -Name 'createdAt') `
        -FieldName 'createdAt'

    return [pscustomobject][ordered]@{
        command = $command
        commandId = $commandId
        createdAt = $createdAt
    }
}

function Write-AIFishBotControlCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RuntimeDirectory')]
        [string]$RunDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string]$CommandId = $([guid]::NewGuid().ToString('N')),

        [Alias('Now')]
        [datetimeoffset]$CreatedAt = $([datetimeoffset]::UtcNow)
    )

    $control = ConvertTo-AIFishBotControlObject -Control ([pscustomobject][ordered]@{
            command = $Command
            commandId = $CommandId
            createdAt = $CreatedAt
        })
    $path = Join-Path -Path ([System.IO.Path]::GetFullPath($RunDirectory)) -ChildPath 'control.json'
    Write-AIFishBotAtomicJson -Path $path -InputObject $control
}

function Read-AIFishBotControlCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RuntimeDirectory')]
        [string]$RunDirectory,

        [switch]$Consume
    )

    $fullRunDirectory = [System.IO.Path]::GetFullPath($RunDirectory)
    $path = Join-Path -Path $fullRunDirectory -ChildPath 'control.json'
    if (-not $Consume) {
        if (-not [System.IO.File]::Exists($path)) {
            return $null
        }
        return ConvertTo-AIFishBotControlObject -Control (Read-AIFishBotJson -Path $path)
    }

    Invoke-AIFishBotRuntimeLocked -DirectoryPath $fullRunDirectory -ScriptBlock {
        if (-not [System.IO.File]::Exists($path)) {
            return
        }

        $control = ConvertTo-AIFishBotControlObject -Control (Read-AIFishBotJson -Path $path)
        $consumedDirectory = Join-Path -Path $fullRunDirectory -ChildPath '.consumed-commands'
        if (-not [System.IO.Directory]::Exists($consumedDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($consumedDirectory)
        }
        $markerName = '{0}.json' -f (Get-AIFishBotRuntimeHash -Text $control.commandId)
        $markerPath = Join-Path -Path $consumedDirectory -ChildPath $markerName
        if ([System.IO.File]::Exists($markerPath)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            return
        }

        Write-AIFishBotAtomicJson -Path $markerPath -InputObject $control -CreateNew | Out-Null
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $control
    }
}

function Test-AIFishBotHeartbeatFresh {
    [CmdletBinding(DefaultParameterSetName = 'Status')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Status')]
        [AllowNull()]
        [object]$Status,

        [Parameter(Mandatory = $true, ParameterSetName = 'RunDirectory')]
        [string]$RunDirectory,

        [Parameter(Mandatory = $true, ParameterSetName = 'Heartbeat')]
        [AllowNull()]
        [object]$HeartbeatAt,

        [datetimeoffset]$Now = $([datetimeoffset]::UtcNow),

        [Parameter(Mandatory = $true)]
        [double]$MaxAgeSeconds
    )

    if ([double]::IsNaN($MaxAgeSeconds) -or [double]::IsInfinity($MaxAgeSeconds) -or
        $MaxAgeSeconds -lt 0) {
        throw 'MaxAgeSeconds must be a finite non-negative number.'
    }

    $heartbeatValue = $null
    if ($PSCmdlet.ParameterSetName -eq 'RunDirectory') {
        try {
            $runtimeStatus = Read-AIFishBotStatus -RunDirectory $RunDirectory
        }
        catch [System.IO.FileNotFoundException] {
            return $false
        }
        $heartbeatValue = $runtimeStatus.heartbeatAt
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Heartbeat') {
        $heartbeatValue = $HeartbeatAt
    }
    else {
        $found = $false
        $heartbeatValue = Get-AIFishBotProtocolValue -InputObject $Status -Name 'heartbeatAt' -Found ([ref]$found)
        if (-not $found) {
            return $false
        }
    }

    if ($null -eq $heartbeatValue -or [string]::IsNullOrWhiteSpace([string]$heartbeatValue)) {
        return $false
    }
    $parsed = [datetimeoffset]::MinValue
    if ($heartbeatValue -is [datetimeoffset]) {
        $parsed = $heartbeatValue
    }
    elseif ($heartbeatValue -is [datetime]) {
        $parsed = [datetimeoffset]$heartbeatValue
    }
    elseif (-not [datetimeoffset]::TryParse(
            [string]$heartbeatValue,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$parsed)) {
        return $false
    }

    if ($parsed -gt $Now) {
        return $false
    }
    return (($Now - $parsed).TotalSeconds -le $MaxAgeSeconds)
}

function Protect-AIFishBotSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    process {
        if ($null -eq $Text) {
            return $null
        }
        $pattern = 'https://discord\.com/api/webhooks/[A-Za-z0-9_-]+/[A-Za-z0-9._-]+(?:\?[^\s<>"'']*)?'
        return [regex]::Replace(
            $Text,
            $pattern,
            'https://discord.com/api/webhooks/***',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
}

function Write-AIFishBotLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('RuntimeDirectory')]
        [string]$RunDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [datetimeoffset]$Now = $([datetimeoffset]::Now)
    )

    $normalizedLevel = $Level.Trim().ToUpperInvariant()
    if ($normalizedLevel -notin @('DEBUG', 'INFO', 'WARN', 'WARNING', 'ERROR')) {
        throw ('Unsupported log level: {0}' -f $Level)
    }

    $fullRunDirectory = [System.IO.Path]::GetFullPath($RunDirectory)
    if (-not [System.IO.Directory]::Exists($fullRunDirectory)) {
        throw (New-Object System.IO.DirectoryNotFoundException('The runtime directory does not exist.'))
    }
    $logsDirectory = Join-Path -Path $fullRunDirectory -ChildPath 'logs'
    $logPath = Join-Path -Path $logsDirectory -ChildPath ($Now.ToString('yyyy-MM-dd') + '.log')
    $safeMessage = (Protect-AIFishBotSecret -Text $Message) -replace '[\r\n]+', ' '
    $line = '{0} [{1}] {2}{3}' -f `
        $Now.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture),
        $normalizedLevel,
        $safeMessage,
        [Environment]::NewLine

    Invoke-AIFishBotRuntimeLocked -DirectoryPath $fullRunDirectory -ScriptBlock {
        if (-not [System.IO.Directory]::Exists($logsDirectory)) {
            [void][System.IO.Directory]::CreateDirectory($logsDirectory)
        }
        $bytes = $script:AIFishBotRuntimeUtf8.GetBytes($line)
        $stream = New-Object System.IO.FileStream(
            $logPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
    }
    return $logPath
}

function ConvertTo-AIFishBotDelaySeconds {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Value) {
        throw ('{0} must be a non-negative number.' -f $Name)
    }
    try {
        $converted = [convert]::ToDecimal($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw ('{0} must be a non-negative number.' -f $Name)
    }
    if ($converted -lt 0) {
        throw ('{0} must be a non-negative number.' -f $Name)
    }
    return $converted
}

function Get-AIFishBotDelayMilliseconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('MinSeconds')]
        [AllowNull()]
        [object]$MinimumSeconds,

        [Parameter(Mandatory = $true)]
        [Alias('MaxSeconds')]
        [AllowNull()]
        [object]$MaximumSeconds,

        [scriptblock]$RandomIntProvider
    )

    $minimum = ConvertTo-AIFishBotDelaySeconds -Value $MinimumSeconds -Name 'MinimumSeconds'
    $maximum = ConvertTo-AIFishBotDelaySeconds -Value $MaximumSeconds -Name 'MaximumSeconds'
    if ($minimum -gt $maximum) {
        throw 'The minimum delay cannot be greater than the maximum delay.'
    }

    try {
        $minimumMillisecondsDecimal = [math]::Round(
            ($minimum * 1000),
            0,
            [System.MidpointRounding]::AwayFromZero)
        $maximumMillisecondsDecimal = [math]::Round(
            ($maximum * 1000),
            0,
            [System.MidpointRounding]::AwayFromZero)
        if ($minimumMillisecondsDecimal -gt [int]::MaxValue -or
            $maximumMillisecondsDecimal -gt [int]::MaxValue) {
            throw 'Delay milliseconds exceed the supported range.'
        }
        $minimumMilliseconds = [int]$minimumMillisecondsDecimal
        $maximumMilliseconds = [int]$maximumMillisecondsDecimal
    }
    catch {
        throw ('Delay seconds cannot be converted to milliseconds: {0}' -f $_.Exception.Message)
    }

    if ($minimumMilliseconds -eq $maximumMilliseconds) {
        return $minimumMilliseconds
    }

    if ($PSBoundParameters.ContainsKey('RandomIntProvider')) {
        $providerResults = @(& $RandomIntProvider $minimumMilliseconds $maximumMilliseconds)
        if ($providerResults.Count -ne 1 -or $null -eq $providerResults[0]) {
            throw 'The random integer provider must return exactly one whole number.'
        }
        try {
            $providedDecimal = [convert]::ToDecimal(
                $providerResults[0],
                [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            throw 'The random integer provider must return exactly one whole number.'
        }
        if ([decimal]::Truncate($providedDecimal) -ne $providedDecimal) {
            throw 'The random integer provider must return a whole number.'
        }
        if ($providedDecimal -lt $minimumMilliseconds -or $providedDecimal -gt $maximumMilliseconds) {
            throw 'The random integer provider returned a value outside the inclusive range.'
        }
        return [int]$providedDecimal
    }

    if ($maximumMilliseconds -lt [int]::MaxValue) {
        return $script:AIFishBotRuntimeRandom.Next($minimumMilliseconds, $maximumMilliseconds + 1)
    }
    $inclusiveWidth = ([long]$maximumMilliseconds - [long]$minimumMilliseconds) + 1
    return [int]([long]$minimumMilliseconds +
        [long][math]::Floor($script:AIFishBotRuntimeRandom.NextDouble() * $inclusiveWidth))
}

Export-ModuleMember -Function @(
    'New-AIFishBotRunDirectory',
    'Write-AIFishBotAtomicJson',
    'Read-AIFishBotJson',
    'Write-AIFishBotStatus',
    'Read-AIFishBotStatus',
    'Write-AIFishBotControlCommand',
    'Read-AIFishBotControlCommand',
    'Test-AIFishBotHeartbeatFresh',
    'Write-AIFishBotLog',
    'Protect-AIFishBotSecret',
    'Get-AIFishBotDelayMilliseconds'
)
