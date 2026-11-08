<#
    CheatOptimizer - Windows optimizer with a WinForms GUI.
    Run in an elevated PowerShell (the script re-launches itself as Administrator if needed):

        & ([scriptblock]::Create((irm "https://raw.githubusercontent.com/cheatzera/CheatOptimizer/refs/heads/main/CheatOptimizer.ps1")))

    Every change is recorded in %ProgramData%\CheatOptimizer\backup.json so that
    "Revert" can restore the exact previous state (and falls back to Windows
    defaults when there is no record).
    NOTE: keep this file ASCII-only (it is downloaded and run through irm).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:RawUrl = 'https://raw.githubusercontent.com/cheatzera/CheatOptimizer/refs/heads/main/CheatOptimizer.ps1'

# =========================
# PRE-FLIGHT: version + admin
# =========================
if ($PSVersionTable.PSVersion.Major -lt 5) {
    [void][System.Windows.Forms.MessageBox]::Show("PowerShell 5.1 or newer is required.", "CheatOptimizer")
    return
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $exe = (Get-Process -Id $PID).Path
        if ($PSCommandPath) {
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
        } else {
            $cmd = "& ([scriptblock]::Create((irm '{0}')))" -f $script:RawUrl
            $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
        }
        Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show("Administrator privileges are required.`r`nRight-click PowerShell > Run as administrator and try again.", "CheatOptimizer")
    }
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# =========================
# STATE / BACKUP
# =========================
$script:BackupDir  = Join-Path $env:ProgramData 'CheatOptimizer'
$script:BackupFile = Join-Path $script:BackupDir 'backup.json'
$script:Backup     = @{ Registry = @(); Keys = @(); Services = @(); Tasks = @() }
$script:LogBox     = $null

function Add-Log($msg) {
    if ($script:LogBox) {
        $script:LogBox.AppendText("$msg`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Save-Backup {
    try {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
        $script:Backup | ConvertTo-Json -Depth 6 | Set-Content -Path $script:BackupFile -Encoding UTF8
    } catch {
        Add-Log "WARNING: could not save backup file: $($_.Exception.Message)"
    }
}

function Import-Backup {
    if (-not (Test-Path -LiteralPath $script:BackupFile)) { return }
    try {
        $j = Get-Content -LiteralPath $script:BackupFile -Raw | ConvertFrom-Json
        foreach ($k in @('Registry', 'Keys', 'Services', 'Tasks')) {
            if ($j.$k) { $script:Backup[$k] = @($j.$k) } else { $script:Backup[$k] = @() }
        }
    } catch {
        # corrupt backup -> start clean
    }
}

# =========================
# REGISTRY HELPERS
# =========================
function Backup-RegValue($path, $name) {
    if (@($script:Backup.Registry | Where-Object { $_.Path -eq $path -and $_.Name -eq $name }).Count -gt 0) { return }
    $entry = @{ Path = $path; Name = $name; Existed = $false; Value = $null; Kind = $null }
    try {
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($key.GetValueNames() -contains $name) {
            $entry.Existed = $true
            $entry.Value   = $key.GetValue($name, $null, 'DoNotExpandEnvironmentVariables')
            $entry.Kind    = $key.GetValueKind($name).ToString()
        }
    } catch { }
    $script:Backup.Registry += $entry
}

function ConvertTo-RegValue($kind, $value) {
    switch ($kind) {
        'DWord'  { return [int]$value }
        'QWord'  { return [long]$value }
        'String' { return [string]$value }
        'ExpandString' { return [string]$value }
        default  { return $value }
    }
}

function Write-RegValue($path, $name, $kind, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name $name -PropertyType $kind -Value (ConvertTo-RegValue $kind $value) -Force | Out-Null
}

function Set-Reg($path, $name, $kind, $value) {
    Backup-RegValue $path $name
    Write-RegValue $path $name $kind $value
    Add-Log "  set $path\$name = $value"
}

function Restore-Reg($path, $name, $defaultValue = $null, $defaultKind = 'DWord') {
    $entry = @($script:Backup.Registry | Where-Object { $_.Path -eq $path -and $_.Name -eq $name }) | Select-Object -First 1
    if ($entry) {
        if ($entry.Existed) {
            Write-RegValue $path $name $entry.Kind $entry.Value
            Add-Log "  restored $path\$name"
        } else {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
            Add-Log "  removed $path\$name"
        }
        $script:Backup.Registry = @($script:Backup.Registry | Where-Object { -not ($_.Path -eq $path -and $_.Name -eq $name) })
    } elseif ($null -ne $defaultValue) {
        Write-RegValue $path $name $defaultKind $defaultValue
        Add-Log "  default $path\$name = $defaultValue"
    } else {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
        Add-Log "  removed $path\$name"
    }
}

function New-RegKeyTracked($path) {
    if (Test-Path -LiteralPath $path) { return }
    New-Item -Path $path -Force | Out-Null
    $script:Backup.Keys += $path
    Add-Log "  created key $path"
}

function Remove-RegKeyTracked($path) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
        Add-Log "  removed key $path"
    }
    $script:Backup.Keys = @($script:Backup.Keys | Where-Object { $_ -ne $path })
}

# =========================
# SERVICE HELPERS
# =========================
function Set-ServiceStartMode($name, $mode, $delayed) {
    Set-Service -Name $name -StartupType $mode -ErrorAction Stop
    if ($mode -eq 'Automatic') {
        $sc = if ($delayed) { 'delayed-auto' } else { 'auto' }
        & sc.exe config $name start= $sc | Out-Null
    }
}

function Disable-ServiceSafe($name) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) { Add-Log "  service $name not present, skipped"; return }

    if (@($script:Backup.Services | Where-Object { $_.Name -eq $name }).Count -eq 0) {
        $cim  = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        $mode = switch ($cim.StartMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { 'Manual' } }
        $delayed = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$name" -Name DelayedAutostart -ErrorAction SilentlyContinue).DelayedAutostart -eq 1
        $script:Backup.Services += @{ Name = $name; StartMode = $mode; Delayed = $delayed; WasRunning = ($svc.Status -eq 'Running') }
    }
    Set-ServiceStartMode $name 'Disabled' $false
    if ($svc.Status -ne 'Stopped') { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
    Add-Log "  service $name disabled"
}

function Restore-ServiceSafe($name, $defaultMode, $defaultDelayed = $false) {
    if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { Add-Log "  service $name not present, skipped"; return }
    $entry = @($script:Backup.Services | Where-Object { $_.Name -eq $name }) | Select-Object -First 1
    if ($entry) {
        $mode = $entry.StartMode; $delayed = [bool]$entry.Delayed; $run = [bool]$entry.WasRunning
    } else {
        $mode = $defaultMode; $delayed = $defaultDelayed; $run = ($defaultMode -eq 'Automatic')
    }
    Set-ServiceStartMode $name $mode $delayed
    if ($run) { Start-Service -Name $name -ErrorAction SilentlyContinue }
    $script:Backup.Services = @($script:Backup.Services | Where-Object { $_.Name -ne $name })
    Add-Log "  service $name restored ($mode)"
}

# =========================
# SCHEDULED TASK HELPERS
# =========================
function Disable-TaskSafe($taskPath, $taskName = '*') {
    $tasks = @(Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue)
    if ($tasks.Count -eq 0) { Add-Log "  no task found at $taskPath$taskName"; return }
    foreach ($t in $tasks) {
        if ($t.State -eq 'Disabled') { continue }
        $full = "$($t.TaskPath)$($t.TaskName)"
        try {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
        } catch {
            & schtasks.exe /Change /TN $full /Disable 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Add-Log "  could not disable $full"; continue }
        }
        if (@($script:Backup.Tasks | Where-Object { $_.Path -eq $t.TaskPath -and $_.Name -eq $t.TaskName }).Count -eq 0) {
            $script:Backup.Tasks += @{ Path = $t.TaskPath; Name = $t.TaskName }
        }
        Add-Log "  task disabled: $full"
    }
}

function Enable-TaskSafe($taskPath, $taskName = '*') {
    $entries = @($script:Backup.Tasks | Where-Object { $_.Path -eq $taskPath -and ($taskName -eq '*' -or $_.Name -eq $taskName) })
    if ($entries.Count -eq 0) {
        $entries = @(Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue |
            ForEach-Object { @{ Path = $_.TaskPath; Name = $_.TaskName } })
    }
    foreach ($e in $entries) {
        $full = "$($e.Path)$($e.Name)"
        try {
            Enable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction Stop | Out-Null
        } catch {
            & schtasks.exe /Change /TN $full /Enable 2>&1 | Out-Null
        }
        Add-Log "  task enabled: $full"
    }
    $script:Backup.Tasks = @($script:Backup.Tasks | Where-Object { -not ($_.Path -eq $taskPath -and ($taskName -eq '*' -or $_.Name -eq $taskName)) })
}

function New-SafeRestorePoint {
    try {
        Checkpoint-Computer -Description 'CheatOptimizer' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Add-Log 'Restore point created.'
    } catch {
        Add-Log "Restore point skipped: $($_.Exception.Message)"
    }
}

# =========================
# OPTIONS (what each checkbox does)
# =========================
function New-Option($Tab, $Text, $Tip, [scriptblock]$Apply, [scriptblock]$Revert, $Warn = '') {
    [pscustomobject]@{ Tab = $Tab; Text = $Text; Tip = $Tip; Apply = $Apply; Revert = $Revert; Warn = $Warn }
}

$script:Options = @()

# ---------- AI / Copilot ----------
$script:Options += New-Option 'AI / Copilot' 'Disable AI registry keys (Recall, Click to Do)' `
    'Policies that turn off Recall snapshots, AI data analysis and Click to Do.' `
    {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' DWord 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' DWord 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' DWord 1
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'TurnOffSavingSnapshots' DWord 1
        Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' DWord 1
    } `
    {
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis'
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement'
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo'
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'TurnOffSavingSnapshots'
        Restore-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis'
    }

$script:Options += New-Option 'AI / Copilot' 'Prevent AI package reinstall' `
    'Marks Copilot packages as deprovisioned so Windows does not reinstall them for new users / updates.' `
    {
        $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
        foreach ($fam in 'Microsoft.Windows.Ai.Copilot.Provider_8wekyb3d8bbwe', 'MicrosoftWindows.Client.CoPilot_cw5n1h2txyewy', 'Microsoft.Copilot_8wekyb3d8bbwe') {
            New-RegKeyTracked "$base\$fam"
        }
    } `
    {
        $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
        foreach ($fam in 'Microsoft.Windows.Ai.Copilot.Provider_8wekyb3d8bbwe', 'MicrosoftWindows.Client.CoPilot_cw5n1h2txyewy', 'Microsoft.Copilot_8wekyb3d8bbwe') {
            Remove-RegKeyTracked "$base\$fam"
        }
    }

$script:Options += New-Option 'AI / Copilot' 'Disable Copilot policies (and taskbar button)' `
    'TurnOffWindowsCopilot policy for machine and user, and hides the Copilot taskbar button.' `
    {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' DWord 1
        Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' DWord 1
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' DWord 0
    } `
    {
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'
        Restore-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot'
        Restore-Reg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 1
    }

$script:Options += New-Option 'AI / Copilot' 'Remove AI Appx packages' `
    'Uninstalls Copilot / AI provider packages for all users and removes them from the provisioned list.' `
    {
        $names = 'Microsoft.Copilot', 'MicrosoftWindows.Client.CoPilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftWindows.Client.AIX', 'MicrosoftWindows.Client.CoreAI'
        foreach ($n in $names) {
            $found = $false
            foreach ($p in @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)) {
                $found = $true
                try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Add-Log "  removed $($p.Name)" }
                catch { Add-Log "  could not remove $($p.Name): $($_.Exception.Message)" }
            }
            foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $n })) {
                $found = $true
                try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null; Add-Log "  deprovisioned $($p.DisplayName)" }
                catch { Add-Log "  could not deprovision $($p.DisplayName): $($_.Exception.Message)" }
            }
            if (-not $found) { Add-Log "  $n not installed" }
        }
    } `
    { Add-Log '  Appx removal cannot be reverted automatically (reinstall from the Microsoft Store).' } `
    'Remove AI Appx packages: cannot be undone automatically.'

$script:Options += New-Option 'AI / Copilot' 'Disable Recall optional feature' `
    'Disables the Windows "Recall" optional feature (payload is kept, so it can be re-enabled).' `
    {
        $f = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue
        if (-not $f) { Add-Log '  Recall feature not present on this Windows build'; return }
        if ($f.State -eq 'Disabled') { Add-Log '  Recall already disabled'; return }
        Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop | Out-Null
        Add-Log '  Recall feature disabled'
    } `
    {
        $f = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue
        if (-not $f) { Add-Log '  Recall feature not present'; return }
        Enable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction Stop | Out-Null
        Add-Log '  Recall feature enabled'
    }

$script:Options += New-Option 'AI / Copilot' 'Remove AI CBS packages (experimental)' `
    'Removes hidden Component Based Servicing packages related to Recall / Copilot / AI.' `
    {
        $pkgs = @(Get-WindowsPackage -Online -ErrorAction Stop | Where-Object { $_.PackageState -eq 'Installed' -and $_.PackageName -match 'Recall|Copilot|[-_.~]AIX|CoreAI' })
        if ($pkgs.Count -eq 0) { Add-Log '  no AI CBS packages found'; return }
        foreach ($p in $pkgs) {
            $k = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages\$($p.PackageName)"
            try { Set-ItemProperty -LiteralPath $k -Name Visibility -Value 1 -ErrorAction Stop } catch { }
            try { Remove-WindowsPackage -Online -PackageName $p.PackageName -NoRestart -ErrorAction Stop | Out-Null; Add-Log "  removed $($p.PackageName)" }
            catch { Add-Log "  could not remove $($p.PackageName): $($_.Exception.Message)" }
        }
    } `
    { Add-Log '  CBS package removal cannot be reverted automatically.' } `
    'Remove AI CBS packages (experimental): cannot be undone automatically.'

$script:Options += New-Option 'AI / Copilot' 'Delete Recall data (snapshots)' `
    'Deletes the Recall snapshot database/images stored for the current user.' `
    {
        $dir = Join-Path $env:LOCALAPPDATA 'CoreAIPlatform.00'
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop; Add-Log "  deleted $dir" }
        else { Add-Log '  no Recall data found' }
    } `
    { Add-Log '  deleted data cannot be restored.' } `
    'Delete Recall data: deleted snapshots cannot be restored.'

$script:Options += New-Option 'AI / Copilot' 'Hide AI components in Settings' `
    'Hides the "AI components" and "App actions" pages in Settings (SettingsPageVisibility policy).' `
    {
        $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
        $cur = [string](Get-ItemProperty -Path $p -Name SettingsPageVisibility -ErrorAction SilentlyContinue).SettingsPageVisibility
        $items = @('aicomponents', 'appactions')
        if ($cur -like 'showonly:*') { Add-Log '  SettingsPageVisibility uses showonly: - left untouched'; return }
        if ($cur -like 'hide:*') {
            $existing = @($cur.Substring(5).Split(';') | Where-Object { $_ })
            $items = @($existing + $items | Select-Object -Unique)
        }
        Set-Reg $p 'SettingsPageVisibility' String ('hide:' + ($items -join ';'))
    } `
    { Restore-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' }

$script:Options += New-Option 'AI / Copilot' 'Disable Notepad Rewrite / AI' `
    'Turns off the AI features (Rewrite, Summarize...) in Notepad.' `
    { Set-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' DWord 1 } `
    { Restore-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' }

$script:Options += New-Option 'AI / Copilot' 'Disable Recall / AI scheduled tasks' `
    'Disables every scheduled task under \Microsoft\Windows\WindowsAI\.' `
    { Disable-TaskSafe '\Microsoft\Windows\WindowsAI\' } `
    { Enable-TaskSafe '\Microsoft\Windows\WindowsAI\' }

# ---------- Services ----------
$serviceDefs = @(
    @('SysMain (Superfetch)',            'SysMain',  'Automatic', $false, 'Prefetching/caching service. Usually safe to disable on SSDs.', ''),
    @('Windows Search (indexing)',       'WSearch',  'Automatic', $true,  'File indexing. Start-menu / Explorer search gets slower.', ''),
    @('BITS (Background Transfer)',      'BITS',     'Manual',    $false, 'Used by Windows Update and Store for downloads.', 'BITS: Windows Update / Store downloads may stop working.'),
    @('Print Spooler',                   'Spooler',  'Automatic', $false, 'Required for printing.', 'Print Spooler: you will NOT be able to print.'),
    @('Telemetry (DiagTrack)',           'DiagTrack','Automatic', $false, 'Connected User Experiences and Telemetry.', ''),
    @('Geolocation (lfsvc)',             'lfsvc',    'Manual',    $false, 'Location service.', ''),
    @('Fax',                             'Fax',      'Manual',    $false, 'Fax service (not present on most systems).', ''),
    @('Smart Card',                      'SCardSvr', 'Manual',    $false, 'Smart-card reader support.', 'Smart Card: smart-card / some token logins will stop working.')
)
foreach ($d in $serviceDefs) {
    $svcName = $d[1]; $svcMode = $d[2]; $svcDelayed = $d[3]
    $applyBlock  = [scriptblock]::Create("Disable-ServiceSafe '$svcName'")
    $revertBlock = [scriptblock]::Create("Restore-ServiceSafe '$svcName' '$svcMode' `$$svcDelayed")
    $script:Options += New-Option 'Services' $d[0] $d[4] $applyBlock $revertBlock $d[5]
}

# ---------- Registry tweaks ----------
$script:Options += New-Option 'Registry Tweaks' 'Disable GameDVR' `
    'Turns off Game Bar background recording / capture.' `
    {
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' DWord 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' DWord 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' DWord 0
    } `
    {
        Restore-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
        Restore-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
        Restore-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
    }

$script:Options += New-Option 'Registry Tweaks' 'Win32PrioritySeparation = 36' `
    'Foreground/background CPU scheduling quantum (Windows default is 2).' `
    { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' DWord 36 } `
    { Restore-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 2 }

$script:Options += New-Option 'Registry Tweaks' 'Disable Multiplane Overlay (MPO)' `
    'Sets Dwm OverlayTestMode=5. Can fix stutter/flicker on some GPUs. Needs a restart.' `
    { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' DWord 5 } `
    { Restore-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' }

$script:Options += New-Option 'Registry Tweaks' 'Disable Power Throttling' `
    'Stops Windows from throttling background processes to save power.' `
    { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' DWord 1 } `
    { Restore-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' }

$script:Options += New-Option 'Registry Tweaks' 'MenuShowDelay = 0' `
    'Menus open instantly (Windows default is 400 ms). Applies after sign-out.' `
    { Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' String '0' } `
    { Restore-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '400' 'String' }

$script:Options += New-Option 'Registry Tweaks' 'Disable NDU' `
    'Disables the Network Data Usage monitor driver (known to leak memory). Needs a restart.' `
    { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' 'Start' DWord 4 } `
    { Restore-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Ndu' 'Start' 2 }

# ---------- Tasks ----------
$script:Options += New-Option 'Tasks' 'Disable WinSAT' `
    'Windows System Assessment Tool scheduled task.' `
    { Disable-TaskSafe '\Microsoft\Windows\Maintenance\' 'WinSAT' } `
    { Enable-TaskSafe '\Microsoft\Windows\Maintenance\' 'WinSAT' }

$script:Options += New-Option 'Tasks' 'Disable Error Reporting' `
    'Windows Error Reporting queue task.' `
    { Disable-TaskSafe '\Microsoft\Windows\Windows Error Reporting\' 'QueueReporting' } `
    { Enable-TaskSafe '\Microsoft\Windows\Windows Error Reporting\' 'QueueReporting' }

$script:Options += New-Option 'Tasks' 'Disable Compatibility Appraiser' `
    'Microsoft Compatibility Appraiser telemetry task.' `
    { Disable-TaskSafe '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser' } `
    { Enable-TaskSafe '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser' }

$script:Options += New-Option 'Tasks' 'Disable Diagnosis tasks' `
    'All scheduled tasks under \Microsoft\Windows\Diagnosis\.' `
    { Disable-TaskSafe '\Microsoft\Windows\Diagnosis\' } `
    { Enable-TaskSafe '\Microsoft\Windows\Diagnosis\' }

# =========================
# FORM
# =========================
function New-Tab($name) {
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $name
    $tab.UseVisualStyleBackColor = $false
    $tab.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 40)
    $tab.AutoScroll = $true
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

function New-Button($text, $x, $y, $w, $h, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.BackColor = [System.Drawing.Color]::FromName($color)
    $b.ForeColor = [System.Drawing.Color]::Black
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    return $b
}

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = "CheatOptimizer"
$script:Form.ClientSize = New-Object System.Drawing.Size(620, 640)
$script:Form.StartPosition = "CenterScreen"
$script:Form.BackColor = [System.Drawing.Color]::FromArgb(12, 18, 28)
$script:Form.FormBorderStyle = "FixedDialog"
$script:Form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "CheatOptimizer"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::Cyan
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 12)
$script:Form.Controls.Add($title)

$script:Tabs = New-Object System.Windows.Forms.TabControl
$script:Tabs.Size = New-Object System.Drawing.Size(580, 360)
$script:Tabs.Location = New-Object System.Drawing.Point(20, 55)
$script:Form.Controls.Add($script:Tabs)

$script:Tip = New-Object System.Windows.Forms.ToolTip
$script:Tip.AutoPopDelay = 15000

$script:Checks = @()
$tabPages = @{}
foreach ($tabName in @('AI / Copilot', 'Services', 'Registry Tweaks', 'Tasks')) {
    $page = New-Tab $tabName
    $script:Tabs.TabPages.Add($page)
    $tabPages[$tabName] = $page
    $y = 15
    foreach ($o in ($script:Options | Where-Object { $_.Tab -eq $tabName })) {
        $cb = New-CheckBox $o.Text $y
        $cb.Tag = $o
        $script:Tip.SetToolTip($cb, $o.Tip)
        $page.Controls.Add($cb)
        $script:Checks += $cb
        $y += 30
    }
}

# Select all / clear (current tab) + restore point option
$btnAll   = New-Button "Select all" 20  422 100 28 "LightGray"
$btnNone  = New-Button "Clear"      126 422 80  28 "LightGray"
$script:Form.Controls.AddRange(@($btnAll, $btnNone))

$script:ChkRestore = New-Object System.Windows.Forms.CheckBox
$script:ChkRestore.Text = "Create restore point before applying"
$script:ChkRestore.ForeColor = [System.Drawing.Color]::White
$script:ChkRestore.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$script:ChkRestore.AutoSize = $true
$script:ChkRestore.Checked = $true
$script:ChkRestore.Location = New-Object System.Drawing.Point(330, 427)
$script:Form.Controls.Add($script:ChkRestore)

# Log box
$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(8, 12, 20)
$script:LogBox.ForeColor = [System.Drawing.Color]::LightGreen
$script:LogBox.Location = New-Object System.Drawing.Point(20, 460)
$script:LogBox.Size = New-Object System.Drawing.Size(580, 120)
$script:Form.Controls.Add($script:LogBox)

# Action buttons
$btnApply  = New-Button "Apply"  70  592 120 36 "Cyan"
$btnRevert = New-Button "Revert" 250 592 120 36 "LightSkyBlue"
$btnCancel = New-Button "Cancel" 430 592 120 36 "LightGray"
$script:Form.Controls.AddRange(@($btnApply, $btnRevert, $btnCancel))
$script:ActionButtons = @($btnApply, $btnRevert, $btnCancel, $btnAll, $btnNone)

function Set-Busy($busy) {
    foreach ($b in $script:ActionButtons) { $b.Enabled = -not $busy }
    $script:Form.UseWaitCursor = $busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-Selected { @($script:Checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }) }

function Show-Info($text) {
    [void][System.Windows.Forms.MessageBox]::Show($text, "CheatOptimizer", 'OK', 'Information')
}

$btnAll.Add_Click({
    foreach ($c in $script:Tabs.SelectedTab.Controls) { if ($c -is [System.Windows.Forms.CheckBox]) { $c.Checked = $true } }
})
$btnNone.Add_Click({
    foreach ($c in $script:Tabs.SelectedTab.Controls) { if ($c -is [System.Windows.Forms.CheckBox]) { $c.Checked = $false } }
})

# =========================
# APPLY
# =========================
$btnApply.Add_Click({
    $selected = Get-Selected
    if ($selected.Count -eq 0) { Show-Info "Nothing selected."; return }

    $warns = @($selected | Where-Object { $_.Warn } | ForEach-Object { " - " + $_.Warn })
    if ($warns.Count -gt 0) {
        $msg = "Some selected options have side effects:`r`n`r`n" + ($warns -join "`r`n") + "`r`n`r`nContinue?"
        $r = [System.Windows.Forms.MessageBox]::Show($msg, "CheatOptimizer", 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }

    $failed = 0
    Set-Busy $true
    try {
        $ErrorActionPreference = 'Stop'
        $script:LogBox.Clear()
        Import-Backup
        if ($script:ChkRestore.Checked) { New-SafeRestorePoint }
        foreach ($o in $selected) {
            Add-Log "Applying: $($o.Text)"
            try { & $o.Apply }
            catch { $failed++; Add-Log "  ERROR: $($_.Exception.Message)" }
        }
        Save-Backup
    } finally {
        Set-Busy $false
    }

    $text = "Applied $($selected.Count - $failed) of $($selected.Count) option(s)."
    if ($failed -gt 0) { $text += "`r`n$failed failed - see the log for details." }
    $text += "`r`nA restart is recommended for all changes to take effect."
    Show-Info $text
})

# =========================
# REVERT
# =========================
$btnRevert.Add_Click({
    $selected = Get-Selected
    if ($selected.Count -eq 0) { Show-Info "Select the options you want to revert first."; return }

    $failed = 0
    Set-Busy $true
    try {
        $ErrorActionPreference = 'Stop'
        $script:LogBox.Clear()
        Import-Backup
        foreach ($o in $selected) {
            Add-Log "Reverting: $($o.Text)"
            try { & $o.Revert }
            catch { $failed++; Add-Log "  ERROR: $($_.Exception.Message)" }
        }
        Save-Backup
    } finally {
        Set-Busy $false
    }

    $text = "Reverted $($selected.Count - $failed) of $($selected.Count) option(s)."
    if ($failed -gt 0) { $text += "`r`n$failed failed - see the log for details." }
    $text += "`r`nRemovals (Appx / CBS packages, deleted data) cannot be restored automatically."
    Show-Info $text
})

$btnCancel.Add_Click({ $script:Form.Close() })

Import-Backup
[void]$script:Form.ShowDialog()
