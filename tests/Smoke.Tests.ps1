$script:SmokeTestRoot = $PSScriptRoot

function Invoke-IsolatedTestRunner {
    param(
        [switch]$WithEmptyTestFile
    )

    $testDirectory = New-TestDirectory

    try {
        Copy-Item -LiteralPath (Join-Path $script:SmokeTestRoot 'Run-Tests.ps1') -Destination $testDirectory
        Copy-Item -LiteralPath (Join-Path $script:SmokeTestRoot 'TestHarness.ps1') -Destination $testDirectory

        if ($WithEmptyTestFile) {
            $null = New-Item -ItemType File -Path (Join-Path $testDirectory 'Empty.Tests.ps1')
        }

        $output = @(& powershell.exe -NoProfile -File (Join-Path $testDirectory 'Run-Tests.ps1') 2>&1)
        $exitCode = $LASTEXITCODE

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output -join [Environment]::NewLine
        }
    }
    finally {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'basic assertions accept valid values' {
    Assert-Equal -Expected 4 -Actual (2 + 2)
    Assert-True -Condition $true
}

Test-Case 'failed assertions can be detected' {
    Assert-Throws -ScriptBlock {
        Assert-Equal -Expected 'expected' -Actual 'actual'
    }

    Assert-Throws -ScriptBlock {
        Assert-True -Condition $false
    }
}

Test-Case 'test directories are unique and created on disk' {
    $firstDirectory = New-TestDirectory
    $secondDirectory = New-TestDirectory

    try {
        Assert-True -Condition (Test-Path -LiteralPath $firstDirectory -PathType Container)
        Assert-True -Condition (Test-Path -LiteralPath $secondDirectory -PathType Container)
        Assert-Throws -ScriptBlock {
            Assert-Equal -Expected $firstDirectory -Actual $secondDirectory
        }
    }
    finally {
        Remove-Item -LiteralPath $firstDirectory, $secondDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case 'Assert-Throws matches exception messages' {
    Assert-Throws -ScriptBlock {
        throw 'fishing hook failed'
    } -MessageLike '*hook failed'
}

Test-Case 'Assert-Throws reports when no exception is thrown' {
    Assert-Throws -ScriptBlock {
        Assert-Throws -ScriptBlock {
            $value = 42
        }
    } -MessageLike '*Expected the script block to throw an exception.*'
}

Test-Case 'Assert-Throws reports exception message mismatches' {
    Assert-Throws -ScriptBlock {
        Assert-Throws -ScriptBlock {
            throw 'actual problem'
        } -MessageLike 'expected problem'
    } -MessageLike "*Expected exception message like 'expected problem', but received 'actual problem'.*"
}

Test-Case 'Assert-Equal compares numeric values across types' {
    Assert-Equal -Expected ([int]1) -Actual ([long]1)
}

Test-Case 'Assert-Equal compares arrays item by item' {
    Assert-Equal -Expected @('one', [int]2) -Actual @('one', [long]2)

    Assert-Throws -ScriptBlock {
        Assert-Equal -Expected @('one', 'two') -Actual @('one', 'changed')
    } -MessageLike "*index 1*Expected 'two', but received 'changed'.*"
}

Test-Case 'runner fails when no test files exist' {
    $result = Invoke-IsolatedTestRunner

    Assert-Equal -Expected 1 -Actual $result.ExitCode
    Assert-True -Condition ($result.Output -like '*FAIL: no test files were found.*')
}

Test-Case 'runner fails when test files contain no test cases' {
    $result = Invoke-IsolatedTestRunner -WithEmptyTestFile

    Assert-Equal -Expected 1 -Actual $result.ExitCode
    Assert-True -Condition ($result.Output -like '*FAIL: no test cases were found.*')
}
