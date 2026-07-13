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
    $stagingPath = $modulePath + '.staging.scenario-op'
    $backupPath = $modulePath + '.backup.scenario-op'
    $context = [pscustomobject]@{
        Steps = New-Object 'System.Collections.Generic.List[string]'
        ObservedPaths = New-Object 'System.Collections.Generic.List[string]'
        FinderCalls = 0
        InitiallyAvailable = $InitiallyAvailable
        AvailableAfterInstall = $AvailableAfterInstall
        MissingSourceFile = $MissingSourceFile
        FailAt = $FailAt
        TargetExists = $false
    }
    $captured = $context
    $mutexHarness = New-DependencyMutexHarness

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
                if ($captured.FinderCalls -eq 2) {
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
                if ($pathType -eq 'Leaf') {
                    return ($leaf -ne $captured.MissingSourceFile)
                }
                if ($pathType -eq 'Container' -and $path -eq $modulePath) {
                    return [bool]$captured.TargetExists
                }
                return $false
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
        MoveProvider = ({
                param($source, $destination)
                [void]$captured.ObservedPaths.Add([string]$source)
                [void]$captured.ObservedPaths.Add([string]$destination)
                if ($source -eq $stagingPath -and $destination -eq $modulePath) {
                    [void]$captured.Steps.Add('move:staging-to-target')
                    $captured.TargetExists = $true
                    return
                }
                if ($source -eq $modulePath -and $destination -eq $backupPath) {
                    [void]$captured.Steps.Add('move:target-to-backup')
                    $captured.TargetExists = $false
                    return
                }
                if ($source -eq $backupPath -and $destination -eq $modulePath) {
                    [void]$captured.Steps.Add('move:backup-to-target')
                    $captured.TargetExists = $true
                    return
                }
                throw ('unexpected mock move: {0} -> {1}' -f $source, $destination)
            }.GetNewClosure())
        RemoveProvider = ({
                param($path)
                [void]$captured.ObservedPaths.Add([string]$path)
                if ($path -eq $stagingPath) {
                    [void]$captured.Steps.Add('remove:staging')
                    return
                }
                if ($path -eq $modulePath) {
                    [void]$captured.Steps.Add('remove:target')
                    $captured.TargetExists = $false
                    return
                }
                if ($path -eq $backupPath) {
                    [void]$captured.Steps.Add('remove:backup')
                    return
                }
                throw ('unexpected mock remove: {0}' -f $path)
            }.GetNewClosure())
        ModuleImporter = ({
                param($path)
                [void]$captured.Steps.Add(('import:{0}' -f (Split-Path -Path $path -Leaf)))
                [void]$captured.ObservedPaths.Add([string]$path)
                if ($captured.FailAt -eq 'import') {
                    throw 'mock import denied'
                }
            }.GetNewClosure())
        OperationIdProvider = { return 'scenario-op' }
        MutexFactory = $mutexHarness.Factory
    }

    return [pscustomobject]@{
        Context = $context
        Options = $options
        SourceDirectory = $sourceDirectory
        ModulePath = $modulePath
        TestRoot = $testRoot
        MutexHarness = $mutexHarness
    }
}

function New-TransactionalDependencyScenario {
    param(
        [bool]$TargetExists = $true,
        [bool]$AvailableInsideLock = $false,
        [bool]$AvailableAfterInstall = $true,
        [string]$FailAt
    )

    $testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) `
        -ChildPath ('AI-FishBot.TransactionMock.{0}' -f [guid]::NewGuid().ToString('N'))
    $sourceDirectory = Join-Path -Path $testRoot -ChildPath 'project\AudioModule'
    $modulePath = Join-Path -Path $testRoot -ChildPath 'profile\Modules\AudioDeviceCmdlets'
    $context = [pscustomobject]@{
        Calls = New-Object 'System.Collections.Generic.List[string]'
        FinderCalls = 0
        TargetExists = $TargetExists
        StagingExists = $false
        BackupExists = $false
        AvailableInsideLock = $AvailableInsideLock
        AvailableAfterInstall = $AvailableAfterInstall
        FailAt = $FailAt
    }
    $captured = $context
    $mutexHarness = New-DependencyMutexHarness
    $stagingPath = $modulePath + '.staging.unit-op'
    $backupPath = $modulePath + '.backup.unit-op'

    $options = @{
        SourceDirectory = $sourceDirectory
        ModulePath = $modulePath
        CommandFinder = ({
                param($name)
                $captured.FinderCalls += 1
                [void]$captured.Calls.Add(('check:{0}' -f $captured.FinderCalls))
                if ($captured.FinderCalls -eq 1) { return $null }
                if ($captured.FinderCalls -eq 2 -and $captured.AvailableInsideLock) {
                    return [pscustomobject]@{ Name = $name }
                }
                if ($captured.FinderCalls -ge 3 -and $captured.AvailableAfterInstall) {
                    return [pscustomobject]@{ Name = $name }
                }
                return $null
            }.GetNewClosure())
        TestPathProvider = ({
                param($path, $pathType)
                [void]$captured.Calls.Add(('exists:{0}:{1}' -f $pathType, $path))
                if ($pathType -eq 'Leaf') { return $true }
                if ($path -eq $modulePath) { return [bool]$captured.TargetExists }
                return $false
            }.GetNewClosure())
        DirectoryCreator = ({
                param($path)
                [void]$captured.Calls.Add(('mkdir:{0}' -f $path))
                if ($captured.FailAt -eq 'mkdir') { throw 'mock staging create failed' }
                if ($path -eq $stagingPath) { $captured.StagingExists = $true }
            }.GetNewClosure())
        CopyProvider = ({
                param($source, $destination)
                [void]$captured.Calls.Add(('copy:{0}->{1}' -f $source, $destination))
                if ($captured.FailAt -eq ('copy:{0}' -f (Split-Path -Path $source -Leaf))) {
                    throw 'mock staging copy failed'
                }
            }.GetNewClosure())
        UnblockProvider = ({
                param($path)
                [void]$captured.Calls.Add(('unblock:{0}' -f $path))
                if ($captured.FailAt -eq ('unblock:{0}' -f (Split-Path -Path $path -Leaf))) {
                    throw 'mock staging unblock failed'
                }
            }.GetNewClosure())
        MoveProvider = ({
                param($source, $destination)
                [void]$captured.Calls.Add(('move:{0}->{1}' -f $source, $destination))
                if ($captured.FailAt -eq ('move:{0}->{1}' -f $source, $destination)) {
                    throw 'mock transactional move failed'
                }
                if ($source -eq $modulePath -and $destination -eq $backupPath) {
                    $captured.TargetExists = $false
                    $captured.BackupExists = $true
                }
                elseif ($source -eq $stagingPath -and $destination -eq $modulePath) {
                    $captured.StagingExists = $false
                    $captured.TargetExists = $true
                }
                elseif ($source -eq $backupPath -and $destination -eq $modulePath) {
                    $captured.BackupExists = $false
                    $captured.TargetExists = $true
                }
            }.GetNewClosure())
        RemoveProvider = ({
                param($path)
                [void]$captured.Calls.Add(('remove:{0}' -f $path))
                if ($path -eq $stagingPath) { $captured.StagingExists = $false }
                if ($path -eq $modulePath) { $captured.TargetExists = $false }
                if ($path -eq $backupPath) { $captured.BackupExists = $false }
            }.GetNewClosure())
        ModuleImporter = ({
                param($path)
                [void]$captured.Calls.Add(('import:{0}' -f $path))
                if ($captured.FailAt -eq 'import') { throw 'mock transactional import failed' }
            }.GetNewClosure())
        OperationIdProvider = { return 'unit-op' }
        MutexFactory = $mutexHarness.Factory
    }

    return [pscustomobject]@{
        Context = $context
        Options = $options
        SourceDirectory = $sourceDirectory
        ModulePath = $modulePath
        StagingPath = $stagingPath
        BackupPath = $backupPath
        MutexHarness = $mutexHarness
    }
}

function New-DependencyMutexHarness {
    param(
        [switch]$AbandonFirstWait,
        [string]$WaitFailure
    )

    $context = [pscustomobject]@{
        Names = New-Object 'System.Collections.Generic.List[string]'
        WaitCount = 0
        ReleaseCount = 0
        DisposeCount = 0
        AbandonNext = [bool]$AbandonFirstWait
        WaitFailure = $WaitFailure
    }
    $captured = $context
    $factory = ({
            param($name)
            [void]$captured.Names.Add([string]$name)
            $mutex = [pscustomobject]@{ Context = $captured }
            $mutex | Add-Member -MemberType ScriptMethod -Name WaitOne -Value {
                    param($timeoutMilliseconds)
                    $this.Context.WaitCount += 1
                    if (-not [string]::IsNullOrWhiteSpace($this.Context.WaitFailure)) {
                        throw $this.Context.WaitFailure
                    }
                    if ($this.Context.AbandonNext) {
                        $this.Context.AbandonNext = $false
                        throw (New-Object System.Threading.AbandonedMutexException('mock abandoned mutex'))
                    }
                    return $true
                }
            $mutex | Add-Member -MemberType ScriptMethod -Name ReleaseMutex -Value {
                    $this.Context.ReleaseCount += 1
                }
            $mutex | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
                    $this.Context.DisposeCount += 1
                }
            return $mutex
        }.GetNewClosure())

    return [pscustomobject]@{ Context = $context; Factory = $factory }
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

Test-Case 'dependency check rejects multiple command objects as an ambiguous result' {
    $result = Test-AIFishBotAudioDependency -CommandFinder {
        param($name)
        [pscustomobject]@{ Name = $name; Source = 'first' }
        [pscustomobject]@{ Name = $name; Source = 'second' }
    }

    Assert-Equal -Expected 'Error' -Actual $result.Status
    Assert-Equal -Expected $false -Actual $result.Available
    Assert-True -Condition ($result.Summary -like '*检查*失败*')
    Assert-True -Condition ($result.Details -like '*一个*有效*对象*')
}

Test-Case 'dependency check rejects explanatory text alone or mixed with one command object' {
    $textOnly = Test-AIFishBotAudioDependency -CommandFinder {
        param($name)
        return 'mock lookup note'
    }
    $mixed = Test-AIFishBotAudioDependency -CommandFinder {
        param($name)
        'mock lookup note'
        [pscustomobject]@{ Name = $name }
    }

    Assert-Equal -Expected 'Error' -Actual $textOnly.Status
    Assert-Equal -Expected $false -Actual $textOnly.Available
    Assert-Equal -Expected 'Error' -Actual $mixed.Status
    Assert-Equal -Expected $false -Actual $mixed.Available
}

Test-Case 'dependency check masks the user profile path in error details' {
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $privatePath = Join-Path -Path $userProfile -ChildPath 'private\lookup.txt'
    $capturedPath = $privatePath
    $result = Test-AIFishBotAudioDependency -CommandFinder ({
            param($name)
            throw ('mock lookup failed at {0}' -f $capturedPath)
        }.GetNewClosure())

    Assert-Equal -Expected 'Error' -Actual $result.Status
    Assert-True -Condition ($result.Details -like '*%USERPROFILE%*')
    Assert-Equal -Expected $false -Actual $result.Details.Contains($userProfile)
    Assert-Equal -Expected $false -Actual $result.Details.Contains([Environment]::UserName)
}

Test-Case 'explicit install stops when its initial command check throws' {
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -ModulePath 'C:\AI-FishBot.Tests.Mock\profile\Modules\AudioDeviceCmdlets' `
        -CommandFinder {
            param($name)
            throw 'mock pre-install lookup exploded'
        } `
        -TestPathProvider { throw 'source validation must not run' } `
        -DirectoryCreator { throw 'directory creation must not run' } `
        -CopyProvider { throw 'copy must not run' } `
        -UnblockProvider { throw 'unblock must not run' } `
        -ModuleImporter { throw 'import must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*确认*状态*')
    Assert-True -Condition ($result.Details -like '*mock pre-install lookup exploded*')
}

Test-Case 'already available dependency succeeds without evaluating a broken profile path' {
    $context = [pscustomobject]@{ ProfileCalls = 0 }
    $captured = $context
    $result = Install-AIFishBotAudioDependency `
        -CommandFinder { param($name) return [pscustomobject]@{ Name = $name } } `
        -ProfileProvider ({
                $captured.ProfileCalls += 1
                throw 'profile provider must not run'
            }.GetNewClosure())

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*已经可用*')
    Assert-Equal -Expected '' -Actual $result.ModulePath
    Assert-Equal -Expected 0 -Actual $context.ProfileCalls
}

Test-Case 'missing dependency returns a failure object when profile path is empty' {
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -CommandFinder { param($name) return $null } `
        -ProfileProvider { return '' } `
        -TestPathProvider { throw 'source validation must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*目标目录*')
    Assert-True -Condition ($result.Details -like '*PROFILE*')
    Assert-Equal -Expected '' -Actual $result.ModulePath
}

Test-Case 'missing dependency contains profile provider exceptions in a failure object' {
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -CommandFinder { param($name) return $null } `
        -ProfileProvider { throw 'mock profile lookup exploded' } `
        -TestPathProvider { throw 'source validation must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*目标目录*')
    Assert-True -Condition ($result.Details -like '*mock profile lookup exploded*')
    Assert-Equal -Expected '' -Actual $result.ModulePath
}

Test-Case 'transactional install stages both files before swapping an existing target' {
    $scenario = New-TransactionalDependencyScenario
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('mkdir:{0}' -f $scenario.StagingPath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'move:{0}->{1}' -f $scenario.ModulePath, $scenario.BackupPath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'move:{0}->{1}' -f $scenario.StagingPath, $scenario.ModulePath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.BackupPath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'import:{0}' -f (Join-Path $scenario.ModulePath 'AudioDeviceCmdlets.psd1')))
    $copyText = @($scenario.Context.Calls | Where-Object { $_ -like 'copy:*' }) -join "`n"
    Assert-True -Condition ($copyText -like ('*{0}*' -f $scenario.StagingPath))
    Assert-Equal -Expected $false -Actual ($copyText -like ('*->{0}\AudioDeviceCmdlets*' -f $scenario.ModulePath))
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
    Assert-Equal -Expected $false -Actual $scenario.Context.StagingExists
    Assert-Equal -Expected $false -Actual $scenario.Context.BackupExists
}

Test-Case 'transactional install removes staging when the second copy fails' {
    $scenario = New-TransactionalDependencyScenario -FailAt 'copy:AudioDeviceCmdlets.psd1'
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.StagingPath))
    Assert-Equal -Expected 0 -Actual @($scenario.Context.Calls | Where-Object { $_ -like 'move:*' }).Count
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
    Assert-Equal -Expected $false -Actual $scenario.Context.StagingExists
}

Test-Case 'transactional install cleans a staging directory when creation partially succeeds then throws' {
    $scenario = New-TransactionalDependencyScenario
    $captured = $scenario.Context
    $stagingPath = $scenario.StagingPath
    $scenario.Options.DirectoryCreator = ({
            param($path)
            [void]$captured.Calls.Add(('mkdir:{0}' -f $path))
            if ($path -eq $stagingPath) { $captured.StagingExists = $true }
            throw 'mock partial staging creation failed'
        }.GetNewClosure())
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.StagingPath))
    Assert-Equal -Expected $false -Actual $scenario.Context.StagingExists
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
}

Test-Case 'transactional install restores the old target when import fails' {
    $scenario = New-TransactionalDependencyScenario -FailAt 'import'
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.ModulePath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'move:{0}->{1}' -f $scenario.BackupPath, $scenario.ModulePath))
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
    Assert-Equal -Expected $false -Actual $scenario.Context.BackupExists
    Assert-Equal -Expected $false -Actual $scenario.Context.StagingExists
}

Test-Case 'transactional install restores the old target when final verification fails' {
    $scenario = New-TransactionalDependencyScenario -AvailableAfterInstall $false
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*仍不可用*')
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.ModulePath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'move:{0}->{1}' -f $scenario.BackupPath, $scenario.ModulePath))
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
    Assert-Equal -Expected $false -Actual $scenario.Context.BackupExists
}

Test-Case 'transactional install restores backup and cleans staging when activation move fails' {
    $scenario = New-TransactionalDependencyScenario
    $scenario.Context.FailAt = 'move:{0}->{1}' -f $scenario.StagingPath, $scenario.ModulePath
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition (@($scenario.Context.Calls) -contains ('remove:{0}' -f $scenario.StagingPath))
    Assert-True -Condition (@($scenario.Context.Calls) -contains (
            'move:{0}->{1}' -f $scenario.BackupPath, $scenario.ModulePath))
    Assert-Equal -Expected $true -Actual $scenario.Context.TargetExists
    Assert-Equal -Expected $false -Actual $scenario.Context.StagingExists
    Assert-Equal -Expected $false -Actual $scenario.Context.BackupExists
}

Test-Case 'locked install rechecks availability and skips every write when another installer won' {
    $scenario = New-TransactionalDependencyScenario -AvailableInsideLock $true
    $mutex = New-DependencyMutexHarness
    $scenario.Options.MutexFactory = $mutex.Factory
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*已经可用*')
    Assert-Equal -Expected 2 -Actual $scenario.Context.FinderCalls
    Assert-Equal -Expected 0 -Actual @($scenario.Context.Calls | Where-Object { $_ -like 'mkdir:*' }).Count
    Assert-Equal -Expected 1 -Actual $mutex.Context.WaitCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.ReleaseCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.DisposeCount
}

Test-Case 'two stale installers for one normalized target perform only one transactional write' {
    $scenario = New-TransactionalDependencyScenario -TargetExists $false
    $mutex = New-DependencyMutexHarness
    $scenario.Options.MutexFactory = $mutex.Factory
    $context = $scenario.Context
    $captured = $context
    $scenario.Options.CommandFinder = ({
            param($name)
            $captured.FinderCalls += 1
            if ($captured.FinderCalls -in @(1, 2, 4)) { return $null }
            return [pscustomobject]@{ Name = $name }
        }.GetNewClosure())
    $options = $scenario.Options

    $first = Install-AIFishBotAudioDependency @options
    $second = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $first.Success
    Assert-Equal -Expected $true -Actual $second.Success
    Assert-True -Condition ($second.Summary -like '*已经可用*')
    Assert-Equal -Expected 1 -Actual @($context.Calls | Where-Object { $_ -like 'mkdir:*' }).Count
    Assert-Equal -Expected 2 -Actual @($context.Calls | Where-Object { $_ -like 'copy:*' }).Count
    Assert-Equal -Expected 2 -Actual $mutex.Context.Names.Count
    Assert-Equal -Expected $mutex.Context.Names[0] -Actual $mutex.Context.Names[1]
    Assert-Equal -Expected 2 -Actual $mutex.Context.ReleaseCount
    Assert-Equal -Expected 2 -Actual $mutex.Context.DisposeCount
}

Test-Case 'abandoned dependency mutex is treated as acquired and still released' {
    $scenario = New-TransactionalDependencyScenario -TargetExists $false
    $mutex = New-DependencyMutexHarness -AbandonFirstWait
    $scenario.Options.MutexFactory = $mutex.Factory
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-Equal -Expected 1 -Actual $mutex.Context.WaitCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.ReleaseCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.DisposeCount
}

Test-Case 'dependency mutex is released when transactional installation fails' {
    $scenario = New-TransactionalDependencyScenario -FailAt 'import'
    $mutex = New-DependencyMutexHarness
    $scenario.Options.MutexFactory = $mutex.Factory
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-Equal -Expected 1 -Actual $mutex.Context.WaitCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.ReleaseCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.DisposeCount
}

Test-Case 'mutex wait exceptions return a failure object and still dispose the lock' {
    $scenario = New-TransactionalDependencyScenario
    $mutex = New-DependencyMutexHarness -WaitFailure 'mock mutex wait failed'
    $scenario.Options.MutexFactory = $mutex.Factory
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*安装锁*')
    Assert-True -Condition ($result.Details -like '*mock mutex wait failed*')
    Assert-Equal -Expected 0 -Actual $mutex.Context.ReleaseCount
    Assert-Equal -Expected 1 -Actual $mutex.Context.DisposeCount
}

Test-Case 'explicit install reports an injected source validation exception' {
    $context = [pscustomobject]@{ FinderCalls = 0; ValidatedPath = $null; PathType = $null }
    $captured = $context
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -ModulePath 'C:\AI-FishBot.Tests.Mock\profile\Modules\AudioDeviceCmdlets' `
        -CommandFinder ({
                param($name)
                $captured.FinderCalls += 1
                return $null
            }.GetNewClosure()) `
        -TestPathProvider ({
                param($path, $pathType)
                $captured.ValidatedPath = $path
                $captured.PathType = $pathType
                throw 'mock source validation exploded'
            }.GetNewClosure()) `
        -DirectoryCreator { throw 'directory creation must not run' } `
        -CopyProvider { throw 'copy must not run' } `
        -UnblockProvider { throw 'unblock must not run' } `
        -ModuleImporter { throw 'import must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*校验*源文件*')
    Assert-True -Condition ($result.Details -like '*mock source validation exploded*')
    Assert-True -Condition ($context.ValidatedPath -like '*AudioDeviceCmdlets.dll')
    Assert-Equal -Expected 'Leaf' -Actual $context.PathType
    Assert-Equal -Expected 1 -Actual $context.FinderCalls
}

Test-Case 'source validation rejects a boolean mixed with provider noise' {
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -ModulePath 'C:\AI-FishBot.Tests.Mock\profile\Modules\AudioDeviceCmdlets' `
        -CommandFinder { param($name) return $null } `
        -TestPathProvider {
            param($path, $pathType)
            'mock path note'
            return $true
        } `
        -DirectoryCreator { throw 'directory creation must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*校验*源文件*')
    Assert-True -Condition ($result.Details -like '*一个*布尔值*')
}

Test-Case 'source validation rejects a truthy non-boolean provider value' {
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory 'C:\AI-FishBot.Tests.Mock\source' `
        -ModulePath 'C:\AI-FishBot.Tests.Mock\profile\Modules\AudioDeviceCmdlets' `
        -CommandFinder { param($name) return $null } `
        -TestPathProvider { param($path, $pathType) return 1 } `
        -DirectoryCreator { throw 'directory creation must not run' }

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*校验*源文件*')
    Assert-True -Condition ($result.Details -like '*一个*布尔值*')
}

Test-Case 'install failure details mask user paths and keep only the necessary exception message' {
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $sourceDirectory = Join-Path -Path $userProfile -ChildPath 'private\AudioModule'
    $modulePath = Join-Path -Path $userProfile -ChildPath 'Documents\WindowsPowerShell\Modules\AudioDeviceCmdlets'
    $privateErrorPath = Join-Path -Path $userProfile -ChildPath 'private\blocked.dll'
    $capturedErrorPath = $privateErrorPath
    $result = Install-AIFishBotAudioDependency `
        -SourceDirectory $sourceDirectory `
        -ModulePath $modulePath `
        -CommandFinder { param($name) return $null } `
        -TestPathProvider ({
                param($path, $pathType)
                throw ('mock validation denied at {0}' -f $capturedErrorPath)
            }.GetNewClosure())

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Details -like '*%USERPROFILE%*')
    Assert-True -Condition ($result.Details -like '*mock validation denied*')
    Assert-Equal -Expected $false -Actual $result.Details.Contains($userProfile)
    Assert-Equal -Expected $false -Actual $result.Details.Contains([Environment]::UserName)
    Assert-Equal -Expected $false -Actual ($result.Details -like '*ScriptStackTrace*')
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
    Assert-True -Condition (@($scenario.Context.Steps) -contains 'mkdir')
    Assert-Equal -Expected 'remove:staging' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports copy failure and stops before unblock' {
    $scenario = New-DependencyInstallScenario -FailAt 'copy:AudioDeviceCmdlets.psd1'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*复制*失败*')
    Assert-True -Condition ($result.Details -like '*mock copy denied*')
    Assert-True -Condition (@($scenario.Context.Steps) -contains 'copy:AudioDeviceCmdlets.psd1')
    Assert-Equal -Expected 'remove:staging' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports unblock failure and stops before import' {
    $scenario = New-DependencyInstallScenario -FailAt 'unblock:AudioDeviceCmdlets.dll'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*解锁*失败*')
    Assert-True -Condition ($result.Details -like '*mock unblock denied*')
    Assert-True -Condition (@($scenario.Context.Steps) -contains 'unblock:AudioDeviceCmdlets.dll')
    Assert-Equal -Expected 'remove:staging' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports module import failure and does not recheck' {
    $scenario = New-DependencyInstallScenario -FailAt 'import'
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*加载*失败*')
    Assert-True -Condition ($result.Details -like '*mock import denied*')
    Assert-True -Condition (@($scenario.Context.Steps) -contains 'import:AudioDeviceCmdlets.psd1')
    Assert-Equal -Expected 'remove:target' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
    Assert-Equal -Expected 2 -Actual $scenario.Context.FinderCalls
}

Test-Case 'explicit install fails when command is still missing after import' {
    $scenario = New-DependencyInstallScenario -AvailableAfterInstall $false
    $options = $scenario.Options
    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*仍不可用*')
    Assert-True -Condition ($result.Details -like '*Write-AudioDevice*')
    Assert-Equal -Expected 3 -Actual $scenario.Context.FinderCalls
    Assert-Equal -Expected 'remove:target' `
        -Actual $scenario.Context.Steps[$scenario.Context.Steps.Count - 1]
}

Test-Case 'explicit install reports a command finder exception during its final recheck' {
    $scenario = New-DependencyInstallScenario
    $context = $scenario.Context
    $captured = $context
    $scenario.Options.CommandFinder = ({
            param($name)
            $captured.FinderCalls += 1
            [void]$captured.Steps.Add(('check:{0}' -f $name))
            if ($captured.FinderCalls -le 2) {
                return $null
            }
            throw 'mock post-install lookup exploded'
        }.GetNewClosure())
    $options = $scenario.Options

    $result = Install-AIFishBotAudioDependency @options

    Assert-Equal -Expected $false -Actual $result.Success
    Assert-True -Condition ($result.Summary -like '*复查失败*')
    Assert-True -Condition ($result.Details -like '*mock post-install lookup exploded*')
    Assert-Equal -Expected 3 -Actual $context.FinderCalls
    Assert-True -Condition (@($context.Steps) -contains 'import:AudioDeviceCmdlets.psd1')
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

Test-Case 'explicit install resolves default project sources and profile target using only captured paths' {
    $context = [pscustomobject]@{
        FinderCalls = 0
        ValidatedPaths = New-Object 'System.Collections.Generic.List[string]'
        CreatedPaths = New-Object 'System.Collections.Generic.List[string]'
        Copies = New-Object 'System.Collections.Generic.List[string]'
        UnblockedPaths = New-Object 'System.Collections.Generic.List[string]'
        ImportedPaths = New-Object 'System.Collections.Generic.List[string]'
        Moves = New-Object 'System.Collections.Generic.List[string]'
    }
    $captured = $context
    $mutex = New-DependencyMutexHarness
    $result = Install-AIFishBotAudioDependency `
        -CommandFinder ({
                param($name)
                $captured.FinderCalls += 1
                if ($captured.FinderCalls -le 2) { return $null }
                return [pscustomobject]@{ Name = $name }
            }.GetNewClosure()) `
        -TestPathProvider ({
                param($path, $pathType)
                [void]$captured.ValidatedPaths.Add([string]$path)
                if ($pathType -eq 'Leaf') { return $true }
                if ($pathType -eq 'Container') { return $false }
                throw ('unexpected path type: {0}' -f $pathType)
            }.GetNewClosure()) `
        -DirectoryCreator ({
                param($path)
                [void]$captured.CreatedPaths.Add([string]$path)
            }.GetNewClosure()) `
        -CopyProvider ({
                param($source, $destination)
                [void]$captured.Copies.Add(('{0}|{1}' -f $source, $destination))
            }.GetNewClosure()) `
        -UnblockProvider ({
                param($path)
                [void]$captured.UnblockedPaths.Add([string]$path)
            }.GetNewClosure()) `
        -MoveProvider ({
                param($source, $destination)
                [void]$captured.Moves.Add(('{0}|{1}' -f $source, $destination))
            }.GetNewClosure()) `
        -RemoveProvider { param($path) throw ('unexpected remove: {0}' -f $path) } `
        -ModuleImporter ({
                param($path)
                [void]$captured.ImportedPaths.Add([string]$path)
            }.GetNewClosure()) `
        -MutexFactory $mutex.Factory `
        -OperationIdProvider { return 'default-path-op' }

    $expectedSourceDirectory = Join-Path -Path $script:DependenciesTestRoot -ChildPath 'AudioModule'
    $expectedDll = Join-Path -Path $expectedSourceDirectory -ChildPath 'AudioDeviceCmdlets.dll'
    $expectedManifest = Join-Path -Path $expectedSourceDirectory -ChildPath 'AudioDeviceCmdlets.psd1'
    $expectedModulePath = Join-Path -Path (Join-Path -Path (Split-Path -Path $PROFILE -Parent) `
            -ChildPath 'Modules') -ChildPath 'AudioDeviceCmdlets'
    $expectedStagingPath = $expectedModulePath + '.staging.default-path-op'
    $expectedTargetDll = Join-Path -Path $expectedModulePath -ChildPath 'AudioDeviceCmdlets.dll'
    $expectedTargetManifest = Join-Path -Path $expectedModulePath -ChildPath 'AudioDeviceCmdlets.psd1'

    Assert-Equal -Expected $true -Actual $result.Success
    Assert-Equal -Expected $expectedModulePath -Actual $result.ModulePath
    Assert-Equal -Expected @($expectedDll, $expectedManifest, $expectedModulePath) `
        -Actual @($context.ValidatedPaths)
    Assert-Equal -Expected @($expectedStagingPath) -Actual @($context.CreatedPaths)
    Assert-Equal -Expected @(
        ('{0}|{1}' -f $expectedDll, (Join-Path $expectedStagingPath 'AudioDeviceCmdlets.dll')),
        ('{0}|{1}' -f $expectedManifest, (Join-Path $expectedStagingPath 'AudioDeviceCmdlets.psd1'))
    ) -Actual @($context.Copies)
    Assert-Equal -Expected @(
        (Join-Path $expectedStagingPath 'AudioDeviceCmdlets.dll'),
        (Join-Path $expectedStagingPath 'AudioDeviceCmdlets.psd1')
    ) -Actual @($context.UnblockedPaths)
    Assert-Equal -Expected @(
        ('{0}|{1}' -f $expectedStagingPath, $expectedModulePath)
    ) -Actual @($context.Moves)
    Assert-Equal -Expected @($expectedTargetManifest) -Actual @($context.ImportedPaths)
    Assert-Equal -Expected 3 -Actual $context.FinderCalls
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
        'check:Write-AudioDevice',
        'mkdir',
        'copy:AudioDeviceCmdlets.dll',
        'copy:AudioDeviceCmdlets.psd1',
        'unblock:AudioDeviceCmdlets.dll',
        'unblock:AudioDeviceCmdlets.psd1',
        'exists:AudioDeviceCmdlets',
        'move:staging-to-target',
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
