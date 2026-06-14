# AD Monitoring & Observability

## Key Metrics to Monitor

| Metric | Tool | Alert Threshold |
|--------|------|----------------|
| AD replication failures | `repadmin /replsummary` | Any failure > 0 |
| DHCP scope utilisation | `Get-DhcpServerv4ScopeStatistics` | > 80% used |
| Failed logon events | Event ID 4625 | > 10 in 5 minutes |
| Account lockouts | Event ID 4740 | > 5 in 5 minutes |
| DC service health | `Get-Service` | Any NTDS/KDC/Netlogon not Running |
| Replication lag | `repadmin /showrepl` | LastAttempt failure > 1 hour |

---

## Automated Daily Checks

### Replication Monitor (scheduled task)

```powershell
# Create daily scheduled task on DC01
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NonInteractive -File C:\scripts\Get-ReplicationStatus.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00AM"
$principal = New-ScheduledTaskPrincipal -UserId "CORP\Administrator" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "AD-ReplicationMonitor" `
    -Action $action -Trigger $trigger -Principal $principal
```

### DHCP Utilisation Check

```powershell
# Add to same or separate scheduled task
$stats   = Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
$freePct = [int](($stats.Free / $stats.TotalAddresses) * 100)
if ($freePct -lt 20) {
    $msg = "DHCP WARNING: Only $($stats.Free) addresses free ($freePct% remaining)"
    Write-EventLog -LogName Application -Source "DHCP-Monitor" `
        -EventId 9001 -EntryType Warning -Message $msg
}
```

---

## Key Event IDs Reference

| Event ID | Log | Meaning |
|----------|-----|---------|
| 4624 | Security | Successful interactive/network logon |
| 4625 | Security | Failed logon attempt |
| 4740 | Security | User account locked out |
| 4648 | Security | Logon using explicit credentials |
| 4672 | Security | Special privileges assigned at logon (admin) |
| 4720 | Security | User account created |
| 4726 | Security | User account deleted |
| 4728 | Security | User added to global group |
| 4732 | Security | User added to local group |
| 1864 | Directory Service | Replication not occurring (>24h) |
| 1722 | Directory Service | RPC error during replication |

---

## dcdiag Key Tests

```powershell
dcdiag /v                          # Verbose — all tests
dcdiag /test:dns                   # DNS-specific tests
dcdiag /test:replications          # Replication topology
dcdiag /test:netlogons             # NETLOGON share accessibility
dcdiag /test:fsmocheck             # FSMO role holder reachability
dcdiag /s:DC02                     # Test DC02 from DC01
```

All tests should report `passed`. Keep `dcdiag /v` output as portfolio evidence.
