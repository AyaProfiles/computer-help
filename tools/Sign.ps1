# Signs Computer Help files (ComputerHelp.ps1, requests/<id>.ps1) with Brad's key:
# adds or replaces the last "# signature:" line. Run after every change, before committing.
# The private key never leaves Brad's PC and is never committed.
#   powershell -ExecutionPolicy Bypass -File tools\Sign.ps1 ComputerHelp.ps1 [requests/<id>.ps1]
param([Parameter(Mandatory = $true)][string[]]$Path)

$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.FromXmlString([IO.File]::ReadAllText('C:\claude-pc\computer-help-keys\signing-private.xml'))

foreach ($p in $Path) {
    $full = (Resolve-Path $p).Path
    # Signed text is LF-only, so git's line-ending conversion can't break the signature.
    $text = [IO.File]::ReadAllText($full) -replace "`r", ''
    $text = $text -replace '\n# signature: [A-Za-z0-9+/=]+\s*$', "`n"
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    $sig = [Convert]::ToBase64String($rsa.SignData([Text.Encoding]::UTF8.GetBytes($text), 'SHA256'))
    [IO.File]::WriteAllText($full, "$text# signature: $sig`n")
    "signed $p"
}
