Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================
# FUNÃ‡Ã•ES BASE
# =========================
function Disable-ServiceSafe($name) {
    Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
}
function Enable-ServiceSafe($name) {
    Set-Service -Name $name -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name $name -ErrorAction SilentlyContinue
}
function Set-Reg($path,$name,$type,$value) {
    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name $name -Type $type -Value $value
}
function Del-Reg($path,$name) {
    Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
}
function Disable-Task($task) {
    schtasks /Change /TN $task /Disable | Out-Null
}
function Enable-Task($task) {
    schtasks /Change /TN $task /Enable | Out-Null
}

# =========================
# FORM
# =========================
$form = New-Object System.Windows.Forms.Form
$form.Text = "CheatOptimizer"
$form.Size = New-Object System.Drawing.Size(620, 540)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(12,18,28)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# =========================
# TITLE
# =========================
$title = New-Object System.Windows.Forms.Label
$title.Text = "CheatOptimizer"
$title.Font = New-Object System.Drawing.Font(
    "Segoe UI",
    18,
    [System.Drawing.FontStyle]::Bold
)
$title.ForeColor = [System.Drawing.Color]::Cyan
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($title)

# =========================
# TABS
# =========================
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Size = New-Object System.Drawing.Size(570, 390)
$tabs.Location = New-Object System.Drawing.Point(20, 60)
$form.Controls.Add($tabs)

function New-Tab($name) {
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $name
    $tab.BackColor = [System.Drawing.Color]::FromArgb(18,28,40)
    return $tab
}
function New-CheckBox($text, $y) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $text
    $cb.ForeColor = [System.Drawing.Color]::White
    $cb.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point(15, $y)
    return $cb
}


# =========================
# TAB AI
# =========================
$tabAI = New-Tab "AI / Copilot"
$tabs.TabPages.Add($tabAI)

$aiChecks = @(
    (New-CheckBox "Disable Registry Keys" 15),
    (New-CheckBox "Prevent AI Package Reinstall" 45),
    (New-CheckBox "Disable Copilot Policies" 75),
    (New-CheckBox "Remove AI Appx Packages" 105),
    (New-CheckBox "Remove Recall Optional Feature" 135),
    (New-CheckBox "Remove AI CBS Packages" 165),
    (New-CheckBox "Remove AI Files" 195),
    (New-CheckBox "Hide AI Components" 225),
    (New-CheckBox "Disable Notepad Rewrite" 255),
    (New-CheckBox "Remove Recall Tasks" 285)
)
$tabAI.Controls.AddRange($aiChecks)

# =========================
# TAB SERVICES
# =========================
$tabServices = New-Tab "Services"
$tabs.TabPages.Add($tabServices)

$svc = @{
    "SysMain"="SysMain"
    "Windows Search"="WSearch"
    "BITS"="BITS"
    "Print Spooler"="Spooler"
    "Telemetry"="DiagTrack"
    "Geolocation"="lfsvc"
    "Fax"="Fax"
    "Smart Card"="SCardSvr"
}
$svcChecks=@()
$y=15
foreach($s in $svc.Keys){
    $cb=New-CheckBox $s $y
    $svcChecks+=$cb
    $tabServices.Controls.Add($cb)
    $y+=30
}

# =========================
# TAB REGISTRY
# =========================
$tabReg = New-Tab "Registry Tweaks"
$tabs.TabPages.Add($tabReg)

$regChecks = @(
    New-CheckBox "Disable GameDVR" 15,
    New-CheckBox "Win32PrioritySeparation = 36" 45,
    New-CheckBox "Disable Multiplane Overlay" 75,
    New-CheckBox "Disable Power Throttling" 105,
    New-CheckBox "MenuShowDelay = 0" 135,
    New-CheckBox "Disable NDU" 165
)
$tabReg.Controls.AddRange($regChecks)

# =========================
# TAB TASKS
# =========================
$tabTasks = New-Tab "Tasks"
$tabs.TabPages.Add($tabTasks)

$taskChecks=@(
    New-CheckBox "Disable WinSAT" 15,
    New-CheckBox "Disable Error Reporting" 45,
    New-CheckBox "Disable Compatibility Appraiser" 75,
    New-CheckBox "Disable Diagnosis Tasks" 105
)
$tabTasks.Controls.AddRange($taskChecks)

# =========================
# BUTTONS
# =========================
function New-Button($text, $x, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size(120, 36)
    $b.Location = New-Object System.Drawing.Point($x, 470)
    $b.BackColor = [System.Drawing.Color]::FromName($color)
    $b.ForeColor = [System.Drawing.Color]::Black
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.Font = New-Object System.Drawing.Font(
        "Segoe UI",
        10,
        [System.Drawing.FontStyle]::Bold
    )
    return $b
}

$btnApply=New-Button "Apply" 70 Cyan
$btnRevert=New-Button "Revert" 240 LightSkyBlue
$btnCancel=New-Button "Cancel" 410 LightGray
$form.Controls.AddRange(@($btnApply,$btnRevert,$btnCancel))

# =========================
# APPLY
# =========================
$btnApply.Add_Click({
    if($svcChecks[0].Checked){Disable-ServiceSafe "SysMain"}
    if($svcChecks[1].Checked){Disable-ServiceSafe "WSearch"}
    if($svcChecks[2].Checked){Disable-ServiceSafe "BITS"}
    if($svcChecks[3].Checked){Disable-ServiceSafe "Spooler"}
    if($svcChecks[4].Checked){Disable-ServiceSafe "DiagTrack"}
    if($svcChecks[5].Checked){Disable-ServiceSafe "lfsvc"}
    if($svcChecks[6].Checked){Disable-ServiceSafe "Fax"}
    if($svcChecks[7].Checked){Disable-ServiceSafe "SCardSvr"}

    if($regChecks[0].Checked){
        Set-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" DWord 0
        Set-Reg "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" "Value" DWord 0
    }
    if($regChecks[1].Checked){Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" DWord 36}
    if($regChecks[2].Checked){Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "DisableMultiplaneOverlay" DWord 1}
    if($regChecks[3].Checked){
        New-Item "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Force | Out-Null
        Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" DWord 1
    }
    if($regChecks[4].Checked){Set-Reg "HKCU:\Control Panel\Desktop" "MenuShowDelay" String "0"}
    if($regChecks[5].Checked){Set-Reg "HKLM:\SYSTEM\ControlSet001\Services\Ndu" "Start" DWord 4}

    if($taskChecks[0].Checked){Disable-Task "\Microsoft\Windows\Maintenance\WinSAT"}
    if($taskChecks[1].Checked){Disable-Task "\Microsoft\Windows\Windows Error Reporting\QueueReporting"}
    if($taskChecks[2].Checked){Disable-Task "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"}
    if($taskChecks[3].Checked){Disable-Task "\Microsoft\Windows\Diagnosis\*"}
    [System.Windows.Forms.MessageBox]::Show("Applied successfully.","CheatOptimizer")
})

# =========================
# REVERT
# =========================
$btnRevert.Add_Click({
    Enable-ServiceSafe "SysMain"
    Enable-ServiceSafe "WSearch"
    Enable-ServiceSafe "BITS"
    Enable-ServiceSafe "Spooler"
    Enable-ServiceSafe "DiagTrack"
    Enable-ServiceSafe "lfsvc"
    Enable-ServiceSafe "Fax"
    Enable-ServiceSafe "SCardSvr"

    Del-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled"
    Del-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "DisableMultiplaneOverlay"
    Del-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff"

    Enable-Task "\Microsoft\Windows\Maintenance\WinSAT"
    Enable-Task "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
    Enable-Task "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"

    [System.Windows.Forms.MessageBox]::Show("Revert completed.","CheatOptimizer")
})

$btnCancel.Add_Click({$form.Close()})

$form.ShowDialog()
