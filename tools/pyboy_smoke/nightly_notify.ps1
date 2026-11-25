# Shows a finished nightly run: opens a new regression's report, leaves a notification up, and copies
# the dashboard and report pages to the documents drive. Called by nightly_windows.ps1; run it alone to
# show or copy the last run again:
#   powershell -ExecutionPolicy Bypass -File nightly_notify.ps1 -Headline (Get-Content latest_attempt.txt)
param(
    [string]$Headline = '',
    [string]$Reports = (Join-Path $env:USERPROFILE 'redrogue_nightly_reports'),
    [string]$Documents = 'K:\Other computers\My Laptop\Red Rogue Files\Nightly',
    [switch]$SkipToast,
    [switch]$SkipOpen,
    [switch]$SkipCopy
)

$ErrorActionPreference = 'Stop'
$problems = @()

# "NEW regression -> /mnt/c/Users/.../<night>/report.md" names the night's folder.
$page = Join-Path $Reports 'index.html'
$detail = $Headline
if ($Headline -match '-> /mnt/([a-z])/(.+)/report\.md') {
    $night = "$($Matches[1].ToUpper()):\" + $Matches[2].Replace('/', '\')
    $candidate = Join-Path $night 'report.html'
    if (Test-Path -LiteralPath $candidate) { $page = $candidate }
    try {
        $report = Get-Content -LiteralPath (Join-Path $night 'report.json') -Raw -Encoding utf8 | ConvertFrom-Json
        $new = @($report.regressions)
        if ($report.runner_error) { $new = @($report.runner_error) + $new }
        if ($new.Count) {
            $detail = ($new | Select-Object -First 3) -join "`n"
            if ($new.Count -gt 3) { $detail += "`n+$($new.Count - 3) more" }
        }
    } catch { $problems += "report.json: $($_.Exception.Message)" }
}

if (-not $SkipCopy) {
    try {
        $parent = Split-Path -Parent $Documents
        if (-not (Test-Path -LiteralPath $parent)) { throw "$parent is not available" }
        New-Item -ItemType Directory -Force -Path $Documents | Out-Null
        Get-ChildItem -LiteralPath $Reports -Directory | ForEach-Object {
            foreach ($name in 'report.html', 'report.md') {
                $from = Join-Path $_.FullName $name
                if (-not (Test-Path -LiteralPath $from)) { continue }
                $to = Join-Path (Join-Path $Documents $_.Name) $name
                if ((Test-Path -LiteralPath $to) -and
                    (Get-Item -LiteralPath $to).LastWriteTimeUtc -ge (Get-Item -LiteralPath $from).LastWriteTimeUtc) { continue }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
                Copy-Item -LiteralPath $from -Destination $to -Force
            }
        }
        Copy-Item -LiteralPath (Join-Path $Reports 'index.html') -Destination $Documents -Force
    } catch { $problems += "copy: $($_.Exception.Message)" }
}

# Clean and known-issues nights stay quiet.
if ($Headline -match 'NEW regression') {
    $uri = ([Uri]$page).AbsoluteUri
    if (-not $SkipOpen) {
        try { Start-Process -FilePath $page } catch { $problems += "open: $($_.Exception.Message)" }
    }
    if (-not $SkipToast) {
        try {
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
            $text = [Security.SecurityElement]::Escape($detail)
            $link = [Security.SecurityElement]::Escape($uri)
            $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
            # scenario="reminder" keeps it on screen until it is dismissed.
            $xml.LoadXml("<toast scenario='reminder' activationType='protocol' launch='$link'><visual><binding template='ToastGeneric'><text>Red Rogue nightly: new problem</text><text>$text</text></binding></visual><actions><action content='Open report' activationType='protocol' arguments='$link'/><action content='Dismiss' activationType='system' arguments='dismiss'/></actions></toast>")
            $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Microsoft.Windows.PowerShell').Show($toast)
        } catch { $problems += "toast: $($_.Exception.Message)" }
    }
}

foreach ($problem in $problems) { Write-Output "Notify error: $problem" }
