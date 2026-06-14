# DHCP Setup & Failover — Operations Guide

## Overview

DHCP is deployed across both domain controllers in Hot Standby failover mode.
DC01 is the Active server; DC02 is the Standby. If DC01 is unreachable for
more than 60 minutes, DC02 automatically takes over.

---

## Scope Configuration

| Parameter | Value |
|-----------|-------|
| Scope Name | Corp-LAN-Scope |
| Network | 192.168.10.0/24 |
| Dynamic Range | 192.168.10.100–192.168.10.200 |
| Excluded | 192.168.10.1–99 (static devices) |
| Lease Duration | 8 days (lab); 1 day (production) |
| Gateway (Option 3) | 192.168.10.1 |
| DNS Servers (Option 6) | 192.168.10.10, 192.168.10.12 |
| Domain Name (Option 15) | corp.local |

---

## Failover Configuration

| Parameter | Value |
|-----------|-------|
| Relationship Name | Corp-DHCP-Failover |
| Mode | Hot Standby |
| Active Server | DC01 (192.168.10.10) |
| Standby Server | DC02 (192.168.10.12) |
| MaxClientLeadTime | 60 minutes |
| Auto State Transition | Enabled |
| Shared Secret | DHCPf@il0ver! (stored in vault) |

---

## Day-to-Day Operations

### Check scope health

```powershell
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
```

### View current leases

```powershell
Get-DhcpServerv4Lease -ScopeId 192.168.10.0 |
    Sort-Object IPAddress |
    Format-Table IPAddress, HostName, LeaseExpiryTime, AddressState -AutoSize
```

### Create a reservation (static IP via DHCP)

```powershell
Add-DhcpServerv4Reservation `
    -ScopeId   192.168.10.0 `
    -IPAddress "192.168.10.201" `
    -ClientId  "AA-BB-CC-DD-EE-FF" `
    -Name      "printer01" `
    -Description "Floor 2 HP LaserJet"
```

### Force failover re-sync after DC01 recovery

```powershell
Invoke-DhcpServerv4FailoverReplication -Name "Corp-DHCP-Failover" -Force
```

---

## Troubleshooting

See [`runbooks/dhcp-scope-exhaustion.md`](../../runbooks/dhcp-scope-exhaustion.md)
for the full scope exhaustion incident runbook.

### Quick diagnostics

```powershell
# Is DHCP service running?
Get-Service DHCPServer

# Is server authorised in AD?
Get-DhcpServerInDC

# What is the failover state?
Get-DhcpServerv4Failover

# Recent DHCP events
Get-EventLog -LogName System -Source "Microsoft-Windows-DHCP*" -Newest 20
```
