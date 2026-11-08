# computer-help-main
# Computer Help: a small window with big buttons for Brad's in-laws.
# It checks the PC (read-only, nothing is changed) and sends the report
# straight to Brad.
# Launcher.ps1 replaces this file with the GitHub copy on every start, so bump
# $Version with every change. Personal settings live in config.json, never here.
# Test without the window:  powershell -ExecutionPolicy Bypass -File ComputerHelp.ps1 -ReportOnly
param([switch]$ReportOnly)

$Version = '2026.11.08.1'

$cfgPath = Join-Path $PSScriptRoot 'config.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }

# ---- The check (read-only) ----
function Section($title, [scriptblock]$body) {
    $text = try { (& $body | Out-String).TrimEnd() } catch { "(could not check: $($_.Exception.Message))" }
    "== $title ==`r`n$text`r`n"
}

function Get-Report {
    $since = (Get-Date).AddDays(-7)
    $parts = @(
        Section 'Computer' {
            $os  = Get-CimInstance Win32_OperatingSystem
            $cs  = Get-CimInstance Win32_ComputerSystem
            $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            $up  = (Get-Date) - $os.LastBootUpTime
            "Windows: $($os.Caption) (build $($os.BuildNumber))"
            "Model: $($cs.Manufacturer) $($cs.Model)"
            $load = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
            "Processor: $($cpu.Name.Trim()), busy right now: $load%"
            "Memory: {0:N1} GB total, {1:N1} GB free" -f ($cs.TotalPhysicalMemory / 1GB), ($os.FreePhysicalMemory / 1MB)
            "Last restart: $([int][math]::Floor($up.TotalDays)) days $($up.Hours) hours ago"
        }
        Section 'Disk' {
            Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
                "{0} {1:N0} GB free of {2:N0} GB ({3:N0}% free)" -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB), (100 * $_.FreeSpace / $_.Size)
            }
            Get-PhysicalDisk | ForEach-Object { "Drive '$($_.FriendlyName)': $($_.MediaType), health $($_.HealthStatus)" }
            $temp = (Get-ChildItem $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            "Temp files: {0:N1} GB" -f ($temp / 1GB)
        }
        Section 'Busiest programs right now (processor)' {
            $cores = [int]$env:NUMBER_OF_PROCESSORS
            Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
                Where-Object { $_.Name -notin '_Total', 'Idle' } |
                Sort-Object PercentProcessorTime -Descending | Select-Object -First 5 |
                ForEach-Object { "{0}: {1}%" -f $_.Name, [math]::Round($_.PercentProcessorTime / $cores) }
        }
        Section 'Biggest programs (memory)' {
            Get-Process | Group-Object ProcessName | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Count = $_.Count; MB = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB }
            } | Sort-Object MB -Descending | Select-Object -First 8 |
                ForEach-Object { "{0} ({1} running): {2:N0} MB" -f $_.Name, $_.Count, $_.MB }
        }
        Section 'Programs that start with Windows' {
            $s = Get-CimInstance Win32_StartupCommand | Select-Object -ExpandProperty Name -Unique
            "$(@($s).Count) programs: $($s -join ', ')"
        }
        Section 'Security' {
            $av = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
            "Antivirus installed: $(($av.displayName | Select-Object -Unique) -join ', ')"
            $d = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if ($d) {
                "Defender real-time protection: $($d.RealTimeProtectionEnabled)"
                "Defender virus definitions age: $($d.AntivirusSignatureAge) days, last quick scan: $($d.QuickScanAge) days ago"
                $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt $since })
                "Threats found in last 7 days: $($threats.Count)"
            }
        }
        Section 'Windows Update' {
            $last = Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
            "Last update installed: $($last.InstalledOn.ToString('yyyy-MM-dd'))"
            $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                       (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
            "Waiting for a restart to finish updates: $pending"
        }
        Section 'Problems in the last 7 days' {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -MaxEvents 3000 -ErrorAction SilentlyContinue)
            "Error entries: $($ev.Count). Most common (count, source, event id):"
            $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 8 |
                ForEach-Object { "  $($_.Count)x $($_.Name)" }
            $power = @($ev | Where-Object { $_.Id -eq 41 -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' })
            "Sudden shutdowns or freezes: $($power.Count)"
            $crashes = $ev | Where-Object { $_.Id -eq 1000 -and $_.ProviderName -eq 'Application Error' } |
                ForEach-Object { $_.Properties[0].Value } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5
            "Programs that crashed: $(($crashes | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ', ')"
        }
        Section 'Internet' {
            "Internet reachable: $(Test-Connection 1.1.1.1 -Count 2 -Quiet)"
            "Websites resolve: $([bool](Resolve-DnsName google.com -QuickTimeout -ErrorAction SilentlyContinue))"
        }
        Section 'Battery' {
            $b = Get-CimInstance Win32_Battery
            if ($b) { "Charge: $($b.EstimatedChargeRemaining)%" } else { 'No battery (desktop)' }
        }
    )
    $text = ($parts -join "`r`n")
    # Keep the user and PC names out of what gets pasted to the AI.
    foreach ($name in $env:USERNAME, $env:COMPUTERNAME) {
        if ($name.Length -ge 3) { $text = $text -replace [regex]::Escape($name), '<name>' }
    }
    $text
}

if ($ReportOnly) { Get-Report; return }

# ---- The window ----
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Computer Help'
$form.ClientSize = New-Object System.Drawing.Size(560, 470)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 15)

$label = New-Object System.Windows.Forms.Label
$label.SetBounds(20, 10, 520, 110)
$label.TextAlign = 'MiddleCenter'
$label.Text = "What's wrong? You can type it here,`r`nor just press the green button."
$form.Controls.Add($label)

$note = New-Object System.Windows.Forms.TextBox
$note.Multiline = $true
$note.SetBounds(40, 125, 480, 110)
$form.Controls.Add($note)

function New-BigButton($text, $top, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.SetBounds(60, $top, 440, 80)
    $b.Text = $text
    $b.FlatStyle = 'Flat'
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($b)
    $b
}
$bradButton  = New-BigButton 'Send to Brad'              255 ([System.Drawing.Color]::FromArgb(30, 140, 80))
$closeButton = New-BigButton 'Close'                      0   ([System.Drawing.Color]::Gray)
$closeButton.SetBounds(180, 360, 200, 55)
$versionLabel = New-Object System.Windows.Forms.Label
$versionLabel.SetBounds(400, 445, 155, 20)
$versionLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$versionLabel.ForeColor = [System.Drawing.Color]::Gray
$versionLabel.Text = "version $Version"
$form.Controls.Add($versionLabel)

$script:report = $null
function Get-CachedReport {
    if (-not $script:report) {
        $label.Text = "Checking your computer...`r`nThis takes about 20 seconds."
        $form.Cursor = 'WaitCursor'
        $form.Refresh()
        $script:report = Get-Report
        $form.Cursor = 'Default'
    }
    $script:report
}

$bradButton.Add_Click({
    $report = Get-CachedReport
    $label.Text = 'Sending to Brad...'
    $form.Refresh()
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $json = @{ key = $cfg.key; who = $cfg.who; version = $Version; note = $note.Text; report = $report } | ConvertTo-Json
        $answer = Invoke-RestMethod -Uri $cfg.uploadUrl -Method Post -TimeoutSec 60 `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json))
        if ("$answer".Trim() -ne 'ok') { throw "server answered: $answer" }
        $label.Text = "Sent! Brad has your report.`r`nHe will get back to you."
    } catch {
        # Upload failed (no internet, setup problem): fall back to an email they send themselves.
        $text = "What's going wrong: $($note.Text)`r`n`r`n$report`r`n`r`n(Upload failed: $($_.Exception.Message))"
        Set-Content -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Computer report for Brad.txt') -Value $text -Encoding UTF8
        Set-Clipboard -Value $text
        $subject = [uri]::EscapeDataString('Computer help report')
        $body = [uri]::EscapeDataString("Hi Brad,`r`n`r`n(Click here and press Ctrl + V to paste the report.)`r`n`r`n")
        Start-Process "mailto:$($cfg.bradEmail)?subject=$subject&body=$body"
        $label.Text = "Couldn't send it by itself.`r`nAn email is opening: click in it, press Ctrl + V, then Send.`r`n(The report is also on your desktop.)"
    }
})

$closeButton.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
# end-of-computer-help
