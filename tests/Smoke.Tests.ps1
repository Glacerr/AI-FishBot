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
