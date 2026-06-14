# Interview Preparation — Active Directory & DNS

This document covers the most commonly asked interview questions for
Junior Linux Administrator, System Administrator L1, NOC Engineer L1,
and Windows System Administrator roles.

---

## Technical Questions

### Q1: What is the difference between a domain, tree, and forest?

**A:** A **domain** is the basic administrative unit of AD — a single namespace (e.g., `corp.local`)
with its own AD database, security policies, and replication boundary.

A **tree** is a collection of domains sharing a contiguous namespace (e.g., `corp.local`,
`sales.corp.local`, `dev.corp.local`). All domains in a tree share a two-way transitive trust.

A **forest** is the outermost boundary of AD — a collection of one or more trees sharing
a common schema, configuration, and Global Catalog, but not necessarily a common namespace.
The first domain created in a forest is the **forest root domain**.

---

### Q2: How does Kerberos authentication work in AD?

**A:** Kerberos uses a ticket-based system with three parties: the client, the KDC (Key Distribution
Center — which is the DC), and the target service.

1. **AS-REQ/AS-REP:** Client requests a Ticket-Granting Ticket (TGT) from the KDC, proving identity
   with a timestamp encrypted with the user's password hash. KDC returns a TGT.
2. **TGS-REQ/TGS-REP:** Client presents the TGT to request a Service Ticket for a specific service
   (e.g., `cifs/fileserver01`). KDC issues the Service Ticket.
3. **AP-REQ:** Client presents the Service Ticket to the target service. Service decrypts it with
   its own key and grants access.

This is why time sync matters: Kerberos rejects tickets where the timestamp differs by more than
5 minutes (prevents replay attacks). You verify Kerberos is working with `klist`.

---

### Q3: What is the SYSVOL share and why is it critical?

**A:** SYSVOL is a special shared folder replicated to all DCs in the domain. It contains:
- **Group Policy templates** — the actual settings files for all GPOs
- **Logon/logoff scripts**
- **Policy definition files**

SYSVOL replication uses DFSR (Distributed File System Replication). If SYSVOL isn't replicating,
clients can't download GPO settings even if the AD object looks correct in GPMC. You verify with
`net share` (look for SYSVOL and NETLOGON) and by comparing contents of
`\\DC01\SYSVOL\corp.local\Policies` vs `\\DC02\SYSVOL\corp.local\Policies`.

---

### Q4: Explain the difference between GPO scope and inheritance.

**A:** **Scope** controls which objects a GPO can affect — determined by where it's linked (Site,
Domain, or OU) and its Security Filtering (who gets "Apply Group Policy" permission).

**Inheritance** means GPOs linked to parent OUs automatically apply to child OUs and their
objects by default. Processing order is **LSDOU**: Local → Site → Domain → OU (child OUs
last, winning on conflicts).

You can modify inheritance:
- **Block Inheritance** on an OU: child ignores all parent-linked GPOs
- **Enforce** on a GPO link: cannot be blocked by Block Inheritance

---

### Q5: What are FSMO roles and which ones matter most day-to-day?

**A:** FSMO (Flexible Single Master Operations) roles are five functions that only one DC can
perform at a time (unlike multi-master AD object changes).

**Forest-wide (one per forest):**
- **Schema Master** — controls AD schema changes (adding new attributes). Only matters during
  major software installs (Exchange, Lync).
- **Domain Naming Master** — controls adding/removing domains from the forest.

**Domain-wide (one per domain):**
- **RID Master** — allocates pools of RIDs (used to build SIDs for new objects).
- **PDC Emulator** — most important day-to-day: handles password changes, account lockouts,
  time sync for the domain, and legacy NT authentication.
- **Infrastructure Master** — updates cross-domain group membership references.

Check with: `netdom query fsmo`

---

## Scenario Questions

### Q6: A user can't log in from one specific machine but can from others. How do you diagnose?

**A:** This is a machine-specific problem, so I check the machine first, not the user account.

1. `ping DC01.corp.local` from the machine — checks DNS and network connectivity to DC
2. `nslookup corp.local` — verifies DNS is pointing to the DC
3. `klist` after attempted login — if empty, Kerberos TGT wasn't obtained (DC unreachable or clock skew)
4. `gpresult /r` on the machine — checks GPOs applied, might reveal a software restriction policy
5. Event Viewer on the machine: Security log, filter for Event ID 4625 (failed logon) — shows the
   failure sub-status code (e.g., 0xC000006A = wrong password, 0xC0000064 = user doesn't exist)
6. Check the machine's computer account: `Get-ADComputer -Identity CLIENT01` — if disabled or missing, rejoin the domain

---

### Q7: DC01 loses network connectivity at 3am. Walk me through impact and remediation.

**A:**

**Immediate impact:**
- Clients whose Kerberos requests hit DC01 fail auth (new logins fail; existing sessions continue
  using cached credentials for ~10 hours on Windows by default)
- DHCP failover triggers after 60 minutes (MaxClientLeadTime) — DC02 takes over
- DNS continues from DC02 (both DCs run DNS with the same zones)
- New AD objects written to DC01 are inaccessible until DC01 recovers

**Remediation:**
1. Verify DC01 is powered on (check Proxmox / hypervisor console)
2. If network issue: check VM NIC, vSwitch bridge assignment
3. Once DC01 comes back: verify NTDS, KDC, Netlogon, ADWS services start
4. Run `repadmin /syncall /AdeP` to catch up missed replication
5. Verify DHCP failover re-syncs: `Invoke-DhcpServerv4FailoverReplication -Name "Corp-DHCP-Failover" -Force`
6. Check for USN rollback if DC01 was restored from snapshot (never restore DC from snapshot taken during writes)

---

## Troubleshooting Questions

### Q8: repadmin /showrepl shows error 1722. What does this mean?

**A:** Error 1722 is "RPC server unavailable." DC02 can't reach DC01's RPC endpoint, which AD
replication requires.

Primary causes and fixes:
1. **Firewall blocking port 135** — `Test-NetConnection DC01 -Port 135`. Open port 135 (RPC Endpoint
   Mapper) and dynamic ports 49152–65535.
2. **DNS resolution failing** — `nslookup DC01.corp.local 192.168.10.12`. If name doesn't resolve,
   fix DNS first.
3. **RPC service stopped** — `Get-Service RpcSs` on DC01. Should be Running.
4. **Network connectivity** — basic `ping DC01` from DC02.

After fixing: `repadmin /syncall /AdeP` to force sync and confirm 1722 clears.

---

### Q9: What's the difference between DHCP Hot Standby and Load Balance modes?

**A:** Both are Windows DHCP failover modes for redundancy:

**Hot Standby:** One server (Active) serves all DHCP requests. The Standby server only activates if
the Active server becomes unreachable for longer than MaxClientLeadTime. Simpler to understand and
troubleshoot. Good for branch offices.

**Load Balance:** Both servers actively serve DHCP, each handling a configured percentage (default
50/50). Better utilisation of both servers. Standard in production environments. Harder to verify
which server gave which lease.

In this lab I used Hot Standby specifically so I could demonstrate failover visually — shutting DC01
down and watching CLIENT01 renew its IP from DC02 is clear, unambiguous evidence the failover worked.

---

## Incident Response Question

### Q10: You receive an alert that 50 accounts were locked out simultaneously. Initial response?

**A:**

1. **Don't panic or immediately unlock** — mass lockouts indicate a systematic issue, not individual user error

2. **Identify the source** — go to the PDC Emulator (it collects all lockout events):
```powershell
Get-WinEvent -ComputerName (Get-ADDomain).PDCEmulator `
    -FilterHashtable @{LogName='Security'; Id=4740} -MaxEvents 50 |
    Select @{n='LockedAccount'; e={$_.Properties[0].Value}},
           @{n='CallerComputer'; e={$_.Properties[1].Value}},
           TimeCreated
```

3. **Common causes:**
   - Service account password expired: a service (scheduled task, IIS app pool) is hammering
     logins with an old password
   - Password spray attack: attacker trying one password against many accounts
   - Kerberos clock skew: auth failures cascading to lockouts

4. **If service account:** disable the service temporarily, update the password, re-enable

5. **If external attack:** check source IPs in security logs, block at firewall, and alert management

6. **Unlock accounts only after source is contained:**
```powershell
Search-ADAccount -LockedOut | Unlock-ADAccount
```
