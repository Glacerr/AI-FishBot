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

    if (-not [object]::Equals($Expected, $Actual)) {
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
        [scriptblock]$ScriptBlock
    )

    $exceptionWasThrown = $false

    try {
        & $ScriptBlock
    }
    catch {
        $exceptionWasThrown = $true
    }

    if (-not $exceptionWasThrown) {
        throw 'Expected the script block to throw an exception.'
    }
}

function New-TestDirectory {
    $directoryName = 'AI-FishBot.Tests.{0}' -f [guid]::NewGuid().ToString('N')
    $directoryPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $directoryName
    $directory = New-Item -ItemType Directory -Path $directoryPath -ErrorAction Stop

    return $directory.FullName
}
