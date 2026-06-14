<#
.SYNOPSIS
    Active Directory Replication Health Monitor

.DESCRIPTION
    Checks replication status across all domain controllers.
    Reports failures with diagnostic guidance.
    Exit code 0 = healthy, 1 = failures detected.

    Schedule via Task Scheduler to run daily and alert on non-zero exit.

.EXAMPLE
    .\Get-ReplicationStatus.ps1
    .\Get-ReplicationStatus.ps1 -Verbose
    .\Get-ReplicationStatus.ps1 -EmailAlert -SmtpServer "mail.corp.local"

.NOTES
    Run on any DC as CORP\Administrator
    Requires: ActiveDirectory module
#>

#Requires -Module ActiveDirectory

param (
    [switch]$EmailAlert,
    [string]$SmtpServer   = "mail.corp.local",
    [string]$AlertTo      = "it-admin@corp.local",
    [string]$AlertFrom    = "monitoring@corp.local"
)

$ErrorActionPreference = "SilentlyContinue"
$timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$domain     = (Get-ADDomain).DNSRoot
$dcs        = Get-ADDomainController -Filter * | Select-Object -ExpandProperty Name
$results    = @()
$totalFails = 0

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   AD Replication Health Monitor              ║" -ForegroundColor Cyan
Write-Host "║   $(Get-Date -Format 'yyyy-MM-dd HH:mm')                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Domain : $domain"
Write-Host "DCs    : $($dcs -join ', ')"
Write-Host ""

# ─── Check Each DC ────────────────────────────────────────────
foreach ($dc in $dcs) {
    Write-Host "Checking $dc..." -NoNewline

    try {
        $partners = Get-ADReplicationPartnerMetadata -Target $dc -ErrorAction Stop

        if (-not $partners) {
            Write-Host " [NO PARTNERS]" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                SourceDC    = $dc
                PartnerDC   = "N/A"
                LastSuccess = "N/A"
                ResultCode  = -1
                Status      = "NO_PARTNERS"
                TimeSince   = "N/A"
            }
            continue
        }

        foreach ($partner in $partners) {
            $partnerShort = $partner.Partner -replace "CN=NTDS Settings,CN=","" -replace ",.*",""
            $isHealthy    = ($partner.LastReplicationResult -eq 0)
            $timeSince    = if ($partner.LastReplicationSuccess) {
                $diff = (Get-Date) - $partner.LastReplicationSuccess
                "{0}h {1}m" -f [int]$diff.TotalHours, $diff.Minutes
            } else { "NEVER" }

            if (-not $isHealthy) { $totalFails++ }

            $results += [PSCustomObject]@{
                SourceDC    = $dc
                PartnerDC   = $partnerShort
                LastSuccess = if ($partner.LastReplicationSuccess) { $partner.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm") } else { "NEVER" }
                ResultCode  = $partner.LastReplicationResult
                Status      = if ($isHealthy) { "OK" } else { "FAILED ($($partner.LastReplicationResult))" }
                TimeSince   = $timeSince
            }
        }
        Write-Host " OK" -ForegroundColor Green

    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
        $totalFails++
        $results += [PSCustomObject]@{
            SourceDC    = $dc
            PartnerDC   = "UNREACHABLE"
            LastSuccess = "N/A"
            ResultCode  = -1
            Status      = "ERROR: $($_.Exception.Message)"
            TimeSince   = "N/A"
        }
    }
}

# ─── Display Results ──────────────────────────────────────────
Write-Host ""
Write-Host "Replication Status Report" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────────"
$results | Format-Table SourceDC, PartnerDC, LastSuccess, TimeSince, Status -AutoSize

# ─── FSMO Roles ───────────────────────────────────────────────
Write-Host "FSMO Role Holders" -ForegroundColor Cyan
Write-Host "─────────────────────────────────────────────────────────────────"
try {
    $domain_info = Get-ADDomain
    $forest_info = Get-ADForest
    [PSCustomObject]@{
        "Schema Master"         = $forest_info.SchemaMaster
        "Domain Naming Master"  = $forest_info.DomainNamingMaster
        "PDC Emulator"          = $domain_info.PDCEmulator
        "RID Master"            = $domain_info.RIDMaster
        "Infrastructure Master" = $domain_info.InfrastructureMaster
    } | Format-List
} catch {
    Write-Host "Could not retrieve FSMO info: $_" -ForegroundColor Yellow
}

# ─── Final Status ─────────────────────────────────────────────
Write-Host "─────────────────────────────────────────────────────────────────"
if ($totalFails -gt 0) {
    Write-Host ""
    Write-Host "  ✗ $totalFails replication failure(s) detected!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Diagnostic steps:" -ForegroundColor Yellow
    Write-Host "    1. repadmin /showrepl          — detailed failure info" -ForegroundColor DarkGray
    Write-Host "    2. repadmin /syncall /AdeP     — force sync all DCs" -ForegroundColor DarkGray
    Write-Host "    3. ping <partner DC>            — check network reachability" -ForegroundColor DarkGray
    Write-Host "    4. Test-NetConnection DC02 -Port 135  — check RPC" -ForegroundColor DarkGray
    Write-Host "    5. See: runbooks/ad-replication-failure.md" -ForegroundColor DarkGray
    Write-Host ""

    if ($EmailAlert) {
        try {
            $body = "AD Replication failure detected at $timestamp.`n`nFailed links: $totalFails`n`n"
            $body += $results | Where-Object { $_.Status -ne "OK" } | Out-String
            $body += "`nRun: repadmin /showrepl for details."
            Send-MailMessage -To $AlertTo -From $AlertFrom -Subject "[ALERT] AD Replication Failure - $domain" `
                -Body $body -SmtpServer $SmtpServer
            Write-Host "  Email alert sent to $AlertTo" -ForegroundColor Yellow
        } catch {
            Write-Host "  Could not send email: $_" -ForegroundColor Red
        }
    }

    exit 1
} else {
    Write-Host ""
    Write-Host "  ✓ All replication links healthy." -ForegroundColor Green
    Write-Host ""
    exit 0
}
