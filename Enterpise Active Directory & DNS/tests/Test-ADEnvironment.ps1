<#
.SYNOPSIS
    End-to-end validation test for the corp.local AD environment.

.DESCRIPTION
    Tests all components of the recommended-tier build:
      - Domain controller health (both DCs)
      - AD replication
      - User and group provisioning
      - GPO configuration and links
      - DNS forward and reverse resolution
      - DHCP scope and failover configuration
      - SYSVOL / NETLOGON shares

    Outputs a pass/fail report. Exit code 0 = all passed.

.NOTES
    Run on DC01 as CORP\Administrator
    Requires: ActiveDirectory, GroupPolicy, DnsServer, DhcpServer modules
#>

#Requires -Module ActiveDirectory

$ErrorActionPreference = "SilentlyContinue"
$pass  = 0
$fail  = 0
$warns = 0
$log   = @()

function Test-Result {
    param([string]$Name, [bool]$Result, [string]$Detail = "", [bool]$IsWarning = $false)
    if ($Result) {
        Write-Host "  ✓ PASS  $Name" -ForegroundColor Green
        if ($Detail) { Write-Host "          $Detail" -ForegroundColor DarkGray }
        $script:pass++
        $script:log += "[PASS] $Name $(if($Detail){"— $Detail"})"
    } elseif ($IsWarning) {
        Write-Host "  ! WARN  $Name" -ForegroundColor Yellow
        if ($Detail) { Write-Host "          $Detail" -ForegroundColor DarkGray }
        $script:warns++
        $script:log += "[WARN] $Name $(if($Detail){"— $Detail"})"
    } else {
        Write-Host "  ✗ FAIL  $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "          $Detail" -ForegroundColor Yellow }
        $script:fail++
        $script:log += "[FAIL] $Name $(if($Detail){"— $Detail"})"
    }
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   corp.local AD Environment — End-to-End Validation       ║" -ForegroundColor Cyan
Write-Host "║   $(Get-Date -Format 'yyyy-MM-dd HH:mm')                                      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════
# 1. DOMAIN CONTROLLER HEALTH
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[1] Domain Controller Health" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$dcs = Get-ADDomainController -Filter * -ErrorAction Stop
Test-Result "Minimum 2 DCs present" ($dcs.Count -ge 2) "$($dcs.Count) DCs: $($dcs.Name -join ', ')"

foreach ($dc in $dcs) {
    $pingable = Test-Connection $dc.IPv4Address -Count 1 -Quiet
    Test-Result "DC $($dc.Name) reachable" $pingable $dc.IPv4Address
    Test-Result "DC $($dc.Name) is GC" $dc.IsGlobalCatalog
}

# FSMO roles
$domain = Get-ADDomain
$forest = Get-ADForest
Test-Result "PDC Emulator assigned" ($null -ne $domain.PDCEmulator) $domain.PDCEmulator
Test-Result "Schema Master assigned" ($null -ne $forest.SchemaMaster) $forest.SchemaMaster

# AD services
foreach ($svc in @("NTDS","ADWS","KDC","Netlogon")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    Test-Result "Service: $svc running" ($s.Status -eq "Running")
}

# ═══════════════════════════════════════════════════════════════
# 2. AD REPLICATION
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[2] AD Replication" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$replPartners = Get-ADReplicationPartnerMetadata -Target (hostname) -ErrorAction SilentlyContinue
$replFailed   = $replPartners | Where-Object { $_.LastReplicationResult -ne 0 }
Test-Result "Replication links exist" ($null -ne $replPartners) "$($replPartners.Count) link(s)"
Test-Result "No replication failures" ($null -eq $replFailed) "Last result codes all 0"

$sysvol = Test-Path "\\$(hostname)\SYSVOL"
$netlogon = Test-Path "\\$(hostname)\NETLOGON"
Test-Result "SYSVOL share accessible"   $sysvol
Test-Result "NETLOGON share accessible" $netlogon

# ═══════════════════════════════════════════════════════════════
# 3. ORGANISATIONAL UNITS
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[3] Organisational Units" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$expectedOUs = @("TechCorp","IT","HR","Development","Servers")
foreach ($ou in $expectedOUs) {
    $exists = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
    Test-Result "OU: $ou exists" ($null -ne $exists) ($exists.DistinguishedName)
}

# ═══════════════════════════════════════════════════════════════
# 4. USERS AND GROUPS
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[4] Users and Groups" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$base = "DC=corp,DC=local"
$users = Get-ADUser -Filter * -SearchBase "OU=TechCorp,$base" -ErrorAction SilentlyContinue
Test-Result "Minimum 10 users exist" ($users.Count -ge 10) "$($users.Count) users found"

$expectedUsers = @("rahul.sharma","priya.patel","meena.iyer","ankit.mehta","sunita.rao","sanjay.kumar","karan.singh","deepa.nair","vikram.joshi","pooja.gupta")
foreach ($u in $expectedUsers) {
    $exists = Get-ADUser -Filter "SamAccountName -eq '$u'" -ErrorAction SilentlyContinue
    Test-Result "User: $u" ($null -ne $exists -and $exists.Enabled)
}

$expectedGroups = @("IT-Admins","HR-Staff","Dev-Team")
foreach ($g in $expectedGroups) {
    $grp = Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue
    Test-Result "Group: $g exists" ($null -ne $grp)
    if ($grp) {
        $members = Get-ADGroupMember $g -ErrorAction SilentlyContinue
        Test-Result "Group $g has members" ($members.Count -gt 0) "$($members.Count) member(s)"
    }
}

# ═══════════════════════════════════════════════════════════════
# 5. GROUP POLICY
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[5] Group Policy" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$gpoModule = Get-Module -ListAvailable GroupPolicy
if ($gpoModule) {
    Import-Module GroupPolicy -ErrorAction SilentlyContinue

    $expectedGPOs = @("Default Domain Policy","HR-Desktop-Policy","Corp-DriveMap-Policy")
    foreach ($gpo in $expectedGPOs) {
        $g = Get-GPO -Name $gpo -ErrorAction SilentlyContinue
        Test-Result "GPO: $gpo exists" ($null -ne $g) ($g.GpoStatus)
    }

    # Check HR GPO is linked to HR OU
    $hrLinks = (Get-GPInheritance -Target "OU=HR,OU=TechCorp,$base" -ErrorAction SilentlyContinue).GpoLinks
    $hrLinked = $hrLinks | Where-Object { $_.DisplayName -eq "HR-Desktop-Policy" }
    Test-Result "HR-Desktop-Policy linked to HR OU" ($null -ne $hrLinked)
} else {
    Test-Result "GroupPolicy module available" $false "Install RSAT tools" -IsWarning $true
}

# ═══════════════════════════════════════════════════════════════
# 6. DNS
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[6] DNS" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$dnsTests = @(
    @{ Name="Resolve DC01.corp.local";   Query="DC01.corp.local" },
    @{ Name="Resolve DC02.corp.local";   Query="DC02.corp.local" },
    @{ Name="Resolve corp.local domain"; Query="corp.local" },
    @{ Name="LDAP SRV record";           Query="_ldap._tcp.corp.local" }
)

foreach ($t in $dnsTests) {
    $result = Resolve-DnsName $t.Query -ErrorAction SilentlyContinue
    Test-Result $t.Name ($null -ne $result) (if($result){$result[0].IPAddress ?? $result[0].NameHost})
}

# Reverse lookup
$revTest = Resolve-DnsName "192.168.10.10" -ErrorAction SilentlyContinue
Test-Result "Reverse lookup 192.168.10.10" ($null -ne $revTest) ($revTest[0].NameHost)

# ═══════════════════════════════════════════════════════════════
# 7. DHCP
# ═══════════════════════════════════════════════════════════════
Write-Host "`n[7] DHCP" -ForegroundColor White
Write-Host "─────────────────────────────────────────"

$dhcpModule = Get-Module -ListAvailable DhcpServer
if ($dhcpModule) {
    Import-Module DhcpServer -ErrorAction SilentlyContinue

    $scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    Test-Result "DHCP scope exists" ($null -ne $scope) "$($scope.ScopeId) — $($scope.State)"

    $stats = Get-DhcpServerv4ScopeStatistics -ScopeId "192.168.10.0" -ErrorAction SilentlyContinue
    if ($stats) {
        $utilPct = if($stats.TotalAddresses -gt 0){ [int](($stats.InUse / $stats.TotalAddresses) * 100) } else { 0 }
        Test-Result "DHCP scope not exhausted" ($stats.Free -gt 0) "Free: $($stats.Free), In Use: $($stats.InUse) ($utilPct%)"
    }

    $failover = Get-DhcpServerv4Failover -ErrorAction SilentlyContinue
    Test-Result "DHCP failover configured" ($null -ne $failover) "$($failover.Name) — Mode: $($failover.Mode), State: $($failover.State)"
} else {
    Test-Result "DhcpServer module available" $false "Install DHCP role on DC01" -IsWarning $true
}

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════
$total = $pass + $fail + $warns

function Format-BoxLine {
    param([string]$Label, [string]$Value)
    # Inner width of box is 59 chars (between the ║ borders)
    # Format: "   Label  Value<pad>"
    $inner   = "   $Label  $Value"
    $padNeeded = 59 - $inner.Length
    if ($padNeeded -lt 0) { $padNeeded = 0 }
    return "║$inner$(' ' * $padNeeded)║"
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Test Summary                                            ║" -ForegroundColor Cyan
Write-Host "╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host (Format-BoxLine "Total:   " "$total tests")
Write-Host (Format-BoxLine "Passed:  " "$pass") -ForegroundColor Green
if ($fail -gt 0) {
    Write-Host (Format-BoxLine "Failed:  " "$fail") -ForegroundColor Red
} else {
    Write-Host (Format-BoxLine "Failed:  " "$fail")
}
if ($warns -gt 0) {
    Write-Host (Format-BoxLine "Warnings:" "$warns") -ForegroundColor Yellow
} else {
    Write-Host (Format-BoxLine "Warnings:" "$warns")
}
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Write log file
$logPath = "C:\ad-test-results-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
$log | Out-File $logPath
Write-Host "Log saved: $logPath" -ForegroundColor DarkGray
Write-Host ""

if ($fail -gt 0) {
    Write-Host "Some tests failed. Check the output above and consult runbooks/." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All required tests passed. Environment is ready." -ForegroundColor Green
    exit 0
}
