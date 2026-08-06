# 7. Windows

The scripts in `scripts/` are Bash, written for macOS/Linux (and Git Bash on Windows
happens to work for most of them since they avoid GNU-only flags — see the portability
note at the top of `scripts/lib/common.sh`). A native PowerShell port isn't included yet.
This page lists what such a port needs to account for, and where it should live.

## The easy option: WSL

If you don't need a native Windows experience, running this project inside WSL (Windows
Subsystem for Linux) requires no porting at all — the existing Bash scripts run as-is.
This is the path of least resistance; consider it before investing in a PowerShell port.

## What a PowerShell port needs to handle

- **ADC location.** On Windows, gcloud writes Application Default Credentials to
  `%APPDATA%\gcloud\application_default_credentials.json`, not
  `~/.config/gcloud/application_default_credentials.json`. `.env`'s `ADC_FILE` needs a
  Windows-appropriate default in a ported `.env.example`.
- **`~/.claude.json` location.** Its path on Windows follows Windows' own user-profile
  conventions, not the Unix home directory the Bash scripts assume.
- **`gcloud` as `gcloud.cmd`.** On Windows, the gcloud CLI is invoked as `gcloud.cmd` (a
  batch wrapper), not a bare `gcloud` binary on PATH the way Bash's `command -v` checks
  expect.
- **The Credential Manager.** `@napi-rs/keyring` (used by `search-console-mcp`, see
  `03-auth-and-rapt.md`) talks to Windows Credential Manager on this platform instead of
  macOS Keychain or a Linux secret service. Any native-module failure mode described in
  `99-troubleshooting.md#native-module` needs a Windows-specific remedy path too.

## The contract to preserve

Every script in `scripts/` documents its own contract in a header comment: what it reads
from `.env`, what it writes to stdout, and its exit codes (`0` success, `1` user error,
`2` missing prerequisite). A PowerShell port should honor that same contract — same
inputs, same exit code meanings — rather than reinventing the scripts' behavior. That way
`doctor.sh`'s callers, and anything else that shells out to these scripts and checks their
exit code, keep working unmodified regardless of which implementation runs underneath.

## Where a port would live

`scripts/windows/` is the reserved location for PowerShell equivalents (e.g.
`scripts/windows/setup.ps1`, `scripts/windows/reconnect.ps1`). It doesn't exist yet as of
this writing — this section documents the intended layout for whoever picks that up.
