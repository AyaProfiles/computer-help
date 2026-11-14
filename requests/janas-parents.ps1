# request-id: 2026-11-14-outlook-2
# kind: check
# title: Check which Edge extensions are on and turn off McAfee WebAdvisor
# Brad approved turning WebAdvisor off (2026-11-13). Everything else is read-only.

function Section($title, [scriptblock]$body) {
    $text = try { (& $body | Out-String -Width 200).TrimEnd() } catch { "(could not check: $($_.Exception.Message))" }
    "== $title ==`r`n$text`r`n"
}

$edgeData = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'

Section 'Rights this runs with' {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    "Running as administrator: $admin"
}

Section 'Edge extensions (on = no disable flag)' {
    foreach ($prof in Get-ChildItem $edgeData -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }) {
        "Profile $($prof.Name):"
        $settings = $null
        try { $settings = (Get-Content (Join-Path $prof.FullName 'Secure Preferences') -Raw -ErrorAction Stop | ConvertFrom-Json).extensions.settings } catch { }
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
                        $hit = (Get-Content $f -Raw | ConvertFrom-Json).PSObject.Properties | Where-Object { $_.Name -ieq $key } | Select-Object -First 1
                        if ($hit) { $name = $hit.Value.message; break }
                    }
                }
            }
            $entry = if ($settings) { $settings.PSObject.Properties[$e.Name] } else { $null }
            $reasons = if ($entry) { $entry.Value.disable_reasons } else { $null }
            $on = if (-not $entry) { 'unknown (no entry)' } elseif (-not $reasons -or $reasons -eq 0) { 'ON' } else { "OFF (disable_reasons $reasons)" }
            "  $name : $on, v$($j.version)"
        }
    }
}

Section 'Edge right now' {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")
    $types = $procs | ForEach-Object { if ($_.CommandLine -match '--type=([a-z-]+)') { $Matches[1] } else { 'browser' } } | Group-Object | Sort-Object Count -Descending
    "Edge processes: $($procs.Count), memory {0:N0} MB" -f (($procs | Measure-Object WorkingSetSize -Sum).Sum / 1MB)
    ($types | ForEach-Object { "  $($_.Count)x $($_.Name)" })
    $main = $procs | Where-Object { $_.CommandLine -notmatch '--type=' } | Sort-Object CreationDate | Select-Object -First 1
    if ($main) { "Edge open since: $($main.CreationDate)" }
}

Section 'McAfee WebAdvisor: before' {
    Get-Service | Where-Object { $_.DisplayName -match 'McAfee|WebAdvisor' -or $_.Name -match 'McAfee|WebAdvisor' } |
        ForEach-Object { "Service $($_.Name) ($($_.DisplayName)): $($_.Status), start type $($_.StartType)" }
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match 'McAfee|WebAdvisor' } | ForEach-Object { "Scheduled task $($_.TaskName): $($_.State)" }
    foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run') {
        $r = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($r) { $r.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and ($_.Name -match 'McAfee|WebAdvisor' -or "$($_.Value)" -match 'McAfee|WebAdvisor') } | ForEach-Object { "Startup entry in ${k}: $($_.Name)" } }
    }
}

Section 'McAfee WebAdvisor: turning it off' {
    $svcs = @(Get-Service | Where-Object { $_.Name -match 'WebAdvisor|McAfee.*Advisor|ServiceHost' -and $_.DisplayName -match 'WebAdvisor' })
    if (-not $svcs) { 'No WebAdvisor service found.' }
    foreach ($s in $svcs) {
        try { Stop-Service -Name $s.Name -Force -ErrorAction Stop; "Stopped $($s.Name)" } catch { "Could not stop $($s.Name): $($_.Exception.Message)" }
        try { Set-Service -Name $s.Name -StartupType Disabled -ErrorAction Stop; "Set $($s.Name) to Disabled" } catch { "Could not disable $($s.Name): $($_.Exception.Message)" }
    }
}

Section 'McAfee WebAdvisor: after' {
    Get-Service | Where-Object { $_.DisplayName -match 'WebAdvisor' } | ForEach-Object { "Service $($_.Name): $($_.Status), start type $($_.StartType)" }
    Get-Process | Where-Object { $_.ProcessName -match 'mcafee|webadvisor|servicehost|uihost' } | ForEach-Object { "Still running: $($_.ProcessName)" }
    $u = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'WebAdvisor|McAfee' }
    $u | ForEach-Object { "Installed: $($_.DisplayName) $($_.DisplayVersion); uninstall: $($_.UninstallString)" }
}

Section 'Recorder and tool version' {
    $main = Join-Path $env:LOCALAPPDATA 'ComputerHelp\ComputerHelp.ps1'
    if (Test-Path $main) { $v = Select-String -Path $main -Pattern "^\`$Version\s*=\s*'([^']+)'" | Select-Object -First 1; "Version: $($v.Matches.Groups[1].Value)" }
    $t = Get-ScheduledTask -TaskName 'Computer Help recorder' -ErrorAction SilentlyContinue
    if ($t) { "Recorder triggers: $(($t.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_Task|Trigger' }) -join ', ')" }
}
# signature: mH7y67zUH7IbqkYc8UnHXJAVqkFsdtS2yZRJNsZKLEomo526Kz7unp+b1fS599zzsAmJXB8y1yxNy3Viwued/Dy04YzBHcuGoHfRo3ctUxzrzqb9f+bL/5pWQbEmsxJDCb4qTk+YBX/qj6/0YWW0RJ5PrIi0CG22MYPPPXCdJghCynxRTcp/sarj364n3Imdir1RhvE9deZvuFtAujZTH5XkLTvhrSEHXTBpyahJd9KSoXUZpMwYGjSwXIYbQE3pQyN6PdOdJpMY0OMywWgUCGOza5mTUxWP3lCAM7pL3AXLsT0VpSLgzFSX9h0E8+jAvCgLFHZfAxMdEN4tGqJIKKCY7A04e92OlYXEdZnM+cwy38SfwdpIblrTXxjrq0km4D8Mkm+Fhu/SQzQZmjsSC7OrUM9+SjDnADab+Ba+y1M6rv5AqzWGQyFlHSkOG0VNb0sC1TFxoT+EVzo/Sr4spq/daig5GdMkSOHnUq0hqsZztTDYQlvx8uHUyVj2hC3t
