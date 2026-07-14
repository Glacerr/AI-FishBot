Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:AIFishBotColors = @{
    Background = [System.Drawing.ColorTranslator]::FromHtml('#071522')
    Card = [System.Drawing.ColorTranslator]::FromHtml('#0D2233')
    Input = [System.Drawing.ColorTranslator]::FromHtml('#102B40')
    Accent = [System.Drawing.ColorTranslator]::FromHtml('#2DD4BF')
    Text = [System.Drawing.ColorTranslator]::FromHtml('#D9F3FF')
    Muted = [System.Drawing.ColorTranslator]::FromHtml('#82A9BC')
    Success = [System.Drawing.ColorTranslator]::FromHtml('#45D483')
    Warning = [System.Drawing.ColorTranslator]::FromHtml('#F4A340')
    Error = [System.Drawing.ColorTranslator]::FromHtml('#F05A67')
}

function New-AIFishBotLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 130,
        [int]$Height = 24,
        [System.Drawing.Color]$ForeColor = $script:AIFishBotColors.Text
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = $ForeColor
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $label
}

function New-AIFishBotButton {
    param(
        [string]$Text,
        [int]$Width = 84,
        [int]$Height = 32,
        [System.Drawing.Color]$BackColor = $script:AIFishBotColors.Input,
        [System.Drawing.Color]$ForeColor = $script:AIFishBotColors.Text
    )

    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.BackColor = $BackColor
    $button.ForeColor = $ForeColor
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderColor = $script:AIFishBotColors.Input
    $button.FlatAppearance.BorderSize = 1
    $button.UseVisualStyleBackColor = $false
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

function New-AIFishBotCheckBox {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$Width = 180
    )

    $checkBox = New-Object System.Windows.Forms.CheckBox
    $checkBox.Text = $Text
    $checkBox.Location = New-Object System.Drawing.Point($X, $Y)
    $checkBox.Size = New-Object System.Drawing.Size($Width, 25)
    $checkBox.ForeColor = $script:AIFishBotColors.Text
    $checkBox.BackColor = [System.Drawing.Color]::Transparent
    $checkBox.UseVisualStyleBackColor = $false
    return $checkBox
}

function New-AIFishBotNumeric {
    param(
        [decimal]$Minimum = 0,
        [decimal]$Maximum = 999,
        [decimal]$Increment = 1,
        [int]$DecimalPlaces = 0,
        [decimal]$Value = 0,
        [int]$Width = 84
    )

    $numeric = New-Object System.Windows.Forms.NumericUpDown
    $numeric.Minimum = $Minimum
    $numeric.Maximum = $Maximum
    $numeric.Increment = $Increment
    $numeric.DecimalPlaces = $DecimalPlaces
    $numeric.Value = $Value
    $numeric.Size = New-Object System.Drawing.Size($Width, 26)
    $numeric.BackColor = $script:AIFishBotColors.Input
    $numeric.ForeColor = $script:AIFishBotColors.Text
    $numeric.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $numeric.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    return $numeric
}

function New-AIFishBotComboBox {
    param(
        [object[]]$Items,
        [int]$Width = 150
    )

    $comboBox = New-Object System.Windows.Forms.ComboBox
    $comboBox.Size = New-Object System.Drawing.Size($Width, 28)
    $comboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboBox.BackColor = $script:AIFishBotColors.Input
    $comboBox.ForeColor = $script:AIFishBotColors.Text
    $comboBox.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    if ($Items.Count -gt 0) {
        [void]$comboBox.Items.AddRange($Items)
        $comboBox.SelectedIndex = 0
    }
    return $comboBox
}

function New-AIFishBotCard {
    param([string]$Text)

    $group = New-Object System.Windows.Forms.GroupBox
    $group.Text = $Text
    $group.Dock = [System.Windows.Forms.DockStyle]::Fill
    $group.BackColor = $script:AIFishBotColors.Card
    $group.ForeColor = $script:AIFishBotColors.Text
    $group.Padding = New-Object System.Windows.Forms.Padding(12)
    return $group
}

function New-AIFishBotPageLayout {
    param([System.Windows.Forms.TabPage]$Page)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.Padding = New-Object System.Windows.Forms.Padding(12)
    $layout.BackColor = $script:AIFishBotColors.Background
    $layout.ColumnCount = 2
    $layout.RowCount = 2
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 48)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 52)))
    $Page.Controls.Add($layout)
    return $layout
}

function Set-AIFishBotControlLocation {
    param(
        [System.Windows.Forms.Control]$Control,
        [int]$X,
        [int]$Y
    )

    $Control.Location = New-Object System.Drawing.Point($X, $Y)
}

function New-AIFishBotMainView {
    [CmdletBinding()]
    param()

    if ([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA) {
        throw '界面必须在 STA 模式下创建。请使用 powershell.exe -Sta。'
    }

    $controls = @{}

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'AI FishBot 深海控制台'
    $form.Size = New-Object System.Drawing.Size(760, 620)
    $form.MinimumSize = New-Object System.Drawing.Size(720, 580)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.BackColor = $script:AIFishBotColors.Background
    $form.ForeColor = $script:AIFishBotColors.Text
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
    $headerPanel.Height = 96
    $headerPanel.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 8)
    $headerPanel.BackColor = $script:AIFishBotColors.Card
    $controls.HeaderPanel = $headerPanel

    $titleLabel = New-AIFishBotLabel -Text 'AI FishBot' -X 16 -Y 8 -Width 190 -Height 32
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-AIFishBotLabel -Text '深海自动钓鱼控制台' -X 17 -Y 37 -Width 190 -Height 20 -ForeColor $script:AIFishBotColors.Muted
    $headerPanel.Controls.Add($subtitleLabel)

    $profileLabel = New-AIFishBotLabel -Text '方案' -X 220 -Y 15 -Width 40 -Height 26 -ForeColor $script:AIFishBotColors.Muted
    $headerPanel.Controls.Add($profileLabel)

    $profileSelector = New-AIFishBotComboBox -Items @('默认方案') -Width 176
    Set-AIFishBotControlLocation -Control $profileSelector -X 262 -Y 14
    $profileSelector.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
    $headerPanel.Controls.Add($profileSelector)
    $controls.ProfileSelector = $profileSelector

    $newProfileButton = New-AIFishBotButton -Text '新建' -Width 52 -Height 28
    Set-AIFishBotControlLocation -Control $newProfileButton -X 220 -Y 53
    $headerPanel.Controls.Add($newProfileButton)
    $controls.NewProfileButton = $newProfileButton

    $copyProfileButton = New-AIFishBotButton -Text '复制' -Width 52 -Height 28
    Set-AIFishBotControlLocation -Control $copyProfileButton -X 278 -Y 53
    $headerPanel.Controls.Add($copyProfileButton)
    $controls.CopyProfileButton = $copyProfileButton

    $renameProfileButton = New-AIFishBotButton -Text '重命名' -Width 64 -Height 28
    Set-AIFishBotControlLocation -Control $renameProfileButton -X 336 -Y 53
    $headerPanel.Controls.Add($renameProfileButton)
    $controls.RenameProfileButton = $renameProfileButton

    $deleteProfileButton = New-AIFishBotButton -Text '删除' -Width 52 -Height 28 -BackColor $script:AIFishBotColors.Error -ForeColor $script:AIFishBotColors.Background
    $deleteProfileButton.FlatAppearance.BorderColor = $script:AIFishBotColors.Error
    Set-AIFishBotControlLocation -Control $deleteProfileButton -X 406 -Y 53
    $headerPanel.Controls.Add($deleteProfileButton)
    $controls.DeleteProfileButton = $deleteProfileButton

    $resetProfileButton = New-AIFishBotButton -Text '恢复默认' -Width 84 -Height 28 `
        -BackColor $script:AIFishBotColors.Input -ForeColor $script:AIFishBotColors.Warning
    $resetProfileButton.FlatAppearance.BorderColor = $script:AIFishBotColors.Warning
    Set-AIFishBotControlLocation -Control $resetProfileButton -X 464 -Y 53
    $headerPanel.Controls.Add($resetProfileButton)
    $controls.ResetProfileButton = $resetProfileButton

    $statusHost = New-Object System.Windows.Forms.Panel
    $statusHost.Dock = [System.Windows.Forms.DockStyle]::Right
    $statusHost.Width = 144
    $statusHost.Padding = New-Object System.Windows.Forms.Padding(16, 9, 16, 35)
    $statusHost.BackColor = $script:AIFishBotColors.Card
    $headerPanel.Controls.Add($statusHost)

    $statusBadge = New-AIFishBotLabel -Text '● 已停止' -X 0 -Y 0 -Width 112 -Height 34 -ForeColor $script:AIFishBotColors.Success
    $statusBadge.Dock = [System.Windows.Forms.DockStyle]::Fill
    $statusBadge.BackColor = $script:AIFishBotColors.Input
    $statusBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $statusBadge.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $statusHost.Controls.Add($statusBadge)
    $controls.StatusBadge = $statusBadge

    $footerPanel = New-Object System.Windows.Forms.Panel
    $footerPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $footerPanel.Height = 66
    $footerPanel.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 12)
    $footerPanel.BackColor = $script:AIFishBotColors.Card
    $controls.FooterPanel = $footerPanel

    $saveStateLabel = New-AIFishBotLabel -Text '所有更改已保存' -X 16 -Y 20 -Width 400 -Height 28 -ForeColor $script:AIFishBotColors.Muted
    $saveStateLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
    $footerPanel.Controls.Add($saveStateLabel)
    $controls.SaveStateLabel = $saveStateLabel

    $footerButtonHost = New-Object System.Windows.Forms.FlowLayoutPanel
    $footerButtonHost.Dock = [System.Windows.Forms.DockStyle]::Right
    $footerButtonHost.Width = 226
    $footerButtonHost.Padding = New-Object System.Windows.Forms.Padding(8, 2, 0, 0)
    $footerButtonHost.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $footerButtonHost.WrapContents = $false
    $footerButtonHost.BackColor = $script:AIFishBotColors.Card
    $footerPanel.Controls.Add($footerButtonHost)

    $saveButton = New-AIFishBotButton -Text '保存' -Width 92 -Height 38
    $saveButton.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
    $footerButtonHost.Controls.Add($saveButton)
    $controls.SaveButton = $saveButton

    $startStopButton = New-AIFishBotButton -Text '开始钓鱼' -Width 104 -Height 38 -BackColor $script:AIFishBotColors.Accent -ForeColor $script:AIFishBotColors.Background
    $startStopButton.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
    $startStopButton.FlatAppearance.BorderColor = $script:AIFishBotColors.Accent
    $footerButtonHost.Controls.Add($startStopButton)
    $controls.StartStopButton = $startStopButton

    $mainTabs = New-Object System.Windows.Forms.TabControl
    $mainTabs.Dock = [System.Windows.Forms.DockStyle]::Fill
    $mainTabs.Padding = New-Object System.Drawing.Point(16, 6)
    $mainTabs.BackColor = $script:AIFishBotColors.Background
    $mainTabs.ForeColor = $script:AIFishBotColors.Text
    $controls.MainTabs = $mainTabs
    $controls.TabControl = $mainTabs

    $pages = @{}
    foreach ($pageName in @('基础', '按键与设备', '增益', '通知', '日志')) {
        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $pageName
        $page.BackColor = $script:AIFishBotColors.Background
        $page.ForeColor = $script:AIFishBotColors.Text
        $page.Padding = New-Object System.Windows.Forms.Padding(4)
        [void]$mainTabs.TabPages.Add($page)
        $pages[$pageName] = $page
    }

    $basicLayout = New-AIFishBotPageLayout -Page $pages['基础']
    $automationCard = New-AIFishBotCard -Text '自动化'
    $statusCard = New-AIFishBotCard -Text '声音与进度'
    $timingCard = New-AIFishBotCard -Text '拟人化等待（秒）'
    $basicLayout.Controls.Add($automationCard, 0, 0)
    $basicLayout.Controls.Add($statusCard, 1, 0)
    $basicLayout.Controls.Add($timingCard, 0, 1)
    $basicLayout.SetColumnSpan($timingCard, 2)

    $retail = New-AIFishBotCheckBox -Text '正式服模式' -X 18 -Y 29
    $automationCard.Controls.Add($retail)
    $controls.Retail = $retail

    $autoStop = New-AIFishBotCheckBox -Text '启用自动停止' -X 18 -Y 61
    $automationCard.Controls.Add($autoStop)
    $controls.AutoStop = $autoStop

    $autoStopTimeLabel = New-AIFishBotLabel -Text '分钟' -X 236 -Y 62 -Width 48
    $automationCard.Controls.Add($autoStopTimeLabel)
    $autoStopTime = New-AIFishBotNumeric -Minimum 1 -Maximum 1440 -Value 60 -Width 74
    Set-AIFishBotControlLocation -Control $autoStopTime -X 155 -Y 61
    $automationCard.Controls.Add($autoStopTime)
    $controls.AutoStopTime = $autoStopTime

    $autoLogout = New-AIFishBotCheckBox -Text '停止后自动登出' -X 18 -Y 96
    $automationCard.Controls.Add($autoLogout)
    $controls.AutoLogout = $autoLogout

    $audioLabel = New-AIFishBotLabel -Text '声音灵敏度' -X 18 -Y 27 -Width 92
    $statusCard.Controls.Add($audioLabel)
    $audioSensitivity = New-Object System.Windows.Forms.TrackBar
    $audioSensitivity.Location = New-Object System.Drawing.Point(108, 22)
    $audioSensitivity.Size = New-Object System.Drawing.Size(135, 38)
    $audioSensitivity.Minimum = 1
    $audioSensitivity.Maximum = 9
    $audioSensitivity.Value = 3
    $audioSensitivity.TickStyle = [System.Windows.Forms.TickStyle]::None
    $audioSensitivity.BackColor = $script:AIFishBotColors.Card
    $statusCard.Controls.Add($audioSensitivity)
    $controls.AudioSensitivity = $audioSensitivity

    $audioPeakBar = New-Object System.Windows.Forms.ProgressBar
    $audioPeakBar.Location = New-Object System.Drawing.Point(18, 64)
    $audioPeakBar.Size = New-Object System.Drawing.Size(230, 12)
    $audioPeakBar.Maximum = 100
    $audioPeakBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $statusCard.Controls.Add($audioPeakBar)
    $controls.AudioPeakBar = $audioPeakBar

    $hookCount = New-AIFishBotLabel -Text '已上钩：0' -X 18 -Y 82 -Width 110
    $remainingTime = New-AIFishBotLabel -Text '剩余：--:--' -X 134 -Y 82 -Width 120 -ForeColor $script:AIFishBotColors.Muted
    $statusCard.Controls.Add($hookCount)
    $statusCard.Controls.Add($remainingTime)
    $controls.HookCount = $hookCount
    $controls.RemainingTime = $remainingTime

    $installAudioButton = New-AIFishBotButton -Text '安装声音组件' -Width 128 -Height 28 -ForeColor $script:AIFishBotColors.Warning
    Set-AIFishBotControlLocation -Control $installAudioButton -X 18 -Y 112
    $statusCard.Controls.Add($installAudioButton)
    $controls.InstallAudioButton = $installAudioButton

    $timingRows = @(
        @{ Label = '咬钩响应'; Min = 'BiteResponseMin'; Max = 'BiteResponseMax'; Y = 31; MinValue = 0.3; MaxValue = 0.7 },
        @{ Label = '提竿前'; Min = 'PreHookMin'; Max = 'PreHookMax'; Y = 65; MinValue = 0.5; MaxValue = 0.5 },
        @{ Label = '提竿后'; Min = 'PostHookMin'; Max = 'PostHookMax'; Y = 99; MinValue = 1.1; MaxValue = 1.5 },
        @{ Label = '抛竿前'; Min = 'PreCastMin'; Max = 'PreCastMax'; Y = 133; MinValue = 0.2; MaxValue = 0.6 }
    )
    foreach ($row in $timingRows) {
        $timingCard.Controls.Add((New-AIFishBotLabel -Text $row.Label -X 18 -Y $row.Y -Width 92))
        $minimum = New-AIFishBotNumeric -Minimum 0 -Maximum 60 -Increment 0.1 -DecimalPlaces 1 -Value $row.MinValue -Width 90
        Set-AIFishBotControlLocation -Control $minimum -X 122 -Y $row.Y
        $timingCard.Controls.Add($minimum)
        $timingCard.Controls.Add((New-AIFishBotLabel -Text '至' -X 226 -Y $row.Y -Width 28))
        $maximum = New-AIFishBotNumeric -Minimum 0 -Maximum 60 -Increment 0.1 -DecimalPlaces 1 -Value $row.MaxValue -Width 90
        Set-AIFishBotControlLocation -Control $maximum -X 262 -Y $row.Y
        $timingCard.Controls.Add($maximum)
        $controls[$row.Min] = $minimum
        $controls[$row.Max] = $maximum
    }

    $deviceLayout = New-AIFishBotPageLayout -Page $pages['按键与设备']
    $keyCard = New-AIFishBotCard -Text '按键'
    $optionCard = New-AIFishBotCard -Text '行为'
    $deviceCard = New-AIFishBotCard -Text '设备'
    $deviceLayout.Controls.Add($keyCard, 0, 0)
    $deviceLayout.Controls.Add($optionCard, 1, 0)
    $deviceLayout.Controls.Add($deviceCard, 0, 1)
    $deviceLayout.SetColumnSpan($deviceCard, 2)

    $functionKeys = [object[]]@(5..12 | ForEach-Object { 'F{0}' -f $_ })
    foreach ($keyRow in @(
            @{ Label = '抛竿'; Name = 'CastKey'; Y = 33; Index = 1 },
            @{ Label = '浮标'; Name = 'BobberKey'; Y = 74; Index = 2 },
            @{ Label = '登出'; Name = 'LogoutKey'; Y = 115; Index = 3 }
        )) {
        $keyCard.Controls.Add((New-AIFishBotLabel -Text $keyRow.Label -X 18 -Y $keyRow.Y -Width 68))
        $keyCombo = New-AIFishBotComboBox -Items $functionKeys -Width 118
        Set-AIFishBotControlLocation -Control $keyCombo -X 95 -Y $keyRow.Y
        $keyCombo.SelectedIndex = $keyRow.Index
        $keyCard.Controls.Add($keyCombo)
        $controls[$keyRow.Name] = $keyCombo
    }

    $useWindowFocus = New-AIFishBotCheckBox -Text '自动聚焦游戏窗口' -X 18 -Y 34 -Width 230
    $useWeakAura = New-AIFishBotCheckBox -Text '使用 WeakAura 浮标键' -X 18 -Y 72 -Width 230
    $optionCard.Controls.Add($useWindowFocus)
    $optionCard.Controls.Add($useWeakAura)
    $controls.UseWindowFocus = $useWindowFocus
    $controls.UseWeakAura = $useWeakAura
    $optionCard.Controls.Add((New-AIFishBotLabel -Text '失败重试次数' -X 18 -Y 112 -Width 110))
    $fishingRetries = New-AIFishBotNumeric -Minimum 0 -Maximum 999 -Value 15 -Width 84
    Set-AIFishBotControlLocation -Control $fishingRetries -X 145 -Y 112
    $optionCard.Controls.Add($fishingRetries)
    $controls.FishingRetries = $fishingRetries

    $usePi = New-AIFishBotCheckBox -Text '使用 Pico 键盘设备' -X 18 -Y 37 -Width 210
    $deviceCard.Controls.Add($usePi)
    $controls.UsePi = $usePi
    $deviceCard.Controls.Add((New-AIFishBotLabel -Text '串口' -X 252 -Y 37 -Width 48))
    $picoComPort = New-AIFishBotComboBox -Items @() -Width 170
    Set-AIFishBotControlLocation -Control $picoComPort -X 307 -Y 36
    $deviceCard.Controls.Add($picoComPort)
    $controls.PicoComPort = $picoComPort

    $buffRoot = New-Object System.Windows.Forms.Panel
    $buffRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buffRoot.Padding = New-Object System.Windows.Forms.Padding(12)
    $buffRoot.BackColor = $script:AIFishBotColors.Background
    $pages['增益'].Controls.Add($buffRoot)

    $buffButtonBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $buffButtonBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $buffButtonBar.Height = 48
    $buffButtonBar.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $buffButtonBar.WrapContents = $false
    $buffButtonBar.BackColor = $script:AIFishBotColors.Card
    $buffButtonBar.Padding = New-Object System.Windows.Forms.Padding(8)

    $addBuffButton = New-AIFishBotButton -Text '新增' -Width 74 -Height 30 -BackColor $script:AIFishBotColors.Accent -ForeColor $script:AIFishBotColors.Background
    $removeBuffButton = New-AIFishBotButton -Text '删除' -Width 74 -Height 30 -BackColor $script:AIFishBotColors.Error -ForeColor $script:AIFishBotColors.Background
    $removeBuffButton.FlatAppearance.BorderColor = $script:AIFishBotColors.Error
    $moveBuffUpButton = New-AIFishBotButton -Text '上移' -Width 74 -Height 30
    $moveBuffDownButton = New-AIFishBotButton -Text '下移' -Width 74 -Height 30
    $buffButtonBar.Controls.AddRange([System.Windows.Forms.Control[]]@($addBuffButton, $removeBuffButton, $moveBuffUpButton, $moveBuffDownButton))

    $buffGrid = New-Object System.Windows.Forms.DataGridView
    $buffGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $buffGrid.BackgroundColor = $script:AIFishBotColors.Card
    $buffGrid.ForeColor = $script:AIFishBotColors.Text
    $buffGrid.GridColor = $script:AIFishBotColors.Input
    $buffGrid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $buffGrid.AllowUserToAddRows = $false
    $buffGrid.AllowUserToDeleteRows = $false
    $buffGrid.AllowUserToResizeRows = $false
    $buffGrid.RowHeadersVisible = $false
    $buffGrid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $buffGrid.MultiSelect = $false
    $buffGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $buffGrid.EnableHeadersVisualStyles = $false
    $buffGrid.ColumnHeadersDefaultCellStyle.BackColor = $script:AIFishBotColors.Input
    $buffGrid.ColumnHeadersDefaultCellStyle.ForeColor = $script:AIFishBotColors.Text
    $buffGrid.DefaultCellStyle.BackColor = $script:AIFishBotColors.Card
    $buffGrid.DefaultCellStyle.ForeColor = $script:AIFishBotColors.Text
    $buffGrid.DefaultCellStyle.SelectionBackColor = $script:AIFishBotColors.Input
    $buffGrid.DefaultCellStyle.SelectionForeColor = $script:AIFishBotColors.Accent

    $enabledColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $enabledColumn.Name = 'enabled'
    $enabledColumn.HeaderText = '启用'
    $enabledColumn.FillWeight = 45
    [void]$buffGrid.Columns.Add($enabledColumn)

    $nameColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $nameColumn.Name = 'name'
    $nameColumn.HeaderText = '名称'
    $nameColumn.FillWeight = 120
    [void]$buffGrid.Columns.Add($nameColumn)

    $keyColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $keyColumn.Name = 'keybind'
    $keyColumn.HeaderText = '按键'
    $keyColumn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    [void]$keyColumn.Items.AddRange($functionKeys)
    [void]$buffGrid.Columns.Add($keyColumn)

    $castTimeColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $castTimeColumn.Name = 'castTime'
    $castTimeColumn.HeaderText = '施放秒数'
    [void]$buffGrid.Columns.Add($castTimeColumn)

    $durationColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $durationColumn.Name = 'duration'
    $durationColumn.HeaderText = '持续分钟'
    [void]$buffGrid.Columns.Add($durationColumn)

    $buffRoot.Controls.Add($buffGrid)
    $buffRoot.Controls.Add($buffButtonBar)
    $controls.BuffGrid = $buffGrid
    $controls.AddBuffButton = $addBuffButton
    $controls.RemoveBuffButton = $removeBuffButton
    $controls.MoveBuffUpButton = $moveBuffUpButton
    $controls.MoveBuffDownButton = $moveBuffDownButton

    $addBuffButton.Add_Click({
            $rowIndex = $buffGrid.Rows.Add()
            $buffGrid.Rows[$rowIndex].Cells['enabled'].Value = $true
            $buffGrid.Rows[$rowIndex].Cells['name'].Value = '新增增益'
            $buffGrid.Rows[$rowIndex].Cells['keybind'].Value = 'F9'
            $buffGrid.Rows[$rowIndex].Cells['castTime'].Value = 1
            $buffGrid.Rows[$rowIndex].Cells['duration'].Value = 10
            $buffGrid.CurrentCell = $buffGrid.Rows[$rowIndex].Cells['name']
        }.GetNewClosure())
    $removeBuffButton.Add_Click({
            if ($null -ne $buffGrid.CurrentCell) {
                $buffGrid.Rows.RemoveAt($buffGrid.CurrentCell.RowIndex)
            }
        }.GetNewClosure())
    $moveBuffRow = {
        param([int]$Direction)

        if ($null -eq $buffGrid.CurrentCell) {
            return
        }

        $sourceIndex = $buffGrid.CurrentCell.RowIndex
        $targetIndex = $sourceIndex + $Direction
        if ($targetIndex -lt 0 -or $targetIndex -ge $buffGrid.Rows.Count) {
            return
        }

        $currentColumn = $buffGrid.CurrentCell.ColumnIndex
        $sourceValues = New-Object object[] $buffGrid.Columns.Count
        for ($columnIndex = 0; $columnIndex -lt $buffGrid.Columns.Count; $columnIndex += 1) {
            $sourceValues[$columnIndex] = $buffGrid.Rows[$sourceIndex].Cells[$columnIndex].Value
            $buffGrid.Rows[$sourceIndex].Cells[$columnIndex].Value = $buffGrid.Rows[$targetIndex].Cells[$columnIndex].Value
        }
        for ($columnIndex = 0; $columnIndex -lt $buffGrid.Columns.Count; $columnIndex += 1) {
            $buffGrid.Rows[$targetIndex].Cells[$columnIndex].Value = $sourceValues[$columnIndex]
        }

        $buffGrid.CurrentCell = $buffGrid.Rows[$targetIndex].Cells[$currentColumn]
    }.GetNewClosure()
    $moveBuffUpButton.Add_Click({ & $moveBuffRow -1 }.GetNewClosure())
    $moveBuffDownButton.Add_Click({ & $moveBuffRow 1 }.GetNewClosure())

    $notificationCard = New-AIFishBotCard -Text 'Discord 通知'
    $notificationCard.Dock = [System.Windows.Forms.DockStyle]::Fill
    $notificationCard.Padding = New-Object System.Windows.Forms.Padding(18, 145, 18, 18)
    $pages['通知'].Padding = New-Object System.Windows.Forms.Padding(16)
    $pages['通知'].Controls.Add($notificationCard)

    $enableNotifications = New-AIFishBotCheckBox -Text '启用通知' -X 22 -Y 40 -Width 180
    $notifyOnStart = New-AIFishBotCheckBox -Text '开始钓鱼时通知' -X 22 -Y 82 -Width 190
    $notifyOnStop = New-AIFishBotCheckBox -Text '停止钓鱼时通知' -X 220 -Y 82 -Width 190
    $notificationCard.Controls.AddRange([System.Windows.Forms.Control[]]@($enableNotifications, $notifyOnStart, $notifyOnStop))
    $controls.EnableNotifications = $enableNotifications
    $controls.NotifyOnStart = $notifyOnStart
    $controls.NotifyOnStop = $notifyOnStop

    $notificationCard.Controls.Add((New-AIFishBotLabel -Text 'Webhook 地址' -X 22 -Y 130 -Width 110))
    $webhookHost = New-Object System.Windows.Forms.Panel
    $webhookHost.Dock = [System.Windows.Forms.DockStyle]::Top
    $webhookHost.Height = 32
    $webhookHost.BackColor = [System.Drawing.Color]::Transparent
    $notificationCard.Controls.Add($webhookHost)

    $webhookText = New-Object System.Windows.Forms.TextBox
    $webhookText.Dock = [System.Windows.Forms.DockStyle]::Fill
    $webhookText.BackColor = $script:AIFishBotColors.Input
    $webhookText.ForeColor = $script:AIFishBotColors.Text
    $webhookText.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $webhookText.PasswordChar = [char]0x25CF
    $webhookText.UseSystemPasswordChar = $false
    $webhookHost.Controls.Add($webhookText)
    $controls.WebhookText = $webhookText

    $showWebhookButton = New-AIFishBotButton -Text '按住显示' -Width 92 -Height 28
    $showWebhookButton.Dock = [System.Windows.Forms.DockStyle]::Right
    $webhookHost.Controls.Add($showWebhookButton)
    $controls.ShowWebhookButton = $showWebhookButton

    $webhookMask = [char]0x25CF
    $revealWebhook = {
        param($sender, $eventArgs)

        if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $webhookText.UseSystemPasswordChar = $false
            $webhookText.PasswordChar = [char]0
        }
    }.GetNewClosure()
    $maskWebhook = {
        $webhookText.UseSystemPasswordChar = $false
        $webhookText.PasswordChar = $webhookMask
    }.GetNewClosure()
    $showWebhookButton.Add_MouseDown($revealWebhook)
    $showWebhookButton.Add_MouseUp($maskWebhook)
    $showWebhookButton.Add_MouseLeave($maskWebhook)
    $showWebhookButton.Add_MouseCaptureChanged($maskWebhook)
    $showWebhookButton.Add_LostFocus($maskWebhook)
    $form.Add_Deactivate($maskWebhook)
    $form.Add_VisibleChanged($maskWebhook)

    $webhookHelp = New-AIFishBotLabel -Text '地址默认隐藏；按住显示按钮时可临时查看。' -X 22 -Y 199 -Width 440 -ForeColor $script:AIFishBotColors.Muted
    $notificationCard.Controls.Add($webhookHelp)

    $logRoot = New-Object System.Windows.Forms.Panel
    $logRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
    $logRoot.Padding = New-Object System.Windows.Forms.Padding(12)
    $logRoot.BackColor = $script:AIFishBotColors.Background
    $pages['日志'].Controls.Add($logRoot)

    $logToolbar = New-Object System.Windows.Forms.FlowLayoutPanel
    $logToolbar.Dock = [System.Windows.Forms.DockStyle]::Top
    $logToolbar.Height = 46
    $logToolbar.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $logToolbar.WrapContents = $false
    $logToolbar.BackColor = $script:AIFishBotColors.Card
    $logToolbar.Padding = New-Object System.Windows.Forms.Padding(8)

    $logLevel = New-AIFishBotComboBox -Items @('全部', '信息', '警告', '错误') -Width 110
    $clearLogButton = New-AIFishBotButton -Text '清空' -Width 72 -Height 28
    $openLogButton = New-AIFishBotButton -Text '打开日志' -Width 92 -Height 28
    $logToolbar.Controls.AddRange([System.Windows.Forms.Control[]]@($logLevel, $clearLogButton, $openLogButton))

    $logBox = New-Object System.Windows.Forms.RichTextBox
    $logBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    $logBox.ReadOnly = $true
    $logBox.BackColor = $script:AIFishBotColors.Card
    $logBox.ForeColor = $script:AIFishBotColors.Text
    $logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logBox.DetectUrls = $false
    $logRoot.Controls.Add($logBox)
    $logRoot.Controls.Add($logToolbar)
    $controls.LogLevel = $logLevel
    $controls.LogBox = $logBox
    $controls.ClearLogButton = $clearLogButton
    $controls.OpenLogButton = $openLogButton

    $form.Controls.Add($mainTabs)
    $form.Controls.Add($footerPanel)
    $form.Controls.Add($headerPanel)

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $trayMenu.BackColor = $script:AIFishBotColors.Card
    $trayMenu.ForeColor = $script:AIFishBotColors.Text
    foreach ($menuDefinition in @(
            @{ Name = 'StatusItem'; Text = '状态：已停止'; Enabled = $false },
            @{ Name = 'OpenItem'; Text = '打开'; Enabled = $true },
            @{ Name = 'StartItem'; Text = '开始'; Enabled = $true },
            @{ Name = 'StopItem'; Text = '停止'; Enabled = $true },
            @{ Name = 'ExitItem'; Text = '退出'; Enabled = $true }
        )) {
        $menuItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $menuItem.Name = $menuDefinition.Name
        $menuItem.Text = $menuDefinition.Text
        $menuItem.Enabled = $menuDefinition.Enabled
        [void]$trayMenu.Items.Add($menuItem)
    }

    $trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $trayIcon.Text = 'AI FishBot'
    $trayIcon.Icon = [System.Drawing.SystemIcons]::Application
    $trayIcon.ContextMenuStrip = $trayMenu
    $trayIcon.Visible = $false

    $errorProvider = New-Object System.Windows.Forms.ErrorProvider
    $errorProvider.ContainerControl = $form
    $errorProvider.BlinkStyle = [System.Windows.Forms.ErrorBlinkStyle]::NeverBlink

    $statusTimer = New-Object System.Windows.Forms.Timer
    $statusTimer.Interval = 500
    $statusTimer.Enabled = $false
    $logTimer = New-Object System.Windows.Forms.Timer
    $logTimer.Interval = 250
    $logTimer.Enabled = $false
    $timers = [pscustomobject]@{
        Status = $statusTimer
        Log = $logTimer
    }

    $lifecycleState = [pscustomobject]@{
        AllowClose = $false
        Disposed = $false
    }
    $form.Add_FormClosing({
            param($sender, $eventArgs)

            & $maskWebhook
            if (-not $lifecycleState.AllowClose -and
                $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
                $eventArgs.Cancel = $true
                $form.Hide()
                $trayIcon.Visible = $true
            }
        }.GetNewClosure())
    $form.Add_Resize({
            if (-not $lifecycleState.AllowClose -and
                $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                & $maskWebhook
                $form.Hide()
                $trayIcon.Visible = $true
            }
        }.GetNewClosure())

    $view = [pscustomobject]@{
        Form = $form
        Controls = $controls
        TrayIcon = $trayIcon
        TrayMenu = $trayMenu
        Timers = $timers
        ErrorProvider = $errorProvider
        _Lifecycle = $lifecycleState
        _Disposed = $false
        _ControllerBinding = $null
    }

    $disposeView = {
        if ($this._Lifecycle.Disposed) {
            return
        }

        $this._Lifecycle.AllowClose = $true
        $this._Lifecycle.Disposed = $true
        $this._Disposed = $true
        if ($null -ne $this._ControllerBinding) {
            $this._ControllerBinding.Dispose()
            $this._ControllerBinding = $null
        }
        $this.Controls.WebhookText.UseSystemPasswordChar = $false
        $this.Controls.WebhookText.PasswordChar = [char]0x25CF
        foreach ($timer in $this.Timers.PSObject.Properties.Value) {
            $timer.Stop()
            $timer.Dispose()
        }
        $this.ErrorProvider.Clear()
        $this.ErrorProvider.Dispose()
        $this.TrayIcon.Visible = $false
        $this.TrayIcon.ContextMenuStrip = $null
        $this.TrayIcon.Dispose()
        $this.TrayMenu.Dispose()
        $this.Form.Dispose()
    }
    $view | Add-Member -MemberType ScriptMethod -Name Exit -Value $disposeView
    $view | Add-Member -MemberType ScriptMethod -Name Dispose -Value $disposeView

    return $view
}

Export-ModuleMember -Function New-AIFishBotMainView
