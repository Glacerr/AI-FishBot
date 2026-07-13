Set-StrictMode -Version 2.0

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
        Details = $Details
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
        [string]$ModulePath
    )

    return [pscustomobject][ordered]@{
        Success = $Success
        Summary = $Summary
        Details = $DetailLines -join [Environment]::NewLine
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
        $command = & $CommandFinder 'Write-AudioDevice'
        if ([bool]$command) {
            return New-AIFishBotDependencyCheckResult -Status 'Available' -Available $true `
                -Summary '声音组件已经可用。' `
                -Details '已找到 Write-AudioDevice 命令。'
        }

        return New-AIFishBotDependencyCheckResult -Status 'Missing' -Available $false `
            -Summary '缺少声音组件，需要手动点击安装。' `
            -Details '未找到 Write-AudioDevice 命令；检查过程没有执行安装或复制。'
    }
    catch {
        return New-AIFishBotDependencyCheckResult -Status 'Error' -Available $false `
            -Summary '声音组件检查失败。' `
            -Details ('检查 Write-AudioDevice 时发生错误：{0}' -f $_.Exception.ToString())
    }
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

        [scriptblock]$PathTester,

        [scriptblock]$DirectoryCreator,

        [scriptblock]$CopyProvider,

        [scriptblock]$UnblockProvider,

        [scriptblock]$ModuleImporter,

        [Alias('ModuleInstaller')]
        [scriptblock]$Installer,

        [scriptblock]$CommandFinder
    )

    if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
        $SourceDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'AudioModule'
    }
    if ([string]::IsNullOrWhiteSpace($ModulePath)) {
        $profileDirectory = Split-Path -Path $PROFILE -Parent
        $modulesDirectory = Join-Path -Path $profileDirectory -ChildPath 'Modules'
        $ModulePath = Join-Path -Path $modulesDirectory -ChildPath 'AudioDeviceCmdlets'
    }
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
    if ($null -eq $ModuleImporter) {
        $ModuleImporter = {
            param($path)
            Import-Module -Name $path -Force -ErrorAction Stop
        }
    }
    if ($null -eq $CommandFinder) {
        $CommandFinder = {
            param($name)
            Get-Command -Name $name -ErrorAction SilentlyContinue
        }
    }

    $details = New-Object 'System.Collections.Generic.List[string]'
    [void]$details.Add(('安装目标：{0}' -f $ModulePath))

    $initialCheck = Test-AIFishBotAudioDependency -CommandFinder $CommandFinder
    [void]$details.Add(('安装前检查：{0}' -f $initialCheck.Details))
    if ($initialCheck.Status -eq 'Error') {
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '无法确认声音组件状态，未执行安装。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }
    if ($initialCheck.Available) {
        return New-AIFishBotDependencyInstallResult -Success $true `
            -Summary '声音组件已经可用，无需重复安装。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }

    $sourceFiles = @(
        (Join-Path -Path $SourceDirectory -ChildPath 'AudioDeviceCmdlets.dll'),
        (Join-Path -Path $SourceDirectory -ChildPath 'AudioDeviceCmdlets.psd1')
    )
    $missingSourceFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($sourceFile in $sourceFiles) {
        try {
            $sourceExists = [bool](& $PathTester $sourceFile 'Leaf')
        }
        catch {
            [void]$details.Add(('校验源文件“{0}”失败：{1}' -f $sourceFile, $_.Exception.ToString()))
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
        $null = & $DirectoryCreator $ModulePath
        [void]$details.Add(('已准备安装目录：{0}' -f $ModulePath))
    }
    catch {
        [void]$details.Add(('创建安装目录“{0}”失败：{1}' -f $ModulePath, $_.Exception.ToString()))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '创建声音组件目录失败。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }

    $targetFiles = @()
    foreach ($sourceFile in $sourceFiles) {
        $targetFile = Join-Path -Path $ModulePath -ChildPath (Split-Path -Path $sourceFile -Leaf)
        try {
            $null = & $CopyProvider $sourceFile $targetFile
            [void]$details.Add(('已复制“{0}”到“{1}”。' -f $sourceFile, $targetFile))
            $targetFiles += $targetFile
        }
        catch {
            [void]$details.Add(('复制“{0}”到“{1}”失败：{2}' -f `
                        $sourceFile, $targetFile, $_.Exception.ToString()))
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '复制声音组件文件失败。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }
    }

    foreach ($targetFile in $targetFiles) {
        try {
            $null = & $UnblockProvider $targetFile
            [void]$details.Add(('已解锁文件：{0}' -f $targetFile))
        }
        catch {
            [void]$details.Add(('解锁文件“{0}”失败：{1}' -f $targetFile, $_.Exception.ToString()))
            return New-AIFishBotDependencyInstallResult -Success $false `
                -Summary '解锁声音组件文件失败。' `
                -DetailLines @($details) -ModulePath $ModulePath
        }
    }

    $manifestPath = Join-Path -Path $ModulePath -ChildPath 'AudioDeviceCmdlets.psd1'
    $importAction = $ModuleImporter
    if ($null -ne $Installer) {
        $importAction = $Installer
    }
    try {
        $null = & $importAction $manifestPath
        [void]$details.Add(('已加载声音组件：{0}' -f $manifestPath))
    }
    catch {
        [void]$details.Add(('加载声音组件“{0}”失败：{1}' -f $manifestPath, $_.Exception.ToString()))
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary '加载声音组件失败。' `
            -DetailLines @($details) -ModulePath $ModulePath
    }

    $finalCheck = Test-AIFishBotAudioDependency -CommandFinder $CommandFinder
    [void]$details.Add(('安装后复查：{0}' -f $finalCheck.Details))
    if (-not $finalCheck.Available) {
        if ($finalCheck.Status -eq 'Error') {
            $summary = '声音组件已复制，但复查失败。'
        }
        else {
            $summary = '声音组件安装后仍不可用。'
        }
        return New-AIFishBotDependencyInstallResult -Success $false `
            -Summary $summary -DetailLines @($details) -ModulePath $ModulePath
    }

    return New-AIFishBotDependencyInstallResult -Success $true `
        -Summary '声音组件安装完成。' `
        -DetailLines @($details) -ModulePath $ModulePath
}

Export-ModuleMember -Function @(
    'Test-AIFishBotAudioDependency',
    'Install-AIFishBotAudioDependency'
)
