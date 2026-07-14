$controllerModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AI-FishBot.Controller.psm1'
$configModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AI-FishBot.Config.psm1'
$runtimeModulePath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AI-FishBot.Runtime.psm1'
Import-Module $configModulePath -Force
Import-Module $runtimeModulePath -Force
Import-Module $controllerModulePath -Force

function New-ControllerFakeControl {
    param(
        [AllowNull()][object]$Value,
        [string]$Text = '',
        [bool]$Checked = $false
    )

    $control = [pscustomobject]@{
        Value = $Value
        Text = $Text
        Checked = $Checked
        SelectedItem = $null
        SelectedIndex = -1
        Items = New-Object System.Collections.ArrayList
        Rows = @()
        Enabled = $true
        ReadOnly = $false
        BackColor = 'normal'
        ForeColor = 'normal'
        ErrorText = ''
        HasError = $false
        Events = @{}
        Visible = $true
        Name = ''
    }
    foreach ($eventName in @(
            'Click', 'CheckedChanged', 'ValueChanged', 'SelectedIndexChanged', 'TextChanged',
            'CellValueChanged', 'RowsAdded', 'RowsRemoved', 'Tick', 'DoubleClick')) {
        $nameCopy = $eventName
        $control | Add-Member -MemberType ScriptMethod -Name ('Add_{0}' -f $eventName) -Value ({
                param([scriptblock]$Handler)
                if (-not $this.Events.ContainsKey($nameCopy)) {
                    $this.Events[$nameCopy] = New-Object System.Collections.ArrayList
                }
                [void]$this.Events[$nameCopy].Add($Handler)
            }.GetNewClosure())
        $control | Add-Member -MemberType ScriptMethod -Name ('Remove_{0}' -f $eventName) -Value ({
                param([scriptblock]$Handler)
                if ($this.Events.ContainsKey($nameCopy)) {
                    [void]$this.Events[$nameCopy].Remove($Handler)
                }
            }.GetNewClosure())
    }
    $control | Add-Member -MemberType ScriptMethod -Name InvokeEvent -Value {
        param([string]$EventName, $EventArgs = $null)
        foreach ($handler in @($this.Events[$EventName])) {
            & $handler $this $EventArgs
        }
    }
    return $control
}

function New-ControllerFakeView {
    $controls = @{}
    foreach ($name in @(
            'ProfileSelector', 'NewProfileButton', 'CopyProfileButton', 'RenameProfileButton',
            'DeleteProfileButton', 'ResetProfileButton', 'StatusBadge', 'SaveStateLabel', 'SaveButton', 'StartStopButton',
            'Retail', 'AutoStop', 'AutoStopTime', 'AutoLogout', 'AudioSensitivity', 'AudioPeakBar',
            'HookCount', 'RemainingTime', 'BiteResponseMin', 'BiteResponseMax', 'PreHookMin',
            'PreHookMax', 'PostHookMin', 'PostHookMax', 'PreCastMin', 'PreCastMax', 'CastKey',
            'BobberKey', 'LogoutKey', 'UseWindowFocus', 'UseWeakAura', 'FishingRetries', 'UsePi',
            'PicoComPort', 'BuffGrid', 'AddBuffButton', 'RemoveBuffButton', 'MoveBuffUpButton',
            'MoveBuffDownButton', 'EnableNotifications', 'NotifyOnStart', 'NotifyOnStop',
            'WebhookText', 'InstallAudioButton', 'LogLevel', 'ClearLogButton', 'OpenLogButton',
            'LogBox')) {
        $controls[$name] = New-ControllerFakeControl -Value 0
        $controls[$name].Name = $name
    }
    $controls.LogBox.Text = ''
    $trayItems = @{}
    foreach ($name in @('StatusItem', 'OpenItem', 'StartItem', 'StopItem', 'ExitItem')) {
        $trayItems[$name] = New-ControllerFakeControl
        $trayItems[$name].Name = $name
    }
    $form = [pscustomobject]@{
        Visible = $true
        WindowState = 'Normal'
        Events = @{}
        WasActivated = $false
        WasDisposed = $false
    }
    foreach ($eventName in @('FormClosing', 'Resize')) {
        $copy = $eventName
        $form | Add-Member -MemberType ScriptMethod -Name ('Add_{0}' -f $eventName) -Value ({
                param([scriptblock]$Handler)
                if (-not $this.Events.ContainsKey($copy)) { $this.Events[$copy] = New-Object System.Collections.ArrayList }
                [void]$this.Events[$copy].Add($Handler)
            }.GetNewClosure())
        $form | Add-Member -MemberType ScriptMethod -Name ('Remove_{0}' -f $eventName) -Value ({
                param([scriptblock]$Handler)
                if ($this.Events.ContainsKey($copy)) {
                    [void]$this.Events[$copy].Remove($Handler)
                }
            }.GetNewClosure())
    }
    $form | Add-Member -MemberType ScriptMethod -Name Show -Value { $this.Visible = $true }
    $form | Add-Member -MemberType ScriptMethod -Name Hide -Value { $this.Visible = $false }
    $form | Add-Member -MemberType ScriptMethod -Name Activate -Value { $this.WasActivated = $true }
    $form | Add-Member -MemberType ScriptMethod -Name InvokeEvent -Value {
        param([string]$EventName, $EventArgs = $null)
        foreach ($handler in @($this.Events[$EventName])) {
            & $handler $this $EventArgs
        }
    }

    $view = [pscustomobject]@{
        Controls = $controls
        Form = $form
        TrayIcon = New-ControllerFakeControl
        TrayMenu = [pscustomobject]@{ Items = @($trayItems.Values); ByName = $trayItems }
        Timers = [pscustomobject]@{ Status = (New-ControllerFakeControl); Log = (New-ControllerFakeControl) }
        ExitCount = 0
    }
    $view | Add-Member -MemberType ScriptMethod -Name Exit -Value {
        $this.ExitCount += 1
        $this.Form.WasDisposed = $true
    }
    return $view
}

function New-ControllerTestConfig {
    param([string]$Name = '中文 方案')
    $config = New-AIFishBotDefaultConfig
    $config.profileName = $Name
    $config.retail = $true
    $config.autoStop = $true
    $config.autoStopTime = 25
    $config.autoLogout = $true
    $config.audioSensitivity = 7
    $config.useWindowFocus = $false
    $config.useWeakAura = $true
    $config.fishingRetries = 23
    $config.castKey = 'F9'
    $config.bobberKey = 'F10'
    $config.logoutKey = 'F11'
    $config.usePi = $true
    $config.picoComPort = 'COM7'
    $config.enableNotifications = $true
    $config.discordWebhook = 'https://discord.com/api/webhooks/123456/secret-token'
    $config.notifyOnStart = $false
    $config.notifyOnStop = $true
    $config.biteResponseMinSeconds = 0.4
    $config.biteResponseMaxSeconds = 0.8
    $config.preHookMinSeconds = 0.6
    $config.preHookMaxSeconds = 0.9
    $config.postHookMinSeconds = 1.2
    $config.postHookMaxSeconds = 1.8
    $config.preCastMinSeconds = 0.3
    $config.preCastMaxSeconds = 0.7
    $config.buffs = @([pscustomobject][ordered]@{
            enabled = $true; name = '帽子'; keybind = 'F12'; castTimeSeconds = 2; durationMinutes = 10
        })
    return $config
}

function New-ControllerForTest {
    param(
        [Parameter(Mandatory = $true)]$View,
        [Parameter(Mandatory = $true)][string]$Root,
        [scriptblock]$DependencyChecker = { [pscustomobject]@{ Status = 'Available'; IsAvailable = $true } },
        [scriptblock]$ProcessStarter = { throw '测试必须注入进程启动器。' },
        [scriptblock]$ProcessLookup = {
            param($id)
            [pscustomobject]@{ Id = $id; StartTime = [datetime]'2026-07-13T01:59:00Z' }
        },
        [scriptblock]$StatusReader = { param($path) throw '没有状态。' },
        [scriptblock]$Clock = { [datetimeoffset]'2026-07-13T10:00:00+08:00' },
        [scriptblock]$Sleeper = { param($milliseconds) },
        [scriptblock]$ConfirmProvider = { param($purpose) $true },
        [scriptblock]$ConfirmExitProvider = { param($running) 'Continue' },
        [scriptblock]$ProfileNameProvider = { param($action, $currentName, $suggestedName) $suggestedName },
        [scriptblock]$ForceStopper = { param($id) },
        [scriptblock]$DependencyInstaller,
        [scriptblock]$LogOpener,
        [scriptblock]$LiveConfigWriter,
        [switch]$Simulation
    )
    $profiles = Join-Path $Root 'profiles'
    $runtime = Join-Path $Root 'runtime'
    $controllerParameters = @{
        View = $View
        ProfilesDirectory = $profiles
        RuntimeRoot = $runtime
        EngineScriptPath = 'C:\测试 目录\AI-FishBot.Engine.ps1'
        DependencyChecker = $DependencyChecker
        ProcessStarter = $ProcessStarter
        ProcessLookup = $ProcessLookup
        StatusReader = $StatusReader
        Clock = $Clock
        Sleeper = $Sleeper
        ConfirmProvider = $ConfirmProvider
        ConfirmExitProvider = $ConfirmExitProvider
        ProfileNameProvider = $ProfileNameProvider
        ForceStopper = $ForceStopper
        AvailablePortsProvider = { @('COM7') }
    }
    if ($PSBoundParameters.ContainsKey('DependencyInstaller')) {
        $controllerParameters.DependencyInstaller = $DependencyInstaller
    }
    if ($PSBoundParameters.ContainsKey('LogOpener')) {
        $controllerParameters.LogOpener = $LogOpener
    }
    if ($PSBoundParameters.ContainsKey('LiveConfigWriter')) {
        $controllerParameters.LiveConfigWriter = $LiveConfigWriter
    }
    if ($Simulation) { $controllerParameters.Simulation = $true }
    New-AIFishBotController @controllerParameters
}

function Remove-ControllerTestDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ControllerRealButtonClick {
    param([Parameter(Mandatory = $true)]$Button)
    $method = $Button.GetType().GetMethod(
        'OnClick',
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    if ($null -eq $method) { throw '无法触发真实按钮的点击事件。' }
    $method.Invoke($Button, [object[]]@([System.EventArgs]::Empty)) | Out-Null
}

function Assert-UnverifiedMarkerBlocksRealViewStart {
    param([Parameter(Mandatory = $true)][scriptblock]$MarkerFactory)

    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) `
                -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        $processStart = [datetimeoffset]'2026-07-13T10:00:00.1234567+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) `
            -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1562; state = 'ready'; startedAt = $processStart.ToString('o')
            processStartedAt = $processStart.ToString('o')
            heartbeatAt = $processStart.AddSeconds(5).ToString('o'); configVersion = 1
        }
        $marker = & $MarkerFactory $run $processStart
        $markerPath = Join-Path (Join-Path $root 'runtime') 'active-run.json'
        Write-AIFishBotAtomicJson -Path $markerPath -InputObject $marker | Out-Null
        $markerBefore = Get-Content -LiteralPath $markerPath -Raw
        $state = [pscustomobject]@{ StarterCalls = 0 }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup {
                param($id)
                if ($id -eq 1562) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter {
                param($request)
                $state.StarterCalls += 1
                [pscustomobject]@{ Id = 2562; StartTime = $processStart.AddMinutes(1).UtcDateTime }
            }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null

        Invoke-ControllerRealButtonClick $view.Controls.StartStopButton

        Assert-Equal -Expected 0 -Actual $state.StarterCalls
        Assert-Equal -Expected $false -Actual $controller.IsRunning
        Assert-True -Condition ($null -ne $controller.UnverifiedBackground)
        Assert-Equal -Expected 1562 -Actual $controller.UnverifiedBackground.Pid
        Assert-Equal -Expected '发现无法验证的后台，可能仍在运行，需要手动处理。' `
            -Actual $view.Controls.SaveStateLabel.Text
        Assert-True -Condition ($view.Controls.StatusBadge.Text -like '*后台身份待处理*')
        Assert-Equal -Expected $markerBefore -Actual (Get-Content -LiteralPath $markerPath -Raw)
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'Controller exports its public commands' {
    $expected = @(
        'New-AIFishBotController', 'Set-AIFishBotViewFromConfig', 'Get-AIFishBotConfigFromView',
        'Test-AIFishBotView', 'Set-AIFishBotRunningState', 'Save-AIFishBotCurrentProfile',
        'Start-AIFishBotRun', 'Stop-AIFishBotRun', 'Resume-AIFishBotRun',
        'Update-AIFishBotViewStatus', 'Update-AIFishBotViewLog'
    )
    $actual = @(Get-Command -Module AI-FishBot.Controller | Select-Object -ExpandProperty Name)
    foreach ($name in $expected) {
        Assert-True -Condition ($actual -contains $name)
    }
}

Test-Case 'Controller owns a resolvable default serial-port provider' {
    $command = & (Get-Module 'AI-FishBot.Controller') {
        Get-Command 'Get-AIFishBotControllerAvailablePorts' -ErrorAction SilentlyContinue
    }
    Assert-True -Condition ($null -ne $command)
}

Test-Case 'Config and every editable view field round trip without marking a load dirty' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $config = New-ControllerTestConfig

        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        $actual = Get-AIFishBotConfigFromView -Controller $controller

        Assert-Equal -Expected (($config | ConvertTo-Json -Depth 10 -Compress)) -Actual (($actual | ConvertTo-Json -Depth 10 -Compress))
        Assert-Equal -Expected $false -Actual $controller.IsDirty
        Assert-Equal -Expected '已保存' -Actual $view.Controls.SaveStateLabel.Text
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'A user edit marks the profile unsaved' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig)

        $view.Controls.AutoStop.Checked = $false
        $view.Controls.AutoStop.InvokeEvent('CheckedChanged')

        Assert-Equal -Expected $true -Actual $controller.IsDirty
        Assert-Equal -Expected '未保存' -Actual $view.Controls.SaveStateLabel.Text
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Invalid view fields show a Chinese error and disable Start' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig)
        $view.Controls.PreHookMin.Value = 2.0
        $view.Controls.PreHookMax.Value = 1.0

        $validation = Test-AIFishBotView -Controller $controller

        Assert-Equal -Expected $false -Actual $validation.IsValid
        Assert-Equal -Expected $true -Actual $view.Controls.PreHookMin.HasError
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($view.Controls.PreHookMin.ErrorText))
        Assert-Equal -Expected $false -Actual $view.Controls.StartStopButton.Enabled
        $view.Controls.StartStopButton.InvokeEvent('Click')
        Assert-True -Condition ($view.Controls.SaveStateLabel.Text -like '配置错误：*')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Running locks fixed settings while live settings remain editable' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotRunningState -Controller $controller -Running $true

        foreach ($name in @('Retail', 'UseWindowFocus', 'UseWeakAura', 'FishingRetries', 'CastKey', 'BobberKey', 'LogoutKey', 'UsePi', 'PicoComPort', 'NotifyOnStart', 'ProfileSelector', 'RenameProfileButton', 'DeleteProfileButton', 'ResetProfileButton')) {
            Assert-Equal -Expected $false -Actual $view.Controls[$name].Enabled
        }
        foreach ($name in @('AudioSensitivity', 'AutoStop', 'AutoStopTime', 'AutoLogout', 'BiteResponseMin', 'BiteResponseMax', 'PreHookMin', 'PreHookMax', 'PostHookMin', 'PostHookMax', 'PreCastMin', 'PreCastMax', 'BuffGrid', 'EnableNotifications', 'WebhookText', 'NotifyOnStop')) {
            Assert-Equal -Expected $true -Actual $view.Controls[$name].Enabled
        }
        Assert-Equal -Expected $true -Actual $view.Timers.Status.Enabled
        Assert-Equal -Expected $true -Actual $view.Timers.Log.Enabled

        $liveControls = @(
            'AudioSensitivity', 'AutoStop', 'AutoStopTime', 'AutoLogout',
            'BiteResponseMin', 'BiteResponseMax', 'PreHookMin', 'PreHookMax',
            'PostHookMin', 'PostHookMax', 'PreCastMin', 'PreCastMax',
            'BuffGrid', 'EnableNotifications', 'WebhookText', 'NotifyOnStop'
        )
        $allConfigControls = @(
            'Retail', 'AutoStop', 'AutoStopTime', 'AutoLogout', 'AudioSensitivity',
            'UseWindowFocus', 'UseWeakAura', 'FishingRetries', 'CastKey', 'BobberKey',
            'LogoutKey', 'UsePi', 'PicoComPort', 'EnableNotifications', 'WebhookText',
            'NotifyOnStart', 'NotifyOnStop', 'BiteResponseMin', 'BiteResponseMax',
            'PreHookMin', 'PreHookMax', 'PostHookMin', 'PostHookMax', 'PreCastMin',
            'PreCastMax', 'BuffGrid'
        )
        foreach ($name in $allConfigControls) {
            Assert-Equal -Expected ($liveControls -contains $name) -Actual $view.Controls[$name].Enabled
        }
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Saving a stopped profile uses the profile store and clears dirty state' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '保存方案')
        $controller.MarkDirty()

        $result = Save-AIFishBotCurrentProfile -Controller $controller
        $saved = Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '保存方案'

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 25 -Actual $saved.autoStopTime
        Assert-Equal -Expected $false -Actual $controller.IsDirty
        Assert-Equal -Expected '已保存' -Actual $view.Controls.SaveStateLabel.Text
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Saving while running persists the profile but writes only live fields with a strict version increment' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $config = New-ControllerTestConfig -Name '运行方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $runDirectory = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 4 })
        $controller.CurrentRunDirectory = $runDirectory
        $controller.ConfigVersion = 4
        Set-AIFishBotRunningState -Controller $controller -Running $true
        $view.Controls.AudioSensitivity.Value = 8
        $view.Controls.WebhookText.Text = 'https://discord.com/api/webhooks/987654/new-secret-token'
        $view.Controls.Retail.Checked = $false

        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $live = Read-AIFishBotJson -Path (Join-Path $runDirectory 'live-config.json')
        $saved = Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '运行方案'

        Assert-Equal -Expected 5 -Actual $live.configVersion
        Assert-Equal -Expected 8 -Actual $live.audioSensitivity
        Assert-Equal -Expected 'https://discord.com/api/webhooks/987654/new-secret-token' -Actual $live.discordWebhook
        Assert-True -Condition ($null -eq $live.PSObject.Properties['retail'])
        Assert-True -Condition ($null -eq $live.PSObject.Properties['notifyOnStart'])
        Assert-Equal -Expected $false -Actual $saved.retail
        Assert-Equal -Expected 'https://discord.com/api/webhooks/987654/new-secret-token' -Actual $saved.discordWebhook
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Reset profile cancellation preserves the file view and dirty state' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:resetPurposes = @()
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider {
            param($purpose)
            $script:resetPurposes += $purpose
            return $false
        }
        $config = New-ControllerTestConfig -Name '取消重置方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $view.Controls.AutoStopTime.Value = 44
        $controller.MarkDirty()
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '取消重置方案'
        $fileBefore = Get-Content -LiteralPath $profilePath -Raw
        $viewBefore = (Get-AIFishBotConfigFromView $controller | ConvertTo-Json -Depth 20 -Compress)

        $result = $controller.ResetProfile()

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.Cancelled
        Assert-Equal -Expected @('ResetProfile') -Actual $script:resetPurposes
        Assert-Equal -Expected $fileBefore -Actual (Get-Content -LiteralPath $profilePath -Raw)
        Assert-Equal -Expected $viewBefore -Actual (Get-AIFishBotConfigFromView $controller | ConvertTo-Json -Depth 20 -Compress)
        Assert-Equal -Expected $true -Actual $controller.IsDirty
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable resetPurposes -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Reset profile atomically restores every default while preserving its name' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider { param($purpose) $purpose -eq 'ResetProfile' }
        $config = New-ControllerTestConfig -Name '保留名称'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $controller.MarkDirty()

        $result = $controller.ResetProfile()
        $saved = Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '保留名称'
        $expected = New-AIFishBotDefaultConfig
        $expected.profileName = '保留名称'

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected ($expected | ConvertTo-Json -Depth 20 -Compress) -Actual ($saved | ConvertTo-Json -Depth 20 -Compress)
        Assert-Equal -Expected ($expected | ConvertTo-Json -Depth 20 -Compress) -Actual (Get-AIFishBotConfigFromView $controller | ConvertTo-Json -Depth 20 -Compress)
        Assert-Equal -Expected $false -Actual $controller.IsDirty
        Assert-Equal -Expected '已保存' -Actual $view.Controls.SaveStateLabel.Text
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Reset profile is disabled and rejected while running' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:resetConfirmCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider { param($purpose) $script:resetConfirmCalls += 1; $true }
        $config = New-ControllerTestConfig -Name '运行重置方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = $controller.ResetProfile()

        Assert-Equal -Expected $false -Actual $view.Controls.ResetProfileButton.Enabled
        Assert-Equal -Expected $false -Actual $result.Success
        Assert-True -Condition ($result.Error -like '*运行中*')
        Assert-Equal -Expected 0 -Actual $script:resetConfirmCalls
        Assert-Equal -Expected ($config | ConvertTo-Json -Depth 20 -Compress) -Actual (Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '运行重置方案' | ConvertTo-Json -Depth 20 -Compress)
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable resetConfirmCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Failed reset preserves the original profile and current view without a half reset' {
    $root = New-TestDirectory
    $lock = $null
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider { param($purpose) $true }
        $config = New-ControllerTestConfig -Name '失败重置方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $profilePath = Get-AIFishBotProfilePath -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '失败重置方案'
        $fileBefore = Get-Content -LiteralPath $profilePath -Raw
        $viewBefore = (Get-AIFishBotConfigFromView $controller | ConvertTo-Json -Depth 20 -Compress)
        $lock = [System.IO.File]::Open($profilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)

        $result = $controller.ResetProfile()
        $lock.Dispose()
        $lock = $null

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($result.Error))
        Assert-Equal -Expected $fileBefore -Actual (Get-Content -LiteralPath $profilePath -Raw)
        Assert-Equal -Expected $viewBefore -Actual (Get-AIFishBotConfigFromView $controller | ConvertTo-Json -Depth 20 -Compress)
    }
    finally {
        if ($null -ne $lock) { $lock.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'Running edits remain unsaved until Save writes one new live version' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $config = New-ControllerTestConfig -Name '实时保存方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 3 })
        $controller.CurrentRunDirectory = $run
        $controller.ConfigVersion = 3
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.Controls.AudioSensitivity.Value = 8
        $view.Controls.AudioSensitivity.InvokeEvent('ValueChanged')
        Assert-Equal -Expected 3 -Actual (Read-AIFishBotJson -Path (Join-Path $run 'live-config.json')).configVersion
        Assert-Equal -Expected $true -Actual $controller.IsDirty

        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        Assert-Equal -Expected 4 -Actual (Read-AIFishBotJson -Path (Join-Path $run 'live-config.json')).configVersion
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Running Save reports when profile persistence succeeds but live persistence fails' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $config = New-ControllerTestConfig -Name '部分保存方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $run = Join-Path $root 'runtime\broken-run'
        New-Item -ItemType Directory -Path (Join-Path $run 'live-config.json') -Force | Out-Null
        $controller.CurrentRunDirectory = $run
        $controller.ConfigVersion = 1
        Set-AIFishBotRunningState -Controller $controller -Running $true
        $view.Controls.AutoStopTime.Value = 33
        $controller.MarkDirty()

        $result = Save-AIFishBotCurrentProfile -Controller $controller
        $saved = Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '部分保存方案'

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.ProfileSaved
        Assert-Equal -Expected $false -Actual $result.LiveConfigSaved
        Assert-Equal -Expected 33 -Actual $saved.autoStopTime
        Assert-Equal -Expected $true -Actual $controller.IsDirty
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Running live-config failure masks the webhook in the returned error and status bar' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:sensitiveWebhook = 'https://discord.com/api/webhooks/654321/private-live-token'
        $controller = New-ControllerForTest -View $view -Root $root -LiveConfigWriter {
            param($controllerState, $configState)
            throw ('模拟写入失败：{0}' -f $script:sensitiveWebhook)
        }
        $config = New-ControllerTestConfig -Name '安全失败方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.ConfigVersion = 1
        Set-AIFishBotRunningState -Controller $controller -Running $true
        $view.Controls.WebhookText.Text = $script:sensitiveWebhook

        $result = Save-AIFishBotCurrentProfile -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.ProfileSaved
        Assert-True -Condition ($result.Error -like '*实时配置写入失败*')
        Assert-True -Condition ($view.Controls.SaveStateLabel.Text -like '*实时配置写入失败*')
        foreach ($text in @([string]$result.Error, [string]$view.Controls.SaveStateLabel.Text, [string]$view.Controls.LogBox.Text)) {
            Assert-True -Condition (-not $text.Contains($script:sensitiveWebhook))
            Assert-True -Condition (-not $text.Contains('private-live-token'))
        }
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable sensitiveWebhook -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'A real hidden reset button click restores defaults through the controller binding' {
    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) `
                -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        $script:realResetPurpose = ''
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider {
            param($purpose)
            $script:realResetPurpose = $purpose
            return $true
        }
        $config = New-ControllerTestConfig -Name '真实按钮方案'
        Set-AIFishBotViewFromConfig -Controller $controller -Config $config
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null

        Invoke-ControllerRealButtonClick $view.Controls.ResetProfileButton

        $expected = New-AIFishBotDefaultConfig
        $expected.profileName = '真实按钮方案'
        $saved = Read-AIFishBotProfile -ProfilesDirectory (Join-Path $root 'profiles') -ProfileName '真实按钮方案'
        Assert-Equal -Expected 'ResetProfile' -Actual $script:realResetPurpose
        Assert-Equal -Expected ($expected | ConvertTo-Json -Depth 20 -Compress) -Actual ($saved | ConvertTo-Json -Depth 20 -Compress)
        Assert-Equal -Expected $false -Actual $controller.IsDirty
        Assert-Equal -Expected $false -Actual $view.Form.Visible
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
        Remove-Variable realResetPurpose -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Profile buttons create copy rename and delete with collision-free copy names' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:names = @('新建方案', '改名方案')
        $nameProvider = {
            param($action, $current, $suggested)
            if ($action -eq 'New') { return $script:names[0] }
            if ($action -eq 'Rename') { return $script:names[1] }
            return $suggested
        }
        $controller = New-ControllerForTest -View $view -Root $root -ProfileNameProvider $nameProvider
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '原方案')
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null

        $controller.NewProfile() | Out-Null
        $controller.CopyProfile() | Out-Null
        $controller.CopyProfile() | Out-Null
        $controller.RenameProfile() | Out-Null
        $controller.DeleteProfile() | Out-Null
        $profiles = @(Get-AIFishBotProfiles -ProfilesDirectory (Join-Path $root 'profiles'))

        Assert-Equal -Expected 3 -Actual $profiles.Count
        foreach ($name in @('原方案', '新建方案', '新建方案 - 副本')) {
            Assert-True -Condition ($profiles -contains $name)
        }
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable names -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Deleting a dirty profile confirms once and loads the remaining profile' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:deleteConfirmCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider {
            param($purpose)
            $script:deleteConfirmCalls += 1
            return ($script:deleteConfirmCalls -eq 1)
        }
        foreach ($name in @('保留方案', '删除方案')) {
            Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name $name)
            Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        }
        $controller.MarkDirty()

        $result = $controller.DeleteProfile()

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 1 -Actual $script:deleteConfirmCalls
        Assert-Equal -Expected '保留方案' -Actual $controller.CurrentProfileName
        Assert-Equal -Expected @('保留方案') -Actual @(Get-AIFishBotProfiles -ProfilesDirectory (Join-Path $root 'profiles'))
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable deleteConfirmCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'An active run blocks profile switching renaming and deletion' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '甲')
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        Set-AIFishBotRunningState -Controller $controller -Running $true

        Assert-Equal -Expected $false -Actual ($controller.SwitchProfile('甲')).Success
        Assert-Equal -Expected $false -Actual ($controller.RenameProfile()).Success
        Assert-Equal -Expected $false -Actual ($controller.DeleteProfile()).Success
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Unsaved profile switching asks for confirmation and respects rejection' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:allowSwitch = $false
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider { param($purpose) $script:allowSwitch }
        foreach ($name in @('甲', '乙')) {
            Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name $name)
            Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        }
        $controller.SwitchProfile('甲') | Out-Null
        $controller.MarkDirty()

        Assert-Equal -Expected $false -Actual ($controller.SwitchProfile('乙')).Success
        Assert-Equal -Expected '甲' -Actual $controller.CurrentProfileName
        $script:allowSwitch = $true
        Assert-Equal -Expected $true -Actual ($controller.SwitchProfile('乙')).Success
        Assert-Equal -Expected '乙' -Actual $controller.CurrentProfileName
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable allowSwitch -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'New and copy actions cannot leave an unsaved profile without confirmation' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmProvider { param($purpose) $false }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '未保存方案')
        Save-AIFishBotCurrentProfile -Controller $controller | Out-Null
        $controller.MarkDirty()

        Assert-Equal -Expected $false -Actual ($controller.NewProfile()).Success
        Assert-Equal -Expected $false -Actual ($controller.CopyProfile()).Success
        Assert-Equal -Expected '未保存方案' -Actual $controller.CurrentProfileName
        Assert-Equal -Expected @('未保存方案') -Actual @(Get-AIFishBotProfiles -ProfilesDirectory (Join-Path $root 'profiles'))
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Start saves then reports a missing dependency without starting or installing anything' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:starterCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -DependencyChecker { [pscustomobject]@{ Status = 'Missing'; IsAvailable = $false } } `
            -ProcessStarter { param($request) $script:starterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '依赖方案')

        $result = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.RequiresDependencyInstall
        Assert-Equal -Expected 0 -Actual $script:starterCalls
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $root 'profiles\依赖方案.json'))
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable starterCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Start writes snapshots and passes safely quoted Chinese paths to hidden Windows PowerShell' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:startRequest = $null
        $controller = New-ControllerForTest -View $view -Root $root -ProcessStarter {
            param($request)
            $script:startRequest = $request
            [pscustomobject]@{ Id = 4321 }
        }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '启动方案')

        $result = Start-AIFishBotRun -Controller $controller
        $start = Read-AIFishBotJson -Path (Join-Path $result.RunDirectory 'start-config.json')
        $live = Read-AIFishBotJson -Path (Join-Path $result.RunDirectory 'live-config.json')

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 4321 -Actual $result.Pid
        Assert-True -Condition ($script:startRequest.FilePath -like '*WindowsPowerShell*v1.0*powershell.exe')
        Assert-True -Condition ($script:startRequest.ArgumentList -like '*-WindowStyle Hidden*')
        Assert-True -Condition ($script:startRequest.ArgumentList -like '*"C:\测试 目录\AI-FishBot.Engine.ps1"*')
        Assert-True -Condition ($script:startRequest.ArgumentList -like ('*"{0}"*' -f $result.RunDirectory))
        Assert-Equal -Expected '启动方案' -Actual $start.profileName
        Assert-Equal -Expected 1 -Actual $live.configVersion
        Assert-True -Condition ($null -eq $live.PSObject.Properties['retail'])
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable startRequest -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Simulation mode is passed only to the engine child process request' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:simulationRequest = $null
        $controller = New-ControllerForTest -View $view -Root $root -Simulation -ProcessStarter {
            param($request)
            $script:simulationRequest = $request
            [pscustomobject]@{ Id = 4322; StartTime = [datetime]'2026-07-13T01:59:00Z' }
        }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '模拟启动方案')

        $result = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-True -Condition ($script:simulationRequest.ArgumentList -match '(?:^|\s)-Simulation(?:\s|$)')

        $normalView = New-ControllerFakeView
        $script:normalRequest = $null
        $normalRoot = Join-Path $root 'normal'
        $normal = New-ControllerForTest -View $normalView -Root $normalRoot -ProcessStarter {
            param($request)
            $script:normalRequest = $request
            [pscustomobject]@{ Id = 4323; StartTime = [datetime]'2026-07-13T01:59:01Z' }
        }
        Set-AIFishBotViewFromConfig -Controller $normal -Config (New-ControllerTestConfig -Name '普通启动方案')
        Assert-Equal -Expected $true -Actual (Start-AIFishBotRun -Controller $normal).Success
        Assert-Equal -Expected $false -Actual ($script:normalRequest.ArgumentList -match '(?:^|\s)-Simulation(?:\s|$)')
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable simulationRequest -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable normalRequest -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'audio dependency installation runs only after the user clicks its button' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:installCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root -DependencyInstaller {
            $script:installCalls += 1
            [pscustomobject]@{ Success = $true; Summary = '模拟安装完成。'; Details = '' }
        }

        Assert-Equal -Expected 0 -Actual $script:installCalls
        Assert-True -Condition ($null -eq $controller.LastDependencyInstallResult)

        $view.Controls.InstallAudioButton.InvokeEvent('Click')

        Assert-Equal -Expected 1 -Actual $script:installCalls
        Assert-Equal -Expected $true -Actual $controller.LastDependencyInstallResult.Success
        Assert-Equal -Expected '模拟安装完成。' -Actual $view.Controls.InstallAudioButton.Text
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable installCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'log toolbar buttons clear the view and open only the isolated run log folder' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:openedLogPath = $null
        $controller = New-ControllerForTest -View $view -Root $root -LogOpener {
            param($path)
            $script:openedLogPath = $path
        }
        $run = Join-Path $root 'runtime\run-test'
        $logs = Join-Path $run 'logs'
        New-Item -ItemType Directory -Path $logs -Force | Out-Null
        $controller.CurrentRunDirectory = $run
        $controller.RawLogHistory = 'old line'
        $view.Controls.LogBox.Text = 'old line'

        $view.Controls.ClearLogButton.InvokeEvent('Click')
        Assert-Equal -Expected '' -Actual $controller.RawLogHistory
        Assert-Equal -Expected '' -Actual $view.Controls.LogBox.Text

        $view.Controls.OpenLogButton.InvokeEvent('Click')
        Assert-Equal -Expected ([IO.Path]::GetFullPath($logs)) -Actual $script:openedLogPath

        $controller.CurrentRunDirectory = $null
        $script:openedLogPath = $null
        $view.Controls.OpenLogButton.InvokeEvent('Click')
        Assert-Equal -Expected ([IO.Path]::GetFullPath((Join-Path $root 'logs'))) -Actual $script:openedLogPath
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable openedLogPath -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'clearing a polled log keeps old lines hidden while allowing later lines to appear' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        Write-AIFishBotLog -RunDirectory $run -Level INFO -Message 'old line' | Out-Null
        Update-AIFishBotViewLog -Controller $controller | Out-Null

        $view.Controls.ClearLogButton.InvokeEvent('Click')
        Update-AIFishBotViewLog -Controller $controller | Out-Null
        Assert-Equal -Expected '' -Actual $view.Controls.LogBox.Text

        Write-AIFishBotLog -RunDirectory $run -Level ERROR -Message 'new line' | Out-Null
        Update-AIFishBotViewLog -Controller $controller | Out-Null
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*new line*')
        Assert-Equal -Expected $false -Actual ($view.Controls.LogBox.Text -like '*old line*')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'log level selection filters existing lines and can restore the complete view' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $content = "2026-07-14T10:00:00+08:00 [INFO] info line`n" +
            "2026-07-14T10:00:01+08:00 [WARNING] warn line`n" +
            '2026-07-14T10:00:02+08:00 [ERROR] error line'
        Update-AIFishBotViewLog -Controller $controller -Content $content | Out-Null

        $view.Controls.LogLevel.SelectedItem = '错误'
        $view.Controls.LogLevel.InvokeEvent('SelectedIndexChanged')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*error line*')
        Assert-Equal -Expected $false -Actual ($view.Controls.LogBox.Text -like '*info line*')
        Assert-Equal -Expected $false -Actual ($view.Controls.LogBox.Text -like '*warn line*')

        $view.Controls.LogLevel.SelectedItem = '全部'
        $view.Controls.LogLevel.InvokeEvent('SelectedIndexChanged')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*info line*')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*warn line*')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*error line*')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'A starter failure rolls back the new run directory and running state' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root -ProcessStarter { param($request) throw '模拟启动失败' }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '失败方案')

        $result = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $false -Actual $controller.IsRunning
        Assert-Equal -Expected 0 -Actual @((Get-ChildItem -LiteralPath (Join-Path $root 'runtime') -Directory -ErrorAction SilentlyContinue)).Count
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'A marker write failure after process start keeps the known background run recoverable' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:markerController = $null
        $controller = New-ControllerForTest -View $view -Root $root -ProcessStarter {
            param($request)
            New-Item -ItemType Directory -Path $script:markerController.ActiveMarkerPath -Force | Out-Null
            [pscustomobject]@{ Id = 7788 }
        }
        $script:markerController = $controller
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '标记失败方案')

        $result = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.MarkerWriteFailed
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected 7788 -Actual $controller.CurrentProcessId
        Assert-True -Condition (Test-Path -LiteralPath $controller.CurrentRunDirectory -PathType Container)
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable markerController -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Start refuses another valid active run under the runtime root' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $runtime = Join-Path $root 'runtime'
        $existing = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $status = [pscustomobject]@{
            processId = 90; state = 'ready'; heartbeatAt = $now.ToString('o')
            startedAt = $now.AddMinutes(-1).ToString('o')
        }
        $script:starterCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader { param($path) $status } `
            -ProcessStarter { param($request) $script:starterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '另一个方案')

        $result = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.AlreadyRunning
        Assert-Equal -Expected $existing -Actual $result.RunDirectory
        Assert-Equal -Expected 0 -Actual $script:starterCalls
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable starterCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Stop writes a stop command and succeeds after observing stopped state' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:reads = 0
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader {
            param($path)
            $script:reads += 1
            [pscustomobject]@{ processId = 222; state = $(if ($script:reads -ge 2) { 'stopped' } else { 'stopping' }); heartbeatAt = '2026-07-13T10:00:00+08:00' }
        }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 222
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = Stop-AIFishBotRun -Controller $controller -TimeoutSeconds 2

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 'stop' -Actual (Read-AIFishBotControlCommand -RunDirectory $run).command
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable reads -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Stop timeout requests explicit force confirmation and never kills by itself' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $script:forceCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) [pscustomobject]@{ processId = 333; state = 'stopping'; heartbeatAt = $script:now.ToString('o') } } `
            -Clock { $script:now } -Sleeper { param($milliseconds) $script:now = $script:now.AddMilliseconds($milliseconds) } `
            -ForceStopper { param($id) $script:forceCalls += 1 }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 333
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = Stop-AIFishBotRun -Controller $controller -TimeoutSeconds 0.2

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.RequiresForceConfirmation
        Assert-Equal -Expected 333 -Actual $result.Pid
        Assert-Equal -Expected 0 -Actual $script:forceCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable now, forceCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Tray Stop force-stops only after injected timeout confirmation' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:trayNow = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $script:trayForcedPid = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) [pscustomobject]@{
                    processId = 334; state = 'stopping'; heartbeatAt = $script:trayNow.ToString('o')
                    startedAt = '2026-07-13T09:59:00+08:00'
                    processStartedAt = '2026-07-13T09:59:00+08:00'
                } } `
            -Clock { $script:trayNow } -Sleeper { param($milliseconds) $script:trayNow = $script:trayNow.AddSeconds(11) } `
            -ConfirmProvider { param($purpose) $purpose -eq 'ForceStop' } `
            -ForceStopper { param($id) $script:trayForcedPid = $id }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 334
        $controller.StopTimeoutSeconds = 0
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.TrayMenu.ByName.StopItem.InvokeEvent('Click')
        Assert-Equal -Expected 0 -Actual $script:trayForcedPid
        $view.Timers.Status.InvokeEvent('Tick')

        Assert-Equal -Expected 334 -Actual $script:trayForcedPid
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable trayNow, trayForcedPid -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Default confirmation refuses a force stop when production wiring omits a dialog' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:defaultNow = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $script:defaultForceCalls = 0
        $controller = New-AIFishBotController -View $view -ProfilesDirectory (Join-Path $root 'profiles') `
            -RuntimeRoot (Join-Path $root 'runtime') -EngineScriptPath 'C:\fake\engine.ps1' `
            -DependencyChecker { [pscustomobject]@{ Status = 'Available'; IsAvailable = $true } } `
            -ProcessStarter { param($request) throw 'not used' } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id } } `
            -StatusReader { param($path) [pscustomobject]@{
                    processId = 335; state = 'stopping'; heartbeatAt = $script:defaultNow.ToString('o')
                    startedAt = '2026-07-13T09:59:00+08:00'
                } } `
            -Clock { $script:defaultNow } -Sleeper { param($milliseconds) $script:defaultNow = $script:defaultNow.AddSeconds(11) } `
            -ForceStopper { param($id) $script:defaultForceCalls += 1 } -AvailablePortsProvider { @() }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-AIFishBotDefaultConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 335
        $controller.StopTimeoutSeconds = 0
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.TrayMenu.ByName.StopItem.InvokeEvent('Click')
        $view.Timers.Status.InvokeEvent('Tick')

        Assert-Equal -Expected 0 -Actual $script:defaultForceCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable defaultNow, defaultForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Force stop only runs after an explicit method call' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:forcedPid = 0
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) [pscustomobject]@{
                    processId = 444; state = 'stopping'; heartbeatAt = $now.ToString('o')
                    startedAt = $now.AddMinutes(-1).ToString('o')
                    processStartedAt = $now.AddMinutes(-1).ToString('o')
                } } `
            -ForceStopper { param($id) $script:forcedPid = $id }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 444
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = $controller.ForceStop()

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 444 -Actual $script:forcedPid
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable forcedPid -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Resume validates process and fresh heartbeat then restores the running view' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $config = New-ControllerTestConfig -Name '恢复方案'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 7; audioSensitivity = 9 })
        $status = [pscustomobject]@{ processId = 555; state = 'ready'; hookCount = 2; retryCount = 1; profileName = '恢复方案'; startedAt = $now.AddMinutes(-1).ToString('o'); processStartedAt = $now.AddMinutes(-1).ToString('o'); remainingSeconds = 60; lastError = $null; heartbeatAt = $now.ToString('o'); configVersion = 7 }
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader { param($path) $status }

        $result = Resume-AIFishBotRun -Controller $controller -RunDirectory $run

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected 555 -Actual $controller.CurrentProcessId
        Assert-Equal -Expected 9 -Actual $view.Controls.AudioSensitivity.Value
        Assert-Equal -Expected $false -Actual $view.Controls.Retail.Enabled
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Resume keeps an identity-matched run with an expired heartbeat and blocks a duplicate start' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 556; state = 'ready'; heartbeatAt = $now.AddSeconds(-10).ToString('o')
            startedAt = $processStart.ToString('o'); processStartedAt = $processStart.ToString('o')
            configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 556; processStartedAt = $processStart.ToString('o')
            }) | Out-Null

        $resume = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $resume.Success
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-True -Condition (Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf)
        Assert-Equal -Expected '● 后台暂时未响应' -Actual $view.Controls.StatusBadge.Text
        Assert-Equal -Expected '停止钓鱼' -Actual $view.Controls.StartStopButton.Text

        $script:expiredStarterCalls = 0
        $secondView = New-ControllerFakeView
        $secondController = New-ControllerForTest -View $secondView -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ProcessStarter { param($request) $script:expiredStarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $secondController -Config (New-ControllerTestConfig)

        $start = Start-AIFishBotRun -Controller $secondController

        Assert-Equal -Expected $false -Actual $start.Success
        Assert-Equal -Expected $true -Actual $start.AlreadyRunning
        Assert-Equal -Expected 0 -Actual $script:expiredStarterCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable expiredStarterCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Real hidden view resumes an exact legacy status without audioPeak and blocks a duplicate start' {
    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) `
                -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        $now = [datetimeoffset]'2026-07-13T10:01:00+08:00'
        $processStart = [datetimeoffset]'2026-07-13T10:00:00.1234567+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $legacyStatus = [pscustomobject][ordered]@{
            processId = 1566; state = 'ready'; hookCount = 2; retryCount = 1
            profileName = '中文 方案'; startedAt = $processStart.ToString('o')
            processStartedAt = $processStart.ToString('o'); remainingSeconds = 60
            lastError = $null; heartbeatAt = $now.ToString('o'); configVersion = 1
        }
        Write-AIFishBotAtomicJson -Path (Join-Path $run 'status.json') `
            -InputObject $legacyStatus | Out-Null
        $state = [pscustomobject]@{ StarterCalls = 0 }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) Read-AIFishBotStatus -RunDirectory $path } `
            -Clock { $now } `
            -ProcessLookup {
                param($id)
                if ($id -eq 1566) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter { param($request) $state.StarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1566
                processStartedAt = $processStart.ToString('o')
            }) | Out-Null

        $resume = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $resume.Success
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected $null -Actual $controller.UnverifiedBackground
        Assert-Equal -Expected ([double]0) -Actual $view.Controls.AudioPeakBar.Value
        Assert-True -Condition (Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf)

        $secondController = New-ControllerForTest -View (New-ControllerFakeView) -Root $root `
            -StatusReader { param($path) Read-AIFishBotStatus -RunDirectory $path } `
            -Clock { $now } `
            -ProcessLookup {
                param($id)
                if ($id -eq 1566) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter { param($request) $state.StarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $secondController -Config (New-ControllerTestConfig) | Out-Null

        $start = Start-AIFishBotRun -Controller $secondController

        Assert-Equal -Expected $false -Actual $start.Success
        Assert-Equal -Expected $true -Actual $start.AlreadyRunning
        Assert-Equal -Expected 0 -Actual $state.StarterCalls
        Assert-True -Condition (Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf)
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'Force stop accepts an expired heartbeat only after the process start time matches' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 557; state = 'stopping'; heartbeatAt = $now.AddSeconds(-10).ToString('o')
            startedAt = $processStart.ToString('o'); processStartedAt = $processStart.ToString('o')
            configVersion = 1
        }
        $script:expiredForceCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:expiredForceCalls += 1 }
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 557
        $controller.CurrentProcessStartedAt = $processStart.ToString('o')
        Set-AIFishBotRunningState -Controller $controller -Running $true
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 557; processStartedAt = $processStart.ToString('o')
            }) | Out-Null

        $result = $controller.ForceStop()

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected 1 -Actual $script:expiredForceCalls
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable expiredForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Exact process identity survives a wall-clock rollback and blocks duplicate start' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $processStart = [datetimeoffset]'2026-07-13T10:00:00.1234567+08:00'
        $rolledBackNow = [datetimeoffset]'2026-07-13T09:10:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 560; state = 'ready'; startedAt = $processStart.ToString('o')
            processStartedAt = $processStart.ToString('o')
            heartbeatAt = '2026-07-13T09:00:00.0000000+08:00'; configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -Clock { $rolledBackNow } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }

        $resume = Resume-AIFishBotRun -Controller $controller -RunDirectory $run

        Assert-Equal -Expected $true -Actual $resume.Success
        Assert-True -Condition (Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf)

        $script:rollbackStarterCalls = 0
        $secondView = New-ControllerFakeView
        $secondController = New-ControllerForTest -View $secondView -Root $root `
            -StatusReader { param($path) $status } `
            -Clock { $rolledBackNow } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ProcessStarter { param($request) $script:rollbackStarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $secondController -Config (New-ControllerTestConfig)

        $start = Start-AIFishBotRun -Controller $secondController

        Assert-Equal -Expected $false -Actual $start.Success
        Assert-Equal -Expected $true -Actual $start.AlreadyRunning
        Assert-Equal -Expected 0 -Actual $script:rollbackStarterCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable rollbackStarterCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Exact process identity rejects PID reuse after a wall-clock rollback' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $oldProcessStart = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $reusedProcessStart = $oldProcessStart.AddSeconds(-10)
        $now = [datetimeoffset]'2026-07-13T10:01:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 561; state = 'ready'; startedAt = $oldProcessStart.ToString('o')
            processStartedAt = $oldProcessStart.ToString('o')
            heartbeatAt = $oldProcessStart.AddSeconds(-5).ToString('o'); configVersion = 1
        }
        $script:rollbackReuseForceCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -Clock { $now } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $reusedProcessStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:rollbackReuseForceCalls += 1 }

        $resume = Resume-AIFishBotRun -Controller $controller -RunDirectory $run
        $markerWasUpgraded = Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 561
        $controller.CurrentProcessStartedAt = $reusedProcessStart.ToString('o')
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $force = $controller.ForceStop()

        Assert-Equal -Expected $false -Actual $resume.Success
        Assert-Equal -Expected $false -Actual $markerWasUpgraded
        Assert-Equal -Expected $false -Actual $force.Success
        Assert-Equal -Expected 0 -Actual $script:rollbackReuseForceCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable rollbackReuseForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Real hidden view blocks start and warns when marker start identity is damaged' {
    Assert-UnverifiedMarkerBlocksRealViewStart -MarkerFactory {
        param($run, $processStart)
        [pscustomobject]@{
            runDirectory = $run; processId = 1562; processStartedAt = '损坏的启动时间'
        }
    }
}

Test-Case 'Real hidden view blocks start and warns when marker PID conflicts with status' {
    Assert-UnverifiedMarkerBlocksRealViewStart -MarkerFactory {
        param($run, $processStart)
        [pscustomobject]@{
            runDirectory = $run; processId = 9999; processStartedAt = $processStart.ToString('o')
        }
    }
}

Test-Case 'Real hidden view blocks start and warns when marker start conflicts with status' {
    Assert-UnverifiedMarkerBlocksRealViewStart -MarkerFactory {
        param($run, $processStart)
        [pscustomobject]@{
            runDirectory = $run; processId = 1562
            processStartedAt = $processStart.AddSeconds(1).ToString('o')
        }
    }
}

Test-Case 'Legacy status without exact identity blocks recovery force stop and duplicate start' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 562; state = 'ready'; startedAt = $processStart.ToString('o')
            heartbeatAt = $processStart.AddSeconds(5).ToString('o'); configVersion = 1
        }
        Write-AIFishBotAtomicJson -Path (Join-Path $run 'status.json') -InputObject $status | Out-Null
        $script:legacyUnknownForceCalls = 0
        $script:legacyUnknownStarterCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) Read-AIFishBotStatus -RunDirectory $path } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:legacyUnknownForceCalls += 1 } `
            -ProcessStarter { param($request) $script:legacyUnknownStarterCalls += 1 }

        $resume = Resume-AIFishBotRun -Controller $controller -RunDirectory $run
        $markerWasUpgraded = Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf
        Remove-Item -LiteralPath $controller.ActiveMarkerPath -Force -ErrorAction SilentlyContinue
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 562
        $controller.CurrentProcessStartedAt = $processStart.ToString('o')
        Set-AIFishBotRunningState -Controller $controller -Running $true
        $force = $controller.ForceStop()
        $secondView = New-ControllerFakeView
        $secondController = New-ControllerForTest -View $secondView -Root $root `
            -StatusReader { param($path) Read-AIFishBotStatus -RunDirectory $path } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ProcessStarter { param($request) $script:legacyUnknownStarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $secondController -Config (New-ControllerTestConfig)

        $start = Start-AIFishBotRun -Controller $secondController

        Assert-Equal -Expected $false -Actual $resume.Success
        Assert-Equal -Expected $true -Actual $resume.IdentityUnverified
        Assert-Equal -Expected $false -Actual $markerWasUpgraded
        Assert-Equal -Expected $false -Actual $force.Success
        Assert-Equal -Expected 0 -Actual $script:legacyUnknownForceCalls
        Assert-Equal -Expected $false -Actual $start.Success
        Assert-Equal -Expected $true -Actual $start.AlreadyRunning
        Assert-Equal -Expected $true -Actual $start.IdentityUnverified
        Assert-Equal -Expected 0 -Actual $script:legacyUnknownStarterCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable legacyUnknownForceCalls, legacyUnknownStarterCalls -Scope Script `
            -ErrorAction SilentlyContinue
    }
}

Test-Case 'Real hidden view keeps a legacy background warning through Start and Exit bindings' {
    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) `
                -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        $processStart = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) `
            -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1563; state = 'ready'; startedAt = $processStart.ToString('o')
            heartbeatAt = $processStart.AddSeconds(5).ToString('o'); configVersion = 1
        }
        Write-AIFishBotAtomicJson -Path (Join-Path $run 'status.json') -InputObject $status | Out-Null
        $state = [pscustomobject]@{
            StarterCalls = 0; ForceCalls = 0; ExitConfirmCalls = 0
            ExitRunning = $null; ExitUnverified = $null; ExitChoice = 'Cancel'
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) Read-AIFishBotStatus -RunDirectory $path } `
            -ProcessLookup {
                param($id)
                if ($id -eq 1563) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter { param($request) $state.StarterCalls += 1 } `
            -ForceStopper { param($id) $state.ForceCalls += 1 } `
            -ConfirmExitProvider {
                param($running, $unverified)
                $state.ExitConfirmCalls += 1
                $state.ExitRunning = $running
                $state.ExitUnverified = $unverified
                $state.ExitChoice
            }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null

        Resume-AIFishBotRun -Controller $controller | Out-Null

        Assert-True -Condition ($null -ne $controller.UnverifiedBackground)
        Assert-Equal -Expected 1563 -Actual $controller.UnverifiedBackground.Pid
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($run)) `
            -Actual $controller.UnverifiedBackground.RunDirectory
        Assert-True -Condition ($controller.UnverifiedBackground.Reason -like '*需要手动处理*')
        Assert-Equal -Expected '发现无法验证的后台，可能仍在运行，需要手动处理。' `
            -Actual $view.Controls.SaveStateLabel.Text
        Assert-True -Condition ($view.Controls.StatusBadge.Text -like '*后台身份待处理*')

        Invoke-ControllerRealButtonClick $view.Controls.StartStopButton

        Assert-Equal -Expected 0 -Actual $state.StarterCalls
        Assert-Equal -Expected '发现无法验证的后台，可能仍在运行，需要手动处理。' `
            -Actual $view.Controls.SaveStateLabel.Text
        Assert-True -Condition ($view.Controls.StatusBadge.Text -like '*后台身份待处理*')

        $exitItem = @($view.TrayMenu.Items | Where-Object { $_.Name -eq 'ExitItem' })[0]
        $exitItem.PerformClick()

        Assert-Equal -Expected 1 -Actual $state.ExitConfirmCalls
        Assert-Equal -Expected $false -Actual $state.ExitRunning
        Assert-Equal -Expected $true -Actual $state.ExitUnverified
        Assert-Equal -Expected 0 -Actual $state.ForceCalls
        Assert-Equal -Expected $false -Actual $view.Form.IsDisposed
        Assert-Equal -Expected '发现无法验证的后台，可能仍在运行，需要手动处理。' `
            -Actual $view.Controls.SaveStateLabel.Text

        $state.ExitChoice = 'Continue'
        $exitItem.PerformClick()

        Assert-Equal -Expected 2 -Actual $state.ExitConfirmCalls
        Assert-Equal -Expected 0 -Actual $state.ForceCalls
        Assert-Equal -Expected $true -Actual $view.Form.IsDisposed
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'An unverified block clears only after its process disappears and Start can continue' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $processStart = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) `
            -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1564; state = 'ready'; startedAt = $processStart.ToString('o')
            processStartedAt = $processStart.ToString('o')
            heartbeatAt = $processStart.AddSeconds(5).ToString('o'); configVersion = 1
        }
        $state = [pscustomobject]@{ ProcessExists = $true; StarterCalls = 0 }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup {
                param($id)
                if ($state.ProcessExists -and $id -eq 1564) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter {
                param($request)
                $state.StarterCalls += 1
                [pscustomobject]@{ Id = 2564; StartTime = $processStart.AddMinutes(1).UtcDateTime }
            }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1564; processStartedAt = '损坏的启动时间'
            }) | Out-Null

        Resume-AIFishBotRun -Controller $controller | Out-Null
        Assert-True -Condition ($null -ne $controller.UnverifiedBackground)
        $state.ProcessExists = $false

        $view.Controls.StartStopButton.InvokeEvent('Click')

        Assert-Equal -Expected 1 -Actual $state.StarterCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected $null -Actual $controller.UnverifiedBackground
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'An unverified block clears after status becomes terminal and Start can continue' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $processStart = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) `
            -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $state = [pscustomobject]@{ StatusState = 'ready'; StarterCalls = 0 }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader {
                param($path)
                [pscustomobject]@{
                    processId = 1565; state = $state.StatusState
                    startedAt = $processStart.ToString('o')
                    processStartedAt = $processStart.ToString('o')
                    heartbeatAt = $processStart.AddSeconds(5).ToString('o'); configVersion = 1
                }
            } `
            -ProcessLookup {
                param($id)
                if ($id -eq 1565) {
                    [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime }
                }
            } `
            -ProcessStarter {
                param($request)
                $state.StarterCalls += 1
                [pscustomobject]@{ Id = 2565; StartTime = $processStart.AddMinutes(1).UtcDateTime }
            }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1565; processStartedAt = '损坏的启动时间'
            }) | Out-Null

        Resume-AIFishBotRun -Controller $controller | Out-Null
        Assert-True -Condition ($null -ne $controller.UnverifiedBackground)
        $state.StatusState = 'stopped'

        $view.Controls.StartStopButton.InvokeEvent('Click')

        Assert-Equal -Expected 1 -Actual $state.StarterCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected $null -Actual $controller.UnverifiedBackground
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Expired legacy status rejects a PID reused after its last heartbeat' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $oldStart = $now.AddMinutes(-1)
        $lastHeartbeat = $oldStart.AddSeconds(5)
        $reusedStart = $oldStart.AddSeconds(10)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 558; state = 'ready'; heartbeatAt = $lastHeartbeat.ToString('o')
            startedAt = $oldStart.ToString('o'); configVersion = 1
        }
        $script:legacyReuseForceCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $reusedStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:legacyReuseForceCalls += 1 }

        $resume = Resume-AIFishBotRun -Controller $controller -RunDirectory $run
        $markerWasUpgraded = Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf
        Remove-Item -LiteralPath $controller.ActiveMarkerPath -Force -ErrorAction SilentlyContinue
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 558
        $controller.CurrentProcessStartedAt = $reusedStart.ToString('o')
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $force = $controller.ForceStop()

        Assert-Equal -Expected $false -Actual $resume.Success
        Assert-Equal -Expected $false -Actual $markerWasUpgraded
        Assert-Equal -Expected $false -Actual $force.Success
        Assert-Equal -Expected 0 -Actual $script:legacyReuseForceCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable legacyReuseForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Expired exact status keeps the original process recoverable and blocks duplicate start' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $statusStart = $processStart.AddSeconds(2)
        $lastHeartbeat = $processStart.AddSeconds(5)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 559; state = 'ready'; heartbeatAt = $lastHeartbeat.ToString('o')
            startedAt = $statusStart.ToString('o'); processStartedAt = $processStart.ToString('o')
            configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }

        $resume = Resume-AIFishBotRun -Controller $controller -RunDirectory $run

        Assert-Equal -Expected $true -Actual $resume.Success
        Assert-True -Condition (Test-Path -LiteralPath $controller.ActiveMarkerPath -PathType Leaf)

        $script:legacyStarterCalls = 0
        $secondView = New-ControllerFakeView
        $secondController = New-ControllerForTest -View $secondView -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ProcessStarter { param($request) $script:legacyStarterCalls += 1 }
        Set-AIFishBotViewFromConfig -Controller $secondController -Config (New-ControllerTestConfig)

        $start = Start-AIFishBotRun -Controller $secondController

        Assert-Equal -Expected $false -Actual $start.Success
        Assert-Equal -Expected $true -Actual $start.AlreadyRunning
        Assert-Equal -Expected 0 -Actual $script:legacyStarterCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable legacyStarterCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Resume clears stale controller state without terminating a process' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:lookupCalls = 0
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{ processId = 666; state = 'ready'; heartbeatAt = $now.AddMinutes(-5).ToString('o'); configVersion = 1 }
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) $script:lookupCalls += 1; [pscustomobject]@{ Id = $id } }
        $controller.CurrentRunDirectory = 'stale'
        $controller.CurrentProcessId = 1
        Set-AIFishBotRunningState -Controller $controller -Running $false

        $result = Resume-AIFishBotRun -Controller $controller -RunDirectory $run

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $false -Actual $controller.IsRunning
        Assert-Equal -Expected $null -Actual $controller.CurrentRunDirectory
        Assert-True -Condition ($script:lookupCalls -ge 1)
    }
    finally { Remove-ControllerTestDirectory $root; Remove-Variable lookupCalls -Scope Script -ErrorAction SilentlyContinue }
}

Test-Case 'Resume never clears an already tracked active run' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $controller.CurrentRunDirectory = 'C:\有效运行'
        $controller.CurrentProcessId = 777
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = Resume-AIFishBotRun -Controller $controller -RunDirectory (Join-Path $root '不存在')

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.AlreadyRunning
        Assert-Equal -Expected 'C:\有效运行' -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected 777 -Actual $controller.CurrentProcessId
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Resume falls back from a stale marker to another valid run' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $runtime = Join-Path $root 'runtime'
        $config = New-ControllerTestConfig -Name '回退恢复方案'
        $script:staleRun = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $script:liveRun = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 2; audioSensitivity = 8 })
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader {
            param($path)
            if ([System.IO.Path]::GetFullPath($path) -eq [System.IO.Path]::GetFullPath($script:liveRun)) {
                return [pscustomobject]@{
                    processId = 991; state = 'ready'; heartbeatAt = '2026-07-13T10:00:00+08:00'
                    startedAt = '2026-07-13T09:59:00+08:00'
                    processStartedAt = '2026-07-13T09:59:00+08:00'; configVersion = 2
                }
            }
            return [pscustomobject]@{
                processId = 990; state = 'ready'; heartbeatAt = '2026-07-13T09:00:00+08:00'
                startedAt = '2026-07-13T08:59:00+08:00'
                processStartedAt = '2026-07-13T08:59:00+08:00'; configVersion = 1
            }
        }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{ runDirectory = $script:staleRun; processId = 990 }) | Out-Null

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($script:liveRun)) -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected 991 -Actual $controller.CurrentProcessId
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable staleRun, liveRun -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Resume scans a valid run after a readable marker has a missing empty or invalid directory' {
    $root = New-TestDirectory
    try {
        $runtime = Join-Path $root 'runtime'
        $config = New-ControllerTestConfig -Name '扫描恢复方案'
        $script:scanCandidate = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 9 })
        $status = [pscustomobject]@{
            processId = 993
            state = 'ready'
            heartbeatAt = '2026-07-13T10:00:00+08:00'
            startedAt = '2026-07-13T09:59:00+08:00'
            processStartedAt = '2026-07-13T09:59:00+08:00'
            configVersion = 9
        }
        $markers = @(
            [pscustomobject]@{ processId = 1 },
            [pscustomobject]@{ runDirectory = ''; processId = 2 },
            [pscustomobject]@{ runDirectory = ([string][char]0); processId = 3 }
        )
        foreach ($marker in $markers) {
            $view = New-ControllerFakeView
            $script:scanHits = 0
            $controller = New-ControllerForTest -View $view -Root $root -StatusReader {
                param($path)
                if ([string]$path -eq [string]$script:scanCandidate) {
                    $script:scanHits += 1
                    return $status
                }
                throw '坏标记路径不可读取。'
            }
            Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject $marker | Out-Null

            $result = Resume-AIFishBotRun -Controller $controller

            Assert-True -Condition ($script:scanHits -ge 1)
            Assert-Equal -Expected $true -Actual $result.Success
            Assert-Equal -Expected ([System.IO.Path]::GetFullPath($script:scanCandidate)) -Actual $controller.CurrentRunDirectory
            Assert-Equal -Expected 993 -Actual $controller.CurrentProcessId
        }
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable scanCandidate, scanHits -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Resume keeps a validated process tracked when the active marker cannot be written' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $config = New-ControllerTestConfig -Name '恢复标记失败'
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 6 })
        $status = [pscustomobject]@{
            processId = 992; state = 'ready'; heartbeatAt = $now.ToString('o')
            startedAt = $now.AddMinutes(-1).ToString('o')
            processStartedAt = $now.AddMinutes(-1).ToString('o'); configVersion = 6
        }
        $controller = New-ControllerForTest -View $view -Root $root -StatusReader { param($path) $status }
        New-Item -ItemType Directory -Path $controller.ActiveMarkerPath -Force | Out-Null

        $result = Resume-AIFishBotRun -Controller $controller -RunDirectory $run

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected $true -Actual $result.MarkerWriteFailed
        Assert-Equal -Expected $true -Actual $controller.IsRunning
        Assert-Equal -Expected 992 -Actual $controller.CurrentProcessId
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($run)) -Actual $controller.CurrentRunDirectory
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Status updates Chinese state statistics remaining time and peak value' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $status = [pscustomobject]@{ state = 'waiting-for-bite'; hookCount = 12; retryCount = 3; remainingSeconds = 65; audioPeak = 88 }

        Update-AIFishBotViewStatus -Controller $controller -Status $status | Out-Null

        Assert-Equal -Expected '● 等待咬钩' -Actual $view.Controls.StatusBadge.Text
        Assert-Equal -Expected '已上钩：12' -Actual $view.Controls.HookCount.Text
        Assert-Equal -Expected '剩余：01:05' -Actual $view.Controls.RemainingTime.Text
        Assert-Equal -Expected 88 -Actual $view.Controls.AudioPeakBar.Value
        Assert-Equal -Expected '状态：等待咬钩' -Actual $view.TrayMenu.ByName.StatusItem.Text
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Terminal status unlocks the view stops timers and clears tracked runtime state' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $controller.CurrentRunDirectory = Join-Path $root 'runtime\run'
        $controller.CurrentProcessId = 888
        New-Item -ItemType Directory -Path (Split-Path $controller.ActiveMarkerPath -Parent) -Force | Out-Null
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{ runDirectory = $controller.CurrentRunDirectory; processId = 888 }) | Out-Null
        Set-AIFishBotRunningState -Controller $controller -Running $true

        Update-AIFishBotViewStatus -Controller $controller -Status ([pscustomobject]@{ state = 'stopped'; hookCount = 4; remainingSeconds = 0 }) | Out-Null

        Assert-Equal -Expected $false -Actual $controller.IsRunning
        Assert-Equal -Expected $null -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected 0 -Actual $controller.CurrentProcessId
        Assert-Equal -Expected $false -Actual $view.Timers.Status.Enabled
        Assert-Equal -Expected $false -Actual $view.Timers.Log.Enabled
        Assert-True -Condition (-not (Test-Path -LiteralPath $controller.ActiveMarkerPath))
        Assert-Equal -Expected $true -Actual $view.Controls.CastKey.Enabled
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Log update appends only new text caps lines and masks Discord webhooks' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $secret = 'https://discord.com/api/webhooks/123456/secret-token'
        Update-AIFishBotViewLog -Controller $controller -Content "one $secret`ntwo" -MaximumLines 3 | Out-Null
        Assert-True -Condition ($view.Controls.LogBox.Text -notlike '*secret-token*')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*webhooks/***')
        Update-AIFishBotViewLog -Controller $controller -Content "one $secret`ntwo`nthree`nfour" -MaximumLines 3 | Out-Null

        Assert-True -Condition ($view.Controls.LogBox.Text -notlike '*secret-token*')
        Assert-Equal -Expected @('two', 'three', 'four') -Actual @($view.Controls.LogBox.Text -split "`r?`n")
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Log line limits do not count a trailing newline as a visible line' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root

        Update-AIFishBotViewLog -Controller $controller -Content "one`ntwo`n" -MaximumLines 2 | Out-Null

        Assert-Equal -Expected @('one', 'two') -Actual @($view.Controls.LogBox.Text -split "`r?`n")
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Webhook masking remains safe when one URL is split across log reads' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $first = 'line https://discord.com/api/webhooks/123456/'
        Update-AIFishBotViewLog -Controller $controller -Content $first | Out-Null
        Update-AIFishBotViewLog -Controller $controller -Content ($first + 'secret-token') | Out-Null

        Assert-True -Condition ($view.Controls.LogBox.Text -notlike '*123456*')
        Assert-True -Condition ($view.Controls.LogBox.Text -notlike '*secret-token*')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*webhooks/***')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Oversized partial log lines are dropped before they can separate a webhook secret from its prefix' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $controller.RawLogHistory = 'https://discord.com/api/webhooks/123456/' + ('x' * 1048576)

        Update-AIFishBotViewLog -Controller $controller -Content 'secret-token' | Out-Null

        Assert-True -Condition ($view.Controls.LogBox.Text -notlike '*secret-token*')
        Assert-True -Condition ($view.Controls.LogBox.Text -like '*日志行过长*')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Runtime log polling tracks a file offset and appends without rereading old lines' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $firstPath = Write-AIFishBotLog -RunDirectory $run -Level INFO -Message 'first' -Now ([datetimeoffset]'2026-07-13T10:00:00+08:00')
        Update-AIFishBotViewLog -Controller $controller | Out-Null
        Write-AIFishBotLog -RunDirectory $run -Level INFO -Message 'second' -Now ([datetimeoffset]'2026-07-13T10:00:01+08:00') | Out-Null
        Update-AIFishBotViewLog -Controller $controller | Out-Null

        Assert-Equal -Expected ([System.IO.FileInfo]$firstPath).Length -Actual $controller.LastLogFileOffset
        Assert-Equal -Expected 1 -Actual @([regex]::Matches($view.Controls.LogBox.Text, 'first')).Count
        Assert-Equal -Expected 1 -Actual @([regex]::Matches($view.Controls.LogBox.Text, 'second')).Count
        Assert-Equal -Expected 0 -Actual $controller.LastLogSourceLength
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Tray open and background exit events are bound by the controller' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root -ConfirmExitProvider { param($running) 'Continue' }
        $view.Form.Visible = $false
        $view.TrayIcon.Visible = $true

        $view.TrayMenu.ByName.OpenItem.InvokeEvent('Click')
        Assert-Equal -Expected $true -Actual $view.Form.Visible
        Assert-Equal -Expected $false -Actual $view.TrayIcon.Visible

        Set-AIFishBotRunningState -Controller $controller -Running $true
        $view.TrayMenu.ByName.ExitItem.InvokeEvent('Click')
        Assert-Equal -Expected 1 -Actual $view.ExitCount
        Assert-Equal -Expected $true -Actual $controller.IsRunning

        Set-AIFishBotRunningState -Controller $controller -Running $false
        $view.TrayMenu.ByName.ExitItem.InvokeEvent('Click')
        Assert-Equal -Expected 2 -Actual $view.ExitCount
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Exit with Stop handles an injected force confirmation before disposing the view' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:exitNow = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $script:exitForcedPid = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) [pscustomobject]@{
                    processId = 445; state = 'stopping'; heartbeatAt = $script:exitNow.ToString('o')
                    startedAt = '2026-07-13T09:59:00+08:00'
                    processStartedAt = '2026-07-13T09:59:00+08:00'
                } } `
            -Clock { $script:exitNow } -Sleeper { param($milliseconds) $script:exitNow = $script:exitNow.AddSeconds(11) } `
            -ConfirmProvider { param($purpose) $purpose -eq 'ForceStop' } `
            -ConfirmExitProvider { param($running) 'Stop' } `
            -ForceStopper { param($id) $script:exitForcedPid = $id }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 445
        $controller.StopTimeoutSeconds = 0
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.TrayMenu.ByName.ExitItem.InvokeEvent('Click')
        Assert-Equal -Expected 0 -Actual $script:exitForcedPid
        Assert-Equal -Expected 0 -Actual $view.ExitCount
        $view.Timers.Status.InvokeEvent('Tick')

        Assert-Equal -Expected 445 -Actual $script:exitForcedPid
        Assert-Equal -Expected 1 -Actual $view.ExitCount
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable exitNow, exitForcedPid -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'A real hidden WinForms view binds the serial port and user change events' {
    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null

        $roundTrip = Get-AIFishBotConfigFromView -Controller $controller
        Assert-Equal -Expected 'COM7' -Actual $roundTrip.picoComPort
        Assert-Equal -Expected $false -Actual $controller.IsDirty

        $view.Controls.AutoLogout.Checked = -not $view.Controls.AutoLogout.Checked
        Assert-Equal -Expected $true -Actual $controller.IsDirty
        Set-AIFishBotRunningState -Controller $controller -Running $true
        Assert-Equal -Expected $false -Actual $view.Controls.CastKey.Enabled
        Assert-Equal -Expected $true -Actual $view.Controls.AudioSensitivity.Enabled
        Assert-Equal -Expected $true -Actual $view.Timers.Status.Enabled
        Assert-Equal -Expected $true -Actual $view.Timers.Log.Enabled
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'A real hidden WinForms view shows and clears Chinese validation errors' {
    $root = New-TestDirectory
    $view = $null
    try {
        Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'AI-FishBot.UI.psm1') -Force
        $view = New-AIFishBotMainView
        Assert-True -Condition ($view.ErrorProvider -is [System.Windows.Forms.ErrorProvider])
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig) | Out-Null

        $view.Controls.PreHookMin.Value = 2.0
        $view.Controls.PreHookMax.Value = 1.0
        $validation = Test-AIFishBotView -Controller $controller
        $startResult = Start-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $validation.IsValid
        Assert-Equal -Expected $false -Actual $startResult.Success
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($view.ErrorProvider.GetError($view.Controls.PreHookMin)))
        Assert-True -Condition ($view.Controls.SaveStateLabel.Text -like '配置错误：*')

        $view.Controls.PreHookMin.Value = 0.6
        $view.Controls.PreHookMax.Value = 0.9
        $validation = Test-AIFishBotView -Controller $controller

        Assert-Equal -Expected $true -Actual $validation.IsValid
        Assert-Equal -Expected '' -Actual $view.ErrorProvider.GetError($view.Controls.PreHookMin)
        Assert-Equal -Expected '未保存' -Actual $view.Controls.SaveStateLabel.Text
    }
    finally {
        if ($null -ne $view) { $view.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}

Test-Case 'Start marker records the launched process start time' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $startedAt = [datetimeoffset]'2026-07-13T01:59:59.125+00:00'
        $controller = New-ControllerForTest -View $view -Root $root -ProcessStarter {
            param($request)
            [pscustomobject]@{ Id = 1201; StartTime = $startedAt.UtcDateTime }
        }
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig -Name '进程身份方案')

        $result = Start-AIFishBotRun -Controller $controller
        $marker = Read-AIFishBotJson -Path $controller.ActiveMarkerPath

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-True -Condition ($null -ne $marker.PSObject.Properties['processStartedAt'])
        Assert-Equal -Expected $startedAt.ToString('o') -Actual ([datetimeoffset]$marker.processStartedAt).ToString('o')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Resume rejects a reused PID whose process start time differs from the marker' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $originalStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1202; state = 'ready'; heartbeatAt = $now.ToString('o')
            startedAt = $originalStart.AddSeconds(1).ToString('o')
            processStartedAt = $originalStart.ToString('o'); configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $originalStart.AddMinutes(5).UtcDateTime } }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1202; processStartedAt = $originalStart.ToString('o')
            }) | Out-Null

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Force stop rechecks process identity and refuses a PID reused after resume' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $originalStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1203; state = 'stopping'; heartbeatAt = $now.ToString('o')
            startedAt = $originalStart.AddSeconds(1).ToString('o')
            processStartedAt = $originalStart.ToString('o'); configVersion = 1
        }
        $script:identityLookups = 0
        $script:identityForceCalls = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup {
                param($id)
                $script:identityLookups += 1
                $start = if ($script:identityLookups -eq 1) { $originalStart } else { $originalStart.AddMinutes(5) }
                [pscustomobject]@{ Id = $id; StartTime = $start.UtcDateTime }
            } `
            -ForceStopper { param($id) $script:identityForceCalls += 1 }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1203; processStartedAt = $originalStart.ToString('o')
            }) | Out-Null
        Assert-Equal -Expected $true -Actual (Resume-AIFishBotRun -Controller $controller).Success

        $result = $controller.ForceStop()

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected 0 -Actual $script:identityForceCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable identityLookups, identityForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Rebuilding a controller on the same view removes the previous event binding' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $first = New-ControllerForTest -View $view -Root $root
        $second = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $second -Config (New-ControllerTestConfig)

        $view.Controls.AutoStop.Checked = -not $view.Controls.AutoStop.Checked
        $view.Controls.AutoStop.InvokeEvent('CheckedChanged')

        Assert-Equal -Expected $false -Actual $first.IsDirty
        Assert-Equal -Expected $true -Actual $second.IsDirty
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Disposed controller binding no longer receives view events' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        Set-AIFishBotViewFromConfig -Controller $controller -Config (New-ControllerTestConfig)

        $controller.Dispose()
        $view.Controls.AutoStop.Checked = -not $view.Controls.AutoStop.Checked
        $view.Controls.AutoStop.InvokeEvent('CheckedChanged')

        Assert-Equal -Expected $false -Actual $controller.IsDirty
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Two controllers sharing one data root start at most one background process' {
    $root = New-TestDirectory
    try {
        $firstView = New-ControllerFakeView
        $secondView = New-ControllerFakeView
        $startedAt = [datetimeoffset]'2026-07-13T01:59:59+00:00'
        $script:concurrentStarterCalls = 0
        $starter = {
            param($request)
            $script:concurrentStarterCalls += 1
            [pscustomobject]@{ Id = 1204; StartTime = $startedAt.UtcDateTime }
        }
        $lookup = { param($id) [pscustomobject]@{ Id = $id; StartTime = $startedAt.UtcDateTime } }
        $first = New-ControllerForTest -View $firstView -Root $root -ProcessStarter $starter -ProcessLookup $lookup
        $second = New-ControllerForTest -View $secondView -Root $root -ProcessStarter $starter -ProcessLookup $lookup
        Set-AIFishBotViewFromConfig -Controller $first -Config (New-ControllerTestConfig -Name '并发方案')
        Set-AIFishBotViewFromConfig -Controller $second -Config (New-ControllerTestConfig -Name '并发方案')

        $firstResult = Start-AIFishBotRun -Controller $first
        $secondResult = Start-AIFishBotRun -Controller $second

        Assert-Equal -Expected $true -Actual $firstResult.Success
        Assert-Equal -Expected $false -Actual $secondResult.Success
        Assert-Equal -Expected $true -Actual $secondResult.AlreadyRunning
        Assert-Equal -Expected 1 -Actual $script:concurrentStarterCalls
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable concurrentStarterCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Resume skips a newer incomplete candidate and restores the older complete run' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $runtime = Join-Path $root 'runtime'
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $older = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig (New-ControllerTestConfig -Name '完整方案') `
            -LiveConfig ([pscustomobject]@{ configVersion = 5; audioSensitivity = 8 })
        $newer = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig (New-ControllerTestConfig -Name '不完整方案') `
            -LiveConfig ([pscustomobject]@{ configVersion = 6 })
        Remove-Item -LiteralPath (Join-Path $newer 'start-config.json') -Force
        (Get-Item -LiteralPath $older).LastWriteTimeUtc = $now.AddMinutes(-2).UtcDateTime
        (Get-Item -LiteralPath $newer).LastWriteTimeUtc = $now.AddMinutes(-1).UtcDateTime
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader {
                param($path)
                $pidValue = if ([System.IO.Path]::GetFullPath($path) -eq [System.IO.Path]::GetFullPath($newer)) { 1206 } else { 1205 }
                [pscustomobject]@{
                    processId = $pidValue; state = 'ready'; heartbeatAt = $now.ToString('o')
                    startedAt = $processStart.AddSeconds(1).ToString('o')
                    processStartedAt = $processStart.ToString('o'); configVersion = 5
                }
            } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($older)) -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected 1205 -Actual $controller.CurrentProcessId
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Live config versions advance from the file across two stale controllers' {
    $root = New-TestDirectory
    try {
        $firstView = New-ControllerFakeView
        $secondView = New-ControllerFakeView
        $first = New-ControllerForTest -View $firstView -Root $root
        $second = New-ControllerForTest -View $secondView -Root $root
        $config = New-ControllerTestConfig -Name '双控制器版本方案'
        Set-AIFishBotViewFromConfig -Controller $first -Config $config
        Set-AIFishBotViewFromConfig -Controller $second -Config $config
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig $config -LiveConfig ([pscustomobject]@{ configVersion = 4 })
        foreach ($controller in @($first, $second)) {
            $controller.CurrentRunDirectory = $run
            $controller.ConfigVersion = 4
            Set-AIFishBotRunningState -Controller $controller -Running $true
        }

        Assert-Equal -Expected $true -Actual (Save-AIFishBotCurrentProfile -Controller $first).Success
        Assert-Equal -Expected 5 -Actual (Read-AIFishBotJson -Path (Join-Path $run 'live-config.json')).configVersion
        Assert-Equal -Expected $true -Actual (Save-AIFishBotCurrentProfile -Controller $second).Success

        Assert-Equal -Expected 6 -Actual (Read-AIFishBotJson -Path (Join-Path $run 'live-config.json')).configVersion
        Assert-Equal -Expected 6 -Actual $second.ConfigVersion
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Controller leaves shutdown and task-manager closes uncancelled' {
    $root = New-TestDirectory
    try {
        foreach ($reason in @('WindowsShutDown', 'TaskManagerClosing')) {
            $view = New-ControllerFakeView
            $controller = New-ControllerForTest -View $view -Root $root
            $view.TrayIcon.Visible = $false
            $eventArgs = [pscustomobject]@{ CloseReason = $reason; Cancel = $false }

            $view.Form.InvokeEvent('FormClosing', $eventArgs)

            Assert-Equal -Expected $false -Actual $eventArgs.Cancel
            Assert-Equal -Expected $true -Actual $view.Form.Visible
            Assert-Equal -Expected $false -Actual $view.TrayIcon.Visible
        }
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Log polling preserves a UTF8 character split across appends without replacement text' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        New-Item -ItemType Directory -Path (Join-Path $run 'logs') -Force | Out-Null
        $path = Join-Path $run 'logs\split.log'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('鱼')
        [System.IO.File]::WriteAllBytes($path, [byte[]]@($bytes[0]))

        Update-AIFishBotViewLog -Controller $controller | Out-Null
        Assert-Equal -Expected '' -Actual $view.Controls.LogBox.Text

        $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try { $stream.Write($bytes, 1, $bytes.Length - 1) }
        finally { $stream.Dispose() }
        Update-AIFishBotViewLog -Controller $controller | Out-Null

        Assert-Equal -Expected '鱼' -Actual $view.Controls.LogBox.Text
        Assert-True -Condition ($view.Controls.LogBox.Text -notlike "*$([char]0xFFFD)*")
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Log polling detects truncate and rapid regrow before the previous offset' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $controller = New-ControllerForTest -View $view -Root $root
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        New-Item -ItemType Directory -Path (Join-Path $run 'logs') -Force | Out-Null
        $path = Join-Path $run 'logs\truncate.log'
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        [System.IO.File]::WriteAllBytes($path, $strictUtf8.GetBytes("old-line`n"))
        Update-AIFishBotViewLog -Controller $controller | Out-Null

        [System.IO.File]::WriteAllBytes($path, $strictUtf8.GetBytes("new-content-that-regrew-past-old-offset`n"))
        Update-AIFishBotViewLog -Controller $controller | Out-Null

        Assert-True -Condition ($view.Controls.LogBox.Text -like '*new-content-that-regrew-past-old-offset*')
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'UI stop returns without sleeping and the status tick handles force timeout' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:uiStopNow = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $script:uiStopNow.AddMinutes(-1)
        $script:uiStopSleeps = 0
        $script:uiStopForceCalls = 0
        $status = [pscustomobject]@{
            processId = 1207; state = 'stopping'; heartbeatAt = $script:uiStopNow.ToString('o')
            startedAt = $processStart.AddSeconds(1).ToString('o')
            processStartedAt = $processStart.ToString('o'); configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -Clock { $script:uiStopNow } `
            -Sleeper { param($milliseconds) $script:uiStopSleeps += 1; $script:uiStopNow = $script:uiStopNow.AddSeconds(11) } `
            -ConfirmProvider { param($purpose) $purpose -eq 'ForceStop' } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:uiStopForceCalls += 1 }
        $controller | Add-Member -MemberType NoteProperty -Name StopTimeoutSeconds -Value 0 -Force
        $controller | Add-Member -MemberType NoteProperty -Name StopPending -Value $false -Force
        $controller | Add-Member -MemberType NoteProperty -Name CurrentProcessStartedAt -Value $processStart.ToString('o') -Force
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 1207
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1207; processStartedAt = $processStart.ToString('o')
            }) | Out-Null
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.Controls.StartStopButton.InvokeEvent('Click')

        Assert-Equal -Expected 0 -Actual $script:uiStopSleeps
        Assert-Equal -Expected 0 -Actual $script:uiStopForceCalls
        Assert-Equal -Expected $true -Actual $controller.StopPending
        Assert-Equal -Expected 'stop' -Actual (Read-AIFishBotControlCommand -RunDirectory $run).command

        $view.Timers.Status.InvokeEvent('Tick')

        Assert-Equal -Expected 1 -Actual $script:uiStopForceCalls
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable uiStopNow, uiStopSleeps, uiStopForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'UI stop timeout still reaches confirmation when status reading fails' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $script:failedStatusConfirmCalls = 0
        $script:failedStatusSleeps = 0
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) throw '模拟状态文件暂时不可读' } `
            -Sleeper { param($milliseconds) $script:failedStatusSleeps += 1 } `
            -ConfirmProvider {
                param($purpose)
                if ($purpose -eq 'ForceStop') { $script:failedStatusConfirmCalls += 1 }
                return $false
            }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 1208
        $controller.StopTimeoutSeconds = 0
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $view.Controls.StartStopButton.InvokeEvent('Click')
        $view.Timers.Status.InvokeEvent('Tick')

        Assert-Equal -Expected 1 -Actual $script:failedStatusConfirmCalls
        Assert-Equal -Expected 0 -Actual $script:failedStatusSleeps
        Assert-Equal -Expected $true -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable failedStatusConfirmCalls, failedStatusSleeps -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Force stop always compares the current process with the tracked start time when marker is missing' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $trackedStart = $now.AddMinutes(-1)
        $reusedStart = $trackedStart.AddSeconds(10)
        $script:trackedForceCalls = 0
        $status = [pscustomobject]@{
            processId = 1209; state = 'stopping'; heartbeatAt = $now.ToString('o')
            startedAt = $reusedStart.ToString('o'); configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $reusedStart.UtcDateTime } } `
            -ForceStopper { param($id) $script:trackedForceCalls += 1 }
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $controller.CurrentRunDirectory = $run
        $controller.CurrentProcessId = 1209
        $controller.CurrentProcessStartedAt = $trackedStart.ToString('o')
        Set-AIFishBotRunningState -Controller $controller -Running $true

        $result = $controller.ForceStop()

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected 0 -Actual $script:trackedForceCalls
        Assert-Equal -Expected $true -Actual $controller.IsRunning
    }
    finally {
        Remove-ControllerTestDirectory $root
        Remove-Variable trackedForceCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Test-Case 'Resume rejects a new-format marker whose process start time is invalid' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $run = New-AIFishBotRunDirectory -RuntimeRoot (Join-Path $root 'runtime') `
            -StartConfig (New-ControllerTestConfig) -LiveConfig ([pscustomobject]@{ configVersion = 1 })
        $status = [pscustomobject]@{
            processId = 1210; state = 'ready'; heartbeatAt = $now.ToString('o')
            startedAt = $processStart.ToString('o'); configVersion = 1
        }
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader { param($path) $status } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $run; processId = 1210; processStartedAt = '损坏的时间'
            }) | Out-Null

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $false -Actual $result.Success
        Assert-Equal -Expected $false -Actual $controller.IsRunning
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Resume skips a newer readable but invalid config and restores the older valid run' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $runtime = Join-Path $root 'runtime'
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $olderConfig = New-ControllerTestConfig -Name '旧有效方案'
        $newerConfig = New-ControllerTestConfig -Name '新无效方案'
        $newerConfig.audioSensitivity = 99
        $older = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig $olderConfig `
            -LiveConfig ([pscustomobject]@{ configVersion = 5 })
        $newer = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig $newerConfig `
            -LiveConfig ([pscustomobject]@{ configVersion = 6 })
        (Get-Item -LiteralPath $older).LastWriteTimeUtc = $now.AddMinutes(-2).UtcDateTime
        (Get-Item -LiteralPath $newer).LastWriteTimeUtc = $now.AddMinutes(-1).UtcDateTime
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader {
                param($path)
                $pidValue = if ([System.IO.Path]::GetFullPath($path) -eq [System.IO.Path]::GetFullPath($newer)) { 1212 } else { 1211 }
                [pscustomobject]@{
                    processId = $pidValue; state = 'ready'; heartbeatAt = $now.ToString('o')
                    startedAt = $processStart.ToString('o')
                    processStartedAt = $processStart.ToString('o'); configVersion = 5
                }
            } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($older)) -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected '旧有效方案' -Actual $controller.CurrentProfileName
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Resume orders valid candidates by newest directory even when marker points to an older run' {
    $root = New-TestDirectory
    try {
        $view = New-ControllerFakeView
        $runtime = Join-Path $root 'runtime'
        $now = [datetimeoffset]'2026-07-13T10:00:00+08:00'
        $processStart = $now.AddMinutes(-1)
        $older = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig (New-ControllerTestConfig -Name '旧标记方案') `
            -LiveConfig ([pscustomobject]@{ configVersion = 7 })
        $newer = New-AIFishBotRunDirectory -RuntimeRoot $runtime -StartConfig (New-ControllerTestConfig -Name '新目录方案') `
            -LiveConfig ([pscustomobject]@{ configVersion = 8 })
        (Get-Item -LiteralPath $older).LastWriteTimeUtc = $now.AddMinutes(-2).UtcDateTime
        (Get-Item -LiteralPath $newer).LastWriteTimeUtc = $now.AddMinutes(-1).UtcDateTime
        $controller = New-ControllerForTest -View $view -Root $root `
            -StatusReader {
                param($path)
                $pidValue = if ([System.IO.Path]::GetFullPath($path) -eq [System.IO.Path]::GetFullPath($newer)) { 1214 } else { 1213 }
                [pscustomobject]@{
                    processId = $pidValue; state = 'ready'; heartbeatAt = $now.ToString('o')
                    startedAt = $processStart.ToString('o')
                    processStartedAt = $processStart.ToString('o'); configVersion = 8
                }
            } `
            -ProcessLookup { param($id) [pscustomobject]@{ Id = $id; StartTime = $processStart.UtcDateTime } }
        Write-AIFishBotAtomicJson -Path $controller.ActiveMarkerPath -InputObject ([pscustomobject]@{
                runDirectory = $older; processId = 1213; processStartedAt = $processStart.ToString('o')
            }) | Out-Null

        $result = Resume-AIFishBotRun -Controller $controller

        Assert-Equal -Expected $true -Actual $result.Success
        Assert-Equal -Expected ([System.IO.Path]::GetFullPath($newer)) -Actual $controller.CurrentRunDirectory
        Assert-Equal -Expected '新目录方案' -Actual $controller.CurrentProfileName
    }
    finally { Remove-ControllerTestDirectory $root }
}

Test-Case 'Start mutex serializes separate PowerShell processes sharing one data root' {
    $root = New-TestDirectory
    $jobs = @()
    $ready = $null
    $release = $null
    $second = $null
    try {
        $id = [guid]::NewGuid().ToString('N')
        $readyName = "Local\AI-FishBot.ControllerTest.Ready.$id"
        $releaseName = "Local\AI-FishBot.ControllerTest.Release.$id"
        $secondName = "Local\AI-FishBot.ControllerTest.Second.$id"
        $ready = New-Object System.Threading.EventWaitHandle(
            $false, [System.Threading.EventResetMode]::ManualReset, $readyName)
        $release = New-Object System.Threading.EventWaitHandle(
            $false, [System.Threading.EventResetMode]::ManualReset, $releaseName)
        $second = New-Object System.Threading.EventWaitHandle(
            $false, [System.Threading.EventResetMode]::ManualReset, $secondName)

        $jobs += Start-Job -ArgumentList $controllerModulePath, $root, $readyName, $releaseName -ScriptBlock {
            param($modulePath, $dataRoot, $readyName, $releaseName)
            Import-Module $modulePath -Force
            $module = Get-Module AI-FishBot.Controller
            & $module {
                param($dataRoot, $readyName, $releaseName)
                $readyEvent = [System.Threading.EventWaitHandle]::OpenExisting($readyName)
                $releaseEvent = [System.Threading.EventWaitHandle]::OpenExisting($releaseName)
                try {
                    Invoke-AIFishBotControllerMutex -Scope 'Start' -Path $dataRoot -Operation {
                        [void]$readyEvent.Set()
                        [void]$releaseEvent.WaitOne(5000)
                    }
                }
                finally { $readyEvent.Dispose(); $releaseEvent.Dispose() }
            } $dataRoot $readyName $releaseName
        }
        Assert-True -Condition $ready.WaitOne(5000)

        $jobs += Start-Job -ArgumentList $controllerModulePath, $root, $secondName -ScriptBlock {
            param($modulePath, $dataRoot, $secondName)
            Import-Module $modulePath -Force
            $module = Get-Module AI-FishBot.Controller
            & $module {
                param($dataRoot, $secondName)
                $secondEvent = [System.Threading.EventWaitHandle]::OpenExisting($secondName)
                try {
                    Invoke-AIFishBotControllerMutex -Scope 'Start' -Path $dataRoot -Operation {
                        [void]$secondEvent.Set()
                    }
                }
                finally { $secondEvent.Dispose() }
            } $dataRoot $secondName
        }

        Assert-Equal -Expected $false -Actual $second.WaitOne(300)
        [void]$release.Set()
        Assert-True -Condition $second.WaitOne(5000)
        foreach ($job in $jobs) {
            Wait-Job -Job $job -Timeout 10 | Out-Null
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
            Assert-Equal -Expected 'Completed' -Actual ([string]$job.State)
        }
    }
    finally {
        if ($null -ne $release) { [void]$release.Set() }
        foreach ($job in $jobs) {
            if ($job.State -eq 'Running') { Stop-Job -Job $job }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $ready) { $ready.Dispose() }
        if ($null -ne $release) { $release.Dispose() }
        if ($null -ne $second) { $second.Dispose() }
        Remove-ControllerTestDirectory $root
    }
}
