$script:TestTotal = 0
$script:TestFailed = 0

function Test-Case {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory = $true, Position = 1)]
        [scriptblock]$ScriptBlock
    )

    $script:TestTotal += 1

    try {
        & $ScriptBlock
        Write-Host "PASS: $Name"
    }
    catch {
        $script:TestFailed += 1
        Write-Host "FAIL: $Name"
        Write-Host ("  {0}" -f $_.Exception.Message)
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Expected,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Actual
    )

    $expectedIsArray = $Expected -is [System.Array]
    $actualIsArray = $Actual -is [System.Array]

    if ($expectedIsArray -or $actualIsArray) {
        if (-not ($expectedIsArray -and $actualIsArray)) {
            throw "Expected '$Expected', but received '$Actual'."
        }

        if ($Expected.Count -ne $Actual.Count) {
            throw "Expected array length $($Expected.Count), but received $($Actual.Count)."
        }

        for ($index = 0; $index -lt $Expected.Count; $index += 1) {
            try {
                Assert-Equal -Expected $Expected[$index] -Actual $Actual[$index]
            }
            catch {
                throw "Arrays differ at index ${index}: $($_.Exception.Message)"
            }
        }

        return
    }

    if ($Expected -ne $Actual) {
        throw "Expected '$Expected', but received '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition
    )

    if (-not $Condition) {
        throw 'Expected condition to be true.'
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [string]$MessageLike
    )

    $caughtException = $null

    try {
        & $ScriptBlock
    }
    catch {
        $caughtException = $_.Exception
    }

    if ($null -eq $caughtException) {
        throw 'Expected the script block to throw an exception.'
    }

    if ($PSBoundParameters.ContainsKey('MessageLike') -and $caughtException.Message -notlike $MessageLike) {
        throw "Expected exception message like '$MessageLike', but received '$($caughtException.Message)'."
    }
}

function New-TestDirectory {
    $directoryName = 'AI-FishBot.Tests.{0}' -f [guid]::NewGuid().ToString('N')
    $directoryPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $directoryName
    $directory = New-Item -ItemType Directory -Path $directoryPath -ErrorAction Stop

    return $directory.FullName
}
