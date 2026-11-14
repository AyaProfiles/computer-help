# Computer Help

A one-button support tool for family and friends' Windows PCs. They press **Send to Brad** and a read-only report of their PC goes to Brad's Google Drive and email.

## How it works

- **Desktop icon** runs `Launcher.ps1`. The launcher fetches the newest `ComputerHelp.ps1` from this repo, keeps it only if it carries Brad's signature, then runs it.
- **Recorder:** a hidden task runs `ComputerHelp.ps1 -Record` every 5 minutes. It logs CPU, memory, disk, the busiest programs and the internet state to `history.csv`, keeping 14 days.
- **Brad's checks and fixes:** `requests/<id>.ps1` is a signed script for one PC.
  - A `check` runs by itself on the next recorder run.
  - A `fix` shows an orange button and waits for a click.
  - Each one runs once per request id, and its output is sent to Brad.
  - Brad prefers fixes to run silently too (a popup looks like a virus to them), so most fixes go out as `check`. Anything they would notice (closing a program, a restart) waits until Brad has called them.
- **Reports** go to a Google Apps Script web app (`apps-script/Code.gs`) in Brad's account, which saves them in the Drive folder "Computer Help reports" and emails Brad.

## Files on each PC

All files live in `%LOCALAPPDATA%\ComputerHelp`:

- `ComputerHelp.ps1`
- `Launcher.ps1` (written by `ComputerHelp.ps1`)
- `config.json` (local only, never in this repo)
- `history.csv` (every 5 minutes: processor, memory, disk, busiest programs, internet and Wi-Fi, Edge processes/memory/pages/start time/version, answer time of login.live.com and outlook.live.com, minutes since start-up)
- `snapshot.json` and `changes.csv` (programs and Edge extensions added, removed or changed since the last sample)
- `requests-done.txt`

## Changing anything

1. Edit `ComputerHelp.ps1` and bump `$Version`.
2. Run `powershell -ExecutionPolicy Bypass -File tools\Sign.ps1 ComputerHelp.ps1`.
3. Commit and push.

Unsigned or tampered files are ignored by every PC, so a forgotten signature fails safe.

The private key is in `C:\claude-pc\computer-help-keys` on Brad's PC, never in git. Without it no PC accepts updates; the only fix would be a reinstall.

## A request

```powershell
# request-id: 2026-11-10-printer-1
# kind: check
# title: Look at why the printer won't print
Get-Printer | Format-List *
```

Save it as `requests/<id>.ps1`, sign it with `tools\Sign.ps1`, then commit and push. A new id means it runs again.

## Adding a PC

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-Install.ps1 -Id <id> -Who "<Name>" [-RecordMinutes 10]
```

This builds `installers\<id>.zip`, using the shared upload URL, key and email from `C:\claude-pc\computer-help-keys\shared.json`.

- The person's config is saved as `config-<id>.json`. Configs and zips are never in git.
- Later rebuilds need only `-Id`.
- Rebuild right before installing, so the zip has the newest version.

On their PC: Extract All, double-click `Install.cmd` (not as admin), then press Send to Brad once. Delete the zip afterwards, because it contains the upload key.

People so far:

- `janas-parents` (installed 2026-11-07)
- `sheila`: config ready, not installed. 10-minute recorder because her PC is old.
