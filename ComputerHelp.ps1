# computer-help-main
# Computer Help: a small window with one big button for Brad's in-laws.
# It checks the PC (read-only, nothing is changed) and sends the report straight to Brad.
# Every 5 minutes a hidden task runs this file with -Record: it logs a history line
# and runs any check Brad has published. Fixes wait for a click in the window.
# Updates and Brad's requests only run when signed with Brad's key (tools\Sign.ps1),
# so bump $Version and re-sign with every change. Personal settings live in config.json.
# Test without the window:  powershell -ExecutionPolicy Bypass -File ComputerHelp.ps1 -ReportOnly
param([switch]$ReportOnly, [switch]$Record, [switch]$Setup)

$Version   = '2026.11.08.3'
$Dir       = $PSScriptRoot
$RepoRaw   = 'https://raw.githubusercontent.com/AyaProfiles/computer-help/main'
$TaskName  = 'Computer Help recorder'
$History   = Join-Path $Dir 'history.csv'
$DoneFile  = Join-Path $Dir 'requests-done.txt'
$PublicKey = '<RSAKeyValue><Modulus>u5MDLLOaAuRnhR2cR9Gn9GB+cOnKjL3+IHiOYV8GflxGN3miag4S/yBPsaGfAdWsMpPVbagUBoy4OXkxDTmT9ddsO0o7RYJvJrcKHZ0RvLKh0DdACsmcHEPoMVrwpy21E3UeMNWUsKFG67s12x+if6aErMuAMMI45hIhxpK5Jgs3DEzGgtvrvCXv0xPpVo2WjrtwuizIa+9HJcu60POLIRvNMTINqkoO9mNfsVEqlYcbjiwt3Pv28AQxoT0m0wk4wWmZj6IOj8KQUgxTKkRDpPbNLbw/AfkliSrqyrMwWpzCiePP4Gp9pstihwKyzJQaXkTcOvdwO3FaKuiae9SrIPNYWWtgkR+dX8nNbGT521WKPjKIEp6mhZWrKejMaxNCeJ2f+EPphPw+XPYM4MQdcaag5SfGLC5CJyPloMGXSxKiMCD307Q5mR9bP5e8Cwpp1ZEpeK1yv/+NCEijqJHLA30NHIUv7xHP6vyhZ0kb+T5GBQ6eDE9vK4Uihf677Xnd</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'

$cfgPath = Join-Path $Dir 'config.json'
$cfg = if (Test-Path $cfgPath) { Get-Content $cfgPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Each PC has a short id (config "id"; older configs fall back to their name), which
# picks its own request file, requests/<id>.ps1, so a fix can only reach the PC it is for.
$PcId = if ($cfg.id) { $cfg.id } else { ("$($cfg.who)".ToLower() -replace "'", '' -replace '[^a-z0-9]+', '-').Trim('-') }
$RecordMinutes = if ($cfg.recordMinutes) { [int]$cfg.recordMinutes } else { 5 }

# The launcher the desktop icon runs. This file writes it (Install-Parts), so it
# changes only through a signed update of this file.
$LauncherTemplate = @'
# Computer Help launcher. Written by ComputerHelp.ps1: change it there, not here.
# Fetches the newest ComputerHelp.ps1 from GitHub and keeps it only if Brad's
# signature checks out, then runs it. Offline or unsigned: runs the copy it has.
param([switch]$UpdateOnly)
$main = Join-Path $PSScriptRoot 'ComputerHelp.ps1'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $c = (Invoke-WebRequest '__URL__' -UseBasicParsing -TimeoutSec 15).Content
    if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
    $new = $c -replace "`r", ''
    $m = [regex]::Match($new, '(?s)^(.*\n)# signature: ([A-Za-z0-9+/=]+)\s*$')
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $rsa.FromXmlString('__KEY__')
    if ($m.Success -and $rsa.VerifyData([Text.Encoding]::UTF8.GetBytes($m.Groups[1].Value), 'SHA256', [Convert]::FromBase64String($m.Groups[2].Value))) {
        $old = if (Test-Path $main) { (Get-Content $main -Raw) -replace "`r", '' } else { '' }
        if ($old -ne $new) {
            [IO.File]::WriteAllText("$main.new", $new)
            Move-Item -Path "$main.new" -Destination $main -Force
        }
    }
} catch { }
if (-not $UpdateOnly) { & $main }
'@

# ---- Signatures ----
# Returns the text without its signature line if Brad signed it, otherwise $null.
function Get-SignedBody($text) {
    $text = "$text" -replace "`r", ''
    $m = [regex]::Match($text, '(?s)^(.*\n)# signature: ([A-Za-z0-9+/=]+)\s*$')
    if (-not $m.Success) { return $null }
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $rsa.FromXmlString($PublicKey)
    try {
        if ($rsa.VerifyData([Text.Encoding]::UTF8.GetBytes($m.Groups[1].Value), 'SHA256', [Convert]::FromBase64String($m.Groups[2].Value))) { return $m.Groups[1].Value }
    } catch { }
    $null
}

# ---- Setup: launcher, recorder task, desktop icon ----
function Install-Parts {
    $launcher = Join-Path $Dir 'Launcher.ps1'
    $text = $LauncherTemplate.Replace('__URL__', "$RepoRaw/ComputerHelp.ps1").Replace('__KEY__', $PublicKey) -replace "`r", ''
    $old = if (Test-Path $launcher) { (Get-Content $launcher -Raw) -replace "`r", '' } else { '' }
    if ($old -ne $text) { [IO.File]::WriteAllText($launcher, $text) }

    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        # conhost --headless keeps the console window from flashing every few minutes.
        # Windows older than 10 1809 lacks it and gets a brief flash instead.
        $run = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\ComputerHelp.ps1`" -Record"
        $action = if ([int](Get-CimInstance Win32_OperatingSystem).BuildNumber -ge 17763) {
            New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless $run"
        } else {
            New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($run -replace '^powershell\.exe ', '')
        }
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $RecordMinutes)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
    }
}

function Hide-Names($text) {
    foreach ($name in $env:USERNAME, $env:COMPUTERNAME) {
        if ($name.Length -ge 3) { $text = $text -replace [regex]::Escape($name), '<name>' }
    }
    $text
}

function Send-ToBrad($note, $report, $history) {
    $data = @{ key = $cfg.key; who = $cfg.who; id = $PcId; version = $Version; note = $note; report = $report }
    if ($history) { $data.history = $history }
    $answer = Invoke-RestMethod -Uri $cfg.uploadUrl -Method Post -TimeoutSec 60 `
        -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json)))
    if ("$answer".Trim() -ne 'ok') { throw "server answered: $answer" }
}

# ---- History (one line every 5 minutes, 14 days kept) ----
function Save-Sample {
    $os    = Get-CimInstance Win32_OperatingSystem
    $cores = [int]$env:NUMBER_OF_PROCESSORS
    $cpu   = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $top   = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total', 'Idle' } |
                 Sort-Object PercentProcessorTime -Descending | Select-Object -First 1
    $mem   = Get-Process | Group-Object ProcessName | ForEach-Object {
                 [pscustomobject]@{ Name = $_.Name; MB = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB }
             } | Sort-Object MB -Descending | Select-Object -First 1
    $disk  = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    $online = Test-Connection 1.1.1.1 -Count 1 -Quiet
    # Whole numbers only, so no locale can put a comma inside a CSV field.
    $line = @((Get-Date -Format 'yyyy-MM-dd HH:mm'), $cpu,
              [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)),
              [math]::Round($disk.FreeSpace / 1GB),
              ($top.Name -replace '#\d+$', ''), [math]::Round($top.PercentProcessorTime / $cores),
              $mem.Name, [math]::Round($mem.MB), [int]$online) -join ','
    if (-not (Test-Path $History)) { Set-Content $History 'Time,CpuPct,MemUsedPct,DiskFreeGB,TopCpuProgram,TopCpuPct,TopMemProgram,TopMemMB,Online' }
    Add-Content $History $line
    if ((Get-Item $History).Length -gt 400KB) {
        $all = Get-Content $History
        Set-Content $History (@($all[0]) + $all[-4032..-1])
    }
}

function Get-HistorySummary {
    if (-not (Test-Path $History)) { return 'Nothing recorded yet. Recording starts the first time this version runs.' }
    $rows = @(Import-Csv $History)
    if (-not $rows) { return 'Nothing recorded yet.' }
    "{0} samples since {1} (about {2:N0} hours with the PC on)" -f $rows.Count, $rows[0].Time, ($rows.Count / 12)
    "Processor average: {0:N0}%" -f ($rows | ForEach-Object { [int]$_.CpuPct } | Measure-Object -Average).Average
    $busy = @($rows | Where-Object { [int]$_.CpuPct -ge 80 })
    "Processor over 80%: $($busy.Count) times"
    $busy | Sort-Object { [int]$_.CpuPct } -Descending | Select-Object -First 5 |
        ForEach-Object { "  $($_.Time): $($_.CpuPct)%, busiest $($_.TopCpuProgram) ($($_.TopCpuPct)%)" }
    if ($busy) { "  Busiest program at those times: $(($busy | Group-Object TopCpuProgram | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count)x)" }) -join ', ')" }
    $full = @($rows | Where-Object { [int]$_.MemUsedPct -ge 90 })
    "Memory over 90% full: $($full.Count) times"
    $full | Select-Object -Last 3 | ForEach-Object { "  $($_.Time): $($_.MemUsedPct)%, biggest $($_.TopMemProgram) ($($_.TopMemMB) MB)" }
    $down = @($rows | Where-Object { $_.Online -eq '0' })
    "Internet down: $($down.Count) of $($rows.Count) checks$(if ($down) { ", last at $($down[-1].Time)" })"
    "C: free space: $($rows[0].DiskFreeGB) GB at the start, $($rows[-1].DiskFreeGB) GB now"
}

# ---- Brad's checks and fixes (requests/<id>.ps1 in the repo, signed) ----
# A request starts with "# request-id: <id>", "# kind: check|fix" and "# title: <plain words>".
# Checks run by themselves in the background; fixes wait for a click. Each runs once.
function Get-Request {
    try { $text = (Invoke-WebRequest "$RepoRaw/requests/$PcId.ps1" -UseBasicParsing -TimeoutSec 15).Content } catch { return $null }
    if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
    $body = Get-SignedBody $text
    if (-not $body) { return $null }
    $id = [regex]::Match($body, '(?m)^# request-id: (\S+)').Groups[1].Value
    if (-not $id) { return $null }
    if ((Test-Path $DoneFile) -and (Get-Content $DoneFile) -contains $id) { return $null }
    [pscustomobject]@{
        Id    = $id
        Kind  = [regex]::Match($body, '(?m)^# kind: (check|fix)').Groups[1].Value
        Title = [regex]::Match($body, '(?m)^# title: (.+)$').Groups[1].Value.Trim()
        Code  = $body
    }
}

function Invoke-Request($req) {
    # Marked done first, so a request that crashes can never run over and over.
    Add-Content $DoneFile $req.Id
    $job = Start-Job -ScriptBlock ([scriptblock]::Create($req.Code))
    $finished = Wait-Job $job -Timeout 600
    $out = Receive-Job $job 2>&1 | Out-String
    if (-not $finished) { Stop-Job $job; $out += "`r`n(stopped after 10 minutes)" }
    Remove-Job $job -Force
    Send-ToBrad "Result of $($req.Kind) $($req.Id): $($req.Title)" (Hide-Names $out)
}

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
            if ([int]$os.BuildNumber -lt 22000) { 'NOTE: Windows 10 or older. Microsoft stopped security updates for Windows 10 in October 2025.' }
            "Model: $($cs.Manufacturer) $($cs.Model)"
            $load = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
            "Processor: $($cpu.Name.Trim()), busy right now: $load%"
            "Memory: {0:N1} GB total, {1:N1} GB free" -f ($cs.TotalPhysicalMemory / 1GB), ($os.FreePhysicalMemory / 1MB)
            "Last restart: $([int][math]::Floor($up.TotalDays)) days $($up.Hours) hours ago"
        }
        Section 'Last 14 days (recorded every 5 minutes)' { Get-HistorySummary }
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
        Section 'Programs installed in the last 30 days' {
            $cut = (Get-Date).AddDays(-30).ToString('yyyyMMdd')
            $apps = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                                       'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                      Where-Object { $_.DisplayName })
            $new = @($apps | Where-Object { "$($_.InstallDate)" -match '^\d{8}$' -and $_.InstallDate -ge $cut } | Sort-Object InstallDate -Descending)
            if ($new) { $new | ForEach-Object { "$($_.InstallDate): $($_.DisplayName)" } } else { 'None' }
            "($($apps.Count) programs installed in total)"
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
        Section 'Reliability history (Windows, last 30 days)' {
            $r = @(Get-CimInstance Win32_ReliabilityRecords | Where-Object { $_.TimeGenerated -gt (Get-Date).AddDays(-30) } |
                   Sort-Object TimeGenerated -Descending)
            "$($r.Count) entries. By source: $(($r | Group-Object SourceName | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')"
            # Successful updates and installs are routine (installs are listed above); show the rest.
            $r | Where-Object { $_.Message -notmatch '^Installation Successful' -and $_.SourceName -ne 'MsiInstaller' } |
                Select-Object -First 15 | ForEach-Object {
                $msg = ($_.Message -replace '\s+', ' ').Trim()
                "  {0:yyyy-MM-dd HH:mm} {1}: {2}" -f $_.TimeGenerated, $_.SourceName, $msg.Substring(0, [math]::Min(140, $msg.Length))
            }
        }
        Section 'Printers' {
            "Print service: $((Get-Service Spooler).Status)"
            $default = (Get-CimInstance Win32_Printer -Filter 'Default=TRUE').Name
            Get-Printer | ForEach-Object {
                $jobs = @(Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue)
                "$($_.Name)$(if ($_.Name -eq $default) { ' (default)' }): $($_.PrinterStatus), port $($_.PortName), $($jobs.Count) jobs waiting$(if ($jobs) { " ($(($jobs.JobStatus | Select-Object -Unique) -join ', '))" })"
            }
            $pe = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'; StartTime = $since } -MaxEvents 50 -ErrorAction SilentlyContinue)
            "Printing errors in last 7 days: $($pe.Count)"
            $pe | Select-Object -First 3 | ForEach-Object { "  {0:yyyy-MM-dd HH:mm}: {1}" -f $_.TimeCreated, (($_.Message -replace '\s+', ' ').Substring(0, [math]::Min(140, $_.Message.Length))) }
        }
        Section 'Internet' {
            "Internet reachable: $(Test-Connection 1.1.1.1 -Count 2 -Quiet)"
            "Websites resolve: $([bool](Resolve-DnsName google.com -QuickTimeout -ErrorAction SilentlyContinue))"
            Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { "Connected by: $($_.InterfaceDescription), $($_.LinkSpeed)" }
            $wifi = netsh wlan show interfaces | Select-String '^\s*(State|Signal|Radio type|Band|Channel|Receive rate \(Mbps\))\s*:'
            if ($wifi) { "Wi-Fi: $(($wifi | ForEach-Object { ($_.Line.Trim() -replace '\s*:\s*', ' ') }) -join ', ')" }
        }
        Section 'Battery' {
            $b = Get-CimInstance Win32_Battery
            if ($b) { "Charge: $($b.EstimatedChargeRemaining)%" } else { 'No battery (desktop)' }
        }
    )
    Hide-Names ($parts -join "`r`n")
}

if ($ReportOnly) { Get-Report; return }

if ($Setup) {
    Install-Parts
    $s = (New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Computer Help.lnk')
    $s.TargetPath = 'powershell.exe'
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\Launcher.ps1`""
    $s.IconLocation = 'shell32.dll,23'
    $s.Save()
    return
}

if ($Record) {
    try { Install-Parts } catch { }
    try { Save-Sample } catch { }
    try { $req = Get-Request; if ($req -and $req.Kind -eq 'check') { Invoke-Request $req } } catch { }
    # Once an hour, take a signed update without waiting for a click.
    if ((Get-Date).Minute -lt 5) { try { & (Join-Path $Dir 'Launcher.ps1') -UpdateOnly } catch { } }
    return
}

# Older installs come here first: this sets up the signing launcher and the recorder.
try { Install-Parts } catch { }

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
$fixButton   = New-BigButton "Run Brad's fix"            350 ([System.Drawing.Color]::FromArgb(200, 120, 20))
$fixButton.Visible = $false
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

# A waiting fix from Brad gets its own orange button.
$script:fix = $null
$form.Add_Shown({
    $form.Refresh()
    try { $req = Get-Request } catch { $req = $null }
    if ($req -and $req.Kind -eq 'fix') {
        $script:fix = $req
        $form.ClientSize = New-Object System.Drawing.Size(560, 565)
        $closeButton.Top = 455
        $versionLabel.Top = 540
        $fixButton.Visible = $true
        $label.Text = "Brad has a fix ready:`r`n$($req.Title)`r`nPress the orange button to run it."
    }
})

$fixButton.Add_Click({
    $label.Text = "Running Brad's fix...`r`nPlease wait, this can take a few minutes."
    $form.Cursor = 'WaitCursor'
    $form.Refresh()
    try {
        Invoke-Request $script:fix
        $label.Text = "Done! Brad will see how it went."
    } catch {
        $label.Text = "The fix ran, but the result couldn't be sent.`r`nPlease tell Brad."
    }
    $form.Cursor = 'Default'
    $fixButton.Enabled = $false
})

$bradButton.Add_Click({
    $report = Get-CachedReport
    $label.Text = 'Sending to Brad...'
    $form.Refresh()
    try {
        $history = if (Test-Path $History) { Get-Content $History -Raw } else { $null }
        Send-ToBrad $note.Text $report $history
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
# signature: FD0ylEf5ELwzlmYBedMU9ZyAHFzMSkoKB19aUobep2aAdTF1flozkHx2+Zo0DKTx1xXFwsPUeDMW4y/NCLsrIfEfhFPVgxezgOgx6w9JHhcC4pFbamdyMzvDMqiGS+EdQRDDLpHrPJ2bjhkFGcvmaxYrJvbsMGT3clMaSb7xNPrqlzfYFM6Ff7ML66ly1STjPyJ6yBJEEqhR9kjCzpFVBC1HzT3d5+v9MyFk0GUH3D1YTloEqAMdHOeJWtd18vizguhPLqEUTWbGdSKVSC74/+Z2YnkV2zfb0QXLs8TLiS3Szlwb6WWGVd39vzWsabIwDCUdVuBXZ/qSMaSv0xHF+NlVTzgqc7imwzAhDn78eIeSS3a3WpxdVm3+QPK9hFW9t4RPJKDnib/vHTownGy4mIORRbO7lCC4BPPirRAI8xMWvEzkFliwcSkbkanZIS8Wos1iyMW2OjiL4syTPzbyAzqB3WoDdR179J6RzEJpN8DAtYZFTvXI6wa3nT8WBVA+
