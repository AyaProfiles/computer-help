# Computer Help launcher: the desktop icon runs this.
# It fetches the newest ComputerHelp.ps1 from GitHub, keeps it only if it is a
# complete, valid script, then runs it. Offline it just runs the copy it has.
# This file itself never updates, so keep it small and boring.
$dir  = $PSScriptRoot
$main = Join-Path $dir 'ComputerHelp.ps1'
$url  = 'https://raw.githubusercontent.com/AyaProfiles/computer-help/main/ComputerHelp.ps1'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $new = (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 15).Content
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($new, [ref]$null, [ref]$errors)
    # The end marker proves the download was not cut off.
    if (-not $errors -and $new -match '# computer-help-main' -and $new -match '# end-of-computer-help') {
        Set-Content -Path "$main.new" -Value $new -Encoding UTF8
        Move-Item -Path "$main.new" -Destination $main -Force
    }
} catch { }

& $main
