# Runbook 03 — DHCP Scope Exhaustion

| Field | Value |
|-------|-------|
| **Severity** | 🔴 HIGH |
| **Category** | Network / DHCP |
| **Resolution SLA** | 15 minutes |
| **On-call contact** | IT-Admins group |
| **Last reviewed** | 2024 |

---

## Scenario

Clients report they cannot connect to the network. Checking `ipconfig /all` reveals
**APIPA addresses** (169.254.x.x) instead of 192.168.10.x. The DHCP scope is full —
all 101 addresses in 192.168.10.100–200 are leased, many potentially to stale or
abandoned devices.

---

## Symptoms

On an affected client:

```
IPv4 Address:      169.254.x.x       ← APIPA — no DHCP response
Subnet Mask:       255.255.0.0
DHCP Enabled:      Yes
DHCP Server:       (empty)           ← no server responded
```

On DC01 DHCP server:

```powershell
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
# Free: 0   InUse: 101   Reserved: 0   Pending: 0
```

---

## Impact

| Component | Impact |
|-----------|--------|
| New device connections | Cannot obtain IP — no network access |
| Rebooting devices | May get APIPA if lease expired |
| Failover (DC02) | Also full — DC02 can't assign addresses either |
| Authentication | Kerberos / AD auth fails without valid IP |

---

## Phase 1: Detect

```powershell
# On DC01 — check scope statistics
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0

# Check failover state (scope applies to both DCs)
Get-DhcpServerv4Failover

# Full lease list — sorted by expiry
Get-DhcpServerv4Lease -ScopeId 192.168.10.0 |
    Sort-Object LeaseExpiryTime |
    Format-Table IPAddress, HostName, ClientId, LeaseExpiryTime, AddressState -AutoSize
```

**Utilisation threshold:**

| Free Addresses | Status |
|---------------|--------|
| > 20 | ✅ Healthy |
| 10–20 | ⚠️ Monitor closely |
| < 10 | 🔴 Immediate action needed |
| 0 | 🔴 CRITICAL — scope exhausted |

---

## Phase 2: Identify Stale Leases

Scope exhaustion is almost always caused by stale leases — devices that are no longer
on the network but still have active leases.

```powershell
# Find leases with past expiry (ActiveExpired state)
Get-DhcpServerv4Lease -ScopeId 192.168.10.0 |
    Where-Object { $_.AddressState -eq "ActiveExpired" } |
    Select IPAddress, HostName, ClientId, LeaseExpiryTime |
    Sort-Object LeaseExpiryTime |
    Format-Table -AutoSize

# Find leases with no hostname (often abandoned)
Get-DhcpServerv4Lease -ScopeId 192.168.10.0 |
    Where-Object { [string]::IsNullOrEmpty($_.HostName) } |
    Select IPAddress, ClientId, LeaseExpiryTime, AddressState

# Cross-reference with AD computer accounts
$leases = Get-DhcpServerv4Lease -ScopeId 192.168.10.0
$adComputers = Get-ADComputer -Filter * | Select -ExpandProperty Name

$stale = $leases | Where-Object {
    $_.HostName -and ($adComputers -notcontains $_.HostName.Split(".")[0])
}
Write-Host "Leases for non-AD computers ($($stale.Count)):"
$stale | Format-Table IPAddress, HostName, LeaseExpiryTime -AutoSize
```

---

## Phase 3: Resolve

### Option A — Remove specific stale leases (surgical)

Use when you can identify the stale device.

```powershell
# Remove by client ID (MAC address)
Remove-DhcpServerv4Lease -ScopeId 192.168.10.0 -ClientId "00-11-22-33-44-55"

# Remove by IP address
Remove-DhcpServerv4Lease -ScopeId 192.168.10.0 `
    -IPAddress "192.168.10.150"
```

### Option B — Remove all expired leases (bulk)

Use when many leases are in `ActiveExpired` state.

```powershell
$expired = Get-DhcpServerv4Lease -ScopeId 192.168.10.0 |
    Where-Object { $_.AddressState -eq "ActiveExpired" }

Write-Host "Found $($expired.Count) expired leases. Removing..."

$expired | ForEach-Object {
    try {
        Remove-DhcpServerv4Lease -ScopeId 192.168.10.0 -ClientId $_.ClientId
        Write-Host "  Removed: $($_.IPAddress) ($($_.HostName))" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to remove $($_.IPAddress): $_" -ForegroundColor Red
    }
}

# Verify free count increased
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
```

### Option C — Extend the scope range

Use when the scope is genuinely too small for the number of devices.

```powershell
# Extend EndRange (check that new range doesn't conflict with static IPs)
Set-DhcpServerv4Scope `
    -ScopeId   192.168.10.0 `
    -EndRange  192.168.10.230    # Extended from .200 to .230

# Verify
Get-DhcpServerv4Scope
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
```

### Option D — Shorten lease time (long-term)

Shorter leases mean addresses return to the pool faster.

```powershell
# Check current lease duration
(Get-DhcpServerv4Scope -ScopeId 192.168.10.0).LeaseDuration

# Shorten to 4 hours for lab (devices cycle faster)
Set-DhcpServerv4Scope -ScopeId 192.168.10.0 `
    -LeaseDuration (New-TimeSpan -Hours 4)

# For production (1 day is typical for most environments)
Set-DhcpServerv4Scope -ScopeId 192.168.10.0 `
    -LeaseDuration (New-TimeSpan -Days 1)
```

---

## Phase 4: Verify Resolution

```powershell
# Confirm free addresses are available
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
# Free should be > 0

# Test from an affected client:
ipconfig /release
ipconfig /renew
ipconfig /all   # Should now show 192.168.10.x from DHCP scope
```

---

## Phase 5: Document & Prevent

**Root cause determination:**

- [ ] Lease time too long (default 8 days) — devices leave but leases persist
- [ ] Sudden growth in devices (new laptops, VMs, IoT)
- [ ] Scope too small for the environment
- [ ] Devices with duplicate MACs / VMs cloning issue

**Preventive measures:**

1. **Monitor scope utilisation** — alert at 80% (< 20 free addresses)

```powershell
# Add this to a scheduled task running daily
$stats = Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
$freePercent = [int](($stats.Free / $stats.TotalAddresses) * 100)
if ($freePercent -lt 20) {
    Write-Warning "DHCP scope utilisation critical: $($freePercent)% free"
    # Add: Send-MailMessage or Teams webhook here
}
```

2. **Size scopes for 2× expected device count** — in production, plan for growth
3. **Use reservations for servers** — keeps them out of the dynamic range
4. **Review leases monthly** — remove orphaned entries for decommissioned devices

---

## IP Planning Reference

```
192.168.10.0/24 — corp.local LAN

Static assignments (excluded from DHCP):
  .1          — Default gateway / router
  .10         — DC01 (Windows Server 2022)
  .11         — LNX-DC01 (Samba AD)
  .12         — DC02 (Windows Server 2022)
  .20         — webserver01
  .21         — fileserver01
  .2–.99      — Reserved for future servers

DHCP dynamic pool:
  .100–.200   — 101 addresses for client devices
  
Reserved:
  .201–.254   — Available for expansion or reservations
```
