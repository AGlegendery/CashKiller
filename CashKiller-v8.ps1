<#
.SYNOPSIS
    CashKiller v7 – Ultimate cache cleaner for Windows
.DESCRIPTION
    High‑performance TUI tool that scans real cache locations across
    the system, browsers, and applications. Shows reclaimable space,
    lets you select items, and deletes them safely.
    Supports long paths (>260) and protects critical system folders.
.NOTES
    Author: AGlegend (improved community edition)
    Requires: PowerShell 5.1+, Windows 10/11
    Run as Administrator.
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
# CashKiller v8 – Ultimate Cache Cleaner (ASCII-safe version)
param()

# Admin check
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$Host.UI.RawUI.WindowTitle = "CashKiller v8 - Ultimate Cache Cleaner"

$ui = $Host.UI.RawUI
$minWidth, $minHeight = 120, 35
do {
    if ($ui.WindowSize.Width -lt $minWidth -or $ui.WindowSize.Height -lt $minHeight) {
        Write-Host "Please maximize the terminal window (or resize to at least $minWidth x $minHeight)." -ForegroundColor Yellow
        Start-Sleep 1
        Clear-Host
    }
} while ($ui.WindowSize.Width -lt $minWidth -or $ui.WindowSize.Height -lt $minHeight)

$ui.BufferSize = New-Object Management.Automation.Host.Size(120, 35)
$ui.WindowSize  = New-Object Management.Automation.Host.Size(120, 35)
[Console]::CursorVisible = $false
Clear-Host

# Logs
$logDir = "$env:LOCALAPPDATA\CashKiller"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$successLogPath = Join-Path $logDir "delete.log"
$failedLogPath  = Join-Path $logDir "failed.log"

$script:logLines       = [System.Collections.Generic.List[string]]::new()
$script:failedLogLines = [System.Collections.Generic.List[string]]::new()

function Add-LogEntry {
    param([string]$Message, [bool]$Failed)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] $Message"
    $target = if ($Failed) { $failedLogPath } else { $successLogPath }
    try { Add-Content -Path $target -Value $entry -ErrorAction Stop } catch {}
    if ($Failed) {
        $script:failedLogLines.Insert(0, $entry)
        if ($script:failedLogLines.Count -gt 5) { $script:failedLogLines.RemoveAt(5) }
    } else {
        $script:logLines.Insert(0, $entry)
        if ($script:logLines.Count -gt 5) { $script:logLines.RemoveAt(5) }
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -lt 1KB)      { return "$Bytes B" }
    elseif ($Bytes -lt 1MB)  { return "{0:N1} KB" -f ($Bytes / 1KB) }
    elseif ($Bytes -lt 1GB)  { return "{0:N1} MB" -f ($Bytes / 1MB) }
    else                     { return "{0:N1} GB" -f ($Bytes / 1GB) }
}

function Trim-Text {
    param([string]$Text, [int]$Max)
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 3) + "..."
}

function Get-FolderSizeFast {
    param([string]$Path)
    try {
        if ($Path.Length -ge 260 -and -not $Path.StartsWith('\\?\') -and -not $Path.StartsWith('\\?\UNC\')) {
            $longPath = "\\?\$Path"
        } else { $longPath = $Path }
        $size = 0L
        $files = [System.IO.Directory]::EnumerateFiles($longPath, '*', [System.IO.SearchOption]::AllDirectories)
        foreach ($f in $files) {
            $fi = [System.IO.FileInfo]::new($f)
            $size += $fi.Length
        }
        return $size
    } catch {
        try {
            (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        } catch { return 0 }
    }
}

function Get-CachePaths {
    $paths = @(
        
        "$env:TEMP",
        "$env:TMP",
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp",
        "C:\Windows\Prefetch",
        "C:\Windows\SoftwareDistribution\Download",
        "C:\Windows\SoftwareDistribution\DeliveryOptimization",
        "C:\Windows\Logs",
        "C:\Windows\Panther",
        "C:\Windows\Minidump",
        "C:\Windows\LiveKernelReports",
        "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp",
        "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Temp",
        "C:\ProgramData\Microsoft\Windows\WER",
        "C:\ProgramData\Microsoft\Diagnosis",
        "C:\ProgramData\Package Cache",
        "C:\ProgramData\NVIDIA Corporation\Downloader",
        "C:\ProgramData\USOShared\Logs"
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:LOCALAPPDATA\IconCache.db",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
        "$env:LOCALAPPDATA\Microsoft\Windows\Caches",
        "$env:LOCALAPPDATA\Microsoft\Windows\History",
        "$env:LOCALAPPDATA\Microsoft\Windows\Notifications",
        "$env:LOCALAPPDATA\Microsoft\Windows\ConnectedDevicesPlatform"
        "$env:LOCALAPPDATA\Packages\*\LocalCache",
        "$env:LOCALAPPDATA\Packages\*\TempState",
        "$env:LOCALAPPDATA\Packages\*\AC\Temp",
        "$env:LOCALAPPDATA\Packages\*\AC\INetCache",
        "$env:LOCALAPPDATA\Packages\*\AC\Microsoft\CryptnetUrlCache"
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\ShaderCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Service Worker\CacheStorage",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GrShaderCache"
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\ShaderCache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Service Worker\CacheStorage"
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\startupCache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\thumbnails",
        "$env:APPDATA\Mozilla\Firefox\Profiles\*\minidumps"
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\Code Cache",
        "$env:LOCALAPPDATA\Opera Software\Opera Stable\GPUCache",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Code Cache"
        "$env:APPDATA\discord\Cache",
        "$env:APPDATA\discord\Code Cache",
        "$env:APPDATA\discord\GPUCache",
        "$env:APPDATA\discord\Service Worker\CacheStorage",
        "$env:APPDATA\Telegram Desktop\tdata\user_data\cache",
        "$env:APPDATA\Telegram Desktop\tdata\user_data\media_cache",
        "$env:APPDATA\Microsoft\Teams\Cache",
        "$env:APPDATA\Microsoft\Teams\Code Cache",
        "$env:APPDATA\Slack\Cache",
        "$env:APPDATA\Slack\Service Worker\CacheStorage",
        "$env:APPDATA\Microsoft\Skype for Desktop\Cache",
        "$env:LOCALAPPDATA\Packages\WhatsAppDesktop_*\LocalCache",
        "$env:APPDATA\Zoom\logs",
        "$env:LOCALAPPDATA\Zoom\data\logs"
        "$env:APPDATA\Code\Cache",
        "$env:APPDATA\Code\CachedData",
        "$env:APPDATA\Code\GPUCache",
        "$env:APPDATA\npm-cache",
        "$env:LOCALAPPDATA\npm-cache",
        "$env:LOCALAPPDATA\pip\Cache",
        "$env:LOCALAPPDATA\Yarn\Cache",
        "$env:LOCALAPPDATA\JetBrains\*\caches",
        "$env:LOCALAPPDATA\JetBrains\*\log",
        "$env:LOCALAPPDATA\Docker\log",
        "$env:LOCALAPPDATA\Temp\nuget",
        "$env:USERPROFILE\.nuget\packages\*\_rels"
        "$env:LOCALAPPDATA\Adobe\Common\Media Cache",
        "$env:LOCALAPPDATA\Adobe\Common\Media Cache Files",
        "$env:APPDATA\Adobe\Common\Media Cache",
        "$env:LOCALAPPDATA\Temp\Adobe",
        "$env:APPDATA\vlc\art"
        "$env:LOCALAPPDATA\Microsoft\Office\16.0\OfficeFileCache",
        "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache",
        "$env:LOCALAPPDATA\CrashDumps",
        "$env:APPDATA\Microsoft\Windows\Recent",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\ThumbCacheToDelete"

    ) | Where-Object { $_ } | Sort-Object -Unique

    $resolved = @()
    foreach ($p in $paths) {
        try {
            $expanded = Resolve-Path $p -ErrorAction SilentlyContinue
            foreach ($rp in $expanded) {
                if (Test-Path $rp -PathType Container -ErrorAction SilentlyContinue) {
                    $resolved += $rp
                }
            }
        } catch {}
    }
    return $resolved
}

$criticalFolders = @(
    "$env:SystemRoot",
    "$env:SystemRoot\System32",
    "$env:SystemRoot\SysWOW64",
    "$env:ProgramFiles",
    "$env:ProgramFiles(x86)",
    "$env:ProgramData\Microsoft",
    "$env:LOCALAPPDATA\Microsoft\Windows\Caches"
)

function Is-CriticalPath {
    param([string]$Path)
    foreach ($crit in $criticalFolders) {
        if ($Path -like "$crit*") { return $true }
    }
    return $false
}


$esc = [char]27    
$cyan = "$esc[36m"
$reset = "$esc[0m"
$red = "$esc[31m"
$1 = "$esc[38;5;120m"
$2 = "$esc[38;5;121m"
$3 = "$esc[38;5;122m"
$4 = "$esc[38;5;123m"
$5 = "$esc[38;5;196m"
$6 = "$esc[38;5;197m"
$7 = "$esc[38;5;198m"
$8 = "$esc[38;5;199m"
$9 = "$esc[38;5;200m"
$l = "$esc[38;5;201m"
$opa = "$esc[38;5;245m"
$0 = "$esc[38;5;68m"

function Build-CacheList {
    $paths = Get-CachePaths
    $totalPaths = $paths.Count
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()

    Clear-Host
    Write-Host "`r`n  CashKiller v8 - Scanning cache locations..." -ForegroundColor Cyan
    Write-Host "  This may take a moment depending on your drive speed.`n" -ForegroundColor DarkGray

    $currentPathIdx = 0
    # Calculate maximum path length to keep the whole line inside the window width.
    # Line format: "  [####...###] 100%  Examining: C:\...   "
    # Fixed parts: 2 spaces + 2 brackets + 40 bar + 1 space + 3 digit % + 2 spaces + "Examining: " (12) + 3 trailing spaces = 66 chars
    $fixedWidth = 66
    $maxPathLen = $Host.UI.RawUI.WindowSize.Width - $fixedWidth
    if ($maxPathLen -lt 10) { $maxPathLen = 10 }

    foreach ($p in $paths) {
        $currentPathIdx++
        $percent = [math]::Min(100, [math]::Round(($currentPathIdx / $totalPaths) * 100))
        $barWidth = 40
        $filled   = [math]::Round(($percent / 100) * $barWidth)
        $bar      = ("#" * $filled).PadRight($barWidth, '-')
        $trimmedPath = Trim-Text $p $maxPathLen

        # Build the progress line, then pad it with spaces to fill the whole line (erasing previous leftovers)
        $progressLine = "  [$bar] " + "$percent%".PadLeft(3) + "  Examining: $trimmedPath   "
        $lineLength = $progressLine.Length
        if ($lineLength -gt $ui.WindowSize.Width) {
            $progressLine = $progressLine.Substring(0, $ui.WindowSize.Width - 1)
        } else {
            $progressLine = $progressLine.PadRight($ui.WindowSize.Width - 1)
        }

        # Overwrite the same console line every time
        [Console]::SetCursorPosition(0, [Console]::CursorTop)
        [Console]::Write($progressLine)

        $items = Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if (Is-CriticalPath $item.FullName) { continue }
            $size = 0L
            if ($item.PSIsContainer) {
                $size = Get-FolderSizeFast $item.FullName
            } else {
                $size = $item.Length
            }
            if ($size -le 0) { continue }
            $type = if ($item.PSIsContainer) { "DIR" } else { "FILE" }
            $list.Add([PSCustomObject]@{
                Path     = $item.FullName
                Type     = $type
                Size     = $size
                Selected = $false
            })
        }
    }
    Write-Host "`n`n  Scan complete. $($list.Count) items found."
    Start-Sleep -Milliseconds 800
    return ,($list | Sort-Object Size -Descending)
}

$script:display = 14
$script:index   = 0
$script:offset  = 0
$script:freedSessionBytes = 0L

function Draw-UI {
    # Clear the screen completely before painting the interactive TUI
    Clear-Host

    [Console]::SetCursorPosition(0, 0)
    $esc   = [char]27
    $reset = "$esc[0m"
    $cyan  = "$esc[36m"
    $gray  = "$esc[90m"
    $brightGreen = "$esc[92m"
    $brightRed   = "$esc[91m"

    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("${cyan}CashKiller v8 - Ultimate Cache Cleaner${reset}") | Out-Null
    $sb.AppendLine("${gray}By AGlegend & community${reset}") | Out-Null
    $sb.AppendLine("${0}Some Junk Files Are Hidded From Your Eyes!! But not after ${1}C${2}a${3}s${4}h ${5}K${6}i${7}l${8}l${9}e${l}r${reset}")
    $sb.AppendLine("") | Out-Null

    $totalReclaimable = ($list | Measure-Object Size -Sum).Sum
    $selectedCount    = ($list | Where-Object Selected).Count
    $totalItems       = $list.Count
    $sb.AppendLine("Total reclaimable space: ${brightGreen}$(Format-Size $totalReclaimable)${reset} up to 200MB is Normal") | Out-Null
    $sb.AppendLine("Selected items         : ${brightGreen}$selectedCount${reset} / $totalItems") | Out-Null
    $sb.AppendLine("Freed this session     : ${brightGreen}$(Format-Size $script:freedSessionBytes)${reset}") | Out-Null
    $sb.AppendLine("") | Out-Null

    $sb.AppendLine("${gray}Controls: Up/Down Move   Space Select   Enter Delete   A SelectAll   U UnselectAll   L LargeFiles   R Reload   Ctrl + C + R Exit${reset}") | Out-Null
    $sb.AppendLine("") | Out-Null

    if ($script:offset -gt 0) {
        $sb.AppendLine("     ${cyan}... more above ...${reset}") | Out-Null
    } else {
        $sb.AppendLine("") | Out-Null
    }

    $end = [math]::Min($script:offset + $script:display, $totalItems)
    for ($i = $script:offset; $i -lt $end; $i++) {
        $item = $list[$i]
        $cursor = if ($i -eq $script:index) { ">" } else { " " }
        $mark   = if ($item.Selected) { "[X]" } else { "[ ]" }
        $sizeStr= Format-Size $item.Size
        $pathStr= Trim-Text $item.Path 80
        $line = "$cursor $mark [$($item.Type)] $sizeStr   $pathStr"
        if ($i -eq $script:index) {
            $sb.AppendLine("${brightGreen}$line${reset}") | Out-Null
        } else {
            $sb.AppendLine($line) | Out-Null
        }
    }

    if ($end -lt $totalItems) {
        $sb.AppendLine("     ${cyan}... more below ...${reset}") | Out-Null
    } else {
        $sb.AppendLine("") | Out-Null
    }

    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("${cyan}Recently deleted (last 2):${reset}") | Out-Null
    if ($script:logLines.Count -gt 0) {
        $count = [math]::Min(2, $script:logLines.Count)
        for ($j = 0; $j -lt $count; $j++) {
            $sb.AppendLine(("  ${gray}" + (Trim-Text $script:logLines[$j] 112) + "${reset}")) | Out-Null
        }
    } else {
        $sb.AppendLine("  ${gray}(none yet)${reset}") | Out-Null
    }

    $sb.AppendLine("${brightRed}Failed deletions (last 2):${reset}") | Out-Null
    if ($script:failedLogLines.Count -gt 0) {
        $count = [math]::Min(2, $script:failedLogLines.Count)
        for ($j = 0; $j -lt $count; $j++) {
            $sb.AppendLine(("  ${brightRed}" + (Trim-Text $script:failedLogLines[$j] 112) + "${reset}")) | Out-Null
        }
    } else {
        $sb.AppendLine("  ${gray}(none)${reset}") | Out-Null
    }

    [Console]::Write($sb.ToString())
}

# Main
$list = Build-CacheList
Draw-UI

while ($true) {
    $key = [Console]::ReadKey($true)

    switch ($key.Key) {
        'UpArrow' {
            if ($script:index -gt 0) { $script:index-- }
            if ($script:index -lt $script:offset) { $script:offset = $script:index }
        }
        'DownArrow' {
            if ($script:index -lt ($list.Count - 1)) { $script:index++ }
            if ($script:index -ge ($script:offset + $script:display)) {
                $script:offset = $script:index - $script:display + 1
            }
        }
        'Spacebar' {
            if ($list.Count -gt 0) {
                $list[$script:index].Selected = -not $list[$script:index].Selected
            }
        }
        'A' {
            foreach ($i in $list) { $i.Selected = $true }
        }
        'U' {
            foreach ($i in $list) { $i.Selected = $false }
        }
        'L' {
            $largeThreshold = 200MB
            foreach ($i in $list) {
                if ($i.Size -gt $largeThreshold -and -not (Is-CriticalPath $i.Path)) {
                    $i.Selected = $true
                }
            }
        }
        'R' {
            $list = Build-CacheList
            $script:index = 0
            $script:offset = 0
        }
        'Enter' {
            $selectedItems = $list | Where-Object { $_.Selected }
            $deletedCount  = 0
            $failedCount   = 0

            foreach ($si in $selectedItems) {
                if (Is-CriticalPath $si.Path) {
                    Add-LogEntry -Message "Skipped critical system path: $($si.Path)" -Failed $true
                    $failedCount++
                    continue
                }

                try {
                    if ($si.Path.Length -ge 260) {
                        $deletePath = "\\?\$($si.Path)"
                    } else {
                        $deletePath = $si.Path
                    }
                    Remove-Item -LiteralPath $deletePath -Recurse -Force -ErrorAction Stop
                    $script:freedSessionBytes += $si.Size
                    Add-LogEntry -Message "Deleted $($si.Path) ($(Format-Size $si.Size))" -Failed $false
                    $deletedCount++
                } catch {
                    Add-LogEntry -Message "Failed: $($si.Path) - $($_.Exception.Message)" -Failed $true
                    $failedCount++
                }
            }

            $list = Build-CacheList
            $script:index = 0
            $script:offset = 0
        }
        'Escape' {
            [Console]::CursorVisible = $true
            Clear-Host
            Write-Host "CashKiller v8 closed. Freed this session: $(Format-Size $script:freedSessionBytes)" -ForegroundColor Green
            break
        }
    }

    Draw-UI
}
