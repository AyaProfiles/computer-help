# Builds an install zip for one person: installers\<id>.zip with Install.cmd, the current
# ComputerHelp.ps1 and their config.json. Run it right before installing, so the zip has
# the newest version and isn't lying around with the upload key in it.
#   powershell -ExecutionPolicy Bypass -File tools\New-Install.ps1 -Id sheila -Who "Sheila" [-RecordMinutes 10]
# Their config is kept as config-<id>.json (not in git) and reused next time, so
# -Who and -RecordMinutes are only needed the first time.
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9-]+$')][string]$Id,
    [string]$Who,
    [int]$RecordMinutes = 5
)
$repo = Split-Path $PSScriptRoot
$configFile = Join-Path $repo "config-$Id.json"

if (-not (Test-Path $configFile)) {
    if (-not $Who) { throw "New person: give -Who (their name as it should appear in reports)." }
    # Upload link, key and email are the same for everyone and live outside the repo.
    $shared = Get-Content 'C:\claude-pc\computer-help-keys\shared.json' -Raw | ConvertFrom-Json
    [ordered]@{ id = $Id; who = $Who; uploadUrl = $shared.uploadUrl; key = $shared.key
                bradEmail = $shared.bradEmail; recordMinutes = $RecordMinutes } |
        ConvertTo-Json | Set-Content $configFile -Encoding UTF8
}

$stage = Join-Path $env:TEMP "computer-help-$Id"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $stage | Out-Null
Copy-Item (Join-Path $repo 'Install.cmd'), (Join-Path $repo 'ComputerHelp.ps1') $stage
Copy-Item $configFile (Join-Path $stage 'config.json')
New-Item -ItemType Directory (Join-Path $repo 'installers') -Force | Out-Null
$zip = Join-Path $repo "installers\$Id.zip"
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Remove-Item $stage -Recurse -Force
"Built $zip"
