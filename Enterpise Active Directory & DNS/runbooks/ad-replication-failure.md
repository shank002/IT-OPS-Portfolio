# Runbook 01 — AD Replication Failure

| Field | Value |
|-------|-------|
| **Severity** | 🔴 HIGH |
| **Category** | Identity Infrastructure |
| **Resolution SLA** | 30 minutes |
| **On-call contact** | IT-Admins group |
| **Last reviewed** | 2024 |

---

## Scenario

DC02 stops replicating from DC01. New users created on DC01 don't appear on DC02.
Clients whose authentication happens to hit DC02 may be unable to log in with recently
created accounts. `repadmin /showrepl` reports error **1722** (RPC server unavailable)
or **8453** (Access Denied).

---

## Impact

| Component | Impact |
|-----------|--------|
| New user accounts | Not visible on stale DC — login fails if routed there |
| Password changes | May not propagate within 15-second intrasite window |
| GPO changes | May not apply to clients whose DC is stale |
| DNS changes | New DNS records may not appear on all DCs |

---

## Phase 1: Detect

```powershell
# Check replication summary (fastest overview)
repadmin /replsummary

# Detailed per-link status
repadmin /showrepl

# PowerShell (our monitoring script)
.\scripts\Get-ReplicationStatus.ps1

# Check Event Log for replication errors
Get-EventLog -LogName "Directory Service" -EntryType Error -Newest 20 |
    Select TimeGenerated, EventID, Message | Format-List
```

**Signs of replication failure:**

- `repadmin /replsummary` shows `Fails > 0` for any naming context
- Event ID **1864** — replication not occurring for > 24 hours
- Event ID **1388** or **1988** — lingering objects detected
- New users/GPOs visible on DC01 but not DC02

---

## Phase 2: Assess Impact

1. Identify which DC is affected: `repadmin /showrepl` shows the direction of failure
2. Check when last successful replication occurred: `Get-ADReplicationPartnerMetadata -Target DC02`
3. Determine if any critical changes were made since failure (new users, password resets)

---

## Phase 3: Diagnose

Work through causes in order. Stop at the first one that resolves the issue.

### Check 3.1 — Network connectivity

```powershell
# From DC01
ping DC02.corp.local
ping 192.168.10.12

# Test RPC endpoint (required for replication)
Test-NetConnection DC02.corp.local -Port 135
Test-NetConnection DC02.corp.local -Port 445

# From DC02
ping DC01.corp.local
ping 192.168.10.10
```

**If ping fails** → network issue, not AD. Check VM is powered on, check vSwitch/bridge.

### Check 3.2 — DNS resolution between DCs

```powershell
# From DC01, resolve DC02
nslookup DC02.corp.local 192.168.10.10

# From DC02, resolve DC01
nslookup DC01.corp.local 192.168.10.12

# Check SRV records exist
nslookup -type=SRV _ldap._tcp.corp.local
```

**If DNS fails** → stale DNS records. Skip to Resolution 3.

### Check 3.3 — Services on the affected DC

```powershell
# Check on DC02
Get-Service NTDS, ADWS, KDC, Netlogon, RpcSs, W32tm | Select Name, Status
```

**Expected:** All `Running`. If any are `Stopped` → skip to Resolution 2.

### Check 3.4 — Time synchronisation

```powershell
# Kerberos requires time within 5 minutes between DCs
w32tm /query /status
w32tm /stripchart /computer:DC01.corp.local /samples:3
```

**If offset > 5 minutes** → skip to Resolution 4.

### Check 3.5 — Firewall

```powershell
# AD replication uses dynamic RPC ports plus port 135 and 445
Test-NetConnection DC02 -Port 135
Test-NetConnection DC02 -Port 389
Test-NetConnection DC02 -Port 445
Test-NetConnection DC02 -Port 636
```

---

## Phase 4: Resolve

### Resolution 1 — Force manual replication

Try this first. Resolves transient failures in most cases.

```powershell
# Force sync from DC01 to all partners
repadmin /syncall /AdeP

# Or sync a specific partner
repadmin /replicate DC02 DC01 "DC=corp,DC=local"
repadmin /replicate DC02 DC01 "CN=Schema,CN=Configuration,DC=corp,DC=local"
repadmin /replicate DC02 DC01 "CN=Configuration,DC=corp,DC=local"
```

### Resolution 2 — Restart AD services

```powershell
# Run on the affected DC
net stop netlogon
net start netlogon

# If NTDS needs restart (brief outage — OK in lab)
Restart-Service NTDS -Force
```

### Resolution 3 — Fix stale DNS records

```powershell
# Clear DNS cache on affected DC
Clear-DnsClientCache
Restart-Service DNS

# Re-register DC's DNS records
ipconfig /registerdns
nltest /dsregdns

# Force DC to re-register all SRV records
net stop netlogon
net start netlogon
```

### Resolution 4 — Fix time synchronisation

```powershell
# On DC02 (non-PDC)
w32tm /config /syncfromflags:domhier /reliable:no /update
net stop w32tm && net start w32tm
w32tm /resync /force

# On DC01 (PDC Emulator)
w32tm /config /manualpeerlist:"pool.ntp.org" /syncfromflags:manual /reliable:yes /update
net stop w32tm && net start w32tm
```

### Resolution 5 — Repair USN rollback (snapshot restored)

> ⚠️ **Use only if DC was restored from a VM snapshot.** This causes a USN rollback which
> permanently invalidates the DC until cleaned up.

```powershell
# Mark DC as non-authoritative (forces full replication)
# Run on the affected DC:
repadmin /options DC02 +DISABLE_OUTBOUND_REPL
# Take snapshot/backup FIRST, then:
repadmin /options DC02 -DISABLE_OUTBOUND_REPL
repadmin /syncall DC02 /AdeP
```

---

## Phase 5: Verify Resolution

```powershell
# Replication should now be clean
repadmin /replsummary

# Create a test object on DC01, verify it appears on DC02
New-ADUser -Name "RepTest" -SamAccountName "reptest" `
    -Path "OU=IT,OU=TechCorp,DC=corp,DC=local" -Enabled $false
Start-Sleep -Seconds 20
# On DC02:
Get-ADUser -Identity "reptest"   # Should return user

# Cleanup
Remove-ADUser -Identity "reptest" -Confirm:$false
```

---

## Phase 6: Document & Prevent

After resolution, update the incident log:

1. **Root cause identified:** (network / services / DNS / time / other)
2. **Time to detect:** ___
3. **Time to resolve:** ___
4. **User impact:** ___

**Prevention:**

- Schedule `scripts/Get-ReplicationStatus.ps1` as a daily Task Scheduler job
- Alert if exit code is non-zero
- Never restore a DC from a snapshot taken during an AD write — use AD Recycle Bin instead
- Set up Event ID monitoring: 1864 (replication overdue), 1722 (RPC error)

---

## Common Error Codes

| Error | Meaning | Primary Cause |
|-------|---------|---------------|
| 1722 | RPC server unavailable | Network / firewall blocking port 135 |
| 8453 | Access denied | Kerberos / time skew |
| 8606 | Insufficient attributes | Schema mismatch |
| 1988 | Lingering objects | DC offline > tombstone lifetime (60 days) |
| -2146893022 | Authentication failure | Kerberos / time > 5 min skew |
