#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnoses common causes of a slow-running Windows 11 machine.

.DESCRIPTION
    Collects a snapshot of system health signals that typically explain a
    sluggish Windows 11 PC: CPU/RAM hogs, low disk space, failing/near-full
    physical disks, startup bloat, stopped-but-should-be-running services,
    recent Error/Critical events, pending reboots, Windows Update backlog,
    Defender status, and basic network latency.

    Designed to be the first script in a personal IT toolkit repo - readable,
    well-commented, and safe to run repeatedly (read-only, makes no changes).

.PARAMETER Top
    Number of top CPU/RAM processes to display. Default: 10.

.PARAMETER ExportPath
    Optional path to also save the report as a plain-text file
    (e.g. C:\Temp\SlowPCReport.txt). If omitted, output goes to the console only.

.EXAMPLE
    .\Get-SlowPCReport.ps1

.EXAMPLE
    .\Get-SlowPCReport.ps1 -Top 15 -ExportPath "$env:USERPROFILE\Desktop\SlowPCReport.txt"

.NOTES
    Run from an elevated PowerShell session for complete results
    (some checks - disk health, some services, event log detail - need admin rights).
    Read-only script: it changes nothing on the machine.
#>

[CmdletBinding()]
param(
    [int]$Top = 10,
    [string]$ExportPath
)

$ErrorActionPreference = 'SilentlyContinue'
$report = New-Object System.Text.StringBuilder

function Write-Section {
    param([string]$Title)
    $line = "`n=== $Title ===`n"
    Write-Host $line -ForegroundColor Cyan
    [void]$report.AppendLine($line)
}

function Write-Line {
    param(
        [string]$Text,
        [string]$Color = 'Gray'
    )
    Write-Host $Text -ForegroundColor $Color
    [void]$report.AppendLine($Text)
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "NOTE: Not running elevated. Some checks (disk health, service state, full event log) will be incomplete. Re-run 'as Administrator' for a full report.`n" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 1. System overview
# ---------------------------------------------------------------------------
Write-Section "System Overview"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$uptime = (Get-Date) - $os.LastBootUpTime

Write-Line ("Computer name : {0}" -f $cs.Name)
Write-Line ("OS            : {0} (Build {1})" -f $os.Caption, $os.BuildNumber)
Write-Line ("Last boot     : {0}" -f $os.LastBootUpTime)
Write-Line ("Uptime        : {0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
if ($uptime.Days -ge 10) {
    Write-Line "WARNING: Uptime over 10 days - a restart alone often fixes sluggishness (clears memory leaks, stuck updates)." 'Yellow'
}

# ---------------------------------------------------------------------------
# 2. CPU - top consumers
# ---------------------------------------------------------------------------
Write-Section "Top CPU-Consuming Processes"
$cpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Get-Process | Sort-Object CPU -Descending | Select-Object -First $Top |
    ForEach-Object {
        $line = "{0,-28} PID:{1,-7} CPU(s):{2,8:N1}  Mem:{3,8:N0} MB" -f `
            $_.ProcessName, $_.Id, $_.CPU, ($_.WorkingSet64 / 1MB)
        Write-Line $line
    }

# ---------------------------------------------------------------------------
# 3. Memory - overview + top consumers
# ---------------------------------------------------------------------------
Write-Section "Memory"
$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
$freeMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
$usedPct = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100, 1)

Write-Line ("Total RAM     : {0:N0} MB" -f $totalMB)
Write-Line ("Free RAM      : {0:N0} MB" -f $freeMB)
Write-Line ("Used          : {0}%" -f $usedPct)
if ($usedPct -ge 85) {
    Write-Line "WARNING: Memory usage is high - see top consumers below, or consider a RAM upgrade." 'Yellow'
}

Write-Line "`nTop RAM-Consuming Processes:"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $Top |
    ForEach-Object {
        Write-Line ("{0,-28} PID:{1,-7} Mem:{2,8:N0} MB" -f $_.ProcessName, $_.Id, ($_.WorkingSet64 / 1MB))
    }

# ---------------------------------------------------------------------------
# 4. Disk space
# ---------------------------------------------------------------------------
Write-Section "Disk Space"
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $freePct = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
    $line = "{0}  {1,6:N1} GB free of {2,6:N1} GB  ({3}% free)" -f `
        $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB), $freePct
    if ($freePct -lt 10) {
        Write-Line "$line  <-- LOW DISK SPACE" 'Red'
    } elseif ($freePct -lt 20) {
        Write-Line "$line  <-- getting low" 'Yellow'
    } else {
        Write-Line $line
    }
}

# ---------------------------------------------------------------------------
# 5. Physical disk health (requires admin + Storage module, usually built in)
# ---------------------------------------------------------------------------
Write-Section "Physical Disk Health"
$disks = Get-PhysicalDisk
if ($disks) {
    $disks | ForEach-Object {
        $health = $_.HealthStatus
        $color = if ($health -ne 'Healthy') { 'Red' } else { 'Green' }
        Write-Line ("{0,-20} Media:{1,-8} Health:{2,-10} OperationalStatus:{3}" -f `
            $_.FriendlyName, $_.MediaType, $health, $_.OperationalStatus) $color
    }
} else {
    Write-Line "Could not query physical disk health (try running as Administrator)." 'Yellow'
}

# ---------------------------------------------------------------------------
# 6. Startup programs
# ---------------------------------------------------------------------------
Write-Section "Startup Programs"
$startupItems = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
if ($startupItems) {
    $startupItems | ForEach-Object {
        Write-Line ("{0,-30} {1}" -f $_.Name, $_.Command)
    }
    $count = @($startupItems).Count
    if ($count -gt 12) {
        Write-Line "`nWARNING: $count startup items is a lot - trimming this list is one of the highest-impact fixes for slow boot/login." 'Yellow'
    }
} else {
    Write-Line "No startup items found or unable to query (try Task Manager > Startup apps for a GUI view)."
}

# ---------------------------------------------------------------------------
# 7. Services that should be running but aren't (Automatic start, Stopped)
# ---------------------------------------------------------------------------
Write-Section "Stopped Services Set to Start Automatically"
$badServices = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State='Stopped'" |
    Select-Object Name, DisplayName, StartName
if ($badServices) {
    $badServices | ForEach-Object {
        Write-Line ("{0,-35} ({1})" -f $_.DisplayName, $_.Name) 'Yellow'
    }
} else {
    Write-Line "None found - all auto-start services are running." 'Green'
}

# ---------------------------------------------------------------------------
# 8. Recent Error/Critical events (last 24 hours)
# ---------------------------------------------------------------------------
Write-Section "Recent Errors (System/Application logs, last 24h)"
$since = (Get-Date).AddHours(-24)
foreach ($logName in 'System', 'Application') {
    $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = 1, 2; StartTime = $since } -MaxEvents 10
    if ($events) {
        Write-Line "`n[$logName]" 'Cyan'
        $events | ForEach-Object {
            Write-Line ("{0}  {1,-10} {2}" -f $_.TimeCreated, $_.ProviderName, ($_.Message -split "`n")[0]) 'Yellow'
        }
    }
}
if (-not $events) {
    Write-Line "No Critical/Error events logged in the last 24 hours." 'Green'
}

# ---------------------------------------------------------------------------
# 9. Pending reboot check
# ---------------------------------------------------------------------------
Write-Section "Pending Reboot"
$pendingReboot = $false
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
)
foreach ($p in $paths) {
    if (Test-Path $p) { $pendingReboot = $true }
}
if ($pendingReboot) {
    Write-Line "A reboot is pending (Windows Update or component servicing). This alone can cause slowdowns - restart when convenient." 'Yellow'
} else {
    Write-Line "No pending reboot detected." 'Green'
}

# ---------------------------------------------------------------------------
# 10. Windows Update status
# ---------------------------------------------------------------------------
Write-Section "Windows Update"
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $searcher = $updateSession.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Software'")
    $pendingCount = $result.Updates.Count
    if ($pendingCount -gt 0) {
        Write-Line "$pendingCount update(s) pending installation." 'Yellow'
    } else {
        Write-Line "No pending software updates." 'Green'
    }
} catch {
    Write-Line "Could not query Windows Update (COM search sometimes blocked by policy)." 'Yellow'
}

# ---------------------------------------------------------------------------
# 11. Windows Defender status
# ---------------------------------------------------------------------------
Write-Section "Windows Defender"
$mp = Get-MpComputerStatus
if ($mp) {
    Write-Line ("Real-time protection : {0}" -f $mp.RealTimeProtectionEnabled)
    Write-Line ("Last quick scan      : {0}" -f $mp.QuickScanEndTime)
    Write-Line ("Signature age (days) : {0}" -f $mp.AntivirusSignatureAge)
    if (-not $mp.RealTimeProtectionEnabled) {
        Write-Line "WARNING: Real-time protection is OFF." 'Red'
    }
} else {
    Write-Line "Could not query Defender status (a third-party AV may be in control)." 'Yellow'
}

# ---------------------------------------------------------------------------
# 12. Temp file bloat
# ---------------------------------------------------------------------------
Write-Section "Temp Folder Size"
$tempPaths = @($env:TEMP, "$env:WINDIR\Temp")
foreach ($t in $tempPaths) {
    if (Test-Path $t) {
        $size = (Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Line ("{0,-30} {1:N0} MB" -f $t, $size)
    }
}
Write-Line "Tip: Disk Cleanup or 'cleanmgr.exe' can safely reclaim this space."

# ---------------------------------------------------------------------------
# 13. Basic network latency
# ---------------------------------------------------------------------------
Write-Section "Network Latency"
$gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object -First 1).NextHop
foreach ($target in @($gateway, '8.8.8.8')) {
    if ($target) {
        $ping = Test-Connection -ComputerName $target -Count 2 -ErrorAction SilentlyContinue
        if ($ping) {
            $avg = ($ping | Measure-Object -Property ResponseTime -Average).Average
            Write-Line ("{0,-15} avg {1:N0} ms" -f $target, $avg)
        } else {
            Write-Line ("{0,-15} unreachable" -f $target) 'Yellow'
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Section "Done"
Write-Line "Review anything above in Yellow/Red first - those are the likely culprits."

if ($ExportPath) {
    try {
        $report.ToString() | Out-File -FilePath $ExportPath -Encoding UTF8
        Write-Host "`nReport saved to: $ExportPath" -ForegroundColor Cyan
    } catch {
        Write-Host "`nCould not save report to $ExportPath : $_" -ForegroundColor Red
    }
}
