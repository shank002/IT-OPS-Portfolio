# Runbook 02 — GPO Not Applying to Client

| Field | Value |
|-------|-------|
| **Severity** | 🟡 MEDIUM |
| **Category** | Group Policy / Desktop Management |
| **Resolution SLA** | 1 hour |
| **On-call contact** | IT-Admins group |
| **Last reviewed** | 2024 |

---

## Scenario

A user reports:
- H: drive is not mapped
- Can still access Control Panel despite HR restriction
- Software or settings aren't appearing after policy change

`gpresult /r` on the client shows the GPO is either absent or filtered out.

---

## Impact

| Component | Impact |
|-----------|--------|
| Drive mapping | Missing shared drive access |
| Desktop restrictions | Security policy not enforced |
| Software deployment | Applications not installed |
| Password policy | Relaxed policies may be in effect |

---

## Phase 1: Detect — Gather Information First

Run on the **client machine** (CLIENT01) as the affected user:

```powershell
# Quick overview — applied GPOs + any filter reasons
gpresult /r

# Full HTML report — open in browser
gpresult /h C:\gpreport.html /f
Start-Process C:\gpreport.html

# Identify which DC authenticated the user this session
klist   # shows the DC in the "KDC" field of the TGT
```

**Look for in `gpresult /r`:**

```
The following GPOs were NOT applied because they were filtered out:
  HR-Desktop-Policy
    Filtering: Not Applied (Empty)        ← GPO has no settings
    Filtering: Denied (Security)          ← user not in security filter group
    Filtering: Disabled (Link)            ← GPO link is disabled
```

---

## Phase 2: Diagnose

Work through these checks in order.

### Check 2.1 — User is in the correct OU

```powershell
# On DC01
Get-ADUser -Identity "ankit.mehta" | Select DistinguishedName
```

**Expected for HR user:**
```
CN=Ankit Mehta,OU=HR,OU=TechCorp,DC=corp,DC=local
```

**If user is in wrong OU**, the GPO linked to HR OU won't apply to them.

```powershell
# Fix — move user to correct OU
Move-ADObject `
    -Identity   "CN=Ankit Mehta,OU=IT,OU=TechCorp,DC=corp,DC=local" `
    -TargetPath "OU=HR,OU=TechCorp,DC=corp,DC=local"
```

### Check 2.2 — GPO is linked to the correct OU

```powershell
# On DC01 — check GPO links on HR OU
Get-GPInheritance -Target "OU=HR,OU=TechCorp,DC=corp,DC=local"
```

**Expected:** `HR-Desktop-Policy` listed in `GpoLinks` with `Enabled = True`.

```powershell
# Fix — add missing link
New-GPLink -Name "HR-Desktop-Policy" `
    -Target "OU=HR,OU=TechCorp,DC=corp,DC=local" `
    -LinkEnabled Yes
```

### Check 2.3 — GPO link is not disabled

```powershell
# On DC01
Get-GPLink -Name "HR-Desktop-Policy" `
    -Target "OU=HR,OU=TechCorp,DC=corp,DC=local"
# LinkEnabled should be True
```

```powershell
# Fix — enable the link
Set-GPLink -Name "HR-Desktop-Policy" `
    -Target "OU=HR,OU=TechCorp,DC=corp,DC=local" `
    -LinkEnabled Yes
```

### Check 2.4 — GPO is not disabled

```powershell
(Get-GPO -Name "HR-Desktop-Policy").GpoStatus
# Should NOT be: AllSettingsDisabled or UserSettingsDisabled
```

```powershell
# Fix — enable GPO
(Get-GPO -Name "HR-Desktop-Policy").GpoStatus = "AllSettingsEnabled"
```

### Check 2.5 — Security filtering

In GPMC, open `HR-Desktop-Policy` → **Scope** tab:

- **Security Filtering** should list `Authenticated Users` or the specific group
- If it lists a group, verify the user is a member

```powershell
# Check security filter (advanced)
Get-GPPermission -Name "HR-Desktop-Policy" -All |
    Where-Object { $_.Permission -eq "GpoApply" }

# Add Authenticated Users if missing
Set-GPPermission -Name "HR-Desktop-Policy" `
    -TargetName "Authenticated Users" `
    -TargetType Group `
    -PermissionLevel GpoApply
```

### Check 2.6 — SYSVOL replication

GPO settings live in SYSVOL. If SYSVOL isn't replicating, GPOs won't apply even if
the AD object (linked GPO) looks correct.

```powershell
# Check SYSVOL content matches on both DCs
$gpoGuid = (Get-GPO -Name "HR-Desktop-Policy").Id.ToString("B")
ls "\\DC01\SYSVOL\corp.local\Policies\$gpoGuid"
ls "\\DC02\SYSVOL\corp.local\Policies\$gpoGuid"
```

Both should list the same files. If DC02 is missing them → see
[`runbooks/ad-replication-failure.md`](ad-replication-failure.md).

### Check 2.7 — Drive map GPO not applying (GP Preferences specific)

Drive maps use GP Preferences (not regular GP settings). They can fail if:
- The network share (`\\DC01\HR-Share`) is unreachable
- The `Apply once and do not reapply` option is checked

```powershell
# Test the share from CLIENT01
Test-Path "\\DC01\HR-Share"
net use \\DC01\HR-Share
```

---

## Phase 3: Resolve — Force Policy Refresh

After fixing the underlying cause, force a refresh:

```powershell
# On CLIENT01
gpupdate /force

# Remote refresh from DC01 (no need to RDP)
Invoke-GPUpdate -Computer "CLIENT01" -Force
```

> **Note:** User-targeting GPO settings (like drive maps and Control Panel restriction)
> only fully apply at **logon**. After `gpupdate /force`, the user must log off and back on
> for user-scope settings to take effect.

---

## Phase 4: Verify Resolution

```powershell
# On CLIENT01 — confirm GPO now listed as applied
gpresult /r
# HR-Desktop-Policy should appear under "Applied Group Policy Objects"

# Generate fresh HTML report
gpresult /h C:\gpreport-after.html /f
Start-Process C:\gpreport-after.html
```

**Manual verification:**

- HR user: try to open Control Panel → should be blocked
- HR user: check H: drive appears in Explorer → should be mapped

---

## Phase 5: Document & Prevent

**Prevention checklist:**

- When creating users, always verify OU placement immediately after creation
- After creating or modifying GPOs, run `gpupdate /force` on a test client
- Periodically run `Get-GPInheritance` on all OUs to audit link status
- When onboarding new employees, use `New-BulkUsers.ps1` which places users in correct OUs automatically

---

## Quick Reference — `gpresult /r` Filter Reasons

| Message | Meaning | Fix |
|---------|---------|-----|
| `Not Applied (Empty)` | GPO has no settings for this user/computer | Edit GPO and add settings |
| `Denied (Security)` | User lacks "Apply Group Policy" permission | Add user/group to security filter |
| `Disabled (Link)` | GPO link is disabled on the OU | Enable link in GPMC |
| `Not Applied (Unknown Reason)` | WMI filter blocking | Check WMI filter on GPO scope tab |
| GPO not listed at all | Not linked to user's OU | Link GPO to correct OU |
