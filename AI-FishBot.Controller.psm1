Set-StrictMode -Version Latest

$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot 'AI-FishBot.Config.psm1')
Import-Module (Join-Path $moduleRoot 'AI-FishBot.Runtime.psm1')
Import-Module (Join-Path $moduleRoot 'AI-FishBot.Dependencies.psm1')

$script:AIFishBotFieldMap = [ordered]@{
    retail = 'Retail'
    autoStop = 'AutoStop'
    autoStopTime = 'AutoStopTime'
    autoLogout = 'AutoLogout'
    audioSensitivity = 'AudioSensitivity'
    useWindowFocus = 'UseWindowFocus'
    useWeakAura = 'UseWeakAura'
    fishingRetries = 'FishingRetries'
    castKey = 'CastKey'
    bobberKey = 'BobberKey'
    logoutKey = 'LogoutKey'
    usePi = 'UsePi'
    picoComPort = 'PicoComPort'
    enableNotifications = 'EnableNotifications'
    discordWebhook = 'WebhookText'
    notifyOnStart = 'NotifyOnStart'
    notifyOnStop = 'NotifyOnStop'
    biteResponseMinSeconds = 'BiteResponseMin'
    biteResponseMaxSeconds = 'BiteResponseMax'
    preHookMinSeconds = 'PreHookMin'
    preHookMaxSeconds = 'PreHookMax'
    postHookMinSeconds = 'PostHookMin'
    postHookMaxSeconds = 'PostHookMax'
    preCastMinSeconds = 'PreCastMin'
    preCastMaxSeconds = 'PreCastMax'
}

$script:AIFishBotBooleanFields = @(
    'retail', 'autoStop', 'autoLogout', 'useWindowFocus', 'useWeakAura', 'usePi',
    'enableNotifications', 'notifyOnStart', 'notifyOnStop'
)
$script:AIFishBotNumericFields = @(
    'autoStopTime', 'audioSensitivity', 'fishingRetries', 'biteResponseMinSeconds',
    'biteResponseMaxSeconds', 'preHookMinSeconds', 'preHookMaxSeconds',
    'postHookMinSeconds', 'postHookMaxSeconds', 'preCastMinSeconds', 'preCastMaxSeconds'
)
$script:AIFishBotLockedControls = @(
    'Retail', 'UseWindowFocus', 'UseWeakAura', 'FishingRetries', 'CastKey', 'BobberKey',
    'LogoutKey', 'UsePi', 'PicoComPort', 'WebhookText', 'NotifyOnStart',
    'ProfileSelector', 'RenameProfileButton', 'DeleteProfileButton'
)
$script:AIFishBotLiveFields = @(
    'audioSensitivity', 'autoStop', 'autoStopTime', 'autoLogout',
    'biteResponseMinSeconds', 'biteResponseMaxSeconds', 'preHookMinSeconds',
    'preHookMaxSeconds', 'postHookMinSeconds', 'postHookMaxSeconds',
    'preCastMinSeconds', 'preCastMaxSeconds', 'buffs', 'enableNotifications', 'notifyOnStop'
)
$script:AIFishBotLiveControls = @(
    'AudioSensitivity', 'AutoStop', 'AutoStopTime', 'AutoLogout', 'BiteResponseMin',
    'BiteResponseMax', 'PreHookMin', 'PreHookMax', 'PostHookMin', 'PostHookMax',
    'PreCastMin', 'PreCastMax', 'BuffGrid', 'EnableNotifications', 'NotifyOnStop'
)

function Get-AIFishBotControllerAvailablePorts {
    return @([System.IO.Ports.SerialPort]::GetPortNames())
}

function Get-AIFishBotControllerControl {
    param([Parameter(Mandatory = $true)]$Controller, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Controller.View -or $null -eq $Controller.View.Controls) { return $null }
    if ($Controller.View.Controls -is [System.Collections.IDictionary]) {
        return $Controller.View.Controls[$Name]
    }
    $property = $Controller.View.Controls.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-AIFishBotObjectPropertyValue {
    param([AllowNull()]$InputObject, [string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Set-AIFishBotObjectPropertyValue {
    param([Parameter(Mandatory = $true)]$InputObject, [string]$Name, [AllowNull()]$Value)
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
    else {
        $property.Value = $Value
    }
}

function Copy-AIFishBotControllerObject {
    param([AllowNull()]$InputObject)
    if ($null -eq $InputObject) { return $null }
    return (($InputObject | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json)
}

function Get-AIFishBotControllerMutexName {
    param(
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/').ToUpperInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hash = [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '')
    }
    finally { $sha256.Dispose() }
    return 'Local\AI-FishBot.Controller.{0}.{1}' -f $Scope, $hash
}

function Invoke-AIFishBotControllerMutex {
    param(
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Operation
    )
    $mutex = New-Object System.Threading.Mutex($false, (Get-AIFishBotControllerMutexName -Scope $Scope -Path $Path))
    $ownsMutex = $false
    try {
        try { $ownsMutex = $mutex.WaitOne() }
        catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }
        if (-not $ownsMutex) { throw '无法取得控制器运行锁。' }
        return & $Operation
    }
    finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function ConvertTo-AIFishBotControllerDateTimeOffset {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [datetimeoffset]) { return [datetimeoffset]$Value }
        if ($Value -is [datetime]) { return [datetimeoffset]([datetime]$Value) }
        $parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse(
                [string]$Value,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsed)) {
            return $parsed
        }
    }
    catch { }
    return $null
}

function Test-AIFishBotControllerPathEqual {
    param([AllowNull()][string]$First, [AllowNull()][string]$Second)
    if ([string]::IsNullOrWhiteSpace($First) -or [string]::IsNullOrWhiteSpace($Second)) { return $false }
    try {
        return [string]::Equals(
            [System.IO.Path]::GetFullPath($First),
            [System.IO.Path]::GetFullPath($Second),
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Get-AIFishBotControllerProcessStartTime {
    param([AllowNull()]$Process)
    if ($null -eq $Process) { return $null }
    $property = $Process.PSObject.Properties['StartTime']
    if ($null -eq $property) { return $null }
    return ConvertTo-AIFishBotControllerDateTimeOffset $property.Value
}

function Get-AIFishBotControllerMarkerForRun {
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [int]$ProcessId = 0
    )
    try {
        $marker = Read-AIFishBotJson -Path $Controller.ActiveMarkerPath
        $markerDirectory = [string](Get-AIFishBotObjectPropertyValue $marker 'runDirectory' '')
        $markerPid = [int](Get-AIFishBotObjectPropertyValue $marker 'processId' 0)
        if (-not (Test-AIFishBotControllerPathEqual $markerDirectory $RunDirectory)) { return $null }
        if ($ProcessId -gt 0 -and $markerPid -ne $ProcessId) { return $null }
        return $marker
    }
    catch { return $null }
}

function Test-AIFishBotControllerProcessIdentity {
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)]$Status,
        [AllowNull()]$Marker,
        [AllowNull()]$Process
    )
    $statusPid = [int](Get-AIFishBotObjectPropertyValue $Status 'processId' 0)
    if ($statusPid -ne $ProcessId) {
        return [pscustomobject]@{ Success = $false; Error = '后台状态中的进程编号不匹配。' }
    }
    if ($null -eq $Process) {
        $processes = @(& $Controller.ProcessLookup $ProcessId)
        if ($processes.Count -eq 0 -or $null -eq $processes[-1]) {
            return [pscustomobject]@{ Success = $false; Error = '后台进程已经不存在。' }
        }
        $Process = $processes[-1]
    }
    $actualPid = [int](Get-AIFishBotObjectPropertyValue $Process 'Id' 0)
    if ($actualPid -ne $ProcessId) {
        return [pscustomobject]@{ Success = $false; Error = '查找到的进程编号不匹配。' }
    }
    $actualStart = Get-AIFishBotControllerProcessStartTime $Process
    if ($null -eq $actualStart) {
        return [pscustomobject]@{ Success = $false; Error = '无法核对后台进程的启动时间。' }
    }

    $source = 'Status'
    $expectedStart = $null
    $toleranceSeconds = [double]$Controller.LegacyProcessStartToleranceSeconds
    if ($null -ne $Marker -and $null -ne $Marker.PSObject.Properties['processStartedAt']) {
        $expectedStart = ConvertTo-AIFishBotControllerDateTimeOffset $Marker.processStartedAt
        if ($null -eq $expectedStart) {
            return [pscustomobject]@{ Success = $false; Error = '运行标记中的进程启动时间无效。' }
        }
        $source = 'Marker'
        $toleranceSeconds = [double]$Controller.MarkerProcessStartToleranceSeconds
    }
    else {
        $expectedStart = ConvertTo-AIFishBotControllerDateTimeOffset (Get-AIFishBotObjectPropertyValue $Status 'startedAt' $null)
    }
    if ($null -eq $expectedStart) {
        return [pscustomobject]@{ Success = $false; Error = '后台记录缺少可核对的启动时间。' }
    }
    if ($source -eq 'Status') {
        $lastHeartbeat = ConvertTo-AIFishBotControllerDateTimeOffset `
            (Get-AIFishBotObjectPropertyValue $Status 'heartbeatAt' $null)
        if ($null -eq $lastHeartbeat) {
            return [pscustomobject]@{ Success = $false; Error = '后台记录缺少可核对的最后心跳时间。' }
        }
        if ($actualStart -gt $lastHeartbeat) {
            return [pscustomobject]@{ Success = $false; Error = '进程编号已在最后心跳后被其他进程重复使用。' }
        }
    }
    if ([math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt $toleranceSeconds) {
        return [pscustomobject]@{ Success = $false; Error = '进程编号已被其他进程重复使用。' }
    }
    return [pscustomobject]@{
        Success = $true
        Process = $Process
        ProcessStartedAt = $actualStart
        IdentitySource = $source
    }
}

function Set-AIFishBotControlEnabled {
    param([AllowNull()]$Control, [bool]$Enabled)
    if ($null -ne $Control -and $null -ne $Control.PSObject.Properties['Enabled']) {
        $Control.Enabled = $Enabled
    }
}

function Set-AIFishBotControlError {
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [AllowNull()]$Control,
        [AllowNull()][string]$Message
    )
    if ($null -eq $Control) { return }
    $hasError = -not [string]::IsNullOrWhiteSpace($Message)
    if ($null -ne $Control.PSObject.Properties['HasError']) { $Control.HasError = $hasError }
    if ($null -ne $Control.PSObject.Properties['ErrorText']) { $Control.ErrorText = [string]$Message }
    if ($null -ne $Control.PSObject.Properties['BackColor']) {
        if ($Control.GetType().FullName -like 'System.Windows.Forms.*') {
            $Control.BackColor = if ($hasError) {
                [System.Drawing.Color]::FromArgb(92, 35, 43)
            }
            else {
                [System.Drawing.Color]::FromArgb(16, 43, 64)
            }
        }
        else {
            $Control.BackColor = if ($hasError) { 'red' } else { 'normal' }
        }
    }
    if ($Control.GetType().FullName -eq 'System.Windows.Forms.DataGridView') {
        $Control.Tag = [string]$Message
    }
    $providerProperty = $Controller.View.PSObject.Properties['ErrorProvider']
    if ($null -ne $providerProperty -and
        $providerProperty.Value -is [System.Windows.Forms.ErrorProvider] -and
        $Control -is [System.Windows.Forms.Control]) {
        $providerProperty.Value.SetError($Control, [string]$Message)
    }
}

function Set-AIFishBotSaveState {
    param([Parameter(Mandatory = $true)]$Controller, [bool]$Dirty)
    $Controller.IsDirty = $Dirty
    $label = Get-AIFishBotControllerControl -Controller $Controller -Name 'SaveStateLabel'
    if ($null -ne $label) {
        $label.Text = if ($Dirty) { '未保存' } else { '已保存' }
    }
}

function Get-AIFishBotControlValue {
    param([AllowNull()]$Control, [string]$Kind)
    if ($null -eq $Control) { return $null }
    switch ($Kind) {
        'Boolean' { return [bool]$Control.Checked }
        'Numeric' { return $Control.Value }
        'Selection' {
            if ($null -ne $Control.SelectedItem) { return [string]$Control.SelectedItem }
            return [string]$Control.Text
        }
        default { return [string]$Control.Text }
    }
}

function Set-AIFishBotControlValue {
    param([AllowNull()]$Control, [string]$Kind, [AllowNull()]$Value)
    if ($null -eq $Control) { return }
    switch ($Kind) {
        'Boolean' { $Control.Checked = [bool]$Value }
        'Numeric' { $Control.Value = $Value }
        'Selection' {
            $Control.SelectedItem = [string]$Value
            if ($null -ne $Control.PSObject.Properties['Text']) { $Control.Text = [string]$Value }
        }
        default { $Control.Text = [string]$Value }
    }
}

function Set-AIFishBotProfileItems {
    param([Parameter(Mandatory = $true)]$Controller, [AllowEmptyCollection()][string[]]$Profiles)
    $selector = Get-AIFishBotControllerControl -Controller $Controller -Name 'ProfileSelector'
    if ($null -eq $selector) { return }
    $Controller.SuppressDirty = $true
    try {
        $selector.Items.Clear()
        foreach ($profile in @($Profiles)) { [void]$selector.Items.Add($profile) }
        if (-not [string]::IsNullOrWhiteSpace($Controller.CurrentProfileName) -and
            @($Profiles) -contains $Controller.CurrentProfileName) {
            $selector.SelectedItem = $Controller.CurrentProfileName
        }
    }
    finally { $Controller.SuppressDirty = $false }
}

function Get-AIFishBotBuffsFromGrid {
    param([AllowNull()]$Grid)
    if ($null -eq $Grid) { return @() }
    $buffs = @()
    if ($Grid.GetType().FullName -eq 'System.Windows.Forms.DataGridView') {
        foreach ($row in @($Grid.Rows)) {
            if ($row.IsNewRow) { continue }
            $buffs += [pscustomobject][ordered]@{
                enabled = [bool]$row.Cells['enabled'].Value
                name = [string]$row.Cells['name'].Value
                keybind = [string]$row.Cells['keybind'].Value
                castTimeSeconds = $row.Cells['castTime'].Value
                durationMinutes = $row.Cells['duration'].Value
            }
        }
        return @($buffs)
    }
    foreach ($row in @($Grid.Rows)) {
        $buffs += [pscustomobject][ordered]@{
            enabled = [bool](Get-AIFishBotObjectPropertyValue $row 'enabled' $false)
            name = [string](Get-AIFishBotObjectPropertyValue $row 'name' '')
            keybind = [string](Get-AIFishBotObjectPropertyValue $row 'keybind' '')
            castTimeSeconds = Get-AIFishBotObjectPropertyValue $row 'castTimeSeconds' (Get-AIFishBotObjectPropertyValue $row 'castTime' $null)
            durationMinutes = Get-AIFishBotObjectPropertyValue $row 'durationMinutes' (Get-AIFishBotObjectPropertyValue $row 'duration' $null)
        }
    }
    return @($buffs)
}

function Set-AIFishBotBuffGrid {
    param([AllowNull()]$Grid, [AllowEmptyCollection()][object[]]$Buffs)
    if ($null -eq $Grid) { return }
    if ($Grid.GetType().FullName -eq 'System.Windows.Forms.DataGridView') {
        $Grid.Rows.Clear()
        foreach ($buff in @($Buffs)) {
            $index = $Grid.Rows.Add()
            $Grid.Rows[$index].Cells['enabled'].Value = [bool](Get-AIFishBotObjectPropertyValue $buff 'enabled' $false)
            $Grid.Rows[$index].Cells['name'].Value = [string](Get-AIFishBotObjectPropertyValue $buff 'name' '')
            $Grid.Rows[$index].Cells['keybind'].Value = [string](Get-AIFishBotObjectPropertyValue $buff 'keybind' 'F9')
            $Grid.Rows[$index].Cells['castTime'].Value = Get-AIFishBotObjectPropertyValue $buff 'castTimeSeconds' 1
            $Grid.Rows[$index].Cells['duration'].Value = Get-AIFishBotObjectPropertyValue $buff 'durationMinutes' 10
        }
        return
    }
    $rows = @()
    foreach ($buff in @($Buffs)) {
        $rows += [pscustomobject][ordered]@{
            enabled = [bool](Get-AIFishBotObjectPropertyValue $buff 'enabled' $false)
            name = [string](Get-AIFishBotObjectPropertyValue $buff 'name' '')
            keybind = [string](Get-AIFishBotObjectPropertyValue $buff 'keybind' 'F9')
            castTimeSeconds = Get-AIFishBotObjectPropertyValue $buff 'castTimeSeconds' 1
            durationMinutes = Get-AIFishBotObjectPropertyValue $buff 'durationMinutes' 10
        }
    }
    $Grid.Rows = @($rows)
}

function Set-AIFishBotViewFromConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [Parameter(Mandatory = $true)][AllowNull()]$Config
    )
    if ($null -eq $Config) { throw '配置不能为空。' }
    $Controller.SuppressDirty = $true
    try {
        $portControl = Get-AIFishBotControllerControl -Controller $Controller -Name 'PicoComPort'
        if ($null -ne $portControl -and $null -ne $portControl.PSObject.Properties['Items']) {
            $portControl.Items.Clear()
            foreach ($port in @(& $Controller.AvailablePortsProvider)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$port) -and -not $portControl.Items.Contains([string]$port)) {
                    [void]$portControl.Items.Add([string]$port)
                }
            }
            $savedPort = [string](Get-AIFishBotObjectPropertyValue $Config 'picoComPort' '')
            if (-not [string]::IsNullOrWhiteSpace($savedPort) -and -not $portControl.Items.Contains($savedPort)) {
                [void]$portControl.Items.Add($savedPort)
            }
        }
        foreach ($entry in $script:AIFishBotFieldMap.GetEnumerator()) {
            $control = Get-AIFishBotControllerControl -Controller $Controller -Name $entry.Value
            $value = Get-AIFishBotObjectPropertyValue -InputObject $Config -Name $entry.Key
            $kind = if ($script:AIFishBotBooleanFields -contains $entry.Key) { 'Boolean' }
            elseif ($script:AIFishBotNumericFields -contains $entry.Key) { 'Numeric' }
            elseif ($entry.Key -in @('castKey', 'bobberKey', 'logoutKey', 'picoComPort')) { 'Selection' }
            else { 'Text' }
            Set-AIFishBotControlValue -Control $control -Kind $kind -Value $value
        }
        Set-AIFishBotBuffGrid -Grid (Get-AIFishBotControllerControl $Controller 'BuffGrid') `
            -Buffs @(Get-AIFishBotObjectPropertyValue $Config 'buffs' @())
        $Controller.CurrentProfileName = [string](Get-AIFishBotObjectPropertyValue $Config 'profileName' '')
        $Controller.CurrentConfig = Copy-AIFishBotControllerObject $Config
        $selector = Get-AIFishBotControllerControl $Controller 'ProfileSelector'
        if ($null -ne $selector) { $selector.SelectedItem = $Controller.CurrentProfileName }
        Set-AIFishBotSaveState -Controller $Controller -Dirty $false
    }
    finally { $Controller.SuppressDirty = $false }
    [void](Test-AIFishBotView -Controller $Controller)
}

function Get-AIFishBotConfigFromView {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller)
    $config = New-AIFishBotDefaultConfig
    $profileName = $Controller.CurrentProfileName
    $selector = Get-AIFishBotControllerControl $Controller 'ProfileSelector'
    if ([string]::IsNullOrWhiteSpace($profileName) -and $null -ne $selector.SelectedItem) {
        $profileName = [string]$selector.SelectedItem
    }
    $config.profileName = $profileName
    foreach ($entry in $script:AIFishBotFieldMap.GetEnumerator()) {
        $kind = if ($script:AIFishBotBooleanFields -contains $entry.Key) { 'Boolean' }
        elseif ($script:AIFishBotNumericFields -contains $entry.Key) { 'Numeric' }
        elseif ($entry.Key -in @('castKey', 'bobberKey', 'logoutKey', 'picoComPort')) { 'Selection' }
        else { 'Text' }
        $config.($entry.Key) = Get-AIFishBotControlValue `
            -Control (Get-AIFishBotControllerControl $Controller $entry.Value) -Kind $kind
    }
    $config.buffs = @(Get-AIFishBotBuffsFromGrid (Get-AIFishBotControllerControl $Controller 'BuffGrid'))
    return $config
}

function Test-AIFishBotView {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller)
    $config = Get-AIFishBotConfigFromView -Controller $Controller
    $ports = @(& $Controller.AvailablePortsProvider)
    $result = Test-AIFishBotConfig -Config $config -AvailablePorts $ports
    foreach ($controlName in @($script:AIFishBotFieldMap.Values + 'BuffGrid')) {
        Set-AIFishBotControlError -Controller $Controller `
            -Control (Get-AIFishBotControllerControl $Controller $controlName) -Message ''
    }
    $orderedErrors = @($result.Errors.GetEnumerator() | Sort-Object -Property Key)
    foreach ($errorEntry in $orderedErrors) {
        $controlName = if ([string]$errorEntry.Key -like 'buffs*') { 'BuffGrid' }
        else { $script:AIFishBotFieldMap[$errorEntry.Key] }
        if (-not [string]::IsNullOrWhiteSpace($controlName)) {
            Set-AIFishBotControlError -Controller $Controller `
                -Control (Get-AIFishBotControllerControl $Controller $controlName) `
                -Message ([string]$errorEntry.Value)
        }
    }
    $saveState = Get-AIFishBotControllerControl $Controller 'SaveStateLabel'
    if ($null -ne $saveState) {
        $saveState.Text = if ($orderedErrors.Count -gt 0) {
            '配置错误：{0}' -f [string]$orderedErrors[0].Value
        }
        elseif ($Controller.IsDirty) { '未保存' }
        else { '已保存' }
    }
    $startButton = Get-AIFishBotControllerControl $Controller 'StartStopButton'
    if ($null -ne $startButton) { $startButton.Enabled = $Controller.IsRunning -or $result.IsValid }
    return $result
}

function New-AIFishBotLiveConfig {
    param([Parameter(Mandatory = $true)]$Config, [Parameter(Mandatory = $true)][int]$Version)
    $live = [pscustomobject][ordered]@{ configVersion = $Version }
    foreach ($field in $script:AIFishBotLiveFields) {
        $value = Get-AIFishBotObjectPropertyValue $Config $field
        Set-AIFishBotObjectPropertyValue -InputObject $live -Name $field -Value (Copy-AIFishBotControllerObject $value)
    }
    return $live
}

function Write-AIFishBotControllerLiveConfig {
    param([Parameter(Mandatory = $true)]$Controller, [Parameter(Mandatory = $true)]$Config)
    if (-not $Controller.IsRunning -or [string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) { return $null }
    $validation = Test-AIFishBotConfig -Config $Config -AvailablePorts @(& $Controller.AvailablePortsProvider)
    if (-not $validation.IsValid) { return $null }
    $operation = {
        $livePath = Join-Path $Controller.CurrentRunDirectory 'live-config.json'
        $fileVersion = 0
        if (Test-Path -LiteralPath $livePath -PathType Leaf) {
            $currentLive = Read-AIFishBotJson -Path $livePath
            $fileVersion = [int](Get-AIFishBotObjectPropertyValue $currentLive 'configVersion' 0)
        }
        $nextVersion = [math]::Max($fileVersion, [int]$Controller.ConfigVersion) + 1
        $live = New-AIFishBotLiveConfig -Config $Config -Version $nextVersion
        Write-AIFishBotAtomicJson -Path $livePath -InputObject $live | Out-Null
        $Controller.ConfigVersion = $nextVersion
        return $live
    }
    return Invoke-AIFishBotControllerMutex -Scope 'LiveConfig' -Path $Controller.CurrentRunDirectory -Operation $operation
}

function Set-AIFishBotRunningState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller, [Parameter(Mandatory = $true)][bool]$Running)
    $Controller.IsRunning = $Running
    foreach ($name in $script:AIFishBotLockedControls) {
        Set-AIFishBotControlEnabled (Get-AIFishBotControllerControl $Controller $name) (-not $Running)
    }
    foreach ($name in $script:AIFishBotLiveControls) {
        Set-AIFishBotControlEnabled (Get-AIFishBotControllerControl $Controller $name) $true
    }
    $button = Get-AIFishBotControllerControl $Controller 'StartStopButton'
    if ($null -ne $button) {
        $button.Text = if ($Running) { '停止钓鱼' } else { '开始钓鱼' }
        if ($Running) { $button.Enabled = $true }
    }
    $startItem = Get-AIFishBotTrayItem $Controller 'StartItem'
    $stopItem = Get-AIFishBotTrayItem $Controller 'StopItem'
    if ($null -ne $startItem) { $startItem.Enabled = -not $Running }
    if ($null -ne $stopItem) { $stopItem.Enabled = $Running }
    foreach ($timerName in @('Status', 'Log')) {
        $timerProperty = $Controller.View.Timers.PSObject.Properties[$timerName]
        if ($null -ne $timerProperty -and $null -ne $timerProperty.Value -and
            $null -ne $timerProperty.Value.PSObject.Properties['Enabled']) {
            $timerProperty.Value.Enabled = $Running
        }
    }
    if (-not $Running) { [void](Test-AIFishBotView -Controller $Controller) }
}

function Save-AIFishBotCurrentProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller)
    $config = Get-AIFishBotConfigFromView -Controller $Controller
    $validation = Test-AIFishBotView -Controller $Controller
    if (-not $validation.IsValid) {
        return [pscustomobject]@{ Success = $false; Validation = $validation; Error = '请先修正标红的配置。' }
    }
    try { $saved = Save-AIFishBotProfile -ProfilesDirectory $Controller.ProfilesDirectory -Config $config }
    catch {
        return [pscustomobject]@{
            Success = $false
            ProfileSaved = $false
            LiveConfigSaved = $false
            Error = $_.Exception.Message
        }
    }
    $Controller.CurrentConfig = Copy-AIFishBotControllerObject $saved
    $Controller.CurrentProfileName = [string]$saved.profileName
    if ($Controller.IsRunning) {
        try { [void](Write-AIFishBotControllerLiveConfig $Controller $config) }
        catch {
            return [pscustomobject]@{
                Success = $false
                ProfileSaved = $true
                LiveConfigSaved = $false
                Config = $saved
                Error = ('方案已保存，但后台实时配置写入失败：{0}' -f $_.Exception.Message)
            }
        }
    }
    Set-AIFishBotSaveState -Controller $Controller -Dirty $false
    Set-AIFishBotProfileItems -Controller $Controller -Profiles @(Get-AIFishBotProfiles $Controller.ProfilesDirectory)
    return [pscustomobject]@{
        Success = $true
        ProfileSaved = $true
        LiveConfigSaved = $true
        Config = $saved
    }
}

function Get-AIFishBotDependencyAvailable {
    param([AllowNull()]$Result)
    if ($null -eq $Result) { return $false }
    $available = Get-AIFishBotObjectPropertyValue $Result 'IsAvailable' $null
    if ($available -is [bool]) { return $available }
    $status = [string](Get-AIFishBotObjectPropertyValue $Result 'Status' '')
    return $status -in @('Available', 'Ready', 'Installed')
}

function Get-AIFishBotRunCandidate {
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [Parameter(Mandatory = $true)][string]$RunDirectory
    )
    try {
        $fullPath = [System.IO.Path]::GetFullPath($RunDirectory)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) { return $null }
        $start = Read-AIFishBotJson -Path (Join-Path $fullPath 'start-config.json')
        $live = Read-AIFishBotJson -Path (Join-Path $fullPath 'live-config.json')
        $mergedConfig = Copy-AIFishBotControllerObject $start
        foreach ($field in $script:AIFishBotLiveFields) {
            $property = $live.PSObject.Properties[$field]
            if ($null -ne $property) { Set-AIFishBotObjectPropertyValue $mergedConfig $field $property.Value }
        }
        $validation = Test-AIFishBotConfig -Config $mergedConfig -AvailablePorts @(& $Controller.AvailablePortsProvider)
        if (-not $validation.IsValid) { return $null }
        $status = & $Controller.StatusReader $fullPath
        $state = [string](Get-AIFishBotObjectPropertyValue $status 'state' '')
        $pidValue = [int](Get-AIFishBotObjectPropertyValue $status 'processId' 0)
        if ($pidValue -le 0 -or $state -in @('stopped', 'error')) { return $null }
        $marker = Get-AIFishBotControllerMarkerForRun -Controller $Controller -RunDirectory $fullPath -ProcessId $pidValue
        $identity = Test-AIFishBotControllerProcessIdentity -Controller $Controller -ProcessId $pidValue `
            -Status $status -Marker $marker -Process $null
        if (-not $identity.Success) { return $null }
        return [pscustomobject]@{
            RunDirectory = $fullPath
            Pid = $pidValue
            Status = $status
            StartConfig = $start
            LiveConfig = $live
            MergedConfig = $mergedConfig
            ProcessStartedAt = $identity.ProcessStartedAt
            IdentitySource = $identity.IdentitySource
        }
    }
    catch { return $null }
}

function Get-AIFishBotActiveRun {
    param([Parameter(Mandatory = $true)]$Controller)
    if (-not (Test-Path -LiteralPath $Controller.RuntimeRoot -PathType Container)) { return $null }
    foreach ($directory in @(Get-ChildItem -LiteralPath $Controller.RuntimeRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)) {
        $candidate = Get-AIFishBotRunCandidate -Controller $Controller -RunDirectory $directory.FullName
        if ($null -ne $candidate) { return $candidate }
    }
    return $null
}

function Get-AIFishBotStartReservation {
    param([Parameter(Mandatory = $true)]$Controller)
    try {
        $marker = Read-AIFishBotJson -Path $Controller.ActiveMarkerPath
        $runDirectory = [string](Get-AIFishBotObjectPropertyValue $marker 'runDirectory' '')
        $pidValue = [int](Get-AIFishBotObjectPropertyValue $marker 'processId' 0)
        $expectedStart = ConvertTo-AIFishBotControllerDateTimeOffset `
            (Get-AIFishBotObjectPropertyValue $marker 'processStartedAt' $null)
        if ([string]::IsNullOrWhiteSpace($runDirectory) -or $pidValue -le 0 -or $null -eq $expectedStart) { return $null }
        if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) { return $null }
        $processes = @(& $Controller.ProcessLookup $pidValue)
        if ($processes.Count -eq 0 -or $null -eq $processes[-1]) { return $null }
        $process = $processes[-1]
        if ([int](Get-AIFishBotObjectPropertyValue $process 'Id' 0) -ne $pidValue) { return $null }
        $actualStart = Get-AIFishBotControllerProcessStartTime $process
        if ($null -eq $actualStart -or
            [math]::Abs(($actualStart - $expectedStart).TotalSeconds) -gt $Controller.MarkerProcessStartToleranceSeconds) {
            return $null
        }
        return [pscustomobject]@{ RunDirectory = [System.IO.Path]::GetFullPath($runDirectory); Pid = $pidValue }
    }
    catch { return $null }
}

function ConvertTo-AIFishBotQuotedArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"{0}"' -f ($Value -replace '"', '\"')
}

function Write-AIFishBotActiveMarker {
    param([Parameter(Mandatory = $true)]$Controller)
    if (-not (Test-Path -LiteralPath $Controller.RuntimeRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $Controller.RuntimeRoot -Force | Out-Null
    }
    Write-AIFishBotAtomicJson -Path $Controller.ActiveMarkerPath -InputObject ([pscustomobject][ordered]@{
            runDirectory = $Controller.CurrentRunDirectory
            processId = $Controller.CurrentProcessId
            processStartedAt = $Controller.CurrentProcessStartedAt
        }) | Out-Null
}

function Clear-AIFishBotActiveMarker {
    param([Parameter(Mandatory = $true)]$Controller)
    if (Test-Path -LiteralPath $Controller.ActiveMarkerPath -PathType Leaf) {
        Remove-Item -LiteralPath $Controller.ActiveMarkerPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AIFishBotDependencyInstall {
    param([Parameter(Mandatory = $true)]$Controller)

    $button = Get-AIFishBotControllerControl $Controller 'InstallAudioButton'
    if ($null -ne $button) { $button.Enabled = $false }
    try {
        $outputs = @(& $Controller.DependencyInstaller)
        if ($outputs.Count -ne 1 -or $null -eq $outputs[0]) {
            throw '声音组件安装没有返回有效结果。'
        }
        $result = $outputs[0]
    }
    catch {
        $result = [pscustomobject]@{
            Success = $false
            Summary = '声音组件安装失败。'
            Details = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $button) { $button.Enabled = $true }
    }

    $Controller.LastDependencyInstallResult = $result
    if ($null -ne $button -and $null -ne $result.PSObject.Properties['Summary'] -and
        -not [string]::IsNullOrWhiteSpace([string]$result.Summary)) {
        $button.Text = [string]$result.Summary
    }
    return $result
}

function Clear-AIFishBotViewLog {
    param([Parameter(Mandatory = $true)]$Controller)

    try { [void](Read-AIFishBotControllerLogDelta -Controller $Controller) }
    catch { }
    $Controller.RawLogHistory = ''
    $Controller.LastLogSourceLength = 0
    $Controller.LastLogSourceTail = ''
    $logBox = Get-AIFishBotControllerControl $Controller 'LogBox'
    if ($null -ne $logBox) { $logBox.Text = '' }
}

function Open-AIFishBotLogDirectory {
    param([Parameter(Mandatory = $true)]$Controller)

    $basePath = if ([string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) {
        $Controller.DataRoot
    }
    else { $Controller.CurrentRunDirectory }
    $logsPath = [IO.Path]::GetFullPath((Join-Path $basePath 'logs'))
    if (-not [IO.Directory]::Exists($logsPath)) {
        [void][IO.Directory]::CreateDirectory($logsPath)
    }
    & $Controller.LogOpener $logsPath | Out-Null
    return $logsPath
}

function Start-AIFishBotRun {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller)
    if ($Controller.IsRunning) {
        return [pscustomobject]@{
            Success = $false; AlreadyRunning = $true
            RunDirectory = $Controller.CurrentRunDirectory; Pid = $Controller.CurrentProcessId
        }
    }
    $config = Get-AIFishBotConfigFromView -Controller $Controller
    $validation = Test-AIFishBotView -Controller $Controller
    if (-not $validation.IsValid) {
        return [pscustomobject]@{ Success = $false; Validation = $validation; Error = '请先修正标红的配置。' }
    }
    $saved = Save-AIFishBotCurrentProfile -Controller $Controller
    if (-not $saved.Success) { return $saved }
    $dependency = & $Controller.DependencyChecker
    if (-not (Get-AIFishBotDependencyAvailable $dependency)) {
        return [pscustomobject]@{ Success = $false; RequiresDependencyInstall = $true; Dependency = $dependency }
    }
    $operation = {
        if ($Controller.IsRunning) {
            return [pscustomobject]@{
                Success = $false; AlreadyRunning = $true
                RunDirectory = $Controller.CurrentRunDirectory; Pid = $Controller.CurrentProcessId
            }
        }
        $active = Get-AIFishBotActiveRun -Controller $Controller
        if ($null -eq $active) { $active = Get-AIFishBotStartReservation -Controller $Controller }
        if ($null -ne $active) {
            return [pscustomobject]@{
                Success = $false; AlreadyRunning = $true
                RunDirectory = $active.RunDirectory; Pid = $active.Pid
            }
        }

        $runDirectory = $null
        $processStarted = $false
        $processId = 0
        $postStartStage = ''
        try {
            $version = 1
            $startSnapshot = Copy-AIFishBotControllerObject $config
            Set-AIFishBotObjectPropertyValue $startSnapshot 'configVersion' $version
            $liveSnapshot = New-AIFishBotLiveConfig -Config $config -Version $version
            $runDirectory = New-AIFishBotRunDirectory -RuntimeRoot $Controller.RuntimeRoot `
                -StartConfig $startSnapshot -LiveConfig $liveSnapshot
            $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File {0} -RunDirectory {1}' -f `
                (ConvertTo-AIFishBotQuotedArgument $Controller.EngineScriptPath),
                (ConvertTo-AIFishBotQuotedArgument $runDirectory)
            if ($Controller.Simulation) { $arguments += ' -Simulation' }
            $request = [pscustomobject][ordered]@{
                FilePath = $powershellPath
                Arguments = $arguments
                ArgumentList = $arguments
                WindowStyle = 'Hidden'
                EngineScriptPath = $Controller.EngineScriptPath
                RunDirectory = $runDirectory
            }
            $processOutput = @(& $Controller.ProcessStarter $request)
            if ($processOutput.Count -eq 0 -or $null -eq $processOutput[-1]) { throw '后台进程没有返回进程编号。' }
            $process = $processOutput[-1]
            $processId = [int](Get-AIFishBotObjectPropertyValue $process 'Id' 0)
            if ($processId -le 0) { throw '后台进程返回了无效的进程编号。' }
            $processStarted = $true
            $processStart = Get-AIFishBotControllerProcessStartTime $process
            if ($null -eq $processStart) {
                $lookedUp = @(& $Controller.ProcessLookup $processId)
                if ($lookedUp.Count -gt 0 -and $null -ne $lookedUp[-1]) {
                    $processStart = Get-AIFishBotControllerProcessStartTime $lookedUp[-1]
                }
            }
            if ($null -eq $processStart) { throw '后台进程没有提供可核对的启动时间。' }
            $Controller.CurrentRunDirectory = $runDirectory
            $Controller.CurrentProcessId = $processId
            $Controller.CurrentProcessStartedAt = $processStart.ToString('o')
            $Controller.ConfigVersion = $version
            $postStartStage = 'View'
            Set-AIFishBotRunningState -Controller $Controller -Running $true | Out-Null
            $postStartStage = 'Marker'
            Write-AIFishBotActiveMarker -Controller $Controller
            return [pscustomobject]@{ Success = $true; RunDirectory = $runDirectory; Pid = $processId }
        }
        catch {
            if ($processStarted) {
                $Controller.CurrentRunDirectory = $runDirectory
                $Controller.CurrentProcessId = $processId
                $Controller.ConfigVersion = 1
                $Controller.IsRunning = $true
                return [pscustomobject]@{
                    Success = $true
                    RunDirectory = $runDirectory
                    Pid = $processId
                    MarkerWriteFailed = ($postStartStage -eq 'Marker')
                    RecoveryStateWriteFailed = $true
                    Warning = $_.Exception.Message
                }
            }
            if ($null -ne $runDirectory -and (Test-Path -LiteralPath $runDirectory)) {
                Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
            $Controller.CurrentRunDirectory = $null
            $Controller.CurrentProcessId = 0
            $Controller.CurrentProcessStartedAt = $null
            Set-AIFishBotRunningState -Controller $Controller -Running $false | Out-Null
            return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message }
        }
    }
    return Invoke-AIFishBotControllerMutex -Scope 'Start' -Path $Controller.DataRoot -Operation $operation
}

function Stop-AIFishBotRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [ValidateRange(0, 3600)][double]$TimeoutSeconds = 10
    )
    if (-not $Controller.IsRunning -or [string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) {
        return [pscustomobject]@{ Success = $true; AlreadyStopped = $true }
    }
    $runDirectory = $Controller.CurrentRunDirectory
    $pidValue = $Controller.CurrentProcessId
    try { Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command 'stop' | Out-Null }
    catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; Pid = $pidValue } }
    $deadline = (& $Controller.Clock).AddSeconds($TimeoutSeconds)
    do {
        try {
            $status = & $Controller.StatusReader $runDirectory
            if ([string](Get-AIFishBotObjectPropertyValue $status 'state' '') -eq 'stopped') {
                Set-AIFishBotRunningState -Controller $Controller -Running $false | Out-Null
                Clear-AIFishBotActiveMarker $Controller
                $Controller.CurrentRunDirectory = $null
                $Controller.CurrentProcessId = 0
                Update-AIFishBotViewStatus -Controller $Controller -Status $status | Out-Null
                return [pscustomobject]@{ Success = $true; Pid = $pidValue }
            }
        }
        catch { }
        if ((& $Controller.Clock) -ge $deadline) { break }
        & $Controller.Sleeper $Controller.PollIntervalMilliseconds
    } while ($true)
    return [pscustomobject]@{
        Success = $false
        RequiresForceConfirmation = $true
        Pid = $pidValue
        RunDirectory = $runDirectory
    }
}

function Request-AIFishBotRunStop {
    param([Parameter(Mandatory = $true)]$Controller)
    if (-not $Controller.IsRunning -or [string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) {
        return [pscustomobject]@{ Success = $true; AlreadyStopped = $true }
    }
    if ($Controller.StopPending) {
        return [pscustomobject]@{ Success = $true; Pending = $true; Pid = $Controller.CurrentProcessId }
    }
    try { Write-AIFishBotControlCommand -RunDirectory $Controller.CurrentRunDirectory -Command 'stop' | Out-Null }
    catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; Pid = $Controller.CurrentProcessId } }
    $Controller.StopStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Controller.StopDeadlineMilliseconds = [double]$Controller.StopTimeoutSeconds * 1000.0
    $Controller.StopPending = $true
    return [pscustomobject]@{
        Success = $true
        Pending = $true
        Pid = $Controller.CurrentProcessId
        RunDirectory = $Controller.CurrentRunDirectory
    }
}

function Complete-AIFishBotPendingExit {
    param([Parameter(Mandatory = $true)]$Controller)
    if (-not $Controller.ExitAfterStop) { return }
    $Controller.ExitAfterStop = $false
    $Controller.Exiting = $true
    $Controller.View.Exit()
}

function Update-AIFishBotStopPoll {
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [AllowNull()]$Status
    )
    if ($null -ne $Status) {
        $state = [string](Get-AIFishBotObjectPropertyValue $Status 'state' '')
        if ($state -in @('stopped', 'error')) {
            Update-AIFishBotViewStatus -Controller $Controller -Status $Status | Out-Null
            Complete-AIFishBotPendingExit -Controller $Controller
            return
        }
        Update-AIFishBotViewStatus -Controller $Controller -Status $Status | Out-Null
    }
    if (-not $Controller.StopPending -or $null -eq $Controller.StopStopwatch) { return }
    if ($Controller.StopStopwatch.Elapsed.TotalMilliseconds -lt $Controller.StopDeadlineMilliseconds) { return }

    $Controller.StopPending = $false
    $Controller.StopStopwatch.Stop()
    $Controller.StopStopwatch = $null
    if (& $Controller.ConfirmProvider 'ForceStop') {
        $result = $Controller.ForceStop()
        if ($result.Success) { Complete-AIFishBotPendingExit -Controller $Controller }
        else { $Controller.ExitAfterStop = $false }
    }
    else { $Controller.ExitAfterStop = $false }
}

function Clear-AIFishBotStaleRun {
    param([Parameter(Mandatory = $true)]$Controller)
    Clear-AIFishBotActiveMarker $Controller
    $Controller.CurrentRunDirectory = $null
    $Controller.CurrentProcessId = 0
    $Controller.CurrentProcessStartedAt = $null
    $Controller.ConfigVersion = 0
    $Controller.StopPending = $false
    if ($null -ne $Controller.StopStopwatch) { $Controller.StopStopwatch.Stop() }
    $Controller.StopStopwatch = $null
    Set-AIFishBotRunningState -Controller $Controller -Running $false | Out-Null
}

function Resume-AIFishBotRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [string]$RunDirectory
    )
    if ($Controller.IsRunning) {
        return [pscustomobject]@{
            Success = $true
            AlreadyRunning = $true
            RunDirectory = $Controller.CurrentRunDirectory
            Pid = $Controller.CurrentProcessId
        }
    }
    $allowFallback = -not $PSBoundParameters.ContainsKey('RunDirectory')
    $candidatePaths = New-Object System.Collections.ArrayList
    if ($allowFallback) {
        if (Test-Path -LiteralPath $Controller.RuntimeRoot -PathType Container) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $Controller.RuntimeRoot -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc -Descending)) {
                [void]$candidatePaths.Add($directory.FullName)
            }
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($RunDirectory)) {
        [void]$candidatePaths.Add($RunDirectory)
    }

    $seen = @{}
    foreach ($candidatePath in @($candidatePaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidatePath)) { continue }
        try { $key = [System.IO.Path]::GetFullPath([string]$candidatePath).ToUpperInvariant() }
        catch { continue }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $candidate = Get-AIFishBotRunCandidate -Controller $Controller -RunDirectory ([string]$candidatePath)
        if ($null -eq $candidate) { continue }

        try {
            $start = Copy-AIFishBotControllerObject $candidate.MergedConfig
            $live = $candidate.LiveConfig
            Set-AIFishBotViewFromConfig -Controller $Controller -Config $start | Out-Null
            $Controller.CurrentRunDirectory = $candidate.RunDirectory
            $Controller.CurrentProcessId = $candidate.Pid
            $Controller.CurrentProcessStartedAt = $candidate.ProcessStartedAt.ToString('o')
            $Controller.ConfigVersion = [int](Get-AIFishBotObjectPropertyValue $live 'configVersion' `
                    (Get-AIFishBotObjectPropertyValue $candidate.Status 'configVersion' 0))
            Set-AIFishBotRunningState -Controller $Controller -Running $true | Out-Null
            $markerWriteError = $null
            try { Write-AIFishBotActiveMarker $Controller }
            catch { $markerWriteError = $_.Exception.Message }
            Update-AIFishBotViewStatus -Controller $Controller -Status $candidate.Status | Out-Null
            return [pscustomobject]@{
                Success = $true
                RunDirectory = $Controller.CurrentRunDirectory
                Pid = $candidate.Pid
                MarkerWriteFailed = ($null -ne $markerWriteError)
                Warning = $markerWriteError
            }
        }
        catch {
            Clear-AIFishBotStaleRun $Controller
            if (-not $allowFallback) {
                return [pscustomobject]@{ Success = $false; IsStale = $true; Error = $_.Exception.Message }
            }
        }
    }
    Clear-AIFishBotStaleRun $Controller
    return [pscustomobject]@{ Success = $false; IsStale = $true; Error = '没有可恢复的后台运行。' }
}

function Get-AIFishBotTrayItem {
    param([Parameter(Mandatory = $true)]$Controller, [Parameter(Mandatory = $true)][string]$Name)
    $menu = $Controller.View.TrayMenu
    if ($null -ne $menu.PSObject.Properties['ByName']) { return $menu.ByName[$Name] }
    foreach ($item in @($menu.Items)) { if ([string]$item.Name -eq $Name) { return $item } }
    return $null
}

function Update-AIFishBotViewStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Controller, [Parameter(Mandatory = $true)][AllowNull()]$Status)
    $state = [string](Get-AIFishBotObjectPropertyValue $Status 'state' 'stopped')
    if ($Controller.IsRunning -and $state -in @('stopped', 'error')) {
        Clear-AIFishBotStaleRun -Controller $Controller
    }
    $labels = @{
        starting = '正在启动'; ready = '运行中'; casting = '正在抛竿';
        'waiting-for-bite' = '等待咬钩'; hooking = '正在提竿'; stopping = '正在停止';
        stopped = '已停止'; error = '出错'
    }
    $heartbeatFresh = Test-AIFishBotHeartbeatFresh -Status $Status -Now (& $Controller.Clock) `
        -MaxAgeSeconds $Controller.HeartbeatMaxAgeSeconds
    $label = if ($Controller.IsRunning -and $state -notin @('stopped', 'error') -and
        -not $heartbeatFresh) {
        '后台暂时未响应'
    }
    elseif ($labels.ContainsKey($state)) { $labels[$state] }
    else { '未知状态' }
    $badge = Get-AIFishBotControllerControl $Controller 'StatusBadge'
    if ($null -ne $badge) { $badge.Text = '● {0}' -f $label }
    $hook = Get-AIFishBotControllerControl $Controller 'HookCount'
    if ($null -ne $hook) { $hook.Text = '已上钩：{0}' -f [int](Get-AIFishBotObjectPropertyValue $Status 'hookCount' 0) }
    $remainingControl = Get-AIFishBotControllerControl $Controller 'RemainingTime'
    if ($null -ne $remainingControl) {
        $remainingValue = Get-AIFishBotObjectPropertyValue $Status 'remainingSeconds' $null
        if ($null -eq $remainingValue) { $remainingControl.Text = '剩余：--:--' }
        else {
            $seconds = [math]::Max(0, [int][math]::Ceiling([double]$remainingValue))
            $hours = [math]::Floor($seconds / 3600)
            if ($hours -gt 0) { $remainingControl.Text = '剩余：{0:00}:{1:00}:{2:00}' -f $hours, ([math]::Floor(($seconds % 3600) / 60)), ($seconds % 60) }
            else { $remainingControl.Text = '剩余：{0:00}:{1:00}' -f ([math]::Floor($seconds / 60)), ($seconds % 60) }
        }
    }
    $peakControl = Get-AIFishBotControllerControl $Controller 'AudioPeakBar'
    $peak = [int](Get-AIFishBotObjectPropertyValue $Status 'audioPeak' 0)
    if ($null -ne $peakControl) { $peakControl.Value = [math]::Max(0, [math]::Min(100, $peak)) }
    $statusItem = Get-AIFishBotTrayItem $Controller 'StatusItem'
    if ($null -ne $statusItem) { $statusItem.Text = '状态：{0}' -f $label }
    $Controller.LastStatus = $Status
    return $label
}

function Read-AIFishBotControllerLogDelta {
    param([Parameter(Mandatory = $true)]$Controller)
    if ([string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) { return '' }
    $logsDirectory = Join-Path $Controller.CurrentRunDirectory 'logs'
    $file = Get-ChildItem -LiteralPath $logsDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -eq $file) { return '' }

    $fullPath = $file.FullName
    $sameFile = [string]::Equals(
        $Controller.LastLogPath,
        $fullPath,
        [System.StringComparison]::OrdinalIgnoreCase)
    $share = [System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $stream = New-Object System.IO.FileStream(
        $fullPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        $share)
    try {
        $signatureMatches = $true
        if ($sameFile -and $Controller.LastLogFileOffset -gt 0 -and
            -not [string]::IsNullOrWhiteSpace($Controller.LastLogByteSignature)) {
            $expectedBytes = [System.Convert]::FromBase64String($Controller.LastLogByteSignature)
            $signatureStart = $Controller.LastLogFileOffset - $expectedBytes.Length
            if ($signatureStart -lt 0 -or $stream.Length -lt $Controller.LastLogFileOffset) {
                $signatureMatches = $false
            }
            else {
                [void]$stream.Seek($signatureStart, [System.IO.SeekOrigin]::Begin)
                $actualBytes = New-Object byte[] $expectedBytes.Length
                $actualCount = $stream.Read($actualBytes, 0, $actualBytes.Length)
                $signatureMatches = $actualCount -eq $expectedBytes.Length -and
                    [System.Convert]::ToBase64String($actualBytes) -ceq $Controller.LastLogByteSignature
            }
        }
        $reset = -not $sameFile -or $stream.Length -lt $Controller.LastLogFileOffset -or -not $signatureMatches
        if ($reset -or $null -eq $Controller.LastLogDecoder) {
            $Controller.LastLogDecoder = (New-Object System.Text.UTF8Encoding($false, $true)).GetDecoder()
            $Controller.LastLogByteSignature = ''
        }
        $offset = if ($reset) { 0L } else { [long]$Controller.LastLogFileOffset }
        [void]$stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
        $builder = New-Object System.Text.StringBuilder
        $buffer = New-Object byte[] 4096
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $characters = New-Object char[] ($read + 2)
            $characterCount = $Controller.LastLogDecoder.GetChars(
                $buffer, 0, $read, $characters, 0, $false)
            if ($characterCount -gt 0) { [void]$builder.Append($characters, 0, $characterCount) }
        }
        $delta = $builder.ToString()
        if ($reset -and $offset -eq 0 -and $delta.Length -gt 0 -and
            $delta.StartsWith([string][char]0xFEFF, [System.StringComparison]::Ordinal)) {
            $delta = $delta.Substring(1)
        }
        $Controller.LastLogPath = $fullPath
        $Controller.LastLogFileOffset = $stream.Position
        $signatureLength = [int][math]::Min(256, $Controller.LastLogFileOffset)
        if ($signatureLength -gt 0) {
            [void]$stream.Seek($Controller.LastLogFileOffset - $signatureLength, [System.IO.SeekOrigin]::Begin)
            $signature = New-Object byte[] $signatureLength
            $signatureRead = $stream.Read($signature, 0, $signature.Length)
            if ($signatureRead -eq $signatureLength) {
                $Controller.LastLogByteSignature = [System.Convert]::ToBase64String($signature)
            }
            else { $Controller.LastLogByteSignature = '' }
        }
        else { $Controller.LastLogByteSignature = '' }
        return $delta
    }
    finally {
        $stream.Dispose()
    }
}

function Update-AIFishBotViewLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Controller,
        [AllowNull()][string]$Content,
        [ValidateRange(1, 10000)][int]$MaximumLines = 500
    )
    $contentIsDelta = -not $PSBoundParameters.ContainsKey('Content')
    if ($contentIsDelta) { $Content = Read-AIFishBotControllerLogDelta -Controller $Controller }
    if ($null -eq $Content) { $Content = '' }
    if ($contentIsDelta) {
        $newText = $Content
    }
    else {
        $sameSource = $false
        if ($Content.Length -ge $Controller.LastLogSourceLength) {
            $tailLength = [math]::Min($Controller.LastLogSourceTail.Length, $Controller.LastLogSourceLength)
            if ($tailLength -eq 0) { $sameSource = ($Controller.LastLogSourceLength -eq 0) }
            else {
                $tailStart = $Controller.LastLogSourceLength - $tailLength
                $sameSource = $Content.Substring($tailStart, $tailLength) -ceq $Controller.LastLogSourceTail
            }
        }
        $newText = if ($sameSource) { $Content.Substring($Controller.LastLogSourceLength) } else { $Content }
        $Controller.LastLogSourceLength = $Content.Length
        $rememberLength = [math]::Min(512, $Content.Length)
        $Controller.LastLogSourceTail = if ($rememberLength -eq 0) { '' } else { $Content.Substring($Content.Length - $rememberLength) }
    }
    $Controller.RawLogHistory += $newText
    $logBox = Get-AIFishBotControllerControl $Controller 'LogBox'
    $normalizedRaw = $Controller.RawLogHistory -replace "`r`n", "`n" -replace "`r", "`n"
    $endedWithNewline = $normalizedRaw.EndsWith("`n")
    $lines = @($normalizedRaw -split "`n")
    if ($lines.Count -gt 0 -and $lines[-1] -eq '' -and $normalizedRaw.EndsWith("`n")) {
        if ($lines.Count -eq 1) { $lines = @() }
        else { $lines = @($lines[0..($lines.Count - 2)]) }
    }
    if ($lines.Count -gt $MaximumLines) { $lines = @($lines[($lines.Count - $MaximumLines)..($lines.Count - 1)]) }
    $Controller.RawLogHistory = ($lines -join "`n") + $(if ($endedWithNewline -and $lines.Count -gt 0) { "`n" } else { '' })
    if ($Controller.RawLogHistory.Length -gt 1048576) {
        $cutAt = $Controller.RawLogHistory.Length - 1048576
        $nextLine = $Controller.RawLogHistory.IndexOf("`n", $cutAt)
        if ($nextLine -ge 0) {
            $Controller.RawLogHistory = $Controller.RawLogHistory.Substring($nextLine + 1)
        }
        else {
            $Controller.RawLogHistory = '[日志行过长，已省略]'
        }
    }
    $safeText = Protect-AIFishBotSecret -Text $Controller.RawLogHistory
    $partialWebhookPattern = '(?<prefix>https:(?:\\/|/){2}(?:(?:canary|ptb)\.)?discord(?:app)?\.com(?::[0-9]{1,5})?' +
        '(?:\\/|/)api(?:(?:\\/|/)v[0-9]+)?(?:\\/|/)webhooks(?:\\/|/))[^\s<>"'']*'
    $safeText = [regex]::Replace(
        $safeText,
        $partialWebhookPattern,
        '${prefix}***',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($null -eq $logBox) { return $safeText }
    $displayText = $safeText -replace "`r`n", "`n" -replace "`r", "`n"
    if ($displayText.EndsWith("`n")) { $displayText = $displayText.Substring(0, $displayText.Length - 1) }
    $logLevelControl = Get-AIFishBotControllerControl $Controller 'LogLevel'
    $selectedLogLevel = if ($null -eq $logLevelControl) { '全部' } else { [string]$logLevelControl.SelectedItem }
    $levelPattern = switch ($selectedLogLevel) {
        '信息' { '\[INFO\]' }
        '警告' { '\[(?:WARN|WARNING)\]' }
        '错误' { '\[ERROR\]' }
        default { $null }
    }
    if ($null -ne $levelPattern -and -not [string]::IsNullOrEmpty($displayText)) {
        $displayText = @($displayText -split "`n" | Where-Object { $_ -match $levelPattern }) -join "`n"
    }
    $logBox.Text = $displayText -replace "`n", [Environment]::NewLine
    if ($null -ne $logBox.PSObject.Properties['SelectionStart'] -and
        $null -ne $logBox.PSObject.Properties['TextLength']) {
        $logBox.SelectionStart = $logBox.TextLength
    }
    return $safeText
}

function Add-AIFishBotEventHandler {
    param(
        [AllowNull()]$Target,
        [Parameter(Mandatory = $true)][string]$EventName,
        [Parameter(Mandatory = $true)][scriptblock]$Handler,
        [AllowNull()]$Binding
    )
    if ($null -eq $Target) { return }
    $method = $Target.PSObject.Methods['Add_' + $EventName]
    if ($null -ne $method) {
        $method.Invoke($Handler) | Out-Null
        if ($null -ne $Binding) {
            [void]$Binding.Entries.Add([pscustomobject]@{
                    Target = $Target
                    EventName = $EventName
                    Handler = $Handler
                })
        }
    }
}

function New-AIFishBotControllerBinding {
    param([Parameter(Mandatory = $true)]$View)
    $binding = [pscustomobject]@{
        View = $View
        Entries = New-Object System.Collections.ArrayList
        Disposed = $false
    }
    $binding | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        if ($this.Disposed) { return }
        $this.Disposed = $true
        for ($index = $this.Entries.Count - 1; $index -ge 0; $index -= 1) {
            $entry = $this.Entries[$index]
            $method = $entry.Target.PSObject.Methods['Remove_' + $entry.EventName]
            if ($null -ne $method) {
                try { $method.Invoke($entry.Handler) | Out-Null } catch { }
            }
        }
        $this.Entries.Clear()
        $property = $this.View.PSObject.Properties['_ControllerBinding']
        if ($null -ne $property -and [object]::ReferenceEquals($property.Value, $this)) {
            $property.Value = $null
        }
    }
    return $binding
}

function Invoke-AIFishBotControllerViewChanged {
    param([Parameter(Mandatory = $true)]$Controller, [string]$ControlName)
    if ($Controller.SuppressDirty) { return }
    $Controller.MarkDirty()
    [void](Test-AIFishBotView -Controller $Controller)
}

function Open-AIFishBotView {
    param([Parameter(Mandatory = $true)]$Controller)
    [void]$Controller.View.Form.Show()
    try { $Controller.View.Form.WindowState = [System.Windows.Forms.FormWindowState]::Normal }
    catch { $Controller.View.Form.WindowState = 'Normal' }
    $Controller.View.TrayIcon.Visible = $false
    [void]$Controller.View.Form.Activate()
}

function Invoke-AIFishBotExit {
    param([Parameter(Mandatory = $true)]$Controller)
    if ($Controller.IsRunning) {
        $choice = & $Controller.ConfirmExitProvider $true
        if ([string]$choice -notin @('Stop', '停止') -and $choice -ne $true) {
            $Controller.Exiting = $true
            $Controller.View.Exit()
            return [pscustomobject]@{ Success = $true; ContinuedInBackground = $true }
        }
        $Controller.ExitAfterStop = $true
        $requested = $Controller.BeginStop()
        if (-not $requested.Success) {
            $Controller.ExitAfterStop = $false
            return $requested
        }
        return [pscustomobject]@{ Success = $true; Pending = $true }
    }
    $Controller.Exiting = $true
    $Controller.View.Exit()
    return [pscustomobject]@{ Success = $true }
}

function Bind-AIFishBotControllerEvents {
    param([Parameter(Mandatory = $true)]$Controller)
    $viewBindingProperty = $Controller.View.PSObject.Properties['_ControllerBinding']
    if ($null -ne $viewBindingProperty -and $null -ne $viewBindingProperty.Value) {
        $viewBindingProperty.Value.Dispose()
    }
    $binding = New-AIFishBotControllerBinding -View $Controller.View
    if ($null -eq $viewBindingProperty) {
        $Controller.View | Add-Member -MemberType NoteProperty -Name '_ControllerBinding' -Value $binding
    }
    else { $viewBindingProperty.Value = $binding }
    foreach ($entry in $script:AIFishBotFieldMap.GetEnumerator()) {
        $controlName = $entry.Value
        $control = Get-AIFishBotControllerControl $Controller $controlName
        $eventName = if ($entry.Key -in $script:AIFishBotBooleanFields) { 'CheckedChanged' }
        elseif ($entry.Key -in $script:AIFishBotNumericFields) { 'ValueChanged' }
        elseif ($entry.Key -in @('castKey', 'bobberKey', 'logoutKey', 'picoComPort')) { 'SelectedIndexChanged' }
        else { 'TextChanged' }
        Add-AIFishBotEventHandler $control $eventName ({ $Controller.HandleViewChanged($controlName) }.GetNewClosure()) -Binding $binding
    }
    $grid = Get-AIFishBotControllerControl $Controller 'BuffGrid'
    foreach ($eventName in @('CellValueChanged', 'RowsAdded', 'RowsRemoved')) {
        Add-AIFishBotEventHandler $grid $eventName ({ $Controller.HandleViewChanged('BuffGrid') }.GetNewClosure()) -Binding $binding
    }
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'SaveButton') 'Click' ({ Save-AIFishBotCurrentProfile $Controller | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'StartStopButton') 'Click' ({
            if ($Controller.IsRunning) { $Controller.BeginStop() | Out-Null }
            else { Start-AIFishBotRun $Controller | Out-Null }
        }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'NewProfileButton') 'Click' ({ $Controller.NewProfile() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'CopyProfileButton') 'Click' ({ $Controller.CopyProfile() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'RenameProfileButton') 'Click' ({ $Controller.RenameProfile() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'DeleteProfileButton') 'Click' ({ $Controller.DeleteProfile() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'InstallAudioButton') 'Click' ({ $Controller.InstallAudio() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'ClearLogButton') 'Click' ({ $Controller.ClearLog() }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'OpenLogButton') 'Click' ({ $Controller.OpenLog() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'LogLevel') 'SelectedIndexChanged' ({ Update-AIFishBotViewLog $Controller -Content '' | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotControllerControl $Controller 'ProfileSelector') 'SelectedIndexChanged' ({
            if (-not $Controller.SuppressDirty) {
                $selected = [string](Get-AIFishBotControllerControl $Controller 'ProfileSelector').SelectedItem
                if (-not [string]::IsNullOrWhiteSpace($selected) -and $selected -ne $Controller.CurrentProfileName) { $Controller.SwitchProfile($selected) | Out-Null }
            }
        }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotTrayItem $Controller 'OpenItem') 'Click' ({ $Controller.OpenView() }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler $Controller.View.TrayIcon 'DoubleClick' ({ $Controller.OpenView() }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotTrayItem $Controller 'StartItem') 'Click' ({ Start-AIFishBotRun $Controller | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotTrayItem $Controller 'StopItem') 'Click' ({ $Controller.BeginStop() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler (Get-AIFishBotTrayItem $Controller 'ExitItem') 'Click' ({ $Controller.ExitApplication() | Out-Null }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler $Controller.View.Form 'Resize' ({
            if ([string]$Controller.View.Form.WindowState -like '*Minimized*') {
                $Controller.View.Form.Hide(); $Controller.View.TrayIcon.Visible = $true
            }
        }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler $Controller.View.Form 'FormClosing' ({
            param($sender, $eventArgs)
            if (-not $Controller.Exiting -and $null -ne $eventArgs -and
                [string]$eventArgs.CloseReason -eq 'UserClosing') {
                if ($null -ne $eventArgs -and $null -ne $eventArgs.PSObject.Properties['Cancel']) { $eventArgs.Cancel = $true }
                $Controller.View.Form.Hide(); $Controller.View.TrayIcon.Visible = $true
            }
        }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler $Controller.View.Timers.Status 'Tick' ({
            if ($Controller.IsRunning -and -not [string]::IsNullOrWhiteSpace($Controller.CurrentRunDirectory)) {
                $status = $null
                try { $status = & $Controller.StatusReader $Controller.CurrentRunDirectory } catch { }
                if ($Controller.StopPending) { $Controller.HandleStatusTick($status) }
                elseif ($null -ne $status) { Update-AIFishBotViewStatus $Controller $status | Out-Null }
            }
        }.GetNewClosure()) -Binding $binding
    Add-AIFishBotEventHandler $Controller.View.Timers.Log 'Tick' ({ Update-AIFishBotViewLog $Controller | Out-Null }.GetNewClosure()) -Binding $binding
    return $binding
}

function New-AIFishBotController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$View,
        [Parameter(Mandatory = $true)][string]$ProfilesDirectory,
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [string]$EngineScriptPath = (Join-Path $PSScriptRoot 'AI-FishBot.Engine.ps1'),
        [scriptblock]$DependencyChecker = { Test-AIFishBotAudioDependency },
        [scriptblock]$DependencyInstaller = { Install-AIFishBotAudioDependency },
        [scriptblock]$LogOpener = {
            param($Path)
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f ($Path -replace '"', '\"'))
        },
        [scriptblock]$ProcessStarter = {
            param($Request)
            Start-Process -FilePath $Request.FilePath -ArgumentList $Request.ArgumentList -WindowStyle Hidden -PassThru
        },
        [scriptblock]$ProcessLookup = { param($ProcessId) Get-Process -Id $ProcessId -ErrorAction SilentlyContinue },
        [scriptblock]$StatusReader = { param($RunDirectory) Read-AIFishBotStatus -RunDirectory $RunDirectory },
        [scriptblock]$Clock = { [datetimeoffset]::UtcNow },
        [scriptblock]$Sleeper = { param($Milliseconds) Start-Sleep -Milliseconds $Milliseconds },
        [scriptblock]$ConfirmProvider = { param($Purpose) $false },
        [scriptblock]$ConfirmExitProvider = { param($Running) 'Continue' },
        [scriptblock]$ProfileNameProvider = { param($Action, $CurrentName, $SuggestedName) $SuggestedName },
        [scriptblock]$ForceStopper = { param($ProcessId) Stop-Process -Id $ProcessId -Force -ErrorAction Stop },
        [scriptblock]$AvailablePortsProvider = { Get-AIFishBotControllerAvailablePorts },
        [ValidateRange(0.1, 3600)][double]$HeartbeatMaxAgeSeconds = 5,
        [ValidateRange(1, 60000)][int]$PollIntervalMilliseconds = 100,
        [ValidateRange(0, 3600)][double]$StopTimeoutSeconds = 10,
        [switch]$Simulation
    )
    $profilesPath = [System.IO.Path]::GetFullPath($ProfilesDirectory)
    $runtimePath = [System.IO.Path]::GetFullPath($RuntimeRoot)
    $dataRoot = [System.IO.Path]::GetDirectoryName($runtimePath.TrimEnd('\', '/'))
    if ([string]::IsNullOrWhiteSpace($dataRoot)) { $dataRoot = $runtimePath }
    $controller = [pscustomobject]@{
        View = $View
        ProfilesDirectory = $profilesPath
        RuntimeRoot = $runtimePath
        DataRoot = $dataRoot
        ActiveMarkerPath = (Join-Path $runtimePath 'active-run.json')
        EngineScriptPath = [System.IO.Path]::GetFullPath($EngineScriptPath)
        DependencyChecker = $DependencyChecker
        DependencyInstaller = $DependencyInstaller
        LogOpener = $LogOpener
        ProcessStarter = $ProcessStarter
        ProcessLookup = $ProcessLookup
        StatusReader = $StatusReader
        Clock = $Clock
        Sleeper = $Sleeper
        ConfirmProvider = $ConfirmProvider
        ConfirmExitProvider = $ConfirmExitProvider
        ProfileNameProvider = $ProfileNameProvider
        ForceStopper = $ForceStopper
        AvailablePortsProvider = $AvailablePortsProvider
        HeartbeatMaxAgeSeconds = $HeartbeatMaxAgeSeconds
        PollIntervalMilliseconds = $PollIntervalMilliseconds
        StopTimeoutSeconds = $StopTimeoutSeconds
        Simulation = [bool]$Simulation
        MarkerProcessStartToleranceSeconds = 2.0
        LegacyProcessStartToleranceSeconds = 30.0
        CurrentProfileName = ''
        CurrentConfig = $null
        CurrentRunDirectory = $null
        CurrentProcessId = 0
        CurrentProcessStartedAt = $null
        ConfigVersion = 0
        IsRunning = $false
        IsDirty = $false
        SuppressDirty = $false
        Exiting = $false
        ExitAfterStop = $false
        StopPending = $false
        StopStopwatch = $null
        StopDeadlineMilliseconds = 0.0
        LastStatus = $null
        LastLogSourceLength = 0
        LastLogSourceTail = ''
        LastLogPath = ''
        LastLogFileOffset = 0L
        LastLogDecoder = $null
        LastLogByteSignature = ''
        RawLogHistory = ''
        Binding = $null
        LastDependencyInstallResult = $null
    }
    $controller | Add-Member -MemberType ScriptMethod -Name MarkDirty -Value {
        if (-not $this.SuppressDirty) { Set-AIFishBotSaveState -Controller $this -Dirty $true }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name HandleViewChanged -Value {
        param([string]$ControlName)
        Invoke-AIFishBotControllerViewChanged -Controller $this -ControlName $ControlName
    }
    $controller | Add-Member -MemberType ScriptMethod -Name OpenView -Value {
        Open-AIFishBotView -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name InstallAudio -Value {
        Invoke-AIFishBotDependencyInstall -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name ClearLog -Value {
        Clear-AIFishBotViewLog -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name OpenLog -Value {
        Open-AIFishBotLogDirectory -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name ExitApplication -Value {
        Invoke-AIFishBotExit -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name RequestStop -Value {
        $result = Stop-AIFishBotRun -Controller $this
        if (-not $result.Success -and
            (Get-AIFishBotObjectPropertyValue $result 'RequiresForceConfirmation' $false) -and
            (& $this.ConfirmProvider 'ForceStop')) {
            return $this.ForceStop()
        }
        return $result
    }
    $controller | Add-Member -MemberType ScriptMethod -Name BeginStop -Value {
        return Request-AIFishBotRunStop -Controller $this
    }
    $controller | Add-Member -MemberType ScriptMethod -Name HandleStatusTick -Value {
        param($Status)
        Update-AIFishBotStopPoll -Controller $this -Status $Status
    }
    $controller | Add-Member -MemberType ScriptMethod -Name SwitchProfile -Value {
        param([string]$ProfileName)
        if ($this.IsRunning) { return [pscustomobject]@{ Success = $false; Error = '运行中不能切换方案。' } }
        if ($this.IsDirty -and -not (& $this.ConfirmProvider 'SwitchProfile')) {
            Set-AIFishBotProfileItems $this @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            return [pscustomobject]@{ Success = $false; Cancelled = $true }
        }
        try {
            $config = Read-AIFishBotProfile $this.ProfilesDirectory $ProfileName
            Set-AIFishBotViewFromConfig $this $config | Out-Null
            Set-AIFishBotProfileItems $this @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            return [pscustomobject]@{ Success = $true; Config = $config }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message } }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name NewProfile -Value {
        if ($this.IsRunning) { return [pscustomobject]@{ Success = $false; Error = '运行中不能新建方案。' } }
        if ($this.IsDirty -and -not (& $this.ConfirmProvider 'SwitchProfile')) {
            return [pscustomobject]@{ Success = $false; Cancelled = $true }
        }
        try {
            $suggested = '新方案'
            $name = [string](& $this.ProfileNameProvider 'New' $this.CurrentProfileName $suggested)
            if ([string]::IsNullOrWhiteSpace($name)) { return [pscustomobject]@{ Success = $false; Cancelled = $true } }
            $config = New-AIFishBotDefaultConfig
            $config.profileName = $name.Trim()
            $saved = Save-AIFishBotProfile $this.ProfilesDirectory $config -CreateNew
            Set-AIFishBotViewFromConfig $this $saved | Out-Null
            Set-AIFishBotProfileItems $this @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            return [pscustomobject]@{ Success = $true; Config = $saved }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message } }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name CopyProfile -Value {
        if ($this.IsRunning) { return [pscustomobject]@{ Success = $false; Error = '运行中不能复制方案。' } }
        if ($this.IsDirty -and -not (& $this.ConfirmProvider 'SwitchProfile')) {
            return [pscustomobject]@{ Success = $false; Cancelled = $true }
        }
        try {
            $profiles = @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            $base = '{0} - 副本' -f $this.CurrentProfileName
            $suggested = $base
            $number = 2
            while ($profiles -contains $suggested) { $suggested = '{0} ({1})' -f $base, $number; $number += 1 }
            $name = [string](& $this.ProfileNameProvider 'Copy' $this.CurrentProfileName $suggested)
            if ([string]::IsNullOrWhiteSpace($name)) { return [pscustomobject]@{ Success = $false; Cancelled = $true } }
            $saved = Copy-AIFishBotProfile $this.ProfilesDirectory $this.CurrentProfileName $name
            Set-AIFishBotViewFromConfig $this $saved | Out-Null
            Set-AIFishBotProfileItems $this @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            return [pscustomobject]@{ Success = $true; Config = $saved }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message } }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name RenameProfile -Value {
        if ($this.IsRunning) { return [pscustomobject]@{ Success = $false; Error = '运行中不能重命名方案。' } }
        try {
            $name = [string](& $this.ProfileNameProvider 'Rename' $this.CurrentProfileName $this.CurrentProfileName)
            if ([string]::IsNullOrWhiteSpace($name)) { return [pscustomobject]@{ Success = $false; Cancelled = $true } }
            $saved = Rename-AIFishBotProfile $this.ProfilesDirectory $this.CurrentProfileName $name
            Set-AIFishBotViewFromConfig $this $saved | Out-Null
            Set-AIFishBotProfileItems $this @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            return [pscustomobject]@{ Success = $true; Config = $saved }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message } }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name DeleteProfile -Value {
        if ($this.IsRunning) { return [pscustomobject]@{ Success = $false; Error = '运行中不能删除方案。' } }
        if (-not (& $this.ConfirmProvider 'DeleteProfile')) { return [pscustomobject]@{ Success = $false; Cancelled = $true } }
        try {
            Remove-AIFishBotProfile $this.ProfilesDirectory $this.CurrentProfileName
            $profiles = @(Get-AIFishBotProfiles $this.ProfilesDirectory)
            if ($profiles.Count -gt 0) {
                $config = Read-AIFishBotProfile $this.ProfilesDirectory $profiles[0]
                Set-AIFishBotViewFromConfig $this $config | Out-Null
                Set-AIFishBotProfileItems $this $profiles
                return [pscustomobject]@{ Success = $true; Config = $config }
            }
            $config = New-AIFishBotDefaultConfig
            $saved = Save-AIFishBotProfile $this.ProfilesDirectory $config -CreateNew
            Set-AIFishBotViewFromConfig $this $saved | Out-Null
            Set-AIFishBotProfileItems $this @($saved.profileName)
            return [pscustomobject]@{ Success = $true; Config = $saved }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message } }
    }
    $controller | Add-Member -MemberType ScriptMethod -Name ForceStop -Value {
        if ($this.CurrentProcessId -le 0) { return [pscustomobject]@{ Success = $false; Error = '没有可强制停止的进程。' } }
        try {
            $pidValue = $this.CurrentProcessId
            if ([string]::IsNullOrWhiteSpace($this.CurrentRunDirectory)) { throw '没有可核对的后台运行目录。' }
            $status = & $this.StatusReader $this.CurrentRunDirectory
            $marker = Get-AIFishBotControllerMarkerForRun -Controller $this `
                -RunDirectory $this.CurrentRunDirectory -ProcessId $pidValue
            $trackedStart = ConvertTo-AIFishBotControllerDateTimeOffset $this.CurrentProcessStartedAt
            if ($null -ne $trackedStart -and $null -ne $marker -and
                $null -ne $marker.PSObject.Properties['processStartedAt']) {
                $markerStart = ConvertTo-AIFishBotControllerDateTimeOffset $marker.processStartedAt
                if ($null -eq $markerStart -or
                    [math]::Abs(($markerStart - $trackedStart).TotalSeconds) -gt $this.MarkerProcessStartToleranceSeconds) {
                    throw '运行标记中的进程启动时间已经改变。'
                }
            }
            $identity = Test-AIFishBotControllerProcessIdentity -Controller $this -ProcessId $pidValue `
                -Status $status -Marker $marker -Process $null
            if (-not $identity.Success) { throw $identity.Error }
            if ($null -ne $trackedStart -and
                [math]::Abs(($identity.ProcessStartedAt - $trackedStart).TotalSeconds) -gt $this.MarkerProcessStartToleranceSeconds) {
                throw '当前进程的启动时间与已跟踪运行不匹配。'
            }
            & $this.ForceStopper $pidValue
            Clear-AIFishBotStaleRun $this
            return [pscustomobject]@{ Success = $true; Pid = $pidValue }
        }
        catch { return [pscustomobject]@{ Success = $false; Error = $_.Exception.Message; Pid = $this.CurrentProcessId } }
    }

    $controller | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        if ($null -ne $this.Binding) {
            $this.Binding.Dispose()
            $this.Binding = $null
        }
    }

    $controller.Binding = Bind-AIFishBotControllerEvents $controller
    Set-AIFishBotProfileItems $controller @(Get-AIFishBotProfiles $profilesPath)
    Set-AIFishBotRunningState $controller $false | Out-Null
    return $controller
}

Export-ModuleMember -Function @(
    'New-AIFishBotController',
    'Set-AIFishBotViewFromConfig',
    'Get-AIFishBotConfigFromView',
    'Test-AIFishBotView',
    'Set-AIFishBotRunningState',
    'Save-AIFishBotCurrentProfile',
    'Start-AIFishBotRun',
    'Stop-AIFishBotRun',
    'Resume-AIFishBotRun',
    'Update-AIFishBotViewStatus',
    'Update-AIFishBotViewLog'
)
