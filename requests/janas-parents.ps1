# request-id: 2026-11-13-outlook-1
# kind: check
# title: Look at why email in Outlook loads slowly
# Read-only: changes nothing on the PC.

function Section($title, [scriptblock]$body) {
    $text = try { (& $body | Out-String -Width 200).TrimEnd() } catch { "(could not check: $($_.Exception.Message))" }
    "== $title ==`r`n$text`r`n"
}

$edgeData = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
$appDir   = Join-Path $env:LOCALAPPDATA 'ComputerHelp'

Section 'Computer Help recorder' {
    $t = Get-ScheduledTask -TaskName 'Computer Help recorder' -ErrorAction SilentlyContinue
    if ($t) {
        $i = $t | Get-ScheduledTaskInfo
        "Task: $($t.State), last run $($i.LastRunTime), result $($i.LastTaskResult), next run $($i.NextRunTime)"
    } else { 'Task: missing' }
    $h = Join-Path $appDir 'history.csv'
    if (Test-Path $h) {
        $rows = @(Get-Content $h)
        "history.csv: $($rows.Count - 1) samples, first: $($rows[1]), last: $($rows[-1])"
    } else { 'history.csv: missing' }
    $main = Join-Path $appDir 'ComputerHelp.ps1'
    if (Test-Path $main) {
        $v = Select-String -Path $main -Pattern "^\`$Version\s*=\s*'([^']+)'" | Select-Object -First 1
        "Installed version: $($v.Matches.Groups[1].Value)"
    } else { 'ComputerHelp.ps1: missing' }
    "Launcher.ps1 present: $(Test-Path (Join-Path $appDir 'Launcher.ps1'))"
    $lnk = [Environment]::GetFolderPath('Desktop') + '\Computer Help.lnk'
    if (Test-Path $lnk) { $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); "Desktop icon runs: $($s.Arguments)" }
}

Section 'Which Outlook is running' {
    foreach ($n in 'OUTLOOK', 'olk', 'HxOutlook', 'msedgewebview2') {
        $p = @(Get-Process $n -ErrorAction SilentlyContinue)
        if ($p) { "{0}: {1} running, {2:N0} MB, oldest started {3}" -f $n, $p.Count, (($p | Measure-Object WorkingSet64 -Sum).Sum / 1MB), ($p | Sort-Object StartTime | Select-Object -First 1).StartTime }
        else { "${n}: not running" }
    }
    '(OUTLOOK = classic Outlook, olk = new Outlook app, HxOutlook = old Windows Mail)'
}

Section 'Open windows (Edge and Outlook)' {
    Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Wins {
    delegate bool EnumProc(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public static List<string> List() {
        var r = new List<string>();
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
            if (sb.Length == 0) return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            r.Add(pid + "|" + sb.ToString()); return true;
        }, IntPtr.Zero);
        return r;
    }
}
'@
    foreach ($w in [Wins]::List()) {
        $procId, $title = $w -split '\|', 2
        $name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
        if ($name -in 'msedge', 'OUTLOOK', 'olk') { "${name}: $title" }
    }
}

Section 'Edge right now' {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")
    $renderers = @($procs | Where-Object { $_.CommandLine -match '--type=renderer' })
    $ext = @($renderers | Where-Object { $_.CommandLine -match '--extension-process' })
    "Edge processes: $($procs.Count) (tabs/pages: about $($renderers.Count - $ext.Count), extensions: $($ext.Count))"
    "Edge memory: {0:N0} MB" -f (($procs | Measure-Object WorkingSetSize -Sum).Sum / 1MB)
    $main = $procs | Where-Object { $_.CommandLine -notmatch '--type=' } | Sort-Object CreationDate | Select-Object -First 1
    if ($main) { "Edge open since: $($main.CreationDate)" }
    foreach ($root in "${env:ProgramFiles(x86)}\Microsoft\Edge\Application", "$env:ProgramFiles\Microsoft\Edge\Application") {
        if (Test-Path "$root\msedge.exe") {
            "Edge installed: $((Get-Item "$root\msedge.exe").VersionInfo.ProductVersion) (file date $((Get-Item "$root\msedge.exe").LastWriteTime))"
            "Update waiting for Edge to restart (new_msedge.exe): $(Test-Path "$root\new_msedge.exe")"
        }
    }
    if ($main -and $main.ExecutablePath) { "Running Edge version: $((Get-Item $main.ExecutablePath).VersionInfo.ProductVersion)" }
}

Section 'Edge extensions' {
    foreach ($prof in Get-ChildItem $edgeData -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
        "Profile $($prof.Name):"
        $state = @{}
        try {
            $prefs = Get-Content (Join-Path $prof.FullName 'Secure Preferences') -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($p in $prefs.extensions.settings.PSObject.Properties) { $state[$p.Name] = $p.Value.state }
        } catch { }
        foreach ($e in Get-ChildItem (Join-Path $prof.FullName 'Extensions') -Directory -ErrorAction SilentlyContinue) {
            $m = Get-ChildItem $e.FullName -Recurse -Filter manifest.json -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $m) { continue }
            $j = Get-Content $m.FullName -Raw | ConvertFrom-Json
            $name = $j.name
            if ($name -match '^__MSG_(.+)__$') {
                $key = $Matches[1]
                foreach ($loc in 'en', 'en_US', $j.default_locale) {
                    $f = Join-Path $m.DirectoryName "_locales\$loc\messages.json"
                    if ($loc -and (Test-Path $f)) {
                        $msgs = Get-Content $f -Raw | ConvertFrom-Json
                        $hit = $msgs.PSObject.Properties | Where-Object { $_.Name -ieq $key } | Select-Object -First 1
                        if ($hit) { $name = $hit.Value.message; break }
                    }
                }
            }
            $on = switch ($state[$e.Name]) { 1 { 'on' } 0 { 'off' } default { '?' } }
            "  $name ($on) v$($j.version)"
        }
    }
}

Section 'Sites in the open Edge session (includes back history, top 20)' {
    $f = Get-ChildItem (Join-Path $edgeData 'Default\Sessions') -Filter 'Session_*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { 'no session file'; return }
    $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
    $bytes = New-Object byte[] $fs.Length; [void]$fs.Read($bytes, 0, $bytes.Length); $fs.Close()
    $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $urls = [regex]::Matches($text, 'https?://([a-zA-Z0-9.-]+)') | ForEach-Object { $_.Groups[1].Value.ToLower() }
    "Session file from $($f.LastWriteTime)"
    $urls | Group-Object | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object { "  $($_.Count)x $($_.Name)" }
}

Section 'How fast the email sites answer' {
    foreach ($u in 'https://outlook.live.com/mail/', 'https://outlook.office.com/mail/', 'https://login.live.com/', 'https://www.bing.com/') {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $r = Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 5 -UserAgent ([Microsoft.PowerShell.Commands.PSUserAgent]::Chrome)
            "{0}: {1} in {2:N1} s ({3:N0} KB)" -f $u, $r.StatusCode, $sw.Elapsed.TotalSeconds, ($r.RawContentLength / 1KB)
        } catch {
            # Outlook turns scripts away (403/417); any answer still shows the server is reachable and how fast.
            if ($_.Exception.Response) { "{0}: answered {1} in {2:N1} s (scripts are turned away, that's normal)" -f $u, [int]$_.Exception.Response.StatusCode, $sw.Elapsed.TotalSeconds }
            else { "{0}: failed after {1:N1} s: {2}" -f $u, $sw.Elapsed.TotalSeconds, $_.Exception.Message }
        }
    }
    foreach ($n in 'outlook.live.com', 'outlook.office.com') {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ip = (Resolve-DnsName $n -Type A -ErrorAction SilentlyContinue | Where-Object IPAddress | Select-Object -First 1).IPAddress
        "DNS {0}: {1} in {2:N0} ms" -f $n, $ip, $sw.Elapsed.TotalMilliseconds
    }
    "Ping to 1.1.1.1: $((Test-Connection 1.1.1.1 -Count 4 -ErrorAction SilentlyContinue | Measure-Object ResponseTime -Average).Average) ms average"
}

Section 'Proxy and hosts file' {
    $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    "Proxy on: $($p.ProxyEnable) $($p.ProxyServer) autoconfig: $($p.AutoConfigURL)"
    $hosts = @(Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" | Where-Object { $_ -match '^\s*[^#\s]' })
    "Hosts file entries: $($hosts.Count)"
    $hosts | Select-Object -First 10
}

Section 'McAfee WebAdvisor' {
    Get-Process | Where-Object { $_.ProcessName -match 'mcafee|webadvisor|servicehost|uihost' } | ForEach-Object { "$($_.ProcessName): $([math]::Round($_.WorkingSet64 / 1MB)) MB" }
    Get-Service | Where-Object { $_.DisplayName -match 'McAfee|WebAdvisor' } | ForEach-Object { "Service $($_.DisplayName): $($_.Status)" }
}

Section 'Unexpected shutdowns (last 30 days)' {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 6008; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.TimeCreated) id $($_.Id): $(($_.Message -split "`n")[0].Trim())" }
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue |
        ForEach-Object { $x = [xml]$_.ToXml(); "  {0}: bugcheck {1}, power button {2}, sleep in progress {3}" -f $_.TimeCreated, ($x.Event.EventData.Data | Where-Object Name -eq 'BugcheckCode').'#text', ($x.Event.EventData.Data | Where-Object Name -eq 'PowerButtonTimestamp').'#text', ($x.Event.EventData.Data | Where-Object Name -eq 'SleepInProgress').'#text' }
}
# signature: hzJrIr0EgzaBO6YShRD1GG2ucKzj+YpGeS4nboAXrlbgO5yuj+YCW0vRnFgkY1XfupWfDSC7+JQj+tCxLI2Z7YHe87FoBJtdxLxgXvsaRBK0s0sIfjANioqVp+x0Q79nWQSaUau9SCE96Mrcy0tIXINY+77GUHkUPXFn7+x8jKE7g2GMY3iYCVfUyu7tgTo1VSWDlcSXEjZ/FzKTbn7U2MXWejlgY02MtlFQ21NMFHqtf1BsUxMRBexbhiAu0V5YLsrfnxrU4nREj/UrG5FtKQ1jjp6JullcgEvm1ztzf30hvt8vfjpCeL81GfFXe/oLV+HkruYlxSKB6MVbfmW5HXkxs51pREAMrmRhjWJmaTMS9v6XGkf6HlM/N40mSNd8DZawc4vSbrSZ+XSrrCUeTV/h2ObyhMRBkpOsGVcN+BfZf+nysljz4d/DPXt/Kd9ZtT7uaZNn/C4H++gLt3CheGsEZliq1fnudSpwqZePefTDegtYPFSWiGUhvsC1a2aQ
