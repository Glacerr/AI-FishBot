$script:DependenciesTestRoot = Split-Path -Path $PSScriptRoot -Parent
$script:DependenciesModulePath = Join-Path -Path $script:DependenciesTestRoot -ChildPath 'AI-FishBot.Dependencies.psm1'

if (-not (Test-Path -LiteralPath $script:DependenciesModulePath -PathType Leaf)) {
    Test-Case 'dependencies module exists before its behavior is tested' {
        Assert-True -Condition (Test-Path -LiteralPath $script:DependenciesModulePath -PathType Leaf)
    }
    return
}

Import-Module -Name $script:DependenciesModulePath -Force -ErrorAction Stop

function New-DependencyInstallScenario {
    param(
        [bool]$InitiallyAvailable = $false,
        [bool]$AvailableAfterInstall = $true,
        [string]$MissingSourceFile,
        [string]$FailAt
    )

    $testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath ('AI-FishBot.DependencyMock.{0}' -f [guid]::NewGuid().ToString('N'))
    $sourceDirectory = Join-Path -Path $testRoot -ChildPath 'project\AudioModule'
    $modulePath = Join-Path -Path $testRoot -ChildPath 'profile\Modules\AudioDeviceCmdlets'
    $context = [pscustomobject]@{
        Steps = New-Object 'System.Collections.Generic.List[string]'
        ObservedPaths = New-Object 'System.Collections.Generic.List[string]'
        FinderCalls = 0
        InitiallyAvailable = $InitiallyAvailable
        AvailableAfterInstall = $AvailableAfterInstall
        MissingSourceFile = $MissingSourceFile
        FailAt = $FailAt
    }
    $captured = $context

    $options = @{
        SourceDirectory = $sourceDirectory
        ModulePath = $modulePath
        CommandFinder = ({
                param($name)
                [void]$captured.Steps.Add(('check:{0}' -f $name))
                $captured.FinderCalls += 1
                if ($captured.FinderCalls -eq 1) {
                    if ($captured.InitiallyAvailable) {
                        return [pscustomobject]@{ Name = $name }
                    }
                    return $null
                }
                if ($captured.AvailableAfterInstall) {
                    return [pscustomobject]@{ Name = $name }
                }
                return $null
            }.GetNewClosure())
        PathTester = ({
                param($path, $pathType)
                $leaf = Split-Path -Path $path -Leaf
                [void]$captured.Steps.Add(('exists:{0}' -f $leaf))
                [void]$captured.ObservedPaths.Add([string]$path)
                return ($leaf -ne $captured.MissingSourceFile)
            }.GetNewClosure())
        DirectoryCreator = ({
                param($path)
                [void]$captured.Steps.Add('mkdir')
                [void]$captured.ObservedPaths.Add([string]$path)
                if ($captured.FailAt -eq 'mkdir') {
                    throw 'mock directory denied'
                }
            }.GetNewClosure())
        CopyProvider = ({
                param($source, $destination)
                $step = 'copy:{0}' -f (Split-Path -Path $source -Leaf)
                [void]$captured.Steps.Add($step)
                [void]$captured.ObservedPaths.Add([string]$source)
                [void]$captured.ObservedPaths.Add([string]$destination)
                if ($captured.FailAt -eq $step) {
                    throw 'mock copy denied'
                }
            }.GetNewClosure())
        UnblockProvider = ({
                param($path)
                $step = 'unblock:{0}' -f (Split-Path -Path $path -Leaf)
                [void]$captured.Steps.Add($step)
                [void]$captured.ObservedPaths.Add([string]$path)
                if ($captured.FailAt -eq $step) {
                    throw 'mock unblock denied'
                }
            }.GetNewClosure())
        ModuleImporter = ({
                param($path)
                [void]$captured.Steps.Add(('import:{0}' -f (Split-Path -Path $path -Leaf)))
                [void]$captured.ObservedPaths.Add([string]$path)
                if ($captured.FailAt -eq 'import') {
                    throw 'mock import denied'
                }
            }.GetNewClosure())
    }

    return [pscustomobject]@{
        Context = $context
        Options = $options
        SourceDirectory = $sourceDirectory
        ModulePath = $modulePath
        TestRoot = $testRoot
    }
}

Test-Case 'dependency module exports only its two public commands' {
    $module = Get-Module | Where-Object { $_.Path -eq $script:DependenciesModulePath } | Select-Object -First 1
    Assert-Equal -Expected @(
        'Install-AIFishBotAudioDependency',
        'Test-AIFishBotAudioDependency'
    ) -Actual @($module.ExportedFunctions.Keys | Sort-Object)
}

Test-Case 'dependency check reports available without changing anything' {
    $calls = New-Object 'System.Collections.Generic.List[string]'
    $captured = $calls
    $result = Test-AIFishBotAudioDependency -CommandFinder ({
            param($name)
            [void]$captured.Add($name)
            return [pscustomobject]@{ Name = $name }
        }.GetNewClosure())

    Assert-Equal -Expected 'Available' -Actual $result.Status
    Assert-Equal -Expected $true -Actual $result.Available
    Assert-True -Condition ($result.Summary -like '*可用*')
    Assert-True -Condition ($result.Details -like '*Write-AudioDevice*')
    Assert-Equal -Expected @('Write-AudioDevice') -Actual @($calls)
}

Test-Case 'dependency check reports missing and never starts installation work' {
    $calls = New-Object 'System.Collections.Generic.List[string]'
    $captured = $calls
    $result = Test-AIFishBotAudioDependency -CommandFinder ({
            param($name)
            [void]$captured.Add($name)
            return $null
        }.GetNewClosure())

    Assert-Equal -Expected 'Missing' -Actual $result.Status
    Assert-Equal -Expected $false -Actual $result.Available
    Assert-True -Condition ($result.Summary -like '*缺少*')
    Assert-True -Condition ($result.Details -like '*Write-AudioDevice*')
    Assert-Equal -Expected @('Write-AudioDevice') -Actual @($calls)
}

Test-Case 'dependency check reports finder errors with full details' {
    $result = Test-AIFishBotAudioDependency -CommandFinder {
        param($name)
        throw 'mock command lookup failed'
    }

    Assert-Equal -Expected 'Error' -Actual $result.Status
    Assert-Equal -Expected $false -Actual $result.Available
    Assert-True -Condition ($result.Summary -like '*检查*失败*')
    Assert-True -Condition ($result.Details -like '*mock command lookup failed*')
}

Test-Case 'explicit install is idempotent when dependency is already available' {
    $scenario = New-DependencyInstallScenario -InitiallyAvailable $true
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*已经可用*')
    Assert-Equal -Expected $scenario.ModulePath -Actual $result.ModulePath
    Assert-Equal -Expected @('check:Write-AudioDevice') -Actual @($scenario.Context.Steps)
    Assert-Equal -Expected $false -Actual ([System.IO.Directory]::Exists($scenario.TestRoot))
}

Test-Case 'explicit install validates both source files before creating a directory' {
    $scenario = New-DependencyInstallScenario -MissingSourceFile 'AudioDeviceCmdlets.psd1'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*源文件*')
    Assert-True -Condition ($result.Details -like '*AudioDeviceCmdlets.psd1*')
    Assert-Equal -Expected @(
        'check:Write-AudioDevice',
        'exists:AudioDeviceCmdlets.dll',
        'exists:AudioDeviceCmdlets.psd1'
    ) -Actual @($scenario.Context.Steps)
    Assert-Equal -Expected $scenario.ModulePath -Actual $result.ModulePath
}

Test-Case 'explicit install reports directory creation failure and stops' {
    $scenario = New-DependencyInstallScenario -FailAt 'mkdir'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*目录*失败*')
    Assert-True -Condition ($result.Details -like '*mock directory denied*')
    Assert-Equal -Expected 'mkdir' -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports copy failure and stops before unblock' {
    $scenario = New-DependencyInstallScenario -FailAt 'copy:AudioDeviceCmdlets.psd1'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*复制*失败*')
    Assert-True -Condition ($result.Details -like '*mock copy denied*')
    Assert-Equal -Expected 'copy:AudioDeviceCmdlets.psd1' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports unblock failure and stops before import' {
    $scenario = New-DependencyInstallScenario -FailAt 'unblock:AudioDeviceCmdlets.dll'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*解锁*失败*')
    Assert-True -Condition ($result.Details -like '*mock unblock denied*')
    Assert-Equal -Expected 'unblock:AudioDeviceCmdlets.dll' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports module import failure and does not recheck' {
    $scenario = New-DependencyInstallScenario -FailAt 'import'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*加载*失败*')
    Assert-True -Condition ($result.Details -like '*mock import denied*')
    Assert-Equal -Expected 'import:AudioDeviceCmdlets.psd1' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
    Assert-Equal -Expected 1 -Actual $scenario.Context.FinderCalls
}

Test-Case 'explicit install fails when command is still missing after import' {
    $scenario = New-DependencyInstallScenario -AvailableAfterInstall $false
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*仍不可用*')
    Assert-True -Condition ($result.Details -like '*Write-AudioDevice*')
    Assert-Equal -Expected 2 -Actual $scenario.Context.FinderCalls
}

Test-Case 'explicit install supports Installer as the injected import action' {
    $scenario = New-DependencyInstallScenario
    $captured = $scenario.Context
    $scenario.Options.Installer = ({
            param($path)
            [void]$captured.Steps.Add(('installer:{0}' -f (Split-Path -Path $path -Leaf)))
        }.GetNewClosure())
    $scenario.Options.ModuleImporter = {
        param($path)
        throw 'ModuleImporter must not run when Installer is supplied'
    }

    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Steps) -contains 'installer:AudioDeviceCmdlets.psd1')
    Assert-Equal -Expected $false `
        -Actual (($scenario.Context.Steps -join "`n") -like '*import:AudioDeviceCmdlets.psd1*')
}

Test-Case 'explicit install returns one result even when injected actions produce output' {
    $scenario = New-DependencyInstallScenario
    $scenario.Options.DirectoryCreator = { param($path) return 'mock directory output' }
    $scenario.Options.CopyProvider = { param($source, $destination) return 'mock copy output' }
    $scenario.Options.UnblockProvider = { param($path) return 'mock unblock output' }
    $scenario.Options.ModuleImporter = { param($path) return 'mock import output' }
    $options = $scenario.Options

    $results = @(Install-AIFishBotAudioDependency @options)

    Assert-Equal -Expected 1 -Actual $results.Count
    Assert-Equal -Expected $true -Actual $results[0].Success
}

Test-Case 'explicit install succeeds in order while all filesystem work remains simulated' {
    $scenario = New-DependencyInstallScenario
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*完成*')
    Assert-True -Condition ($result.Details -like '*Write-AudioDevice*')
    Assert-Equal -Expected $scenario.ModulePath -Actual $result.ModulePath
    Assert-Equal -Expected @(
        'check:Write-AudioDevice',
        'exists:AudioDeviceCmdlets.dll',
        'exists:AudioDeviceCmdlets.psd1',
        'mkdir',
        'copy:AudioDeviceCmdlets.dll',
        'copy:AudioDeviceCmdlets.psd1',
        'unblock:AudioDeviceCmdlets.dll',
        'unblock:AudioDeviceCmdlets.psd1',
        'import:AudioDeviceCmdlets.psd1',
        'check:Write-AudioDevice'
    ) -Actual @($scenario.Context.Steps)

    $realModulePath = Join-Path -Path (Join-Path -Path (Split-Path -Path $PROFILE -Parent) `
            -ChildPath 'Modules') -ChildPath 'AudioDeviceCmdlets'
    foreach ($observedPath in $scenario.Context.ObservedPaths) {
        Assert-True -Condition $observedPath.StartsWith(
            $scenario.TestRoot,
            [System.StringComparison]::OrdinalIgnoreCase)
        Assert-Equal -Expected $false -Actual $observedPath.StartsWith(
            $realModulePath,
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    Assert-Equal -Expected $false -Actual ([System.IO.Directory]::Exists($scenario.TestRoot))
}
