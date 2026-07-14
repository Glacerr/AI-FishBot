[CmdletBinding()]
param(
    [string]$DataRoot,
    [switch]$SelfTest,
    [switch]$NoShow,
    [switch]$Simulation
)

$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('DataRoot')) {
    $DataRoot = $PSScriptRoot
}
$exitCode = 0
$mutex = $null
$ownsMutex = $false
$view = $null
$controller = $null
$fullDataRoot = $null
$runtimeImported = $false
$alreadyRunning = $false
$failureSummary = $null
$failureContext = 'AI FishBot 界面启动失败'
$selfTestReport = $null
$cleanupErrors = New-Object 'System.Collections.Generic.List[string]'

function Get-AIFishBotGuiMutexName {
    $projectPath = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('\', '/'))
    $canonicalPath = $projectPath.ToUpperInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonicalPath))
    }
    finally { $sha.Dispose() }
    $prefix = -join @($hash[0..7] | ForEach-Object { $_.ToString('x2') })
    return 'Local\AI-FishBot.GUI.{0}' -f $prefix
}

function Write-AIFishBotGuiFailureLog {
    param([Parameter(Mandatory = $true)][string]$Details)

    if (-not $runtimeImported -or [string]::IsNullOrWhiteSpace($fullDataRoot) -or
        -not [IO.Directory]::Exists($fullDataRoot)) {
        return
    }
    try {
        $safeDetails = Protect-AIFishBotSecret -Text $Details
        Write-AIFishBotLog -RunDirectory $fullDataRoot -Level Error `
            -Message ('GUI 启动失败：{0}' -f $safeDetails) | Out-Null
    }
    catch {
    }
}

function Get-SafeErrorSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception,

        [Parameter(Mandatory = $true)]
        [string]$Context,

        [ValidateRange(1, 2000)]
        [int]$MaximumLength = 500
    )

    $safeMessage = [string]$Exception.Message
    if ([string]::IsNullOrWhiteSpace($safeMessage)) {
        $safeMessage = '未知错误。'
    }

    try {
        if ($null -ne (Get-Command -Name Protect-AIFishBotSecret -ErrorAction SilentlyContinue)) {
            $safeMessage = Protect-AIFishBotSecret -Text $safeMessage
        }
    }
    catch {
    }

    $webhookPattern = '(?<prefix>https:(?:\\/|/){2}(?:(?:canary|ptb)\.)?discord(?:app)?\.com(?::[0-9]{1,5})?' +
        '(?:\\/|/)api(?:(?:\\/|/)v[0-9]+)?(?:\\/|/)webhooks(?:\\/|/))' +
        '[A-Za-z0-9_-]+(?:\\/|/)[A-Za-z0-9._-]+(?:\?[^\s<>"'']*)?'
    $safeMessage = [regex]::Replace(
        $safeMessage,
        $webhookPattern,
        '[Webhook已隐藏]',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $protectedWebhookPattern = 'https:(?:\\/|/){2}(?:(?:canary|ptb)\.)?discord(?:app)?\.com(?::[0-9]{1,5})?' +
        '(?:\\/|/)api(?:(?:\\/|/)v[0-9]+)?(?:\\/|/)webhooks(?:\\/|/)\*{3}'
    $safeMessage = [regex]::Replace(
        $safeMessage,
        $protectedWebhookPattern,
        '[Webhook已隐藏]',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $profilePaths = @(
        [string]$HOME,
        [string]$env:USERPROFILE,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object Length -Descending -Unique
    foreach ($profilePath in $profilePaths) {
        $trimmedPath = $profilePath.TrimEnd([char[]]@('\', '/'))
        if ([string]::IsNullOrWhiteSpace($trimmedPath)) { continue }
        $safeMessage = [regex]::Replace(
            $safeMessage,
            ([regex]::Escape($trimmedPath) + '(?=$|[\\/])'),
            '%USERPROFILE%',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $userName = [Environment]::UserName
    if (-not [string]::IsNullOrWhiteSpace($userName)) {
        $commonUserPath = '[A-Za-z]:[\\/]+Users[\\/]+' + [regex]::Escape($userName) + '(?=$|[\\/])'
        $safeMessage = [regex]::Replace(
            $safeMessage,
            $commonUserPath,
            '%USERPROFILE%',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $safeMessage = [regex]::Replace($safeMessage, '[\r\n\u2028\u2029]+', ' ')
    $safeMessage = [regex]::Replace($safeMessage, '[ \t]{2,}', ' ').Trim()
    $safeContext = ([string]$Context).Trim().TrimEnd([char[]]@('：', ':'))
    if ([string]::IsNullOrWhiteSpace($safeContext)) { $safeContext = 'AI FishBot 界面启动失败' }
    $prefix = $safeContext + '：'
    if ($prefix.Length -ge $MaximumLength) {
        return $prefix.Substring(0, $MaximumLength)
    }

    $availableLength = $MaximumLength - $prefix.Length
    if ($safeMessage.Length -gt $availableLength) {
        if ($availableLength -eq 1) {
            $safeMessage = '…'
        }
        else {
            $safeMessage = $safeMessage.Substring(0, $availableLength - 1) + '…'
        }
    }
    return $prefix + $safeMessage
}

function Show-AIFishBotGuiErrorSummary {
    param([Parameter(Mandatory = $true)][string]$Summary)

    $injected = Get-Variable -Name AIFishBotGuiErrorPresenter -Scope Global `
        -ErrorAction SilentlyContinue
    if ($null -ne $injected -and $injected.Value -is [scriptblock]) {
        & $injected.Value $Summary | Out-Null
        return $true
    }

    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show(
        $Summary,
        'AI FishBot',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error)
    return $false
}

try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw '界面必须在 STA 模式下运行。请使用启动脚本重新打开。'
    }

    $mutex = New-Object Threading.Mutex($false, (Get-AIFishBotGuiMutexName))
    try {
        $ownsMutex = $mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        $ownsMutex = $true
    }

    if (-not $ownsMutex) {
        $alreadyRunning = $true
        $exitCode = 2
    }
    else {
        if ([string]::IsNullOrWhiteSpace($DataRoot)) {
            throw '数据目录不能为空。'
        }
        $fullDataRoot = [IO.Path]::GetFullPath($DataRoot)
        [void][IO.Directory]::CreateDirectory($fullDataRoot)
        $profilesDirectory = Join-Path $fullDataRoot 'profiles'
        $runtimeRoot = Join-Path $fullDataRoot 'runtime'
        $logsRoot = Join-Path $fullDataRoot 'logs'
        foreach ($directory in @($profilesDirectory, $runtimeRoot, $logsRoot)) {
            [void][IO.Directory]::CreateDirectory($directory)
        }

        $moduleFiles = @(
            'AI-FishBot.Config.psm1',
            'AI-FishBot.Runtime.psm1',
            'AI-FishBot.Dependencies.psm1',
            'AI-FishBot.UI.psm1',
            'AI-FishBot.Controller.psm1'
        )
        $importedModules = New-Object 'System.Collections.Generic.List[string]'
        foreach ($moduleFile in $moduleFiles) {
            $modulePath = Join-Path $PSScriptRoot $moduleFile
            Import-Module -Name $modulePath -Force -ErrorAction Stop
            if ($moduleFile -eq 'AI-FishBot.Runtime.psm1') { $runtimeImported = $true }
            [void]$importedModules.Add($moduleFile)
        }

        $legacyScriptPath = Join-Path $PSScriptRoot 'AI-FishBot.ps1'
        if (@(Get-AIFishBotProfiles -ProfilesDirectory $profilesDirectory).Count -eq 0) {
            $failureContext = '首次配置导入失败'
        }
        $profiles = @(Initialize-AIFishBotProfiles -ProfilesDirectory $profilesDirectory `
                -LegacyScriptPath $legacyScriptPath -InitialProfileName '时光服')
        $failureContext = 'AI FishBot 界面启动失败'
        if ($profiles.Count -eq 0) {
            throw '没有可用的钓鱼方案。'
        }
        $config = Read-AIFishBotProfile -ProfilesDirectory $profilesDirectory -ProfileName $profiles[0]

        $view = New-AIFishBotMainView
        $confirmProvider = {
            param($Purpose)
            $message = switch ($Purpose) {
                'DeleteProfile' { '确定删除当前方案吗？' }
                'ResetProfile' { '确定将当前方案的所有设置恢复为默认值吗？' }
                'ForceStop' { '后台没有及时停止，是否强制结束它？' }
                default { '当前更改尚未保存，确定继续吗？' }
            }
            $choice = [Windows.Forms.MessageBox]::Show(
                $message,
                'AI FishBot',
                [Windows.Forms.MessageBoxButtons]::YesNo,
                [Windows.Forms.MessageBoxIcon]::Question)
            return ($choice -eq [Windows.Forms.DialogResult]::Yes)
        }.GetNewClosure()
        $confirmExitProvider = {
            param($Running, $Unverified)
            if ($Unverified) {
                $choice = [Windows.Forms.MessageBox]::Show(
                    '发现无法验证的后台，它可能仍在运行且不能安全停止。是否仍然退出？',
                    'AI FishBot',
                    [Windows.Forms.MessageBoxButtons]::YesNo,
                    [Windows.Forms.MessageBoxIcon]::Warning)
                if ($choice -eq [Windows.Forms.DialogResult]::Yes) { return 'Continue' }
                return 'Cancel'
            }
            $choice = [Windows.Forms.MessageBox]::Show(
                '后台仍在运行。是否先停止后台再退出？选择“否”会让后台继续运行。',
                'AI FishBot',
                [Windows.Forms.MessageBoxButtons]::YesNo,
                [Windows.Forms.MessageBoxIcon]::Question)
            if ($choice -eq [Windows.Forms.DialogResult]::Yes) { return 'Stop' }
            return 'Continue'
        }.GetNewClosure()
        $profileNameProvider = {
            param($Action, $CurrentName, $SuggestedName)
            Add-Type -AssemblyName Microsoft.VisualBasic
            return [Microsoft.VisualBasic.Interaction]::InputBox(
                '请输入方案名称：',
                'AI FishBot',
                $SuggestedName)
        }.GetNewClosure()

        $controller = New-AIFishBotController -View $view `
            -ProfilesDirectory $profilesDirectory -RuntimeRoot $runtimeRoot `
            -EngineScriptPath (Join-Path $PSScriptRoot 'AI-FishBot.Engine.ps1') `
            -ConfirmProvider $confirmProvider -ConfirmExitProvider $confirmExitProvider `
            -ProfileNameProvider $profileNameProvider -Simulation:$Simulation
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config | Out-Null
        Resume-AIFishBotRun -Controller $controller | Out-Null

        $validation = Test-AIFishBotView -Controller $controller
        if (-not $validation.IsValid) {
            throw '当前方案配置无效，无法创建界面。'
        }
        $pageCount = $view.Controls.MainTabs.TabPages.Count
        $controlCount = $view.Controls.Count
        $requiredControls = @(
            'ProfileSelector', 'SaveButton', 'StartStopButton', 'InstallAudioButton',
            'ClearLogButton', 'OpenLogButton', 'BuffGrid', 'WebhookText'
        )
        foreach ($controlName in $requiredControls) {
            if (-not $view.Controls.ContainsKey($controlName) -or $null -eq $view.Controls[$controlName]) {
                throw ('界面缺少必要控件：{0}' -f $controlName)
            }
        }
        if ($pageCount -ne 5) { throw ('界面页数不正确：{0}' -f $pageCount) }
        if ($null -eq $controller.Binding -or $controller.Binding.Disposed) {
            throw '界面事件没有正确绑定。'
        }

        if ($SelfTest) {
            $selfTestReport = [ordered]@{
                success = $true
                message = '自检通过。'
                modules = @($importedModules)
                profileCount = $profiles.Count
                initialProfile = [string]$config.profileName
                pageCount = $pageCount
                controlCount = $controlCount
                controllerInitialized = $true
                controllerDisposed = $false
                viewDisposed = $false
                simulation = [bool]$Simulation
            }
        }
        elseif (-not $NoShow) {
            [Windows.Forms.Application]::Run($view.Form)
        }
    }
}
catch {
    $exitCode = 1
    $failureSummary = Get-SafeErrorSummary -Exception $_.Exception -Context $failureContext
    Write-AIFishBotGuiFailureLog -Details $_.Exception.ToString()
}
finally {
    if ($null -ne $controller) {
        try { $controller.Dispose() }
        catch { [void]$cleanupErrors.Add(('控制器清理失败：{0}' -f $_.Exception.Message)) }
    }
    if ($null -ne $view) {
        try {
            if (-not $view._Disposed) { $view.Dispose() }
        }
        catch { [void]$cleanupErrors.Add(('界面清理失败：{0}' -f $_.Exception.Message)) }
    }
    if ($null -ne $mutex) {
        if ($ownsMutex) {
            try { $mutex.ReleaseMutex() }
            catch { [void]$cleanupErrors.Add(('单实例锁释放失败：{0}' -f $_.Exception.Message)) }
        }
        try { $mutex.Dispose() }
        catch { [void]$cleanupErrors.Add(('单实例锁清理失败：{0}' -f $_.Exception.Message)) }
    }
}

if ($cleanupErrors.Count -gt 0) {
    $exitCode = 1
    $failureSummary = 'AI FishBot 界面关闭时发生错误。请查看日志了解详情。'
    Write-AIFishBotGuiFailureLog -Details ($cleanupErrors -join '；')
}

if ($alreadyRunning) {
    $result = [ordered]@{
        success = $false
        code = 'AlreadyRunning'
        message = 'AI FishBot 界面已经在此项目路径下运行。'
    }
    if (-not $NoShow -and -not $SelfTest) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show(
                $result.message,
                'AI FishBot',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information)
        }
        catch {
        }
    }
    Write-Output ($result | ConvertTo-Json -Compress)
}
elseif ($SelfTest) {
    if ($null -ne $selfTestReport -and $exitCode -eq 0) {
        $selfTestReport.controllerDisposed = ($null -eq $controller.Binding)
        $selfTestReport.viewDisposed = [bool]$view._Disposed
        if (-not $selfTestReport.controllerDisposed -or -not $selfTestReport.viewDisposed) {
            $selfTestReport.success = $false
            $selfTestReport.message = '自检清理失败。'
            $exitCode = 1
        }
        Write-Output ($selfTestReport | ConvertTo-Json -Depth 5 -Compress)
    }
    else {
        Write-Output ([ordered]@{
                success = $false
                message = $failureSummary
            } | ConvertTo-Json -Compress)
    }
}
elseif ($exitCode -ne 0) {
    if ($NoShow) {
        [Console]::Error.WriteLine($failureSummary)
    }
    else {
        try {
            $usedInjectedPresenter = Show-AIFishBotGuiErrorSummary -Summary $failureSummary
            if ($usedInjectedPresenter) { [Console]::Error.WriteLine($failureSummary) }
        }
        catch {
            [Console]::Error.WriteLine($failureSummary)
        }
    }
}

exit $exitCode
