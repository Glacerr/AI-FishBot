$script:AIFishBotAdaptersRoot = $PSScriptRoot
Import-Module -Name (Join-Path -Path $script:AIFishBotAdaptersRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
    -ErrorAction Stop

function Invoke-AIFishBotAdapterObjectMember {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object[]]$ArgumentList = @()
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property -and $property.Value -is [scriptblock]) {
        return & $property.Value @ArgumentList
    }
    if ($null -ne $property -and $property.Value -is [System.Delegate]) {
        return $property.Value.DynamicInvoke($ArgumentList)
    }
    $method = $Object.PSObject.Methods[$Name]
    if ($null -ne $method) {
        return $method.Invoke($ArgumentList)
    }
    throw ('Adapter dependency does not provide {0}.' -f $Name)
}

function Write-AIFishBotAdapterLogSafely {
    param(
        [AllowNull()]
        [scriptblock]$LogProvider,

        [Parameter(Mandatory = $true)]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($null -eq $LogProvider) {
        return
    }
    try {
        & $LogProvider $Level $Message | Out-Null
    }
    catch {
    }
}

function Test-AIFishBotAdapterFunctionKey {
    param([AllowNull()][object]$Key)

    return $null -ne $Key -and ([string]$Key -cmatch '^F(?:[5-9]|1[0-2])$')
}

function ConvertTo-AIFishBotAudioPeak {
    param([AllowNull()][object[]]$Values)

    $found = $false
    $maximum = [double]0
    foreach ($value in @($Values)) {
        $candidate = $null
        $isNumeric = $value -is [sbyte] -or $value -is [byte] -or
            $value -is [int16] -or $value -is [uint16] -or
            $value -is [int32] -or $value -is [uint32] -or
            $value -is [int64] -or $value -is [uint64] -or
            $value -is [single] -or $value -is [double] -or $value -is [decimal]
        if ($isNumeric) {
            try {
                $candidate = [convert]::ToDouble(
                    $value,
                    [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
            }
        }
        elseif ($value -is [string]) {
            $parsed = [double]0
            if ([double]::TryParse(
                    $value,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$parsed)) {
                $candidate = $parsed
            }
        }
        if ($null -eq $candidate -or [double]::IsNaN($candidate) -or
            [double]::IsInfinity($candidate)) {
            continue
        }
        $found = $true
        $maximum = [math]::Max($maximum, [double]$candidate)
    }
    if (-not $found) {
        return [double]0
    }
    return [double][math]::Min(100, [math]::Max(0, $maximum))
}

function New-AIFishBotKeySender {
    [CmdletBinding()]
    param(
        [ValidateSet('Software', 'Pico')]
        [string]$Mode = 'Software',

        [switch]$UsePico,

        [Alias('PicoComPort', 'PortName')]
        [AllowEmptyString()]
        [string]$ComPort = '',

        [scriptblock]$SendKeysProvider,

        [Alias('SerialPortProvider')]
        [scriptblock]$SerialPortFactory
    )

    $invokeObjectMember = ${function:Invoke-AIFishBotAdapterObjectMember}
    $testFunctionKey = ${function:Test-AIFishBotAdapterFunctionKey}
    $effectiveMode = if ($UsePico) { 'Pico' } else { $Mode }
    $context = [pscustomobject]@{
        Lock = New-Object object
        Disposed = $false
        Opened = $false
        SerialPort = $null
        Mode = $effectiveMode
    }

    if ($effectiveMode -eq 'Pico') {
        if ([string]::IsNullOrWhiteSpace($ComPort)) {
            throw 'The Pico COM port cannot be blank.'
        }
        if ($null -eq $SerialPortFactory) {
            $SerialPortFactory = {
                param($portName, $baudRate, $parity, $dataBits, $stopBits)
                return New-Object System.IO.Ports.SerialPort `
                    -ArgumentList @($portName, $baudRate, $parity, $dataBits, $stopBits)
            }
        }
        $port = $null
        try {
            $ports = @(& $SerialPortFactory $ComPort 115200 `
                    ([System.IO.Ports.Parity]::None) 8 ([System.IO.Ports.StopBits]::One))
            if ($ports.Count -ne 1 -or $null -eq $ports[0]) {
                throw 'The serial port factory must return exactly one port object.'
            }
            $port = $ports[0]
            Invoke-AIFishBotAdapterObjectMember -Object $port -Name Open | Out-Null
            $context.SerialPort = $port
            $context.Opened = $true
        }
        catch {
            if ($null -ne $port) {
                try {
                    Invoke-AIFishBotAdapterObjectMember -Object $port -Name Dispose | Out-Null
                }
                catch {
                }
            }
            throw (New-Object System.InvalidOperationException(
                    ('Unable to open Pico serial port {0}: {1}' -f $ComPort, $_.Exception.Message),
                    $_.Exception))
        }
    }
    elseif ($null -eq $SendKeysProvider) {
        $SendKeysProvider = {
            param($value)
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.SendKeys]::SendWait([string]$value)
        }
    }

    $captured = $context
    $capturedSendKeys = $SendKeysProvider
    $sendAction = ({
            param($key)
            if (-not (& $testFunctionKey -Key $key)) {
                throw 'The key must be between F5 and F12.'
            }
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    throw 'The key sender has been disposed.'
                }
                if ($captured.Mode -eq 'Pico') {
                    & $invokeObjectMember -Object $captured.SerialPort `
                        -Name WriteLine -ArgumentList @([string]$key) | Out-Null
                }
                else {
                    & $capturedSendKeys ('{{{0}}}' -f [string]$key) | Out-Null
                }
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())
    $disposeAction = ({
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    return
                }
                $captured.Disposed = $true
                if ($captured.Mode -eq 'Pico' -and $null -ne $captured.SerialPort) {
                    try {
                        if ($captured.Opened) {
                            $captured.Opened = $false
                            & $invokeObjectMember -Object $captured.SerialPort `
                                -Name Close | Out-Null
                        }
                    }
                    finally {
                        & $invokeObjectMember -Object $captured.SerialPort `
                            -Name Dispose | Out-Null
                    }
                }
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())

    return [pscustomobject]@{
        Context = $context
        Send = $sendAction
        SendKey = $sendAction
        Dispose = $disposeAction
    }
}

function New-AIFishBotGameFocuser {
    [CmdletBinding()]
    param(
        [scriptblock]$AppActivateProvider,
        [scriptblock]$LogProvider
    )

    $writeLogSafely = ${function:Write-AIFishBotAdapterLogSafely}
    if ($null -eq $AppActivateProvider) {
        $AppActivateProvider = {
            param($target)
            $shell = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                return [bool]$shell.AppActivate([string]$target)
            }
            finally {
                if ($null -ne $shell -and [System.Runtime.InteropServices.Marshal]::IsComObject($shell)) {
                    [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
                }
            }
        }
    }
    $capturedActivate = $AppActivateProvider
    $capturedLog = $LogProvider
    $focusAction = ({
            try {
                $activated = [bool](& $capturedActivate 'World of Warcraft')
                if (-not $activated) {
                    & $writeLogSafely -LogProvider $capturedLog -Level Warning `
                        -Message 'The World of Warcraft window was not found.'
                }
                return $activated
            }
            catch {
                & $writeLogSafely -LogProvider $capturedLog -Level Warning `
                    -Message ('Unable to activate the World of Warcraft window: {0}' -f $_.Exception.Message)
                return $false
            }
        }.GetNewClosure())

    return [pscustomobject]@{
        Focus = $focusAction
        FocusWindow = $focusAction
        FocusGame = $focusAction
        Dispose = { }
    }
}

function Test-AIFishBotDiscordWebhook {
    param([AllowNull()][string]$Webhook)

    if ([string]::IsNullOrWhiteSpace($Webhook)) {
        return $false
    }
    $uri = $null
    if (-not [uri]::TryCreate($Webhook, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
        return $false
    }
    if ($uri.Host -notmatch '^(?:(?:canary|ptb)\.)?discord(?:app)?\.com$') {
        return $false
    }
    return $uri.AbsolutePath -match '^/api(?:/v[0-9]+)?/webhooks/[A-Za-z0-9_-]+/[A-Za-z0-9._-]+/?$'
}

function New-AIFishBotNotifier {
    [CmdletBinding()]
    param(
        [scriptblock]$InvokeRestMethodProvider,
        [scriptblock]$LogProvider,
        [scriptblock]$ProtectProvider
    )

    $testWebhook = ${function:Test-AIFishBotDiscordWebhook}
    $writeLogSafely = ${function:Write-AIFishBotAdapterLogSafely}
    if ($null -eq $InvokeRestMethodProvider) {
        $InvokeRestMethodProvider = {
            param($Uri, $Method, $ContentType, $Body)
            Invoke-RestMethod -Uri $Uri -Method $Method -ContentType $ContentType `
                -Body $Body -ErrorAction Stop
        }
    }
    if ($null -eq $ProtectProvider) {
        $ProtectProvider = { param($text) return Protect-AIFishBotSecret -Text $text }
    }
    $capturedRest = $InvokeRestMethodProvider
    $capturedLog = $LogProvider
    $capturedProtect = $ProtectProvider
    $notifyAction = ({
            param($eventName, $webhook)
            if (-not (& $testWebhook -Webhook ([string]$webhook))) {
                & $writeLogSafely -LogProvider $capturedLog -Level Warning `
                    -Message 'The notification webhook is blank or invalid; the request was rejected.'
                return $false
            }
            $payload = [pscustomobject][ordered]@{
                event = [string]$eventName
                content = 'AI FishBot: {0}' -f [string]$eventName
            }
            $body = $payload | ConvertTo-Json -Compress
            try {
                & $capturedRest -Uri ([string]$webhook) -Method Post `
                    -ContentType 'application/json' -Body $body | Out-Null
                return $true
            }
            catch {
                $rawMessage = 'Notification request failed: {0}' -f $_.Exception.Message
                $safeValues = @(& $capturedProtect $rawMessage)
                $safeMessage = if ($safeValues.Count -eq 1) {
                    [string]$safeValues[0]
                }
                else {
                    'Notification request failed.'
                }
                & $writeLogSafely -LogProvider $capturedLog -Level Warning `
                    -Message $safeMessage
                return $false
            }
        }.GetNewClosure())

    return [pscustomobject]@{
        Notify = $notifyAction
        Dispose = { }
    }
}

function New-AIFishBotAudioMonitor {
    [CmdletBinding()]
    param(
        [Alias('SampleProvider')]
        [scriptblock]$WriteAudioDeviceProvider,
        [scriptblock]$StartJobProvider,
        [scriptblock]$ReceiveJobProvider,
        [scriptblock]$StopJobProvider,
        [scriptblock]$RemoveJobProvider
    )

    $convertAudioPeak = ${function:ConvertTo-AIFishBotAudioPeak}
    $directMode = $null -ne $WriteAudioDeviceProvider
    if (-not $directMode) {
        if ($null -eq $StartJobProvider) {
            $StartJobProvider = { param($scriptBlock) return Start-Job -ScriptBlock $scriptBlock }
        }
        if ($null -eq $ReceiveJobProvider) {
            $ReceiveJobProvider = { param($job) return Receive-Job -Job $job -ErrorAction Stop }
        }
        if ($null -eq $StopJobProvider) {
            $StopJobProvider = { param($job) Stop-Job -Job $job -ErrorAction SilentlyContinue }
        }
        if ($null -eq $RemoveJobProvider) {
            $RemoveJobProvider = {
                param($job)
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $context = [pscustomobject]@{
        Lock = New-Object object
        Started = $false
        Disposed = $false
        Job = $null
        DirectMode = $directMode
    }
    $captured = $context
    $capturedWriteAudio = $WriteAudioDeviceProvider
    $capturedStartJob = $StartJobProvider
    $capturedReceiveJob = $ReceiveJobProvider
    $capturedStopJob = $StopJobProvider
    $capturedRemoveJob = $RemoveJobProvider
    $audioManifest = Join-Path -Path $script:AIFishBotAdaptersRoot `
        -ChildPath 'AudioModule\AudioDeviceCmdlets.psd1'
    $escapedManifest = $audioManifest.Replace("'", "''")
    $playbackScript = [scriptblock]::Create(
        "Import-Module -Name '$escapedManifest' -ErrorAction Stop; Write-AudioDevice -PlaybackStream")

    $cleanupAction = ({
            if ($captured.DirectMode -or $null -eq $captured.Job) {
                $captured.Started = $false
                return
            }
            $job = $captured.Job
            $captured.Job = $null
            $captured.Started = $false
            try {
                $stateProperty = $job.PSObject.Properties['State']
                if ($null -eq $stateProperty -or [string]$stateProperty.Value -in @('Running', 'NotStarted')) {
                    & $capturedStopJob $job | Out-Null
                }
            }
            finally {
                & $capturedRemoveJob $job | Out-Null
            }
        }.GetNewClosure())
    $startAction = ({
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    throw 'The audio monitor has been disposed.'
                }
                if ($captured.Started) {
                    return
                }
                if (-not $captured.DirectMode) {
                    $jobs = @(& $capturedStartJob $playbackScript)
                    if ($jobs.Count -ne 1 -or $null -eq $jobs[0]) {
                        throw 'The audio job factory must return exactly one job.'
                    }
                    $captured.Job = $jobs[0]
                }
                $captured.Started = $true
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())
    $readAction = ({
            & $startAction | Out-Null
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    throw 'The audio monitor has been disposed.'
                }
                $values = if ($captured.DirectMode) {
                    @(& $capturedWriteAudio)
                }
                else {
                    @(& $capturedReceiveJob $captured.Job)
                }
                return & $convertAudioPeak -Values $values
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())
    $resetAction = ({
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    throw 'The audio monitor has been disposed.'
                }
                & $cleanupAction | Out-Null
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
            & $startAction | Out-Null
        }.GetNewClosure())
    $disposeAction = ({
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) {
                    return
                }
                $captured.Disposed = $true
                & $cleanupAction | Out-Null
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())

    return [pscustomobject]@{
        Context = $context
        Start = $startAction
        ReadPeak = $readAction
        Reset = $resetAction
        Dispose = $disposeAction
    }
}

function New-AIFishBotEngineAdapter {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Config,
        [AllowEmptyString()][string]$RunDirectory = '',
        [switch]$Simulation,
        [AllowNull()][object]$AudioMonitor,
        [AllowNull()][object]$KeySender,
        [AllowNull()][object]$GameFocuser,
        [AllowNull()][object]$Notifier,
        [scriptblock]$SleepProvider,
        [scriptblock]$NowProvider,
        [scriptblock]$MonotonicMillisecondsProvider,
        [scriptblock]$LogProvider,
        [AllowNull()][object[]]$SimulationPeaks = @(),
        [scriptblock]$SimulationEventSink,
        [datetimeoffset]$SimulationNow = $([datetimeoffset]'2026-07-13T00:00:00Z')
    )

    $invokeObjectMember = ${function:Invoke-AIFishBotAdapterObjectMember}
    $testFunctionKey = ${function:Test-AIFishBotAdapterFunctionKey}
    $convertAudioPeak = ${function:ConvertTo-AIFishBotAudioPeak}
    $writeLogSafely = ${function:Write-AIFishBotAdapterLogSafely}
    if ($Simulation) {
        $peakQueue = New-Object 'System.Collections.Generic.Queue[object]'
        foreach ($peak in @($SimulationPeaks)) {
            $peakQueue.Enqueue($peak)
        }
        $context = [pscustomobject]@{
            Lock = New-Object object
            Now = $SimulationNow
            MonotonicMilliseconds = [double]0
            Peaks = $peakQueue
            Events = New-Object 'System.Collections.Generic.List[string]'
            DisposeCount = 0
            Disposed = $false
        }
        $captured = $context
        $capturedSink = $SimulationEventSink
        $emit = ({
                param($eventName)
                [void]$captured.Events.Add([string]$eventName)
                if ($null -ne $capturedSink) {
                    & $capturedSink ([string]$eventName) | Out-Null
                }
            }.GetNewClosure())
        $nowAction = ({ return [datetimeoffset]$captured.Now }.GetNewClosure())
        $millisecondsAction = ({ return [double]$captured.MonotonicMilliseconds }.GetNewClosure())
        $sleepAction = ({
                param($milliseconds)
                $value = [int]$milliseconds
                if ($value -lt 0) { throw 'Sleep milliseconds cannot be negative.' }
                $captured.Now = $captured.Now.AddMilliseconds($value)
                $captured.MonotonicMilliseconds += [double]$value
                & $emit ('sleep:{0}' -f $value) | Out-Null
            }.GetNewClosure())
        $sendAction = ({
                param($key)
                if (-not (& $testFunctionKey -Key $key)) {
                    throw 'The key must be between F5 and F12.'
                }
                & $emit ('key:{0}' -f [string]$key) | Out-Null
            }.GetNewClosure())
        $focusAction = ({ & $emit 'focus' | Out-Null; return $true }.GetNewClosure())
        $peakAction = ({
                $value = if ($captured.Peaks.Count -gt 0) {
                    & $convertAudioPeak -Values @($captured.Peaks.Dequeue())
                }
                else {
                    [double]0
                }
                & $emit ('peak:{0}' -f $value.ToString(
                        [System.Globalization.CultureInfo]::InvariantCulture)) | Out-Null
                return [double]$value
            }.GetNewClosure())
        $notifyAction = ({
                param($eventName, $webhook)
                & $emit ('notify:{0}' -f [string]$eventName) | Out-Null
                return $true
            }.GetNewClosure())
        $logAction = ({
                param($level, $message)
                & $emit ('log:{0}:{1}' -f [string]$level, [string]$message) | Out-Null
            }.GetNewClosure())
        $disposeAction = ({
                [System.Threading.Monitor]::Enter($captured.Lock)
                try {
                    if ($captured.Disposed) { return }
                    $captured.Disposed = $true
                    $captured.DisposeCount += 1
                    & $emit 'dispose' | Out-Null
                }
                finally {
                    [System.Threading.Monitor]::Exit($captured.Lock)
                }
            }.GetNewClosure())
        $monotonicNowAction = ({
                return [timespan]::FromMilliseconds($captured.MonotonicMilliseconds)
            }.GetNewClosure())

        return [pscustomobject]@{
            Context = $context
            Now = $nowAction
            MonotonicMilliseconds = $millisecondsAction
            Milliseconds = $millisecondsAction
            MonotonicNow = $monotonicNowAction
            SleepMilliseconds = $sleepAction
            Sleep = $sleepAction
            SendKey = $sendAction
            FocusWindow = $focusAction
            FocusGame = $focusAction
            ReadPeak = $peakAction
            Notify = $notifyAction
            Log = $logAction
            Dispose = $disposeAction
        }
    }

    if ($null -eq $LogProvider) {
        if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
            $LogProvider = { param($level, $message) }
        }
        else {
            $capturedRunDirectory = [System.IO.Path]::GetFullPath($RunDirectory)
            $LogProvider = ({
                    param($level, $message)
                    Write-AIFishBotLog -RunDirectory $capturedRunDirectory `
                        -Level $level -Message $message | Out-Null
                }.GetNewClosure())
        }
    }
    if ($null -eq $SleepProvider) {
        $SleepProvider = { param($milliseconds) Start-Sleep -Milliseconds ([int]$milliseconds) }
    }
    if ($null -eq $NowProvider) {
        $NowProvider = { return [datetimeoffset]::Now }
    }
    $stopwatch = $null
    if ($null -eq $MonotonicMillisecondsProvider) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $capturedStopwatch = $stopwatch
        $MonotonicMillisecondsProvider = ({
                return [double]$capturedStopwatch.Elapsed.TotalMilliseconds
            }.GetNewClosure())
    }

    $created = New-Object 'System.Collections.Generic.List[object]'
    try {
        if ($null -eq $AudioMonitor) {
            $AudioMonitor = New-AIFishBotAudioMonitor
            [void]$created.Add($AudioMonitor)
        }
        if ($null -eq $KeySender) {
            $usePico = $false
            $comPort = ''
            if ($null -ne $Config) {
                $usePiProperty = $Config.PSObject.Properties['usePi']
                $portProperty = $Config.PSObject.Properties['picoComPort']
                if ($null -ne $usePiProperty) { $usePico = [bool]$usePiProperty.Value }
                if ($null -ne $portProperty) { $comPort = [string]$portProperty.Value }
            }
            $KeySender = New-AIFishBotKeySender -UsePico:$usePico -ComPort $comPort
            [void]$created.Add($KeySender)
        }
        if ($null -eq $GameFocuser) {
            $GameFocuser = New-AIFishBotGameFocuser -LogProvider $LogProvider
            [void]$created.Add($GameFocuser)
        }
        if ($null -eq $Notifier) {
            $Notifier = New-AIFishBotNotifier -LogProvider $LogProvider
            [void]$created.Add($Notifier)
        }
        Invoke-AIFishBotAdapterObjectMember -Object $AudioMonitor -Name Start | Out-Null
    }
    catch {
        foreach ($dependency in $created) {
            try {
                Invoke-AIFishBotAdapterObjectMember -Object $dependency -Name Dispose | Out-Null
            }
            catch {
            }
        }
        if ($null -ne $stopwatch) { $stopwatch.Stop() }
        throw
    }

    $context = [pscustomobject]@{
        Lock = New-Object object
        Disposed = $false
        AudioMonitor = $AudioMonitor
        KeySender = $KeySender
        GameFocuser = $GameFocuser
        Notifier = $Notifier
        Stopwatch = $stopwatch
    }
    $captured = $context
    $capturedSleep = $SleepProvider
    $capturedNow = $NowProvider
    $capturedMilliseconds = $MonotonicMillisecondsProvider
    $capturedLog = $LogProvider
    $nowAction = ({ return & $capturedNow }.GetNewClosure())
    $millisecondsAction = ({ return [double](& $capturedMilliseconds) }.GetNewClosure())
    $sleepAction = ({ param($milliseconds) & $capturedSleep ([int]$milliseconds) | Out-Null }.GetNewClosure())
    $sendAction = ({
            param($key)
            & $invokeObjectMember -Object $captured.KeySender `
                -Name Send -ArgumentList @($key) | Out-Null
        }.GetNewClosure())
    $focusAction = ({
            return [bool](& $invokeObjectMember -Object $captured.GameFocuser -Name Focus)
        }.GetNewClosure())
    $peakAction = ({
            return [double](& $invokeObjectMember -Object $captured.AudioMonitor -Name ReadPeak)
        }.GetNewClosure())
    $notifyAction = ({
            param($eventName, $webhook)
            return [bool](& $invokeObjectMember -Object $captured.Notifier `
                    -Name Notify -ArgumentList @($eventName, $webhook))
        }.GetNewClosure())
    $logAction = ({ param($level, $message) & $capturedLog $level $message | Out-Null }.GetNewClosure())
    $disposeAction = ({
            [System.Threading.Monitor]::Enter($captured.Lock)
            try {
                if ($captured.Disposed) { return }
                $captured.Disposed = $true
                foreach ($dependency in @(
                        $captured.AudioMonitor,
                        $captured.KeySender,
                        $captured.GameFocuser,
                        $captured.Notifier
                    )) {
                    try {
                        & $invokeObjectMember -Object $dependency -Name Dispose | Out-Null
                    }
                    catch {
                        & $writeLogSafely -LogProvider $capturedLog -Level Warning `
                            -Message ('Adapter dependency disposal failed: {0}' -f $_.Exception.Message)
                    }
                }
                if ($captured.Stopwatch -is [System.Diagnostics.Stopwatch]) {
                    $captured.Stopwatch.Stop()
                }
            }
            finally {
                [System.Threading.Monitor]::Exit($captured.Lock)
            }
        }.GetNewClosure())
    $monotonicNowAction = ({
            return [timespan]::FromMilliseconds([double](& $capturedMilliseconds))
        }.GetNewClosure())

    return [pscustomobject]@{
        Context = $context
        Now = $nowAction
        MonotonicMilliseconds = $millisecondsAction
        Milliseconds = $millisecondsAction
        MonotonicNow = $monotonicNowAction
        SleepMilliseconds = $sleepAction
        Sleep = $sleepAction
        SendKey = $sendAction
        FocusWindow = $focusAction
        FocusGame = $focusAction
        ReadPeak = $peakAction
        Notify = $notifyAction
        Log = $logAction
        Dispose = $disposeAction
    }
}

Export-ModuleMember -Function @(
    'New-AIFishBotAudioMonitor',
    'New-AIFishBotKeySender',
    'New-AIFishBotGameFocuser',
    'New-AIFishBotNotifier',
    'New-AIFishBotEngineAdapter'
)
