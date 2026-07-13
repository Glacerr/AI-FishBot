Set-StrictMode -Version 2.0

function Protect-AIFishBotDependencyDetails {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    $safeText = [string]$Text
    $safeText = $safeText -replace '[\r\n\u2028\u2029]+', ' '
    $profilePaths = @(
        [string]$HOME,
        [string]$env:USERPROFILE,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object Length -Descending -Unique

    foreach ($profilePath in $profilePaths) {
        $trimmedPath = $profilePath.TrimEnd('\', '/')
        if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
            continue
        }
        $pattern = [regex]::Escape($trimmedPath) + '(?=$|[\\/])'
        $safeText = [regex]::Replace(
            $safeText,
            $pattern,
            '%USERPROFILE%',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $userName = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($userName)) {
        $commonUserPath = '[A-Za-z]:[\\/]+Users[\\/]+' + [regex]::Escape($userName) + '(?=$|[\\/])'
        $safeText = [regex]::Replace(
            $safeText,
            $commonUserPath,
            '%USERPROFILE%',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    return $safeText
}

function New-AIFishBotDependencyCheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Available', 'Missing', 'Error')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [bool]$Available,

        [Parameter(Mandatory = $true)]
        [string]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$Details
    )

    return [pscustomobject][ordered]@{
        Status = $Status
        Available = $Available
        Summary = $Summary
        Details = Protect-AIFishBotDependencyDetails -Text $Details
    }
}

function New-AIFishBotDependencyInstallResult {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $true)]
        [string]$Summary,

        [Parameter(Mandatory = $true)]
        [string[]]$DetailLines,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ModulePath
    )

    return [pscustomobject][ordered]@{
        Success = $Success
        Summary = $Summary
        Details = @($DetailLines | ForEach-Object {
                Protect-AIFishBotDependencyDetails -Text $_
            }) -join [Environment]::NewLine
        ModulePath = $ModulePath
    }
}

function Test-AIFishBotAudioDependency {
    [CmdletBinding()]
    param(
        [scriptblock]$CommandFinder
    )

    if ($null -eq $CommandFinder) {
        $CommandFinder = {
            param($name)
            Get-Command -Name $name -ErrorAction SilentlyContinue
        }
    }

    try {
        $rawCommandOutput = & $CommandFinder 'Write-AudioDevice'
        if ($null -eq $rawCommandOutput) {
            $commandOutput = @()
        }
        else {
            $commandOutput = @($rawCommandOutput)
        }
        if ($commandOutput.Count -eq 0) {
            return New-AIFishBotDependencyCheckResult -Status 'Missing' -Available $false `
                -Summary '缺少声音组件，需要手动点击安装。' `
                -Details '未找到 Write-AudioDevice 命令；检查过程没有执行安装或复制。'
        }
        if ($commandOutput.Count -ne 1) {
            return New-AIFishBotDependencyCheckResult -Status 'Error' -Available $false `
                -Summary '声音组件检查失败。' `
                -Details 'Write-AudioDevice 查询必须只返回一个有效命令对象。'
        }

        $command = $commandOutput[0]
        $commandType = $null
        if ($null -ne $command) {
            $commandType = $command.GetType()
        }
        $validCommand = $null -ne $command -and $command -isnot [string] -and
            $null -ne $commandType -and -not $commandType.IsValueType
        if (-not $validCommand) {
            return New-AIFishBotDependencyCheckResult -Status 'Error' -Available $false `
                -Summary '声音组件检查失败。' `
                -Details 'Write-AudioDevice 查询必须只返回一个有效命令对象，不能返回说明文字或普通值。'
        }

        $nameProperty = $command.PSObject.Properties['Name']
        $commandName = $null
        if ($null -ne $nameProperty -and $nameProperty.Value -is [string]) {
            $commandName = [string]$nameProperty.Value
        }
        if (-not [string]::Equals(
                $commandName,
                'Write-AudioDevice',
                [System.StringComparison]::Ordinal)) {
            return New-AIFishBotDependencyCheckResult -Status 'Error' -Available $false `
                -Summary '声音组件检查失败。' `
                -Details '命令查询结果的 Name 必须准确等于 Write-AudioDevice。'
        }

        return New-AIFishBotDependencyCheckResult -Status 'Available' -Available $true `
            -Summary '声音组件已经可用。' `
            -Details '已找到 Write-AudioDevice 命令。'
    }
    catch {
        return New-AIFishBotDependencyCheckResult -Status 'Error' -Available $false `
            -Summary '声音组件检查失败。' `
            -Details ('检查 Write-AudioDevice 时发生错误：{0}' -f $_.Exception.Message)
    }
}

function Invoke-AIFishBotPathTestProvider {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Leaf', 'Container')]
        [string]$PathType
    )

    $rawPathOutput = & $Provider $Path $PathType
    if ($null -eq $rawPathOutput) {
        $pathOutput = @()
    }
    else {
        $pathOutput = @($rawPathOutput)
    }
    if ($pathOutput.Count -ne 1 -or $pathOutput[0] -isnot [bool]) {
        throw '路径检查必须只返回一个实际布尔值。'
    }
    return [bool]$pathOutput[0]
}

function Get-AIFishBotDependencyMutexName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($ModulePath).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        throw '声音组件目标目录无效。'
    }
    $normalizedPath = $normalizedPath.ToUpperInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedPath)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }
    $hashText = -join @($hash | ForEach-Object { $_.ToString('x2') })
    return 'Local\AIFishBot.AudioDependency.{0}' -f $hashText
}

function Install-AIFishBotAudioDependency {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SourceDirectory,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ModulePath,

        [Alias('TestPathProvider')]
        [scriptblock]$PathTester,

        [scriptblock]$DirectoryCreator,

        [scriptblock]$CopyProvider,

        [scriptblock]$UnblockProvider,

        [scriptblock]$MoveProvider,

        [scriptblock]$RemoveProvider,

        [scriptblock]$ModuleImporter,

        [Alias('ModuleInstaller')]
        [scriptblock]$Installer,

        [scriptblock]$CommandFinder,

        [scriptblock]$SourceDirectoryProvider,

        [scriptblock]$ProfileProvider,

        [scriptblock]$OperationIdProvider,

        [scriptblock]$MutexFactory,

        [scriptblock]$LockWaitProvider,

        [ValidateRange(1, 300000)]
        [int]$MutexTimeoutMilliseconds = 30000
    )

    if ($null -eq $CommandFinder) {
        $CommandFinder = {
            param($name)
            Get-Command -Name $name -ErrorAction SilentlyContinue
        }
    }
    if ($null -eq $ProfileProvider) {
        $ProfileProvider = {
            return $PROFILE
        }
    }
    if ($null -eq $SourceDirectoryProvider) {
        $SourceDirectoryProvider = {
            return Join-Path -Path $PSScriptRoot -ChildPath 'AudioModule'
        }
    }

    $resultModulePath = [string]$ModulePath
    if ([string]::IsNullOrWhiteSpace($resultModulePath)) {
        $resultModulePath = ''
    }
    $details = New-Object 'System.Collections.Generic.List[string]'
    $initialCheck = Test-AIFishBotAudioDependency -CommandFinder $CommandFinder
    [void]$details.Add(('安装前检查：{0}' -f $initialCheck.Details))
    if ($initialCheck.Status -eq 'Error') {
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法确认声音组件状态，未执行安装。' `
            -DetailLines @($details) -ModulePath $resultModulePath
    }
    if ($initialCheck.Available) {
        return New-AIFishBotDependencyInstallResult -Success $true `
            -Summary '声音组件已经可用，无需重复安装。' `
            -DetailLines @($details) -ModulePath $resultModulePath
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
            $rawSourceOutput = & $SourceDirectoryProvider
            if ($null -eq $rawSourceOutput) {
                $sourceOutput = @()
            }
            else {
                $sourceOutput = @($rawSourceOutput)
            }
            if ($sourceOutput.Count -ne 1 -or $sourceOutput[0] -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string]$sourceOutput[0])) {
                throw '默认源目录必须返回一个有效路径。'
            }
            $SourceDirectory = [string]$sourceOutput[0]
        }
    }
    catch {
        [void]$details.Add(('无法确定声音组件源文件位置：{0}' -f $_.Exception.Message))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法确定声音组件源文件位置。' `
            -DetailLines @($details) -ModulePath $resultModulePath
    }

    try {
        if ([string]::IsNullOrWhiteSpace($ModulePath)) {
            $profileOutput = @(& $ProfileProvider)
            if ($profileOutput.Count -ne 1 -or $profileOutput[0] -isnot [string] -or
                [string]::IsNullOrWhiteSpace([string]$profileOutput[0])) {
                throw 'PROFILE 路径为空或无效。'
            }
            $profileDirectory = Split-Path -Path ([string]$profileOutput[0]) -Parent
            if ([string]::IsNullOrWhiteSpace($profileDirectory)) {
                throw 'PROFILE 路径没有可用的父目录。'
            }
            $modulesDirectory = Join-Path -Path $profileDirectory -ChildPath 'Modules'
            $ModulePath = Join-Path -Path $modulesDirectory -ChildPath 'AudioDeviceCmdlets'
        }
        $resultModulePath = $ModulePath
    }
    catch {
        [void]$details.Add(('无法根据 PROFILE 确定目标目录：{0}' -f $_.Exception.Message))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法确定声音组件目标目录。' `
            -DetailLines @($details) -ModulePath $resultModulePath
    }
    [void]$details.Add(('安装目标：{0}' -f $ModulePath))

    if ($null -eq $PathTester) {
        $PathTester = {
            param($path, $pathType)
            Test-Path -LiteralPath $path -PathType $pathType
        }
    }
    if ($null -eq $DirectoryCreator) {
        $DirectoryCreator = {
            param($path)
            New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        }
    }
    if ($null -eq $CopyProvider) {
        $CopyProvider = {
            param($source, $destination)
            Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
        }
    }
    if ($null -eq $UnblockProvider) {
        $UnblockProvider = {
            param($path)
            Unblock-File -LiteralPath $path -ErrorAction Stop
        }
    }
    if ($null -eq $MoveProvider) {
        $MoveProvider = {
            param($source, $destination)
            Move-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
        }
    }
    if ($null -eq $RemoveProvider) {
        $RemoveProvider = {
            param($path)
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
    }
    if ($null -eq $ModuleImporter) {
        $ModuleImporter = {
            param($path)
            Import-Module -Name $path -Force -ErrorAction Stop
        }
    }
    if ($null -eq $OperationIdProvider) {
        $OperationIdProvider = {
            return [guid]::NewGuid().ToString('N')
        }
    }
    if ($null -eq $MutexFactory) {
        $MutexFactory = {
            param($name)
            return New-Object System.Threading.Mutex($false, $name)
        }
    }
    if ($null -eq $LockWaitProvider) {
        $LockWaitProvider = {
            param($mutexObject, $timeoutMilliseconds)
            return $mutexObject.WaitOne($timeoutMilliseconds)
        }
    }

    try {
        $sourceFiles = @(
            (Join-Path -Path $SourceDirectory -ChildPath 'AudioDeviceCmdlets.dll'),
            (Join-Path -Path $SourceDirectory -ChildPath 'AudioDeviceCmdlets.psd1')
        )
    }
    catch {
        [void]$details.Add(('无法构造声音组件源文件位置：{0}' -f $_.Exception.Message))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法确定声音组件源文件位置。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }
    $missingSourceFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($sourceFile in $sourceFiles) {
        try {
            $sourceExists = Invoke-AIFishBotPathTestProvider `
                -Provider $PathTester -Path $sourceFile -PathType 'Leaf'
        }
        catch {
            [void]$details.Add(('校验源文件“{0}”失败：{1}' -f $sourceFile, $_.Exception.Message))
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '无法校验声音组件源文件。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }

        if (-not $sourceExists) {
            [void]$missingSourceFiles.Add($sourceFile)
        }
        else {
            [void]$details.Add(('已确认源文件：{0}' -f $sourceFile))
        }
    }
    if ($missingSourceFiles.Count -gt 0) {
        [void]$details.Add(('缺少源文件：{0}' -f (@($missingSourceFiles) -join '；')))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '声音组件源文件不完整，无法安装。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }

    try {
        $mutexName = Get-AIFishBotDependencyMutexName -ModulePath $ModulePath
        $mutexOutput = @(& $MutexFactory $mutexName)
        if ($mutexOutput.Count -ne 1 -or $null -eq $mutexOutput[0]) {
            throw '安装锁创建器必须返回一个锁对象。'
        }
        $mutex = $mutexOutput[0]
    }
    catch {
        [void]$details.Add(('无法创建声音组件安装锁：{0}' -f $_.Exception.Message))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法建立声音组件安装锁。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }

    $lockState = [pscustomobject]@{ Acquired = $false }
    $lockedResult = $null
    $lockCleanupErrors = New-Object 'System.Collections.Generic.List[string]'
    try {
        $lockedResult = & {
        try {
        try {
            $rawWaitOutput = & $LockWaitProvider $mutex $MutexTimeoutMilliseconds
            if ($null -eq $rawWaitOutput) {
                $waitOutput = @()
            }
            else {
                $waitOutput = @($rawWaitOutput)
            }
            if ($waitOutput.Count -ne 1 -or $waitOutput[0] -isnot [bool]) {
                throw '安装锁等待动作必须只返回一个实际布尔值。'
            }
            $lockState.Acquired = [bool]$waitOutput[0]
        }
        catch {
            $waitException = $_.Exception
            $abandoned = $false
            $currentException = $waitException
            while ($null -ne $currentException) {
                if ($currentException -is [System.Threading.AbandonedMutexException]) {
                    $abandoned = $true
                    break
                }
                $currentException = $currentException.InnerException
            }
            if (-not $abandoned) {
                throw
            }
            $lockState.Acquired = $true
            [void]$details.Add('检测到已废弃的安装锁，已安全接管。')
        }

        if (-not $lockState.Acquired) {
            [void]$details.Add(('等待声音组件安装锁超过 {0} 毫秒。' -f $MutexTimeoutMilliseconds))
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '等待声音组件安装锁超时。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }

        $lockedCheck = Test-AIFishBotAudioDependency -CommandFinder $CommandFinder
        [void]$details.Add(('锁内复查：{0}' -f $lockedCheck.Details))
        if ($lockedCheck.Status -eq 'Error') {
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '锁内复查声音组件失败，未执行安装。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }
        if ($lockedCheck.Available) {
            return New-AIFishBotDependencyInstallResult -Success $true `
                -Summary '声音组件已经可用，无需重复安装。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }

        try {
            $operationIdOutput = @(& $OperationIdProvider)
        if ($operationIdOutput.Count -ne 1) {
            throw '安装操作编号必须只有一个值。'
        }
        $operationId = [string]$operationIdOutput[0]
        if ([string]::IsNullOrWhiteSpace($operationId) -or $operationId -notmatch '^[A-Za-z0-9-]+$') {
            throw '安装操作编号无效。'
        }
        }
        catch {
            [void]$details.Add(('无法创建安装操作编号：{0}' -f $_.Exception.Message))
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '无法准备声音组件安装。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }

        $stagingPath = '{0}.staging.{1}' -f $ModulePath, $operationId
        $backupPath = '{0}.backup.{1}' -f $ModulePath, $operationId
        $stagingCreated = $false
        $oldTargetMoved = $false
        $newTargetActivated = $false
        $failureSummary = '声音组件安装失败。'
        $failureLabel = '安装失败'

        $importAction = $ModuleImporter
        if ($null -ne $Installer) {
            $importAction = $Installer
        }

        try {
        $failureSummary = '创建声音组件临时目录失败。'
        $failureLabel = '创建临时目录失败'
        $stagingCreated = $true
        $null = & $DirectoryCreator $stagingPath
        [void]$details.Add(('已准备临时目录：{0}' -f $stagingPath))

        $stagedFiles = @()
        foreach ($sourceFile in $sourceFiles) {
            $stagedFile = Join-Path -Path $stagingPath -ChildPath (Split-Path -Path $sourceFile -Leaf)
            $failureSummary = '复制声音组件文件失败。'
            $failureLabel = '复制到临时目录失败'
            $null = & $CopyProvider $sourceFile $stagedFile
            [void]$details.Add(('已复制“{0}”到临时目录。' -f (Split-Path -Path $sourceFile -Leaf)))
            $stagedFiles += $stagedFile
        }

        foreach ($stagedFile in $stagedFiles) {
            $failureSummary = '解锁声音组件文件失败。'
            $failureLabel = '解锁临时文件失败'
            $null = & $UnblockProvider $stagedFile
            [void]$details.Add(('已解锁临时文件：{0}' -f (Split-Path -Path $stagedFile -Leaf)))
        }

        $failureSummary = '无法检查现有声音组件目录。'
        $failureLabel = '检查现有目录失败'
        $targetExists = Invoke-AIFishBotPathTestProvider `
            -Provider $PathTester -Path $ModulePath -PathType 'Container'
        if ($targetExists) {
            $failureSummary = '备份现有声音组件失败。'
            $failureLabel = '备份现有目录失败'
            $oldTargetMoved = $true
            $null = & $MoveProvider $ModulePath $backupPath
            [void]$details.Add('已暂存现有声音组件。')
        }

        $failureSummary = '启用新的声音组件失败。'
        $failureLabel = '切换临时目录失败'
        $newTargetActivated = $true
        $null = & $MoveProvider $stagingPath $ModulePath
        $stagingCreated = $false
        [void]$details.Add('已切换到新的声音组件目录。')

        $manifestPath = Join-Path -Path $ModulePath -ChildPath 'AudioDeviceCmdlets.psd1'
        $failureSummary = '加载声音组件失败。'
        $failureLabel = '加载声音组件失败'
        $null = & $importAction $manifestPath
        [void]$details.Add(('已加载声音组件：{0}' -f $manifestPath))

        $finalCheck = Test-AIFishBotAudioDependency -CommandFinder $CommandFinder
        [void]$details.Add(('安装后复查：{0}' -f $finalCheck.Details))
        if (-not $finalCheck.Available) {
            if ($finalCheck.Status -eq 'Error') {
                $failureSummary = '声音组件已切换，但复查失败。'
            }
            else {
                $failureSummary = '声音组件安装后仍不可用。'
            }
            $failureLabel = '安装后复查失败'
            throw (New-Object System.InvalidOperationException($finalCheck.Details))
        }

        if ($oldTargetMoved) {
            $failureSummary = '声音组件已安装，但清理旧版本失败。'
            $failureLabel = '清理备份目录失败'
            $null = & $RemoveProvider $backupPath
            $oldTargetMoved = $false
            [void]$details.Add('已清理旧的声音组件备份。')
        }

        return New-AIFishBotDependencyInstallResult -Success $true `
            -Summary '声音组件安装完成。' `
            -DetailLines @($details) -ModulePath $ModulePath
        }
        catch {
        [void]$details.Add(('{0}：{1}' -f $failureLabel, $_.Exception.Message))

        if ($newTargetActivated) {
            try {
                $null = & $RemoveProvider $ModulePath
                $newTargetActivated = $false
                [void]$details.Add('已移除未通过验证的新声音组件。')
            }
            catch {
                [void]$details.Add(('移除新声音组件失败：{0}' -f $_.Exception.Message))
            }
        }

        if ($oldTargetMoved) {
            try {
                $null = & $MoveProvider $backupPath $ModulePath
                $oldTargetMoved = $false
                [void]$details.Add('已恢复原有声音组件。')
            }
            catch {
                [void]$details.Add(('恢复原有声音组件失败：{0}' -f $_.Exception.Message))
            }
        }

        if ($stagingCreated) {
            try {
                $null = & $RemoveProvider $stagingPath
                $stagingCreated = $false
                [void]$details.Add('已清理声音组件临时目录。')
            }
            catch {
                [void]$details.Add(('清理声音组件临时目录失败：{0}' -f $_.Exception.Message))
            }
        }

            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary $failureSummary -DetailLines @($details) -ModulePath $ModulePath
        }
        }
        catch {
        [void]$details.Add(('声音组件安装锁处理失败：{0}' -f $_.Exception.Message))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '声音组件安装锁处理失败。' `
            -DetailLines @($details) -ModulePath $ModulePath
        }
        }
    }
    catch {
        [void]$details.Add(('声音组件安装锁处理失败：{0}' -f $_.Exception.Message))
        $lockedResult = New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '声音组件安装锁处理失败。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }
    finally {
        if ($lockState.Acquired) {
            try {
                $null = $mutex.ReleaseMutex()
            }
            catch {
                [void]$lockCleanupErrors.Add(('释放声音组件安装锁失败：{0}' -f $_.Exception.Message))
            }
        }
        try {
            $null = $mutex.Dispose()
        }
        catch {
            [void]$lockCleanupErrors.Add(('销毁声音组件安装锁失败：{0}' -f $_.Exception.Message))
        }
    }

    if ($null -eq $lockedResult) {
        $lockedResult = New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '声音组件安装没有产生有效结果。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }
    if ($lockCleanupErrors.Count -gt 0) {
        $finalDetailLines = New-Object 'System.Collections.Generic.List[string]'
        if (-not [string]::IsNullOrWhiteSpace([string]$lockedResult.Details)) {
            [void]$finalDetailLines.Add([string]$lockedResult.Details)
        }
        foreach ($cleanupError in $lockCleanupErrors) {
            [void]$finalDetailLines.Add($cleanupError)
        }
        if ($lockedResult.Success) {
            $cleanupSummary = '声音组件操作完成，但安装锁清理失败。'
        }
        else {
            $cleanupSummary = '声音组件安装失败，且安装锁清理失败。'
        }
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary $cleanupSummary -DetailLines @($finalDetailLines) -ModulePath $ModulePath
    }

    return $lockedResult
}

Export-ModuleMember -Function @(
    'Test-AIFishBotAudioDependency',
    'Install-AIFishBotAudioDependency'
)
