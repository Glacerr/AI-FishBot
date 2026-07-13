$script:RuntimeRepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$script:RuntimeModulePath = Join-Path -Path $script:RuntimeRepositoryRoot -ChildPath 'AI-FishBot.Runtime.psm1'

if (Test-Path -LiteralPath $script:RuntimeModulePath -PathType Leaf) {
    Import-Module -Name $script:RuntimeModulePath -Force -ErrorAction Stop
}

function Remove-RuntimeTestDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-RuntimeStatus {
    param(
        [string]$State = 'running',
        [string]$HeartbeatAt = '2026-07-13T04:00:00.0000000+00:00'
    )

    return [pscustomobject][ordered]@{
        processId = 4321
        state = $State
        hookCount = 12
        retryCount = 3
        profileName = 'Test Profile'
        startedAt = '2026-07-13T03:30:00.0000000+00:00'
        remainingSeconds = 90
        lastError = $null
        heartbeatAt = $HeartbeatAt
        configVersion = 4
    }
}

Test-Case 'runtime module exports the public protocol functions' {
    $expectedNames = @(
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

    foreach ($name in $expectedNames) {
        $command = Get-Command -Name $name -ErrorAction SilentlyContinue
        Assert-True -Condition ($null -ne $command)
    }
}

Test-Case 'fixed delay rounds seconds to milliseconds away from zero' {
    $providerCalls = 0
    $actual = Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.0005 -MaximumSeconds 0.0005 `
        -RandomIntProvider { $providerCalls += 1; return 99 }

    Assert-Equal -Expected 1 -Actual $actual
    Assert-Equal -Expected 0 -Actual $providerCalls
}

Test-Case 'delay provider can choose the inclusive minimum endpoint' {
    $probe = [pscustomobject]@{ Minimum = $null; Maximum = $null }
    $actual = Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.301 -MaximumSeconds 0.709 `
        -RandomIntProvider {
            param($minimum, $maximum)
            $probe.Minimum = $minimum
            $probe.Maximum = $maximum
            return $minimum
        }

    Assert-Equal -Expected 301 -Actual $probe.Minimum
    Assert-Equal -Expected 709 -Actual $probe.Maximum
    Assert-Equal -Expected 301 -Actual $actual
}

Test-Case 'delay provider can choose the inclusive maximum endpoint' {
    $actual = Get-AIFishBotDelayMilliseconds -MinimumSeconds 0.3 -MaximumSeconds 0.7 `
        -RandomIntProvider { param($minimum, $maximum) return $maximum }

    Assert-Equal -Expected 700 -Actual $actual
}

Test-Case 'delay rejects negative seconds' {
    Assert-Throws -ScriptBlock {
        Get-AIFishBotDelayMilliseconds -MinimumSeconds -0.1 -MaximumSeconds 1
    } -MessageLike '*non-negative*'
}

Test-Case 'delay rejects a reversed range' {
    Assert-Throws -ScriptBlock {
        Get-AIFishBotDelayMilliseconds -MinimumSeconds 1.1 -MaximumSeconds 1
    } -MessageLike '*minimum*maximum*'
}

Test-Case 'delay rejects a provider result above the inclusive range' {
    Assert-Throws -ScriptBlock {
        Get-AIFishBotDelayMilliseconds -MinimumSeconds 1 -MaximumSeconds 2 `
            -RandomIntProvider { param($minimum, $maximum) return ($maximum + 1) }
    } -MessageLike '*outside*range*'
}

Test-Case 'delay rejects a fractional provider result' {
    Assert-Throws -ScriptBlock {
        Get-AIFishBotDelayMilliseconds -MinimumSeconds 1 -MaximumSeconds 2 `
            -RandomIntProvider { return 1500.5 }
    } -MessageLike '*whole number*'
}

Test-Case 'atomic JSON round trips Unicode data as strict UTF-8' {
    $directory = New-TestDirectory
    try {
        $path = Join-Path -Path $directory -ChildPath 'data.json'
        $unicodeName = [string]([char[]]@(0x9493, 0x9C7C, 0x4F1A, 0x8BDD))
        $value = [pscustomobject][ordered]@{
            name = $unicodeName
            count = 7
            nested = [pscustomobject]@{ enabled = $true }
        }

        Write-AIFishBotAtomicJson -Path $path -InputObject $value -CreateNew | Out-Null
        $actual = Read-AIFishBotJson -Path $path
        $bytes = [System.IO.File]::ReadAllBytes($path)

        Assert-Equal -Expected $unicodeName -Actual $actual.name
        Assert-Equal -Expected 7 -Actual $actual.count
        Assert-Equal -Expected $true -Actual $actual.nested.enabled
        Assert-True -Condition (-not ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    }
    finally {
        Remove-RuntimeTestDirectory -Path $directory
    }
}

Test-Case 'atomic JSON replacement preserves the previous file as a backup' {
    $directory = New-TestDirectory
    try {
        $path = Join-Path -Path $directory -ChildPath 'replace.json'
        Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ version = 1 }) -CreateNew | Out-Null
        Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ version = 2 }) | Out-Null

        Assert-Equal -Expected 2 -Actual (Read-AIFishBotJson -Path $path).version
        Assert-Equal -Expected 1 -Actual (Read-AIFishBotJson -Path ($path + '.backup')).version
    }
    finally {
        Remove-RuntimeTestDirectory -Path $directory
    }
}

Test-Case 'atomic JSON create-new never overwrites an existing target' {
    $directory = New-TestDirectory
    try {
        $path = Join-Path -Path $directory -ChildPath 'create.json'
        Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ owner = 'first' }) -CreateNew | Out-Null

        Assert-Throws -ScriptBlock {
            Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ owner = 'second' }) -CreateNew
        }
        Assert-Equal -Expected 'first' -Actual (Read-AIFishBotJson -Path $path).owner
    }
    finally {
        Remove-RuntimeTestDirectory -Path $directory
    }
}

Test-Case 'failed atomic JSON serialization leaves the old file and no temporary file' {
    $directory = New-TestDirectory
    try {
        $path = Join-Path -Path $directory -ChildPath 'safe.json'
        Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ value = 'old' }) -CreateNew | Out-Null
        $cyclic = [pscustomobject]@{ value = 'bad' }
        $cyclic | Add-Member -MemberType NoteProperty -Name self -Value $cyclic

        Assert-Throws -ScriptBlock {
            Write-AIFishBotAtomicJson -Path $path -InputObject $cyclic
        }
        Assert-Equal -Expected 'old' -Actual (Read-AIFishBotJson -Path $path).value
        Assert-Equal -Expected 0 -Actual @(Get-ChildItem -LiteralPath $directory -Filter '*.tmp').Count
    }
    finally {
        Remove-RuntimeTestDirectory -Path $directory
    }
}

Test-Case 'concurrent atomic JSON writers always leave one complete document' {
    $directory = New-TestDirectory
    $workers = @()
    try {
        $path = Join-Path -Path $directory -ChildPath 'concurrent.json'
        Write-AIFishBotAtomicJson -Path $path -InputObject ([pscustomobject]@{ writer = -1; payload = ('x' * 2048) }) -CreateNew | Out-Null

        foreach ($writer in 0..3) {
            $powerShell = [powershell]::Create()
            [void]$powerShell.AddScript({
                    param($modulePath, $targetPath, $writerNumber)
                    Import-Module -Name $modulePath -Force -ErrorAction Stop
                    foreach ($iteration in 0..7) {
                        Write-AIFishBotAtomicJson -Path $targetPath -InputObject ([pscustomobject]@{
                                writer = $writerNumber
                                iteration = $iteration
                                payload = ([string]$writerNumber * 2048)
                            }) | Out-Null
                    }
                }).AddArgument($script:RuntimeModulePath).AddArgument($path).AddArgument($writer)
            $workers += [pscustomobject]@{
                PowerShell = $powerShell
                Async = $powerShell.BeginInvoke()
            }
        }

        foreach ($worker in $workers) {
            [void]$worker.PowerShell.EndInvoke($worker.Async)
            if ($worker.PowerShell.HadErrors) {
                throw [string]$worker.PowerShell.Streams.Error[0]
            }
        }

        $actual = Read-AIFishBotJson -Path $path
        Assert-True -Condition ($actual.writer -in 0..3)
        Assert-Equal -Expected 7 -Actual $actual.iteration
        Assert-Equal -Expected 2048 -Actual $actual.payload.Length
        Assert-Equal -Expected 0 -Actual @(Get-ChildItem -LiteralPath $directory -Filter '*.tmp').Count
    }
    finally {
        foreach ($worker in $workers) {
            $worker.PowerShell.Dispose()
        }
        Remove-RuntimeTestDirectory -Path $directory
    }
}

Test-Case 'run directories are unique and contain immutable start and writable live configs' {
    $runtimeRoot = New-TestDirectory
    try {
        $config = [pscustomobject][ordered]@{ profileName = 'Main Profile'; configVersion = 1 }
        $first = New-AIFishBotRunDirectory -RuntimeRoot $runtimeRoot -StartConfig $config
        $second = New-AIFishBotRunDirectory -RuntimeRoot $runtimeRoot -StartConfig $config

        Assert-True -Condition ($first -ne $second)
        Assert-True -Condition (Test-Path -LiteralPath $first -PathType Container)
        $startPath = Join-Path -Path $first -ChildPath 'start-config.json'
        $livePath = Join-Path -Path $first -ChildPath 'live-config.json'
        Assert-Equal -Expected 'Main Profile' -Actual (Read-AIFishBotJson -Path $startPath).profileName
        Assert-Equal -Expected 1 -Actual (Read-AIFishBotJson -Path $livePath).configVersion
        Assert-True -Condition (([System.IO.File]::GetAttributes($startPath) -band
                    [System.IO.FileAttributes]::ReadOnly) -ne 0)

        Write-AIFishBotAtomicJson -Path $livePath -InputObject ([pscustomobject]@{
                profileName = 'Main Profile'; configVersion = 2
            }) | Out-Null
        Assert-Equal -Expected 2 -Actual (Read-AIFishBotJson -Path $livePath).configVersion
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runtimeRoot
    }
}

Test-Case 'status round trip contains exactly the fixed protocol fields' {
    $runDirectory = New-TestDirectory
    try {
        Write-AIFishBotStatus -RunDirectory $runDirectory -Status (New-RuntimeStatus) | Out-Null
        $actual = Read-AIFishBotStatus -RunDirectory $runDirectory
        $expectedNames = @(
            'processId', 'state', 'hookCount', 'retryCount', 'profileName', 'startedAt',
            'remainingSeconds', 'lastError', 'heartbeatAt', 'configVersion'
        )

        Assert-Equal -Expected $expectedNames -Actual @($actual.PSObject.Properties.Name)
        Assert-Equal -Expected 4321 -Actual $actual.processId
        Assert-Equal -Expected 'running' -Actual $actual.state
        Assert-Equal -Expected 4 -Actual $actual.configVersion
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'status replacement is atomic and keeps a backup' {
    $runDirectory = New-TestDirectory
    try {
        Write-AIFishBotStatus -RunDirectory $runDirectory -Status (New-RuntimeStatus -State 'starting') | Out-Null
        Write-AIFishBotStatus -RunDirectory $runDirectory -Status (New-RuntimeStatus -State 'running') | Out-Null

        Assert-Equal -Expected 'running' -Actual (Read-AIFishBotStatus -RunDirectory $runDirectory).state
        Assert-Equal -Expected 'starting' -Actual (Read-AIFishBotJson -Path (
                (Join-Path -Path $runDirectory -ChildPath 'status.json') + '.backup')).state
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'stop control command has an identity and timestamp and can be consumed once' {
    $runDirectory = New-TestDirectory
    try {
        $createdAt = [datetimeoffset]'2026-07-13T04:05:00+00:00'
        $written = Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command 'stop' `
            -CommandId 'command-1' -CreatedAt $createdAt
        $peeked = Read-AIFishBotControlCommand -RunDirectory $runDirectory
        $consumed = Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume
        $secondRead = Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume

        Assert-Equal -Expected 'stop' -Actual $written.command
        Assert-Equal -Expected 'command-1' -Actual $peeked.commandId
        Assert-Equal -Expected 'command-1' -Actual $consumed.commandId
        Assert-Equal -Expected '2026-07-13T04:05:00.0000000+00:00' -Actual $written.createdAt
        Assert-True -Condition ($null -eq $secondRead)
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'a consumed command identity is never returned again' {
    $runDirectory = New-TestDirectory
    try {
        Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command stop -CommandId 'duplicate-id' | Out-Null
        $first = Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume
        Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command stop -CommandId 'duplicate-id' | Out-Null
        $duplicate = Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume

        Assert-Equal -Expected 'duplicate-id' -Actual $first.commandId
        Assert-True -Condition ($null -eq $duplicate)
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'consuming returns a command even when its pending file is temporarily locked' {
    $runDirectory = New-TestDirectory
    $lockStream = $null
    try {
        Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command stop -CommandId 'locked-id' | Out-Null
        $controlPath = Join-Path -Path $runDirectory -ChildPath 'control.json'
        $lockStream = New-Object System.IO.FileStream(
            $controlPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read)

        $consumed = Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume
        Assert-Equal -Expected 'locked-id' -Actual $consumed.commandId
        $lockStream.Dispose()
        $lockStream = $null
        Assert-True -Condition ($null -eq (Read-AIFishBotControlCommand -RunDirectory $runDirectory -Consume))
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
        }
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'control protocol rejects unsupported commands' {
    $runDirectory = New-TestDirectory
    try {
        Assert-Throws -ScriptBlock {
            Write-AIFishBotControlCommand -RunDirectory $runDirectory -Command pause
        } -MessageLike '*Unsupported*command*'
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'heartbeat is fresh at the maximum allowed age' {
    $status = New-RuntimeStatus -HeartbeatAt '2026-07-13T04:00:00+00:00'
    $actual = Test-AIFishBotHeartbeatFresh -Status $status `
        -Now ([datetimeoffset]'2026-07-13T04:00:30+00:00') -MaxAgeSeconds 30

    Assert-Equal -Expected $true -Actual $actual
}

Test-Case 'heartbeat is stale when it is missing' {
    $status = New-RuntimeStatus
    $status.PSObject.Properties.Remove('heartbeatAt')

    Assert-Equal -Expected $false -Actual (Test-AIFishBotHeartbeatFresh -Status $status `
            -Now ([datetimeoffset]'2026-07-13T04:00:30+00:00') -MaxAgeSeconds 30)
}

Test-Case 'heartbeat is stale when it is in the future' {
    $status = New-RuntimeStatus -HeartbeatAt '2026-07-13T04:00:31+00:00'

    Assert-Equal -Expected $false -Actual (Test-AIFishBotHeartbeatFresh -Status $status `
            -Now ([datetimeoffset]'2026-07-13T04:00:30+00:00') -MaxAgeSeconds 30)
}

Test-Case 'heartbeat is stale after the maximum allowed age' {
    $status = New-RuntimeStatus -HeartbeatAt '2026-07-13T03:59:59+00:00'

    Assert-Equal -Expected $false -Actual (Test-AIFishBotHeartbeatFresh -Status $status `
            -Now ([datetimeoffset]'2026-07-13T04:00:30+00:00') -MaxAgeSeconds 30)
}

Test-Case 'secret protection masks a complete Discord webhook value' {
    $secret = 'https://discord.com/api/webhooks/123456/very.secret-token_ABC'

    Assert-Equal -Expected 'https://discord.com/api/webhooks/***' -Actual (Protect-AIFishBotSecret -Text $secret)
}

Test-Case 'secret protection masks Discord webhooks embedded in other text' {
    $text = 'Send to https://discord.com/api/webhooks/987654/token-value when ready'

    Assert-Equal -Expected 'Send to https://discord.com/api/webhooks/*** when ready' `
        -Actual (Protect-AIFishBotSecret -Text $text)
}

Test-Case 'dated logs contain levels and never expose Discord webhook tokens' {
    $runDirectory = New-TestDirectory
    try {
        $secret = 'https://discord.com/api/webhooks/123456/do-not-leak-this-token'
        $date = [datetimeoffset]'2026-07-13T12:34:56.789+08:00'
        $firstPath = Write-AIFishBotLog -RunDirectory $runDirectory -Level Info `
            -Message "Notify $secret" -Now $date
        $secondPath = Write-AIFishBotLog -RunDirectory $runDirectory -Level Error `
            -Message 'Notification failed' -Now $date
        $bytes = [System.IO.File]::ReadAllBytes($firstPath)
        $text = [System.IO.File]::ReadAllText($firstPath, (New-Object System.Text.UTF8Encoding($false, $true)))

        Assert-Equal -Expected $firstPath -Actual $secondPath
        Assert-Equal -Expected '2026-07-13.log' -Actual (Split-Path -Path $firstPath -Leaf)
        Assert-True -Condition ($text.Contains('2026-07-13T12:34:56.7890000+08:00 [INFO]'))
        Assert-True -Condition ($text.Contains('[ERROR]'))
        Assert-True -Condition ($text.Contains('https://discord.com/api/webhooks/***'))
        Assert-True -Condition (-not $text.Contains('do-not-leak-this-token'))
        Assert-True -Condition (-not ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}

Test-Case 'logs preserve the complete warning level name' {
    $runDirectory = New-TestDirectory
    try {
        $path = Write-AIFishBotLog -RunDirectory $runDirectory -Level Warning `
            -Message 'A warning' -Now ([datetimeoffset]'2026-07-13T12:00:00+08:00')
        $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false, $true)))

        Assert-True -Condition ($text.Contains('[WARNING]'))
    }
    finally {
        Remove-RuntimeTestDirectory -Path $runDirectory
    }
}
