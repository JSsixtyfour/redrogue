param([switch]$Quick, [switch]$SkipToast)

$ErrorActionPreference = 'Stop'
$reports = Join-Path $env:USERPROFILE 'redrogue_nightly_reports'
$log = Join-Path $reports 'nightly_runs.log'
$latest = Join-Path $reports 'latest_attempt.txt'
$headline = 'NEW regression - Windows wrapper failed'
$code = 2
$held = $false
$runLog = Join-Path $reports ".nightly-attempt-$PID.log"

try {
    Add-Type @"
using System.Runtime.InteropServices;
public static class NightlyPower {
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint flags);
}
"@
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED. Keep the display power policy intact.
    $held = [NightlyPower]::SetThreadExecutionState([uint32]2147483649) -ne 0
    if (-not $held) { throw 'Could not acquire the system-required power request.' }

    $linuxReports = '/mnt/c/Users/justi/redrogue_nightly_reports'
    $runner = '/mnt/c/Users/justi/redrogue/tools/pyboy_smoke/nightly.py'
    $flags = '--force'
    if ($Quick) {
        $flags += ' --quick --suites sram'
    }
    # Stop the existing run at 12 hours before another run can acquire the lock.
    & wsl.exe -- bash -c "exec timeout --kill-after=30s 12h python3 '$runner' $flags > '$linuxReports/.nightly-attempt-$PID.log' 2>&1"
    $code = $LASTEXITCODE
    if (Test-Path -LiteralPath $runLog) {
        Get-Content -LiteralPath $runLog -Encoding utf8 | Add-Content -LiteralPath $log -Encoding utf8
        $result = Get-Content -LiteralPath $runLog -Encoding utf8 |
            Select-String '^(clean|known issues only|NEW regression) -> ' | Select-Object -Last 1
    }
    if ($result) {
        $headline = $result.Line
    } else {
        $headline = "NEW regression - nightly runner stopped without a report (WSL exit $code)"
        $code = 2
    }
} catch {
    $headline = "NEW regression - $($_.Exception.Message)"
    $code = 2
} finally {
    if ($held) { [void][NightlyPower]::SetThreadExecutionState([uint32]2147483648) }
    if (Test-Path -LiteralPath $runLog) { Remove-Item -LiteralPath $runLog }
}

$attempt = "$(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') $headline"
Add-Content -LiteralPath $log -Value $attempt -Encoding utf8
if (-not $Quick) { Set-Content -LiteralPath $latest -Value $attempt -Encoding utf8 }
if (-not $SkipToast) {
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $message = [Security.SecurityElement]::Escape($headline)
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>Red Rogue nightly</text><text>$message</text></binding></visual></toast>")
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Microsoft.Windows.PowerShell').Show($toast)
    } catch {
        Add-Content -LiteralPath $log -Value "Toast delivery error: $($_.Exception.Message)" -Encoding utf8
    }
}
Write-Output $attempt
exit $code
