# Security Hardening — Active Directory Environment

## Overview

This document covers the security hardening applied to the TechCorp corp.local
Active Directory environment. Each control is mapped to the threat it mitigates.

---

## Applied Hardening Controls

### 1. Password Policy (via Default Domain Policy)

| Setting | Value | Rationale |
|---------|-------|-----------|
| Minimum password length | 12 characters | Prevents brute-force |
| Complexity required | Enabled | Prevents dictionary attacks |
| Password history | 24 passwords | Prevents reuse |
| Maximum age | 90 days | Limits exposure window |
| Minimum age | 1 day | Prevents rapid cycling |
| Reversible encryption | Disabled | Prevents plaintext exposure |

### 2. Account Lockout Policy

| Setting | Value | Rationale |
|---------|-------|-----------|
| Lockout threshold | 5 attempts | Stops online brute-force |
| Lockout duration | 30 minutes | Auto-recovers without helpdesk |
| Observation window | 30 minutes | Resets counter after window |

### 3. AD Recycle Bin

```powershell
# Enable AD Recycle Bin (one-time, irreversible)
Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' `
    -Scope ForestOrConfigurationSet `
    -Target 'corp.local' `
    -Confirm:$false

# Restore deleted object
Get-ADObject -Filter 'isDeleted -eq $true -and Name -like "*rahul*"' `
    -IncludeDeletedObjects | Restore-ADObject
```

**Why:** Prevents accidental permanent deletion of AD objects. Default tombstone
lifetime is 60 days — objects can be restored within that window.

### 4. Disable SMBv1

```powershell
# Disable SMBv1 (EternalBlue / WannaCry vector)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Confirm:$false

# Verify
Get-SmbServerConfiguration | Select EnableSMB1Protocol
# Expected: False
```

### 5. Audit Logon Events

```powershell
# Enable via Default Domain Policy or direct auditpol:
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Account Lockout" /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable

# Verify
auditpol /get /category:"Logon/Logoff"
```

**Key Event IDs to monitor:**

| Event ID | Meaning |
|----------|---------|
| 4624 | Successful logon |
| 4625 | Failed logon attempt |
| 4740 | Account locked out |
| 4648 | Logon with explicit credentials |
| 4672 | Admin privileges assigned |
| 4720 | User account created |
| 4726 | User account deleted |
| 4728/4732 | User added to privileged group |

### 6. DSRM Password

A strong DSRM (Directory Services Restore Mode) password was set during DC promotion.
This is used for offline AD recovery and must be documented securely (not in this repo).

### 7. Protected Users Group

Consider adding privileged accounts (IT-Admins) to the **Protected Users** group:

```powershell
# Protected Users prevents: NTLM, DES, RC4, unconstrained delegation, credential caching
Add-ADGroupMember -Identity "Protected Users" -Members "rahul.sharma","priya.patel"
```

> ⚠️ Test thoroughly before applying in production — Protected Users has strict requirements
> and can lock out accounts if services depend on NTLM.

---

## Threat Model

### Assets

| Asset | Sensitivity |
|-------|-------------|
| AD database (NTDS.dit) | Critical — contains all credential hashes |
| SYSVOL / NETLOGON | High — contains GPOs and scripts |
| DSRM password | Critical — offline domain admin access |
| Domain Admin accounts | Critical |
| Service accounts | High |

### Attack Surface

| Vector | Control |
|--------|---------|
| Password spray attacks | Account lockout (5 attempts / 30 min) |
| Pass-the-Hash (NTLM) | Protected Users group, Credential Guard |
| Kerberoasting | Strong service account passwords, AES encryption |
| DCSync attack | Restrict "Replicating Directory Changes" right |
| SMBv1 exploits (WannaCry) | SMBv1 disabled |
| Accidental deletion | AD Recycle Bin enabled |
| Weak passwords | Complexity + length policy enforced |

---

## Hardening Checklist

- [x] 12-character minimum password with complexity
- [x] 5-attempt account lockout (30-minute auto-unlock)
- [x] AD Recycle Bin enabled
- [x] SMBv1 disabled on all DCs
- [x] Logon audit events enabled
- [x] DSRM password set (documented in vault)
- [ ] Credential Guard enabled (Windows 11 clients)
- [ ] Fine-Grained Password Policy for admin accounts (Advanced tier)
- [ ] LAPS (Local Administrator Password Solution) for workstations (Advanced tier)
- [ ] PAW (Privileged Access Workstation) for domain admins (Advanced tier)
- [ ] AD tiered admin model (Advanced tier)

---

## Incident: Simultaneous Account Lockouts

**Scenario:** 50 accounts lock out simultaneously. Likely causes:

1. Service account with hardcoded expired password hammering logins
2. Distributed password spray attack
3. Kerberos clock skew causing auth failures

```powershell
# Find all locked accounts
Search-ADAccount -LockedOut | Select Name, SamAccountName, LockedOut

# Find the source of lockouts — check PDC Emulator event log
Get-WinEvent -ComputerName (Get-ADDomain).PDCEmulator `
    -FilterHashtable @{LogName='Security'; Id=4740} -MaxEvents 50 |
    Select TimeCreated, `
        @{n='LockedAccount'; e={$_.Properties[0].Value}}, `
        @{n='CallerComputer'; e={$_.Properties[1].Value}} |
    Sort-Object TimeCreated -Descending

# Unlock all accounts (after investigating source)
Search-ADAccount -LockedOut | Unlock-ADAccount
```
