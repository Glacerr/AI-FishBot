$script:AdaptersTestRoot = Split-Path -Path $PSScriptRoot -Parent
$script:AdaptersModulePath = Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Adapters.psm1'
$script:AdaptersEngineScriptPath = Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Engine.ps1'

if (-not (Test-Path -LiteralPath $script:AdaptersModulePath -PathType Leaf)) {
    Test-Case 'adapters module exists before its behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:AdaptersModulePath -PathType Leaf)
    }
    return
}

Import-Module -Name $script:AdaptersModulePath -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Config.psm1') `
    -Force -ErrorAction Stop
Import-Module -Name (Join-Path -Path $script:AdaptersTestRoot -ChildPath 'AI-FishBot.Runtime.psm1') `
    -Force -ErrorAction Stop

function Remove-AdaptersTestDirectory {
    param([AllowNull()][string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path) -and
        [System.IO.Directory]::Exists($Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AdaptersMember {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [object[]]$Arguments = @()
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property -and $property.Value -is [scriptblock]) {
        return & $property.Value @Arguments
    }
    $method = $Object.PSObject.Methods[$Name]
    if ($null -ne $method) {
        return $method.Invoke($Arguments)
    }
    throw ('Missing test member: {0}' -f $Name)
}

Test-Case 'adapter module exports every public factory' {
    foreach ($name in @(
            'New-AIFishBotAudioMonitor',
            'New-AIFishBotKeySender',
            'New-AIFishBotGameFocuser',
            'New-AIFishBotNotifier',
            'New-AIFishBotEngineAdapter'
        )) {
        Assert-True -Condition ($null -ne (Get-Command -Name $name -ErrorAction SilentlyContinue))
    }
}

Test-Case 'software key sender validates and formats function keys for SendKeys' {
    $sent = New-Object 'System.Collections.Generic.List[string]'
    $captured = $sent
    $sender = New-AIFishBotKeySender -SendKeysProvider ({
            param($value)
            [void]$captured.Add([string]$value)
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F7') | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected @('{F7}') -Actual @($sent)
}

Test-Case 'key sender rejects keys outside F5 through F12' {
    $sender = New-AIFishBotKeySender -SendKeysProvider { param($value) }
    try {
        Assert-Throws -ScriptBlock {
            Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F4') | Out-Null
        } -MessageLike '*F5*F12*'
    }
    finally {
        Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    }
}

Test-Case 'Pico key sender opens with fixed serial settings sends lines and closes once' {
    $context = [pscustomobject]@{
        Arguments = @()
        OpenCount = 0
        CloseCount = 0
        DisposeCount = 0
        Lines = New-Object 'System.Collections.Generic.List[string]'
        IsOpen = $false
    }
    $captured = $context
    $serial = [pscustomobject]@{ IsOpen = $false; WriteTimeout = 0 }
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value {
        $captured.OpenCount += 1
        $this.IsOpen = $true
        $captured.IsOpen = $true
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name WriteLine -Value {
        param($line)
        [void]$captured.Lines.Add([string]$line)
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Close -Value {
        $captured.CloseCount += 1
        $this.IsOpen = $false
        $captured.IsOpen = $false
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = {
        param($portName, $baudRate, $parity, $dataBits, $stopBits)
        $captured.Arguments = @($portName, $baudRate, $parity, $dataBits, $stopBits)
        return $serial
    }.GetNewClosure()

    $sender = New-AIFishBotKeySender -UsePico -ComPort 'COM9' -SerialPortFactory $factory
    Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F12') | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected 'COM9' -Actual $context.Arguments[0]
    Assert-Equal -Expected 115200 -Actual $context.Arguments[1]
    Assert-Equal -Expected ([System.IO.Ports.Parity]::None) -Actual $context.Arguments[2]
    Assert-Equal -Expected 8 -Actual $context.Arguments[3]
    Assert-Equal -Expected ([System.IO.Ports.StopBits]::One) -Actual $context.Arguments[4]
    Assert-Equal -Expected 2000 -Actual $serial.WriteTimeout
    Assert-Equal -Expected @('F12') -Actual @($context.Lines)
    Assert-Equal -Expected 1 -Actual $context.OpenCount
    Assert-Equal -Expected 1 -Actual $context.CloseCount
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
}

Test-Case 'Pico key sender accepts an injected legacy port without a WriteTimeout property' {
    $context = [pscustomobject]@{
        OpenCount = 0
        CloseCount = 0
        DisposeCount = 0
        Lines = New-Object 'System.Collections.Generic.List[string]'
    }
    $captured = $context
    $serial = [pscustomobject]@{ IsOpen = $false }
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value {
        $captured.OpenCount += 1
        $this.IsOpen = $true
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name WriteLine -Value {
        param($line)
        [void]$captured.Lines.Add([string]$line)
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Close -Value {
        $captured.CloseCount += 1
        $this.IsOpen = $false
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = {
        param($portName, $baudRate, $parity, $dataBits, $stopBits)
        return $serial
    }.GetNewClosure()

    $sender = New-AIFishBotKeySender -UsePico -ComPort 'COM6' -SerialPortFactory $factory
    Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F6') | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected @('F6') -Actual @($context.Lines)
    Assert-Equal -Expected 1 -Actual $context.OpenCount
    Assert-Equal -Expected 1 -Actual $context.CloseCount
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
    Assert-Equal -Expected $null -Actual $serial.PSObject.Properties['WriteTimeout']
}

Test-Case 'Pico key sender bounds writes and reports timeout details before disposing once' {
    $context = [pscustomobject]@{ CloseCount = 0; DisposeCount = 0 }
    $captured = $context
    $serial = [pscustomobject]@{ IsOpen = $false; WriteTimeout = 0 }
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value { $this.IsOpen = $true }
    $serial | Add-Member -MemberType ScriptMethod -Name WriteLine -Value {
        param($line)
        throw (New-Object System.TimeoutException('serial write blocked'))
    }
    $serial | Add-Member -MemberType ScriptMethod -Name Close -Value {
        $captured.CloseCount += 1
        $this.IsOpen = $false
    }.GetNewClosure()
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = {
        param($portName, $baudRate, $parity, $dataBits, $stopBits)
        return $serial
    }.GetNewClosure()
    $sender = New-AIFishBotKeySender -UsePico -ComPort 'COM8' `
        -WriteTimeoutMilliseconds 1500 -SerialPortFactory $factory

    Assert-Throws -ScriptBlock {
        Invoke-AdaptersMember -Object $sender -Name Send -Arguments @('F8') | Out-Null
    } -MessageLike '*COM8*timed out*1500*'
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $sender -Name Dispose | Out-Null

    Assert-Equal -Expected 1500 -Actual $serial.WriteTimeout
    Assert-Equal -Expected 1 -Actual $context.CloseCount
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
}

Test-Case 'Pico key sender reports a clear open failure and disposes the failed port' {
    $context = [pscustomobject]@{ DisposeCount = 0 }
    $captured = $context
    $serial = [pscustomobject]@{ WriteTimeout = 0 }
    $serial | Add-Member -MemberType ScriptMethod -Name Open -Value { throw 'access denied' }
    $serial | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
        $captured.DisposeCount += 1
    }.GetNewClosure()
    $factory = { param($portName, $baudRate, $parity, $dataBits, $stopBits) return $serial }.GetNewClosure()

    Assert-Throws -ScriptBlock {
        New-AIFishBotKeySender -UsePico -ComPort 'COM7' -SerialPortFactory $factory | Out-Null
    } -MessageLike '*COM7*access denied*'
    Assert-Equal -Expected 1 -Actual $context.DisposeCount
}

Test-Case 'game focuser activates only World of Warcraft' {
    $targets = New-Object 'System.Collections.Generic.List[string]'
    $captured = $targets
    $focuser = New-AIFishBotGameFocuser -AppActivateProvider ({
            param($target)
            [void]$captured.Add([string]$target)
            return $true
        }.GetNewClosure()) -LogProvider { param($level, $message) }

    $result = Invoke-AdaptersMember -Object $focuser -Name Focus

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected @('World of Warcraft') -Actual @($targets)
}

Test-Case 'game focuser logs failure and returns false without choosing another window' {
    $targets = New-Object 'System.Collections.Generic.List[string]'
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedTargets = $targets
    $capturedLogs = $logs
    $focuser = New-AIFishBotGameFocuser -AppActivateProvider ({
            param($target)
            [void]$capturedTargets.Add([string]$target)
            throw 'window unavailable'
        }.GetNewClosure()) -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add(('{0}:{1}' -f $level, $message))
        }.GetNewClosure())

    $result = Invoke-AdaptersMember -Object $focuser -Name Focus

    Assert-Equal -Expected $false -Actual $result
    Assert-Equal -Expected @('World of Warcraft') -Actual @($targets)
    Assert-True -Condition (($logs -join "`n") -like '*window unavailable*')
}

Test-Case 'notifier posts JSON to a valid Discord webhook' {
    $requests = New-Object 'System.Collections.Generic.List[object]'
    $captured = $requests
    $rest = {
        param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
        [void]$captured.Add([pscustomobject]@{
                Uri = $Uri; Method = $Method; ContentType = $ContentType
                Body = $Body; TimeoutSec = $TimeoutSec
            })
        return [pscustomobject]@{ ok = $true }
    }.GetNewClosure()
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider $rest `
        -LogProvider { param($level, $message) } -ProtectProvider { param($text) return $text }
    $webhook = 'https://discord.com/api/webhooks/123456/secret-token'

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', $webhook)

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected 1 -Actual $requests.Count
    Assert-Equal -Expected $webhook -Actual $requests[0].Uri
    Assert-Equal -Expected 'Post' -Actual $requests[0].Method
    Assert-Equal -Expected 'application/json' -Actual $requests[0].ContentType
    Assert-Equal -Expected 10 -Actual $requests[0].TimeoutSec
    Assert-Equal -Expected 'start' -Actual (($requests[0].Body | ConvertFrom-Json).event)
}

Test-Case 'notifier preserves legacy named HTTP parameters and adds TimeoutSec' {
    $context = [pscustomobject]@{
        Keys = @()
        Uri = $null
        Method = $null
        ContentType = $null
        Body = $null
        TimeoutSec = $null
        ExtraCount = -1
    }
    $captured = $context
    $http = {
        [CmdletBinding(PositionalBinding = $false)]
        param(
            [Parameter(Mandatory = $true)][string]$Uri,
            [Parameter(Mandatory = $true)][string]$Method,
            [Parameter(Mandatory = $true)][string]$ContentType,
            [Parameter(Mandatory = $true)][string]$Body,
            [Parameter(Mandatory = $true)][int]$TimeoutSec
        )
        $captured.Keys = @($PSBoundParameters.Keys | Sort-Object)
        $captured.Uri = $Uri
        $captured.Method = $Method
        $captured.ContentType = $ContentType
        $captured.Body = $Body
        $captured.TimeoutSec = $TimeoutSec
        $captured.ExtraCount = $args.Count
    }.GetNewClosure()
    $webhook = 'https://discord.com/api/v10/webhooks/named-id/named-token'
    $notifier = New-AIFishBotNotifier -HttpProvider $http -TimeoutSec 12 `
        -LogProvider { param($level, $message) }

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', $webhook)

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected @('Body', 'ContentType', 'Method', 'TimeoutSec', 'Uri') -Actual $context.Keys
    Assert-Equal -Expected $webhook -Actual $context.Uri
    Assert-Equal -Expected 'Post' -Actual $context.Method
    Assert-Equal -Expected 'application/json' -Actual $context.ContentType
    Assert-Equal -Expected 'start' -Actual (($context.Body | ConvertFrom-Json).event)
    Assert-Equal -Expected 12 -Actual $context.TimeoutSec
    Assert-Equal -Expected 0 -Actual $context.ExtraCount
}

Test-Case 'notifier preserves a strict legacy four-parameter HTTP provider' {
    $context = [pscustomobject]@{
        Keys = @()
        Uri = $null
        Method = $null
        ContentType = $null
        Body = $null
        ExtraCount = -1
    }
    $captured = $context
    $http = {
        [CmdletBinding(PositionalBinding = $false)]
        param(
            [Parameter(Mandatory = $true)][string]$Uri,
            [Parameter(Mandatory = $true)][string]$Method,
            [Parameter(Mandatory = $true)][string]$ContentType,
            [Parameter(Mandatory = $true)][string]$Body
        )
        $captured.Keys = @($PSBoundParameters.Keys | Sort-Object)
        $captured.Uri = $Uri
        $captured.Method = $Method
        $captured.ContentType = $ContentType
        $captured.Body = $Body
        $captured.ExtraCount = $args.Count
    }.GetNewClosure()
    $webhook = 'https://discord.com/api/v10/webhooks/legacy-id/legacy-token'
    $notifier = New-AIFishBotNotifier -HttpProvider $http -TimeoutSec 12 `
        -LogProvider { param($level, $message) }

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', $webhook)

    Assert-Equal -Expected $true -Actual $result
    Assert-Equal -Expected @('Body', 'ContentType', 'Method', 'Uri') -Actual $context.Keys
    Assert-Equal -Expected $webhook -Actual $context.Uri
    Assert-Equal -Expected 'Post' -Actual $context.Method
    Assert-Equal -Expected 'application/json' -Actual $context.ContentType
    Assert-Equal -Expected 'start' -Actual (($context.Body | ConvertFrom-Json).event)
    Assert-Equal -Expected 0 -Actual $context.ExtraCount
}

Test-Case 'notifier passes an injected timeout from one through sixty seconds' {
    $timeouts = New-Object 'System.Collections.Generic.List[int]'
    $captured = $timeouts
    $http = {
        param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
        [void]$captured.Add([int]$TimeoutSec)
    }.GetNewClosure()
    $webhook = 'https://discord.com/api/webhooks/timeout-id/timeout-token'

    foreach ($timeout in @(1, 60)) {
        $notifier = New-AIFishBotNotifier -HttpProvider $http -TimeoutSec $timeout `
            -LogProvider { param($level, $message) }
        Assert-Equal -Expected $true -Actual (Invoke-AdaptersMember -Object $notifier `
                -Name Notify -Arguments @('start', $webhook))
    }

    Assert-Equal -Expected @(1, 60) -Actual @($timeouts)
    Assert-Throws -ScriptBlock {
        New-AIFishBotNotifier -HttpProvider $http -TimeoutSec 0 | Out-Null
    } -MessageLike '*minimum*1*'
    Assert-Throws -ScriptBlock {
        New-AIFishBotNotifier -HttpProvider $http -TimeoutSec 61 | Out-Null
    } -MessageLike '*maximum*60*'
}

Test-Case 'notifier contains an injected request timeout without exposing its webhook' {
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedLogs = $logs
    $webhook = 'https://discord.com:443/api/v10/webhooks/timeout-id/timeout-secret-token'
    $http = {
        param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
        throw (New-Object System.TimeoutException(('timed out after {0}s at {1}' -f $TimeoutSec, $Uri)))
    }
    $notifier = New-AIFishBotNotifier -HttpProvider $http -TimeoutSec 3 -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add(('{0}:{1}' -f $level, $message))
        }.GetNewClosure())

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('stop', $webhook)
    $logText = $logs -join "`n"

    Assert-Equal -Expected $false -Actual $result
    Assert-True -Condition ($logText -like '*timed out after 3s*')
    Assert-Equal -Expected $false -Actual $logText.Contains('timeout-id')
    Assert-Equal -Expected $false -Actual $logText.Contains('timeout-secret-token')
}

Test-Case 'notifier contains a timeout even when an injected protector fails' {
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedLogs = $logs
    $webhook = 'https://discord.com:443/api/v10/webhooks/protect-id/protect-secret-token'
    $http = {
        param($Uri, $Method, $ContentType, $Body, $TimeoutSec)
        throw (New-Object System.TimeoutException(('request timed out at {0}' -f $Uri)))
    }
    $notifier = New-AIFishBotNotifier -HttpProvider $http -ProtectProvider {
        param($text)
        throw 'protector failed'
    } -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add(('{0}:{1}' -f $level, $message))
        }.GetNewClosure())

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('stop', $webhook)
    $logText = $logs -join "`n"

    Assert-Equal -Expected $false -Actual $result
    Assert-True -Condition ($logText -like '*request timed out*')
    Assert-Equal -Expected $false -Actual $logText.Contains('protect-id')
    Assert-Equal -Expected $false -Actual $logText.Contains('protect-secret-token')
}

Test-Case 'notifier rejects empty and non-Discord webhook values without a request' {
    $context = [pscustomobject]@{ RequestCount = 0 }
    $captured = $context
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider ({
            param($Uri, $Method, $ContentType, $Body)
            $captured.RequestCount += 1
        }.GetNewClosure()) -LogProvider { param($level, $message) }

    $emptyResult = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('start', '')
    $invalidResult = Invoke-AdaptersMember -Object $notifier -Name Notify `
        -Arguments @('stop', 'https://example.com/webhooks/123/token')

    Assert-Equal -Expected $false -Actual $emptyResult
    Assert-Equal -Expected $false -Actual $invalidResult
    Assert-Equal -Expected 0 -Actual $context.RequestCount
}

Test-Case 'notifier contains network errors and masks webhook tokens in logs' {
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedLogs = $logs
    $webhook = 'https://discord.com/api/webhooks/123456/secret-token'
    $rest = { param($Uri, $Method, $ContentType, $Body) throw ('request failed: {0}' -f $Uri) }
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider $rest -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add([string]$message)
        }.GetNewClosure()) -ProtectProvider {
        param($text)
        return [regex]::Replace($text, '(webhooks/)[^/]+/[^\s]+', '${1}***')
    }

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('stop', $webhook)
    $logText = $logs -join "`n"

    Assert-Equal -Expected $false -Actual $result
    Assert-True -Condition ($logText -like '*webhooks/***')
    Assert-Equal -Expected $false -Actual $logText.Contains('secret-token')
}

Test-Case 'notifier masks a port-bearing webhook when an injected request fails' {
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedLogs = $logs
    $webhook = 'https://canary.discordapp.com:8443/api/v11/webhooks/port-id/port-secret-token'
    $rest = {
        param($Uri, $Method, $ContentType, $Body)
        throw ('request failed: {0}' -f $Uri)
    }
    $notifier = New-AIFishBotNotifier -InvokeRestMethodProvider $rest -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add([string]$message)
        }.GetNewClosure())

    $result = Invoke-AdaptersMember -Object $notifier -Name Notify -Arguments @('stop', $webhook)
    $logText = $logs -join "`n"

    Assert-Equal -Expected $false -Actual $result
    Assert-True -Condition ($logText -like '*webhooks/***')
    Assert-Equal -Expected $false -Actual $logText.Contains('port-id')
    Assert-Equal -Expected $false -Actual $logText.Contains('port-secret-token')
}

Test-Case 'audio monitor returns one numeric peak clamped to zero through one hundred' {
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue(@('noise', 12, 105))
    $queue.Enqueue(-4)
    $captured = $queue
    $monitor = New-AIFishBotAudioMonitor -WriteAudioDeviceProvider ({
            if ($captured.Count -eq 0) { return $null }
            return $captured.Dequeue()
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $monitor -Name Start | Out-Null
    $high = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    $low = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]) -Actual $high.GetType()
    Assert-Equal -Expected ([double]100) -Actual $high
    Assert-Equal -Expected ([double]0) -Actual $low
}

Test-Case 'audio monitor owns and removes every playback job exactly once' {
    $context = [pscustomobject]@{
        StartCount = 0
        StopCount = 0
        RemoveCount = 0
        Job = $null
        ScriptText = ''
    }
    $captured = $context
    $startProvider = {
        param($scriptBlock)
        $captured.StartCount += 1
        $captured.ScriptText = [string]$scriptBlock
        $captured.Job = [pscustomobject]@{ State = 'Running'; Output = @(32) }
        return $captured.Job
    }.GetNewClosure()
    $receiveProvider = { param($job) return @($job.Output) }
    $stopProvider = {
        param($job)
        $captured.StopCount += 1
        $job.State = 'Stopped'
    }.GetNewClosure()
    $removeProvider = { param($job) $captured.RemoveCount += 1 }.GetNewClosure()
    $monitor = New-AIFishBotAudioMonitor -StartJobProvider $startProvider `
        -ReceiveJobProvider $receiveProvider -StopJobProvider $stopProvider `
        -RemoveJobProvider $removeProvider

    Invoke-AdaptersMember -Object $monitor -Name Start | Out-Null
    $peak = Invoke-AdaptersMember -Object $monitor -Name ReadPeak
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $monitor -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]32) -Actual $peak
    Assert-True -Condition ($context.ScriptText -match 'Write-AudioDevice\s+-PlaybackStream')
    Assert-Equal -Expected 1 -Actual $context.StartCount
    Assert-Equal -Expected 1 -Actual $context.StopCount
    Assert-Equal -Expected 1 -Actual $context.RemoveCount
}

Test-Case 'engine adapter simulation is memory-only and records injected events' {
    $events = New-Object 'System.Collections.Generic.List[string]'
    $captured = $events
    $adapter = New-AIFishBotEngineAdapter -Simulation -SimulationPeaks @(37) `
        -SimulationEventSink ({ param($eventName) [void]$captured.Add([string]$eventName) }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name SleepMilliseconds -Arguments @(250) | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name SendKey -Arguments @('F7') | Out-Null
    $focused = Invoke-AdaptersMember -Object $adapter -Name FocusWindow
    $peak = Invoke-AdaptersMember -Object $adapter -Name ReadPeak
    $notified = Invoke-AdaptersMember -Object $adapter -Name Notify `
        -Arguments @('start', 'https://discord.com/api/webhooks/1/token')
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]250) -Actual (Invoke-AdaptersMember -Object $adapter -Name MonotonicMilliseconds)
    Assert-Equal -Expected $true -Actual $focused
    Assert-Equal -Expected ([double]37) -Actual $peak
    Assert-Equal -Expected $true -Actual $notified
    Assert-Equal -Expected 1 -Actual $adapter.Context.DisposeCount
    Assert-Equal -Expected @('sleep:250', 'key:F7', 'focus', 'peak:37', 'notify:start', 'dispose') `
        -Actual @($events)
}

Test-Case 'simulation wall clock is current UTC and independent from virtual monotonic time' {
    $before = [datetimeoffset]::UtcNow
    $adapter = New-AIFishBotEngineAdapter -Simulation

    $wallBefore = Invoke-AdaptersMember -Object $adapter -Name Now
    Invoke-AdaptersMember -Object $adapter -Name SleepMilliseconds -Arguments @(60000) | Out-Null
    $wallAfter = Invoke-AdaptersMember -Object $adapter -Name Now
    $after = [datetimeoffset]::UtcNow

    Assert-Equal -Expected ([timespan]::Zero) -Actual $wallBefore.Offset
    Assert-Equal -Expected ([timespan]::Zero) -Actual $wallAfter.Offset
    Assert-True -Condition ($wallBefore -ge $before -and $wallBefore -le $after)
    Assert-True -Condition ($wallAfter -ge $before -and $wallAfter -le $after)
    Assert-True -Condition (($wallAfter - $wallBefore).TotalSeconds -lt 5)
    Assert-Equal -Expected ([double]60000) `
        -Actual (Invoke-AdaptersMember -Object $adapter -Name MonotonicMilliseconds)
}

Test-Case 'simulation read points use a short injectable throttle' {
    $throttles = New-Object 'System.Collections.Generic.List[int]'
    $captured = $throttles
    $adapter = New-AIFishBotEngineAdapter -Simulation -SimulationThrottleProvider ({
            param($milliseconds)
            [void]$captured.Add([int]$milliseconds)
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name ReadPeak | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name ReadPeak | Out-Null

    Assert-Equal -Expected @(1, 1) -Actual @($throttles)
}

Test-Case 'simulation event history keeps only its newest one thousand entries' {
    $adapter = New-AIFishBotEngineAdapter -Simulation `
        -SimulationThrottleProvider { param($milliseconds) }

    foreach ($index in 0..1004) {
        Invoke-AdaptersMember -Object $adapter -Name Log -Arguments @('Info', [string]$index) | Out-Null
    }
    $events = @($adapter.Context.Events)

    Assert-Equal -Expected 1000 -Actual $events.Count
    Assert-Equal -Expected 'log:Info:5' -Actual $events[0]
    Assert-Equal -Expected 'log:Info:1004' -Actual $events[999]
}

Test-Case 'engine adapter delegates every core operation through injected components' {
    $events = New-Object 'System.Collections.Generic.List[string]'
    $captured = $events
    $monitor = [pscustomobject]@{
        Start = ({ [void]$captured.Add('audio:start') }.GetNewClosure())
        ReadPeak = ({ [void]$captured.Add('audio:read'); return [double]44 }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('audio:dispose') }.GetNewClosure())
    }
    $sender = [pscustomobject]@{
        Send = ({ param($key) [void]$captured.Add(('key:{0}' -f $key)) }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('key:dispose') }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = ({ [void]$captured.Add('focus'); return $true }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('focus:dispose') }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = ({ param($eventName, $webhook) [void]$captured.Add(('notify:{0}' -f $eventName)); return $true }.GetNewClosure())
        Dispose = ({ [void]$captured.Add('notify:dispose') }.GetNewClosure())
    }
    $adapter = New-AIFishBotEngineAdapter -AudioMonitor $monitor -KeySender $sender `
        -GameFocuser $focuser -Notifier $notifier `
        -SleepProvider ({ param($milliseconds) [void]$captured.Add(('sleep:{0}' -f $milliseconds)) }.GetNewClosure()) `
        -NowProvider { return [datetimeoffset]'2026-07-13T12:00:00+08:00' } `
        -MonotonicMillisecondsProvider { return [double]1234 } `
        -LogProvider ({ param($level, $message) [void]$captured.Add(('log:{0}:{1}' -f $level, $message)) }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name SleepMilliseconds -Arguments @(10) | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name SendKey -Arguments @('F6') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name FocusWindow | Out-Null
    $peak = Invoke-AdaptersMember -Object $adapter -Name ReadPeak
    Invoke-AdaptersMember -Object $adapter -Name Notify -Arguments @('stop', 'webhook') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Log -Arguments @('Info', 'message') | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null

    Assert-Equal -Expected ([double]44) -Actual $peak
    Assert-Equal -Expected ([double]1234) `
        -Actual (Invoke-AdaptersMember -Object $adapter -Name MonotonicMilliseconds)
    Assert-Equal -Expected @(
        'audio:start', 'sleep:10', 'key:F6', 'focus', 'audio:read', 'notify:stop',
        'log:Info:message', 'audio:dispose', 'key:dispose', 'focus:dispose', 'notify:dispose'
    ) -Actual @($events)
}

Test-Case 'engine adapter disposes every injected component once when startup fails' {
    $counts = [pscustomobject]@{ Audio = 0; Key = 0; Focus = 0; Notify = 0 }
    $captured = $counts
    $monitor = [pscustomobject]@{
        Start = { throw 'audio startup failed' }
        ReadPeak = { return [double]0 }
        Dispose = ({ $captured.Audio += 1 }.GetNewClosure())
    }
    $sender = [pscustomobject]@{
        Send = { param($key) }
        Dispose = ({ $captured.Key += 1 }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = { return $true }
        Dispose = ({ $captured.Focus += 1 }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = { param($eventName, $webhook) return $true }
        Dispose = ({ $captured.Notify += 1 }.GetNewClosure())
    }

    Assert-Throws -ScriptBlock {
        New-AIFishBotEngineAdapter -AudioMonitor $monitor -KeySender $sender `
            -GameFocuser $focuser -Notifier $notifier `
            -SleepProvider { param($milliseconds) } `
            -NowProvider { return [datetimeoffset]::UtcNow } `
            -MonotonicMillisecondsProvider { return [double]0 } `
            -LogProvider { param($level, $message) } | Out-Null
    } -MessageLike '*audio startup failed*'

    Assert-Equal -Expected 1 -Actual $counts.Audio
    Assert-Equal -Expected 1 -Actual $counts.Key
    Assert-Equal -Expected 1 -Actual $counts.Focus
    Assert-Equal -Expected 1 -Actual $counts.Notify
}

Test-Case 'engine adapter owns later injected components before an internal component fails' {
    $counts = [pscustomobject]@{ Audio = 0; Focus = 0; Notify = 0 }
    $captured = $counts
    $monitor = [pscustomobject]@{
        Start = { }
        ReadPeak = { return [double]0 }
        Dispose = ({ $captured.Audio += 1 }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = { return $true }
        Dispose = ({ $captured.Focus += 1 }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = { param($eventName, $webhook) return $true }
        Dispose = ({ $captured.Notify += 1 }.GetNewClosure())
    }
    $config = [pscustomobject]@{ usePi = $true; picoComPort = '' }

    Assert-Throws -ScriptBlock {
        New-AIFishBotEngineAdapter -Config $config -AudioMonitor $monitor `
            -GameFocuser $focuser -Notifier $notifier `
            -SleepProvider { param($milliseconds) } `
            -NowProvider { return [datetimeoffset]::UtcNow } `
            -MonotonicMillisecondsProvider { return [double]0 } `
            -LogProvider { param($level, $message) } | Out-Null
    } -MessageLike '*Pico COM port*blank*'

    Assert-Equal -Expected 1 -Actual $counts.Audio
    Assert-Equal -Expected 1 -Actual $counts.Focus
    Assert-Equal -Expected 1 -Actual $counts.Notify
}

Test-Case 'engine adapter owns injected components before run directory setup fails' {
    $counts = [pscustomobject]@{ Audio = 0; Key = 0; Focus = 0; Notify = 0 }
    $captured = $counts
    $monitor = [pscustomobject]@{
        Start = { }
        ReadPeak = { return [double]0 }
        Dispose = ({ $captured.Audio += 1 }.GetNewClosure())
    }
    $sender = [pscustomobject]@{
        Send = { param($key) }
        Dispose = ({ $captured.Key += 1 }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = { return $true }
        Dispose = ({ $captured.Focus += 1 }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = { param($eventName, $webhook) return $true }
        Dispose = ({ $captured.Notify += 1 }.GetNewClosure())
    }

    Assert-Throws -ScriptBlock {
        New-AIFishBotEngineAdapter -RunDirectory ([string][char]0) `
            -AudioMonitor $monitor -KeySender $sender -GameFocuser $focuser `
            -Notifier $notifier | Out-Null
    }

    Assert-Equal -Expected 1 -Actual $counts.Audio
    Assert-Equal -Expected 1 -Actual $counts.Key
    Assert-Equal -Expected 1 -Actual $counts.Focus
    Assert-Equal -Expected 1 -Actual $counts.Notify
}

Test-Case 'engine adapter masks disposal errors and continues cleaning each component once' {
    $counts = [pscustomobject]@{ Audio = 0; Key = 0; Focus = 0; Notify = 0 }
    $logs = New-Object 'System.Collections.Generic.List[string]'
    $capturedCounts = $counts
    $capturedLogs = $logs
    $monitor = [pscustomobject]@{
        Start = { }
        ReadPeak = { return [double]0 }
        Dispose = ({
                $capturedCounts.Audio += 1
                throw 'cleanup failed at https://discord.com:443/api/v10/webhooks/dispose-id/dispose-secret-token'
            }.GetNewClosure())
    }
    $sender = [pscustomobject]@{
        Send = { param($key) }
        Dispose = ({ $capturedCounts.Key += 1 }.GetNewClosure())
    }
    $focuser = [pscustomobject]@{
        Focus = { return $true }
        Dispose = ({ $capturedCounts.Focus += 1 }.GetNewClosure())
    }
    $notifier = [pscustomobject]@{
        Notify = { param($eventName, $webhook) return $true }
        Dispose = ({ $capturedCounts.Notify += 1 }.GetNewClosure())
    }
    $adapter = New-AIFishBotEngineAdapter -AudioMonitor $monitor -KeySender $sender `
        -GameFocuser $focuser -Notifier $notifier `
        -SleepProvider { param($milliseconds) } `
        -NowProvider { return [datetimeoffset]::UtcNow } `
        -MonotonicMillisecondsProvider { return [double]0 } `
        -LogProvider ({
            param($level, $message)
            [void]$capturedLogs.Add(('{0}:{1}' -f $level, $message))
        }.GetNewClosure())

    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    Invoke-AdaptersMember -Object $adapter -Name Dispose | Out-Null
    $logText = $logs -join "`n"

    Assert-Equal -Expected 1 -Actual $counts.Audio
    Assert-Equal -Expected 1 -Actual $counts.Key
    Assert-Equal -Expected 1 -Actual $counts.Focus
    Assert-Equal -Expected 1 -Actual $counts.Notify
    Assert-True -Condition ($logText -like '*webhooks/***')
    Assert-Equal -Expected $false -Actual $logText.Contains('dispose-id')
    Assert-Equal -Expected $false -Actual $logText.Contains('dispose-secret-token')
}

if (-not (Test-Path -LiteralPath $script:AdaptersEngineScriptPath -PathType Leaf)) {
    Test-Case 'engine entry script exists before integration behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:AdaptersEngineScriptPath -PathType Leaf)
    }
    return
}

Test-Case 'simulation engine process observes stop and exits with a final heartbeat and log' {
    $runDirectory = New-TestDirectory
    $process = $null
    try {
        $config = New-AIFishBotDefaultConfig
        $config.profileName = 'Simulation Integration'
        $config.autoStop = $false
        $config.useWindowFocus = $true
        $config | Add-Member -NotePropertyName configVersion -NotePropertyValue 1
        $startPath = Join-Path $runDirectory 'start-config.json'
        $livePath = Join-Path $runDirectory 'live-config.json'
        Write-AIFishBotAtomicJson -Path $startPath -InputObject $config | Out-Null
        Write-AIFishBotAtomicJson -Path $livePath -InputObject $config | Out-Null
        [System.IO.File]::SetAttributes(
            $startPath,
            ([System.IO.File]::GetAttributes($startPath) -bor [System.IO.FileAttributes]::ReadOnly))

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'powershell.exe'
        $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -RunDirectory "{1}" -Simulation' -f `
            $script:AdaptersEngineScriptPath, $runDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)

        $deadline = [datetime]::UtcNow.AddSeconds(15)
        $status = $null
        while ([datetime]::UtcNow -lt $deadline) {
            try {
                $status = Read-AIFishBotStatus -RunDirectory $runDirectory
                if ($null -ne $status) { break }
            }
            catch {
            }
            Start-Sleep -Milliseconds 25
        }
        Assert-True -Condition ($null -ne $status)
        Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command stop | Out-Null
        Assert-True -Condition $process.WaitForExit(15000)

        $final = Read-AIFishBotStatus -RunDirectory $runDirectory
        $logFiles = @(Get-ChildItem -LiteralPath (Join-Path $runDirectory 'logs') -Filter '*.log' -File)
        Assert-Equal -Expected 0 -Actual $process.ExitCode
        Assert-Equal -Expected 'stopped' -Actual $final.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$final.heartbeatAt))
        Assert-True -Condition ($logFiles.Count -ge 1)
    }
    finally {
        if ($null -ne $process) {
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
        }
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}

Test-Case 'engine entry exits one and writes error status when start config is missing' {
    $runDirectory = New-TestDirectory
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:AdaptersEngineScriptPath `
            -RunDirectory $runDirectory -Simulation 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $status = Read-AIFishBotStatus -RunDirectory $runDirectory

        Assert-Equal -Expected 1 -Actual $exitCode
        Assert-Equal -Expected 'error' -Actual $status.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$status.lastError))
    }
    finally {
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}

Test-Case 'engine entry exits one and writes error status for malformed startup JSON' {
    $runDirectory = New-TestDirectory
    try {
        [System.IO.File]::WriteAllText((Join-Path $runDirectory 'start-config.json'), '{bad json')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:AdaptersEngineScriptPath `
            -RunDirectory $runDirectory -Simulation 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $status = Read-AIFishBotStatus -RunDirectory $runDirectory

        Assert-Equal -Expected 1 -Actual $exitCode
        Assert-Equal -Expected 'error' -Actual $status.state
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$status.lastError))
    }
    finally {
        Remove-AdaptersTestDirectory -Path $runDirectory
    }
}
