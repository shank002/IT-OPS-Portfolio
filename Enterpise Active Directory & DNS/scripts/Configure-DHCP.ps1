<#
.SYNOPSIS
    Configures DHCP Server with Hot-Standby failover for TechCorp corp.local

.DESCRIPTION
    Part 1 (run on DC01): Install DHCP, create scope, configure options
    Part 2 (run on DC02): Install DHCP
    Part 3 (run on DC01): Configure Hot-Standby failover partnership

    Run each part in order. DC02 must be promoted as additional DC first.

.NOTES
    Scope:        192.168.10.0/24
    DHCP range:   192.168.10.100–200
    Exclusions:   192.168.10.1–99 (static IPs)
    Failover:     Hot Standby — DC02 activates if DC01 unreachable for 60 min
#>

#Requires -RunAsAdministrator

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Part1-DC01","Part2-DC02","Part3-Failover","Test","Status")]
    [string]$Action
)

$ErrorActionPreference = "Stop"
$ScopeId    = "192.168.10.0"
$ScopeStart = "192.168.10.100"
$ScopeEnd   = "192.168.10.200"
$SubnetMask = "255.255.255.0"
$Gateway    = "192.168.10.1"
$DC01IP     = "192.168.10.10"
$DC02IP     = "192.168.10.12"
$DC01FQDN   = "DC01.corp.local"
$DC02FQDN   = "DC02.corp.local"
$Domain     = "corp.local"
$FailoverName   = "Corp-DHCP-Failover"
$FailoverSecret = "DHCPf@il0ver!"

switch ($Action) {

    "Part1-DC01" {
        Write-Host "`n=== Part 1: DHCP Setup on DC01 ===" -ForegroundColor Cyan

        # Install DHCP role
        Write-Host "[1] Installing DHCP Server role..." -NoNewline
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        Write-Host " Done" -ForegroundColor Green

        # Authorise in AD
        Write-Host "[2] Authorising DHCP server in AD..." -NoNewline
        try {
            Add-DhcpServerInDC -DnsName $DC01FQDN -IPAddress $DC01IP
            Write-Host " Done" -ForegroundColor Green
        } catch {
            Write-Host " Already authorised" -ForegroundColor Yellow
        }

        # Create scope
        Write-Host "[3] Creating DHCP scope..." -NoNewline
        try {
            Add-DhcpServerv4Scope `
                -Name        "Corp-LAN-Scope" `
                -StartRange  $ScopeStart `
                -EndRange    $ScopeEnd `
                -SubnetMask  $SubnetMask `
                -Description "Main LAN scope for corp.local clients" `
                -LeaseDuration (New-TimeSpan -Days 8)
            Write-Host " Done" -ForegroundColor Green
        } catch {
            Write-Host " Scope may already exist: $_" -ForegroundColor Yellow
        }

        # Exclusions for static IPs
        Write-Host "[4] Adding exclusion range (static IPs)..." -NoNewline
        try {
            Add-DhcpServerv4ExclusionRange `
                -ScopeId    $ScopeId `
                -StartRange "192.168.10.1" `
                -EndRange   "192.168.10.99"
            Write-Host " Done" -ForegroundColor Green
        } catch {
            Write-Host " Exclusion may already exist" -ForegroundColor Yellow
        }

        # Scope options (gateway, DNS, domain)
        Write-Host "[5] Setting scope options (gateway, DNS, domain)..." -NoNewline
        Set-DhcpServerv4OptionValue `
            -ScopeId   $ScopeId `
            -Router    $Gateway `
            -DnsServer $DC01IP, $DC02IP `
            -DnsDomain $Domain
        Write-Host " Done" -ForegroundColor Green

        # Activate scope
        Write-Host "[6] Activating scope..." -NoNewline
        Set-DhcpServerv4Scope -ScopeId $ScopeId -State Active
        Write-Host " Done" -ForegroundColor Green

        Write-Host "`n✓ Part 1 complete. Now run Part2-DC02 on DC02." -ForegroundColor Green
    }

    "Part2-DC02" {
        Write-Host "`n=== Part 2: DHCP Installation on DC02 ===" -ForegroundColor Cyan

        Write-Host "[1] Installing DHCP Server role..." -NoNewline
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        Write-Host " Done" -ForegroundColor Green

        Write-Host "[2] Authorising DC02 DHCP in AD..." -NoNewline
        try {
            Add-DhcpServerInDC -DnsName $DC02FQDN -IPAddress $DC02IP
            Write-Host " Done" -ForegroundColor Green
        } catch {
            Write-Host " Already authorised" -ForegroundColor Yellow
        }

        Write-Host "`n✓ Part 2 complete. Now run Part3-Failover on DC01." -ForegroundColor Green
    }

    "Part3-Failover" {
        Write-Host "`n=== Part 3: Configure Hot-Standby Failover ===" -ForegroundColor Cyan
        Write-Host "Active server:  DC01 ($DC01IP)"
        Write-Host "Standby server: DC02 ($DC02IP)"
        Write-Host "Mode:           Hot Standby (DC02 takes over if DC01 unreachable > 60 min)"
        Write-Host ""

        try {
            Add-DhcpServerv4Failover `
                -Name                  $FailoverName `
                -ScopeId               $ScopeId `
                -PartnerServer         $DC02FQDN `
                -Mode                  HotStandby `
                -ServerRole            Active `
                -StandbyPercent        0 `
                -AutoStateTransition   $true `
                -MaxClientLeadTime     (New-TimeSpan -Minutes 60) `
                -SharedSecret          $FailoverSecret

            Write-Host "✓ Failover partnership configured successfully" -ForegroundColor Green
        } catch {
            Write-Host "ERROR configuring failover: $_" -ForegroundColor Red
        }

        # Show status inline after configuring failover
        Write-Host "`n=== Failover Status ===" -ForegroundColor Cyan
        Get-DhcpServerv4Failover -ErrorAction SilentlyContinue | Format-List
        Write-Host "Scope Statistics:" -ForegroundColor White
        Get-DhcpServerv4ScopeStatistics -ScopeId $ScopeId -ErrorAction SilentlyContinue | Format-Table -AutoSize
    }

    "Test" {
        Write-Host "`n=== DHCP Failover Test Procedure ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Step 1: Verify CLIENT01 gets IP from DC01" -ForegroundColor White
        Write-Host "  On CLIENT01: ipconfig /release && ipconfig /renew"
        Write-Host "  Expected DHCP Server: $DC01IP"
        Write-Host ""
        Write-Host "Step 2: Check active lease on DC01" -ForegroundColor White
        Get-DhcpServerv4Lease -ScopeId $ScopeId -ErrorAction SilentlyContinue |
            Format-Table IPAddress, ClientId, HostName, LeaseExpiryTime, AddressState -AutoSize
        Write-Host ""
        Write-Host "Step 3: Simulate DC01 failure" -ForegroundColor Yellow
        Write-Host "  Action: Shut down DC01 (Stop-Computer -Force on DC01, or via Proxmox)"
        Write-Host "  Wait:   60-90 seconds for failover to trigger"
        Write-Host ""
        Write-Host "Step 4: On CLIENT01, renew again" -ForegroundColor White
        Write-Host "  ipconfig /release && ipconfig /renew"
        Write-Host "  Expected DHCP Server: $DC02IP  ← confirms failover worked"
        Write-Host ""
        Write-Host "Step 5: Bring DC01 back and re-sync" -ForegroundColor White
        Write-Host "  Invoke-DhcpServerv4FailoverReplication -Name '$FailoverName' -Force"
    }

    "Status" {
        Write-Host "`n=== DHCP Status ===" -ForegroundColor Cyan

        Write-Host "`nScope:" -ForegroundColor White
        Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Format-Table -AutoSize

        Write-Host "Scope Statistics:" -ForegroundColor White
        Get-DhcpServerv4ScopeStatistics -ScopeId $ScopeId -ErrorAction SilentlyContinue | Format-Table -AutoSize

        Write-Host "Failover Relationship:" -ForegroundColor White
        Get-DhcpServerv4Failover -ErrorAction SilentlyContinue | Format-List

        Write-Host "Active Leases:" -ForegroundColor White
        Get-DhcpServerv4Lease -ScopeId $ScopeId -ErrorAction SilentlyContinue |
            Sort-Object IPAddress |
            Format-Table IPAddress, HostName, LeaseExpiryTime, AddressState -AutoSize
    }
}
