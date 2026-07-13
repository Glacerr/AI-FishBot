$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestHarness.ps1')

$testFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
        Sort-Object -Property Name)
$loadFailures = 0

if ($testFiles.Count -eq 0) {
    Write-Host 'FAIL: no test files were found.'
    Write-Host ''
    Write-Host 'Tests: 0; Passed: 0; Failed: 1'
    exit 1
}

foreach ($testFile in $testFiles) {
    try {
        . $testFile.FullName
    }
    catch {
        $loadFailures += 1
        Write-Host "FAIL: unable to load $($testFile.Name)"
        Write-Host ("  {0}" -f $_.Exception.Message)
    }
}

$total = $script:TestTotal + $loadFailures
$failed = $script:TestFailed + $loadFailures
$passed = $total - $failed

if ($total -eq 0) {
    Write-Host 'FAIL: no test cases were found.'
    $failed = 1
}

Write-Host ''
Write-Host ('Tests: {0}; Passed: {1}; Failed: {2}' -f $total, $passed, $failed)

if ($failed -gt 0) {
    exit 1
}

exit 0
