$script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
$script:UIModulePath = Join-Path -Path $script:RepositoryRoot -ChildPath 'AI-FishBot.UI.psm1'
$script:View = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Assert-ColorHex {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Color]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    $actualHex = '#{0:X2}{1:X2}{2:X2}' -f $Actual.R, $Actual.G, $Actual.B
    Assert-Equal -Expected $Expected.ToUpperInvariant() -Actual $actualHex
}

function Invoke-TestButtonClick {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Button]$Button
    )

    $onClick = [System.Windows.Forms.Button].GetMethod(
        'OnClick',
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    [void]$onClick.Invoke($Button, @([System.EventArgs]::Empty))
}

Test-Case 'UI module imports without creating a window or starting external work' {
    Assert-True -Condition (Test-Path -LiteralPath $script:UIModulePath -PathType Leaf)
    $openFormsBefore = @([System.Windows.Forms.Application]::OpenForms).Count
    Import-Module -Name $script:UIModulePath -Force -ErrorAction Stop

    Assert-Equal -Expected $openFormsBefore -Actual @([System.Windows.Forms.Application]::OpenForms).Count
    Assert-Equal -Expected @('New-AIFishBotMainView') -Actual @(
        (Get-Command -Module 'AI-FishBot.UI' -CommandType Function).Name | Sort-Object
    )

    $moduleText = [System.IO.File]::ReadAllText($script:UIModulePath)
    Assert-True -Condition (-not [regex]::IsMatch(
            $moduleText,
            '(?im)^\s*(Start-Process|Get-CimInstance|Get-WmiObject)\b|System\.IO\.Ports|SerialPort'
        ))
}

Test-Case 'main view can be created in STA without showing the form' {
    Assert-Equal -Expected 'STA' -Actual ([Threading.Thread]::CurrentThread.ApartmentState.ToString())

    $script:View = New-AIFishBotMainView

    Assert-True -Condition ($script:View.Form -is [System.Windows.Forms.Form])
    Assert-Equal -Expected $false -Actual $script:View.Form.Visible
    Assert-True -Condition (-not @([System.Windows.Forms.Application]::OpenForms).Contains($script:View.Form))
}

Test-Case 'view exposes the stable controller contract' {
    foreach ($propertyName in @('Form', 'Controls', 'TrayIcon', 'TrayMenu', 'Timers')) {
        Assert-True -Condition ($script:View.PSObject.Properties.Name -contains $propertyName)
    }

    foreach ($controlName in @(
            'ProfileSelector', 'NewProfileButton', 'CopyProfileButton', 'RenameProfileButton',
            'DeleteProfileButton', 'StatusBadge', 'SaveStateLabel', 'SaveButton', 'StartStopButton',
            'Retail', 'AutoStop', 'AutoStopTime', 'AutoLogout', 'AudioSensitivity', 'AudioPeakBar',
            'HookCount', 'RemainingTime', 'BiteResponseMin', 'BiteResponseMax', 'PreHookMin',
            'PreHookMax', 'PostHookMin', 'PostHookMax', 'PreCastMin', 'PreCastMax', 'CastKey',
            'BobberKey', 'LogoutKey', 'UseWindowFocus', 'UseWeakAura', 'FishingRetries', 'UsePi',
            'PicoComPort', 'BuffGrid', 'AddBuffButton', 'RemoveBuffButton', 'MoveBuffUpButton',
            'MoveBuffDownButton', 'EnableNotifications', 'NotifyOnStart', 'NotifyOnStop',
            'WebhookText', 'ShowWebhookButton', 'LogLevel', 'LogBox', 'ClearLogButton',
            'OpenLogButton', 'InstallAudioButton'
        )) {
        Assert-True -Condition $script:View.Controls.ContainsKey($controlName)
        Assert-True -Condition ($null -ne $script:View.Controls[$controlName])
    }
}

Test-Case 'window uses the deep ocean theme and safe desktop sizing' {
    $form = $script:View.Form

    Assert-Equal -Expected ([Drawing.Size]::new(760, 620)) -Actual $form.Size
    Assert-Equal -Expected ([Drawing.Size]::new(720, 580)) -Actual $form.MinimumSize
    Assert-Equal -Expected ([System.Windows.Forms.FormStartPosition]::CenterScreen) -Actual $form.StartPosition
    Assert-Equal -Expected ([System.Windows.Forms.AutoScaleMode]::Dpi) -Actual $form.AutoScaleMode
    Assert-Equal -Expected 'Segoe UI' -Actual $form.Font.Name
    Assert-ColorHex -Actual $form.BackColor -Expected '#071522'
    Assert-ColorHex -Actual $script:View.Controls.HeaderPanel.BackColor -Expected '#0D2233'
    Assert-ColorHex -Actual $script:View.Controls.ProfileSelector.BackColor -Expected '#102B40'
    Assert-ColorHex -Actual $script:View.Controls.StartStopButton.BackColor -Expected '#2DD4BF'
    Assert-ColorHex -Actual $script:View.Controls.SaveStateLabel.ForeColor -Expected '#82A9BC'
    Assert-ColorHex -Actual $script:View.Controls.StatusBadge.ForeColor -Expected '#45D483'
}

Test-Case 'header tabs and persistent footer are laid out in the required order' {
    $tabs = $script:View.Controls.MainTabs

    Assert-Equal -Expected @('基础', '按键与设备', '增益', '通知', '日志') -Actual @(
        $tabs.TabPages | ForEach-Object { $_.Text }
    )
    Assert-True -Condition ($script:View.Controls.ProfileSelector.Parent -ne $null)
    Assert-True -Condition ($script:View.Controls.StatusBadge.Parent -ne $null)
    Assert-True -Condition (($script:View.Controls.FooterPanel.Dock -band [System.Windows.Forms.DockStyle]::Bottom) -ne 0)
    Assert-True -Condition ($script:View.Controls.SaveStateLabel.Parent -eq $script:View.Controls.FooterPanel)
    Assert-True -Condition ($script:View.Controls.SaveButton.Parent -eq $script:View.Controls.FooterPanel)
    Assert-True -Condition ($script:View.Controls.StartStopButton.Parent -eq $script:View.Controls.FooterPanel)
}

Test-Case 'all four timing ranges use tenths of a second with bounded values' {
    foreach ($name in @(
            'BiteResponseMin', 'BiteResponseMax', 'PreHookMin', 'PreHookMax',
            'PostHookMin', 'PostHookMax', 'PreCastMin', 'PreCastMax'
        )) {
        $numeric = $script:View.Controls[$name]
        Assert-True -Condition ($numeric -is [System.Windows.Forms.NumericUpDown])
        Assert-Equal -Expected 1 -Actual $numeric.DecimalPlaces
        Assert-Equal -Expected ([decimal]0.1) -Actual $numeric.Increment
        Assert-Equal -Expected ([decimal]0) -Actual $numeric.Minimum
        Assert-True -Condition ($numeric.Maximum -ge 10 -and $numeric.Maximum -le 600)
    }
}

Test-Case 'key selectors offer only F5 through F12' {
    $expectedKeys = @(5..12 | ForEach-Object { 'F{0}' -f $_ })

    foreach ($name in @('CastKey', 'BobberKey', 'LogoutKey')) {
        $selector = $script:View.Controls[$name]
        Assert-Equal -Expected $expectedKeys -Actual @($selector.Items | ForEach-Object { [string]$_ })
        Assert-Equal -Expected ([System.Windows.Forms.ComboBoxStyle]::DropDownList) -Actual $selector.DropDownStyle
    }
}

Test-Case 'buff grid has stable columns and supports add remove and ordering' {
    $grid = $script:View.Controls.BuffGrid
    Assert-Equal -Expected @('enabled', 'name', 'keybind', 'castTime', 'duration') -Actual @(
        $grid.Columns | ForEach-Object { $_.Name }
    )
    Assert-Equal -Expected $false -Actual $grid.AllowUserToAddRows
    Assert-Equal -Expected $false -Actual $grid.AllowUserToDeleteRows

    Invoke-TestButtonClick -Button $script:View.Controls.AddBuffButton
    Invoke-TestButtonClick -Button $script:View.Controls.AddBuffButton
    Assert-Equal -Expected 2 -Actual $grid.Rows.Count
    $grid.Rows[0].Cells['name'].Value = '第一项'
    $grid.Rows[1].Cells['name'].Value = '第二项'
    $grid.CurrentCell = $grid.Rows[1].Cells['name']

    Invoke-TestButtonClick -Button $script:View.Controls.MoveBuffUpButton
    Assert-Equal -Expected '第二项' -Actual ([string]$grid.Rows[0].Cells['name'].Value)

    Invoke-TestButtonClick -Button $script:View.Controls.MoveBuffDownButton
    Assert-Equal -Expected '第二项' -Actual ([string]$grid.Rows[1].Cells['name'].Value)

    Invoke-TestButtonClick -Button $script:View.Controls.RemoveBuffButton
    Assert-Equal -Expected 1 -Actual $grid.Rows.Count
}

Test-Case 'webhook stays masked and reveal behavior is left to the controller' {
    $webhook = $script:View.Controls.WebhookText
    $showButton = $script:View.Controls.ShowWebhookButton

    Assert-True -Condition ($webhook.PasswordChar -ne [char]0)
    Assert-Equal -Expected $false -Actual $webhook.UseSystemPasswordChar
    Assert-Equal -Expected 'MouseDown' -Actual $showButton.PSObject.Methods['add_MouseDown'].Name.Substring(4)
    Assert-Equal -Expected 'MouseUp' -Actual $showButton.PSObject.Methods['add_MouseUp'].Name.Substring(4)

    $maskBefore = $webhook.PasswordChar
    Invoke-TestButtonClick -Button $showButton
    Assert-Equal -Expected $maskBefore -Actual $webhook.PasswordChar
}

Test-Case 'basic controls expose counters audio meter and safe input ranges' {
    Assert-True -Condition ($script:View.Controls.Retail -is [System.Windows.Forms.CheckBox])
    Assert-True -Condition ($script:View.Controls.AutoStopTime -is [System.Windows.Forms.NumericUpDown])
    Assert-True -Condition ($script:View.Controls.AudioSensitivity -is [System.Windows.Forms.TrackBar])
    Assert-True -Condition ($script:View.Controls.AudioPeakBar -is [System.Windows.Forms.ProgressBar])
    Assert-True -Condition ($script:View.Controls.HookCount -is [System.Windows.Forms.Label])
    Assert-True -Condition ($script:View.Controls.RemainingTime -is [System.Windows.Forms.Label])
    Assert-True -Condition ($script:View.Controls.FishingRetries.Minimum -ge 0)
}

Test-Case 'notification and log controls are controller ready' {
    foreach ($name in @('EnableNotifications', 'NotifyOnStart', 'NotifyOnStop')) {
        Assert-True -Condition ($script:View.Controls[$name] -is [System.Windows.Forms.CheckBox])
    }

    Assert-Equal -Expected $true -Actual $script:View.Controls.LogBox.ReadOnly
    Assert-Equal -Expected @('全部', '信息', '警告', '错误') -Actual @(
        $script:View.Controls.LogLevel.Items | ForEach-Object { [string]$_ }
    )
    Assert-Equal -Expected ([System.Windows.Forms.ComboBoxStyle]::DropDownList) -Actual $script:View.Controls.LogLevel.DropDownStyle
}

Test-Case 'tray menu and timers expose lifecycle actions without running them' {
    Assert-True -Condition ($script:View.TrayIcon -is [System.Windows.Forms.NotifyIcon])
    Assert-Equal -Expected $false -Actual $script:View.TrayIcon.Visible
    Assert-Equal -Expected @('状态：已停止', '打开', '开始', '停止', '退出') -Actual @(
        $script:View.TrayMenu.Items | ForEach-Object { $_.Text }
    )
    Assert-Equal -Expected $false -Actual $script:View.TrayMenu.Items[0].Enabled

    foreach ($timerName in @('Status', 'Log')) {
        Assert-True -Condition $script:View.Timers.ContainsKey($timerName)
        Assert-True -Condition ($script:View.Timers[$timerName] -is [System.Windows.Forms.Timer])
        Assert-Equal -Expected $false -Actual $script:View.Timers[$timerName].Enabled
        Assert-True -Condition ($script:View.Timers[$timerName].Interval -gt 0)
    }
}

Test-Case 'dispose is idempotent and releases every UI handle' {
    $form = $script:View.Form
    $null = $form.Handle
    Assert-Equal -Expected $true -Actual $form.IsHandleCreated

    $script:View.Dispose()
    $script:View.Dispose()

    Assert-Equal -Expected $true -Actual $form.IsDisposed
    Assert-Equal -Expected $false -Actual $form.IsHandleCreated
    Assert-Equal -Expected $true -Actual $script:View.TrayMenu.IsDisposed
    Assert-Equal -Expected $false -Actual $script:View.TrayIcon.Visible
    Assert-True -Condition (-not @([System.Windows.Forms.Application]::OpenForms).Contains($form))
}
