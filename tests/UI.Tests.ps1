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

function Invoke-TestProtectedEvent {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control,

        [Parameter(Mandatory = $true)]
        [string]$MethodName,

        [Parameter(Mandatory = $true)]
        [System.EventArgs]$EventArgs
    )

    $method = $Control.GetType().GetMethod(
        $MethodName,
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    if ($null -eq $method) {
        throw "Unable to find protected event method '$MethodName'."
    }
    [void]$method.Invoke($Control, @($EventArgs))
}

function Invoke-TestLayoutTree {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control
    )

    $Control.CreateControl()
    $Control.PerformLayout()
    foreach ($child in $Control.Controls) {
        Invoke-TestLayoutTree -Control $child
    }
}

function Get-TestFormBounds {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Form]$Form
    )

    $x = $Control.Left
    $y = $Control.Top
    $parent = $Control.Parent
    while ($null -ne $parent -and $parent -ne $Form) {
        $x += $parent.Left
        $y += $parent.Top
        $parent = $parent.Parent
    }
    if ($parent -ne $Form) {
        throw "Control '$($Control.Name)' is not attached to the form."
    }

    return New-Object System.Drawing.Rectangle($x, $y, $Control.Width, $Control.Height)
}

function Get-TestTabPage {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control
    )

    $parent = $Control.Parent
    while ($null -ne $parent) {
        if ($parent -is [System.Windows.Forms.TabPage]) {
            return $parent
        }
        $parent = $parent.Parent
    }
    return $null
}

function Test-ControlDescendsFrom {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control,

        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$ExpectedAncestor
    )

    $parent = $Control.Parent
    while ($null -ne $parent) {
        if ([object]::ReferenceEquals($parent, $ExpectedAncestor)) {
            return $true
        }
        $parent = $parent.Parent
    }
    return $false
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

    Assert-True -Condition $script:View.Controls.ContainsKey('TabControl')
    Assert-True -Condition ([object]::ReferenceEquals(
            $script:View.Controls.TabControl,
            $script:View.Controls.MainTabs
        ))
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
    Assert-True -Condition (Test-ControlDescendsFrom -Control $script:View.Controls.SaveStateLabel -ExpectedAncestor $script:View.Controls.FooterPanel)
    Assert-True -Condition (Test-ControlDescendsFrom -Control $script:View.Controls.SaveButton -ExpectedAncestor $script:View.Controls.FooterPanel)
    Assert-True -Condition (Test-ControlDescendsFrom -Control $script:View.Controls.StartStopButton -ExpectedAncestor $script:View.Controls.FooterPanel)
}

Test-Case 'every controller control remains inside the laid out client area' {
    $form = $script:View.Form
    $form.Size = New-Object System.Drawing.Size(760, 620)
    $null = $form.Handle
    $form.CreateControl()

    $checked = New-Object 'System.Collections.Generic.HashSet[System.Windows.Forms.Control]'
    $tabControl = if ($script:View.Controls.ContainsKey('TabControl')) {
        $script:View.Controls.TabControl
    }
    else {
        $script:View.Controls.MainTabs
    }
    $null = $tabControl.Handle
    foreach ($entry in $script:View.Controls.GetEnumerator()) {
        $control = $entry.Value
        if (-not ($control -is [System.Windows.Forms.Control]) -or -not $checked.Add($control)) {
            continue
        }

        $tabPage = Get-TestTabPage -Control $control
        if ($null -ne $tabPage) {
            $tabControl.SelectedTab = $tabPage
            $null = $tabPage.Handle
        }
        Invoke-TestLayoutTree -Control $form

        $bounds = Get-TestFormBounds -Control $control -Form $form
        $client = $form.ClientRectangle
        if ($bounds.Left -lt $client.Left -or $bounds.Top -lt $client.Top -or
            $bounds.Right -gt $client.Right -or $bounds.Bottom -gt $client.Bottom) {
            throw "Control '$($entry.Key)' is outside the client area: $bounds vs $client."
        }
    }

    Assert-True -Condition ($script:View.Controls.StatusBadge.Height -ge 30)

    $notificationPage = Get-TestTabPage -Control $script:View.Controls.WebhookText
    $tabControl.SelectedTab = $notificationPage
    $null = $notificationPage.Handle
    Invoke-TestLayoutTree -Control $form
    $webhookBounds = Get-TestFormBounds -Control $script:View.Controls.WebhookText -Form $form
    $showBounds = Get-TestFormBounds -Control $script:View.Controls.ShowWebhookButton -Form $form
    Assert-True -Condition ($webhookBounds.Width -ge 300)
    Assert-True -Condition ($webhookBounds.Right -le $showBounds.Left)

    Assert-Equal -Expected $false -Actual $form.Visible
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

Test-Case 'webhook reveals only while the show button is held' {
    $webhook = $script:View.Controls.WebhookText
    $showButton = $script:View.Controls.ShowWebhookButton

    Assert-True -Condition ($webhook.PasswordChar -ne [char]0)
    Assert-Equal -Expected $false -Actual $webhook.UseSystemPasswordChar
    Assert-Equal -Expected 'MouseDown' -Actual $showButton.PSObject.Methods['add_MouseDown'].Name.Substring(4)
    Assert-Equal -Expected 'MouseUp' -Actual $showButton.PSObject.Methods['add_MouseUp'].Name.Substring(4)

    $mask = $webhook.PasswordChar
    $mouseDown = New-Object System.Windows.Forms.MouseEventArgs(
        [System.Windows.Forms.MouseButtons]::Left, 1, 2, 2, 0)
    $mouseUp = New-Object System.Windows.Forms.MouseEventArgs(
        [System.Windows.Forms.MouseButtons]::Left, 1, 2, 2, 0)

    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnMouseDown' -EventArgs $mouseDown
    Assert-Equal -Expected ([char]0) -Actual $webhook.PasswordChar
    Assert-Equal -Expected $false -Actual $webhook.UseSystemPasswordChar
    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnMouseUp' -EventArgs $mouseUp
    Assert-Equal -Expected $mask -Actual $webhook.PasswordChar

    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnMouseDown' -EventArgs $mouseDown
    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnMouseLeave' -EventArgs ([System.EventArgs]::Empty)
    Assert-Equal -Expected $mask -Actual $webhook.PasswordChar

    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnMouseDown' -EventArgs $mouseDown
    Invoke-TestProtectedEvent -Control $showButton -MethodName 'OnLostFocus' -EventArgs ([System.EventArgs]::Empty)
    Assert-Equal -Expected $mask -Actual $webhook.PasswordChar
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

    Assert-True -Condition ($script:View.Timers -is [System.Management.Automation.PSCustomObject])
    foreach ($timerName in @('Status', 'Log')) {
        Assert-True -Condition ($script:View.Timers.PSObject.Properties.Name -contains $timerName)
        Assert-True -Condition ($script:View.Timers.$timerName -is [System.Windows.Forms.Timer])
        Assert-Equal -Expected $false -Actual $script:View.Timers.$timerName.Enabled
        Assert-True -Condition ($script:View.Timers.$timerName.Interval -gt 0)
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
