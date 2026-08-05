# Windows-Troubleshooting-Toolkit

A growing collection of PowerShell scripts for diagnosing and fixing common Windows issues, built from 23+ years of hands-on IT support experience.

## Scripts

### `Get-SlowPCReport.ps1`

Diagnoses why a Windows 11 machine is running slow. Read-only — it makes no changes to the system, just reports.

Checks:

- System uptime / last boot time
- Top CPU- and RAM-consuming processes
- Disk space per drive, and physical disk health status
- Startup program count/list
- Auto-start services that have stopped
- Recent Critical/Error events (System & Application logs, last 24h)
- Pending reboot flags
- Windows Update backlog
- Windows Defender real-time protection status
- Temp folder size
- Basic network latency (gateway + 8.8.8.8)

#### Usage

Run from an elevated PowerShell session for the most complete results:

```powershell
.\Get-SlowPCReport.ps1
```

Show more/fewer top processes, and save the output to a file:

```powershell
.\Get-SlowPCReport.ps1 -Top 15 -ExportPath "$env:USERPROFILE\Desktop\SlowPCReport.txt"
```

If script execution is blocked, run once per session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Roadmap

Planned additions:

- `Repair-CommonIssues.ps1` — opt-in fixes (clear temp, restart stuck services, run DISM/SFC)
- `Get-NetworkDiagnostics.ps1` — deeper connectivity/DNS troubleshooting
- `New-ITSupportTicketSummary.ps1` — formats findings into a ticket-ready summary

## License

MIT — see [LICENSE](LICENSE).
