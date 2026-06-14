# Project 01 — Active Directory & DNS

> **Portfolio Project** | Recommended Tier | ₹0 Cost | 6–8 Hours

A production-quality Active Directory lab simulating an enterprise identity infrastructure for a fictional 80-user company (**TechCorp Pvt. Ltd.**). Covers Windows Server 2022 domain controllers, Samba AD on Linux, DNS, DHCP with failover, Group Policy, and operational runbooks.

---

## Business Scenario

> *"TechCorp Pvt. Ltd. needed to centralise identity management for 80 employees across three departments. I deployed an Active Directory domain controller on Windows Server 2022, configured DNS for all internal services, enforced password and security policies via GPOs, implemented DHCP with hot-standby failover across two domain controllers, and joined client machines to the domain — reducing login management from per-machine local accounts to a single directory. I also deployed an equivalent Samba AD on Linux to demonstrate cross-platform directory services."*

---

## Architecture

```
corp.local — 192.168.10.0/24
┌──────────────────────────────────────────────────────────────┐
│                    PROXMOX / HYPERVISOR                      │
│                                                              │
│  ┌──────────────────┐       ┌──────────────────┐            │
│  │  DC01  (Primary) │◄─────►│  DC02 (Secondary)│            │
│  │  192.168.10.10   │  AD   │  192.168.10.12   │            │
│  │  ──────────────  │  Rep  │  ──────────────  │            │
│  │  • AD DS (PDC)   │◄─────►│  • AD DS         │            │
│  │  • DNS Primary   │       │  • DNS Secondary  │            │
│  │  • DHCP Active   │       │  • DHCP Standby   │            │
│  └──────────────────┘       └──────────────────┘            │
│           │                          │                       │
│           └──────────┬───────────────┘                      │
│                      │ corp.local                            │
│           ┌──────────▼──────────┐  ┌──────────────────┐    │
│           │  CLIENT01           │  │  LNX-DC01         │    │
│           │  Windows 10/11      │  │  Ubuntu + Samba   │    │
│           │  192.168.10.50      │  │  192.168.10.11   │    │
│           │  (domain member)    │  │  linuxcorp.local  │    │
│           └─────────────────────┘  └──────────────────┘    │
└──────────────────────────────────────────────────────────────┘

DHCP Scope: 192.168.10.100–200 (active on DC01, hot-standby on DC02)
```

---

## Completion Tier

| Tier | Status | Description |
|------|--------|-------------|
| MVP | ✅ Included | Single DC, 10 users, GPOs, DNS, client joined |
| **Recommended** | ✅ **This repo** | Dual DC + replication, DHCP failover, PowerShell automation, incident runbooks |
| Advanced | 🔲 Extension | CA, Azure AD Connect, LAPS, tiered admin model |

---

## Table of Contents

- [VM Specifications](#vm-specifications)
- [IP Addressing](#ip-addressing)
- [Windows Server Setup (DC01)](#windows-server-setup-dc01)
- [Second Domain Controller (DC02)](#second-domain-controller-dc02)
- [Linux Samba AD Setup](#linux-samba-ad-setup)
- [Users, OUs & Groups](#users-ous--groups)
- [Group Policy Objects](#group-policy-objects)
- [DNS Configuration](#dns-configuration)
- [DHCP & Failover](#dhcp--failover)
- [Client Domain Join](#client-domain-join)
- [Verification & Testing](#verification--testing)
- [Monitoring](#monitoring)
- [Security Hardening](#security-hardening)
- [Incident Runbooks](#incident-runbooks)
- [Screenshots](#screenshots)
- [Resume Bullets](#resume-bullets)
- [Interview Preparation](#interview-preparation)

---

## VM Specifications

| VM | OS | vCPU | RAM | Disk | IP |
|----|-----|------|-----|------|----|
| DC01 | Windows Server 2022 | 2 | 4 GB | 60 GB | 192.168.10.10 |
| DC02 | Windows Server 2022 | 2 | 4 GB | 60 GB | 192.168.10.12 |
| LNX-DC01 | Ubuntu Server 22.04 | 2 | 2 GB | 40 GB | 192.168.10.11 |
| CLIENT01 | Windows 10/11 | 2 | 2–4 GB | 40 GB | 192.168.10.50 (DHCP) |

---

## IP Addressing

| Range | Purpose |
|-------|---------|
| 192.168.10.1 | Default gateway |
| 192.168.10.10–19 | Domain controllers (static) |
| 192.168.10.20–99 | Servers (static) |
| 192.168.10.100–200 | DHCP scope (clients) |
| 192.168.10.201–254 | Reserved |

---

## Windows Server Setup (DC01)

### 1. Download Windows Server 2022

Download the 180-day evaluation ISO from:
`https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022`

Choose **"Windows Server 2022 Standard Evaluation (Desktop Experience)"** during install.

> **Proxmox tip:** Attach the VirtIO drivers ISO as a second CD-ROM if the disk isn't visible during install.  
> Download: `https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso`

### 2. Set Static IP (do this BEFORE AD install)

Right-click NIC → Properties → IPv4:

```
IP address:      192.168.10.10
Subnet mask:     255.255.255.0
Default gateway: 192.168.10.1
Preferred DNS:   127.0.0.1
Alternate DNS:   8.8.8.8
```

Rename PC to `DC01`: Start → System → "Rename this PC" → Restart.

### 3. Install AD DS Role

Server Manager → Manage → Add Roles → **Active Directory Domain Services** → Add Features → Install.

### 4. Promote to Domain Controller

Flag icon → "Promote this server to a domain controller":

```
New forest
Root domain name:          corp.local
Forest functional level:   Windows Server 2016
Domain functional level:   Windows Server 2016
☑ DNS server  ☑ Global Catalog  ☐ RODC
DSRM password:             P@ssw0rd2024!
NetBIOS name:              CORP
```

Click Install — server auto-restarts. Log in as `CORP\Administrator`.

### 5. Post-Promotion Verification

```powershell
Get-ADDomain
Get-Service NTDS, ADWS, KDC | Select Name, Status
Resolve-DnsName corp.local
dcdiag /test:dns /test:replications /test:netlogons
```

See [`assets/screenshots/windows-setup-pics/`](assets/screenshots/) for verification evidence (dc-diag.png, DNS-verification.png, get-addomain.png).

---

## Second Domain Controller (DC02)

### 1. Create DC02 VM and Set Static IP

```
IP address:      192.168.10.12
Subnet mask:     255.255.255.0
Default gateway: 192.168.10.1
Preferred DNS:   192.168.10.10   ← points to DC01 (not 127.0.0.1 yet)
Alternate DNS:   8.8.8.8
```

Rename PC to `DC02` → Restart.

### 2. Join DC02 to corp.local Domain

```powershell
Add-Computer -DomainName "corp.local" `
  -Credential (Get-Credential) `
  -Restart
```

### 3. Promote DC02 as Additional DC

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

$cred = Get-Credential  # CORP\Administrator

Install-ADDSDomainController `
  -DomainName "corp.local" `
  -Credential $cred `
  -InstallDns:$true `
  -CreateDnsDelegation:$false `
  -DatabasePath "C:\Windows\NTDS" `
  -LogPath "C:\Windows\NTDS" `
  -SysvolPath "C:\Windows\SYSVOL" `
  -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force) `
  -Force:$true
```

> **Critical:** Choose **"Add a domain controller to an existing domain"** — NOT "Add a new forest."

After reboot, update DC02's DNS:
- Preferred DNS: `127.0.0.1`
- Alternate DNS: `192.168.10.10`

### 4. Verify Replication

```powershell
repadmin /replsummary
repadmin /showrepl
Get-ADDomainController -Filter * | Select Name, IPv4Address, IsGlobalCatalog
```

Run the replication monitor script:

```powershell
.\scripts\Get-ReplicationStatus.ps1
```

---

## Linux Samba AD Setup

Full commands: [`scripts/samba-ad-setup.sh`](scripts/samba-ad-setup.sh)

### 1. Configure Static IP (Netplan)

```yaml
# /etc/netplan/00-installer-config.yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses: [192.168.10.11/24]
      nameservers:
        addresses: [127.0.0.1, 8.8.8.8]
      routes:
        - to: default
          via: 192.168.10.1
```

```bash
sudo netplan apply
sudo hostnamectl set-hostname lnx-dc01
```

Add to `/etc/hosts`:
```
192.168.10.11   lnx-dc01.linuxcorp.local   lnx-dc01
```

### 2. Install Samba Packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt remove --purge -y samba* winbind* 2>/dev/null
sudo apt install -y samba krb5-config krb5-user winbind \
  libpam-winbind libnss-winbind smbclient
# Kerberos prompts: realm=LINUXCORP.LOCAL  server=lnx-dc01.linuxcorp.local
```

### 3. Provision the Domain

```bash
sudo systemctl stop smbd nmbd winbind samba-ad-dc 2>/dev/null
sudo systemctl disable smbd nmbd winbind 2>/dev/null
sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null

sudo samba-tool domain provision \
  --use-rfc2307 \
  --realm=LINUXCORP.LOCAL \
  --domain=LINUXCORP \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --adminpass='P@ssw0rd2024!'

sudo cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
sudo systemctl unmask samba-ad-dc
sudo systemctl enable --now samba-ad-dc
```

### 4. Verify

```bash
sudo samba-tool domain info 192.168.10.11
sudo samba-tool user list
kinit administrator@LINUXCORP.LOCAL && klist
host -t SRV _ldap._tcp.linuxcorp.local 127.0.0.1
smbclient -L localhost -U Administrator%'P@ssw0rd2024!'
```

See [`assets/screenshots/linux-setup-pics/`](assets/screenshots/) for evidence (domain-info.png, user-list.png, dns-resolution-check-1.png).

---

## Users, OUs & Groups

Full script: [`scripts/New-BulkUsers.ps1`](scripts/New-BulkUsers.ps1)

### OU Structure

```
corp.local
└── TechCorp
    ├── IT
    ├── HR
    ├── Development
    └── Servers
```

### Users Created

| Name | Username | Department | Group |
|------|----------|-----------|-------|
| Rahul Sharma | rahul.sharma | IT | IT-Admins |
| Priya Patel | priya.patel | IT | IT-Admins |
| Meena Iyer | meena.iyer | IT | IT-Admins |
| Ankit Mehta | ankit.mehta | HR | HR-Staff |
| Sunita Rao | sunita.rao | HR | HR-Staff |
| Sanjay Kumar | sanjay.kumar | HR | HR-Staff |
| Karan Singh | karan.singh | Development | Dev-Team |
| Deepa Nair | deepa.nair | Development | Dev-Team |
| Vikram Joshi | vikram.joshi | Development | Dev-Team |
| Pooja Gupta | pooja.gupta | Development | Dev-Team |

---

## Group Policy Objects

| GPO Name | Linked To | Purpose |
|----------|-----------|---------|
| Default Domain Policy | corp.local | Password & lockout policy |
| HR-Desktop-Policy | OU=HR | Block Control Panel |
| Corp-DriveMap-Policy | OU=TechCorp | Map H: drive via GP Preferences |

### Password Policy Settings

```
Enforce password history:   24 passwords
Maximum password age:       90 days
Minimum password age:       1 day
Minimum password length:    12 characters
Complexity requirements:    Enabled
Account lockout threshold:  5 attempts
Lockout duration:           30 minutes
```

Full script: [`scripts/Create-GPOs.ps1`](scripts/Create-GPOs.ps1)

---

## DNS Configuration

```powershell
# Reverse lookup zone
Add-DnsServerPrimaryZone -NetworkID "192.168.10.0/24" -ReplicationScope "Forest"

# A records
Add-DnsServerResourceRecordA -ZoneName "corp.local" -Name "webserver01" `
  -IPv4Address "192.168.10.20" -CreatePtr
Add-DnsServerResourceRecordA -ZoneName "corp.local" -Name "fileserver01" `
  -IPv4Address "192.168.10.21" -CreatePtr

# CNAME
Add-DnsServerResourceRecordCName -ZoneName "corp.local" `
  -Name "intranet" -HostNameAlias "webserver01.corp.local."
```

---

## DHCP & Failover

Full details: [`docs/operations/dhcp-setup.md`](docs/operations/dhcp-setup.md)

### Scope Configuration (DC01)

```powershell
Install-WindowsFeature -Name DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName "DC01.corp.local" -IPAddress 192.168.10.10

Add-DhcpServerv4Scope -Name "Corp-LAN-Scope" `
  -StartRange 192.168.10.100 -EndRange 192.168.10.200 `
  -SubnetMask 255.255.255.0

Add-DhcpServerv4ExclusionRange -ScopeId 192.168.10.0 `
  -StartRange 192.168.10.1 -EndRange 192.168.10.99

Set-DhcpServerv4OptionValue -ScopeId 192.168.10.0 `
  -Router 192.168.10.1 `
  -DnsServer 192.168.10.10, 192.168.10.12 `
  -DnsDomain corp.local

Set-DhcpServerv4Scope -ScopeId 192.168.10.0 -State Active
```

### Hot-Standby Failover

```powershell
# Install DHCP on DC02 first, then run this on DC01:
Add-DhcpServerv4Failover `
  -Name "Corp-DHCP-Failover" `
  -ScopeId 192.168.10.0 `
  -PartnerServer DC02.corp.local `
  -Mode HotStandby `
  -ServerRole Active `
  -AutoStateTransition $true `
  -MaxClientLeadTime (New-TimeSpan -Minutes 60) `
  -SharedSecret "DHCPf@il0ver!"
```

### Test Failover

```powershell
# On CLIENT01:
ipconfig /release
ipconfig /renew
ipconfig /all   # note DHCP Server field

# Shut down DC01, wait 60–90 seconds, renew again:
ipconfig /release
ipconfig /renew
ipconfig /all   # DHCP Server should now show 192.168.10.12
```

---

## Client Domain Join

```powershell
# CLIENT01 NIC DNS must point to DC01:
# Preferred DNS: 192.168.10.10
# Alternate DNS: 192.168.10.12

# Verify connectivity
ping DC01.corp.local
nslookup corp.local

# Join domain
Add-Computer -DomainName "corp.local" -Credential (Get-Credential) -Restart

# After reboot, login as: CORP\rahul.sharma
```

---

## Verification & Testing

Full test script: [`tests/Test-ADEnvironment.ps1`](tests/Test-ADEnvironment.ps1)

```powershell
# DC health
dcdiag /v
repadmin /replsummary
repadmin /showrepl
netdom query fsmo

# Users and groups
Get-ADUser -Filter * -SearchBase "OU=TechCorp,DC=corp,DC=local" | Select Name, Enabled
Get-ADGroupMember "IT-Admins" | Select Name

# GPOs
Get-GPO -All | Select DisplayName, GpoStatus
gpresult /h C:\gpresult.html /f

# DHCP
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0
Get-DhcpServerv4Failover

# DNS
Resolve-DnsName DC01.corp.local
Resolve-DnsName 192.168.10.10
```

---

## Monitoring

See [`docs/monitoring/ad-monitoring.md`](docs/monitoring/ad-monitoring.md)

Key metrics to monitor:
- AD replication failures (`repadmin /replsummary` exit code)
- DHCP scope utilisation (target: < 80%)
- Failed logon events (Event ID 4625)
- Account lockout events (Event ID 4740)
- DC service health (NTDS, KDC, ADWS, Netlogon)

Automated monitoring script: [`scripts/Get-ReplicationStatus.ps1`](scripts/Get-ReplicationStatus.ps1)

---

## Security Hardening

See [`docs/security/hardening.md`](docs/security/hardening.md)

Applied hardening:
- [x] 12-character minimum password with complexity
- [x] 5-attempt account lockout
- [x] AD Recycle Bin enabled
- [x] SMBv1 disabled
- [x] Audit logon events enabled
- [x] DSRM password set

---

## Incident Runbooks

| Runbook | Severity | File |
|---------|----------|------|
| AD Replication Failure | 🔴 HIGH | [`runbooks/ad-replication-failure.md`](runbooks/ad-replication-failure.md) |
| GPO Not Applying | 🟡 MEDIUM | [`runbooks/gpo-not-applying.md`](runbooks/gpo-not-applying.md) |
| DHCP Scope Exhaustion | 🔴 HIGH | [`runbooks/dhcp-scope-exhaustion.md`](runbooks/dhcp-scope-exhaustion.md) |

---

## Screenshots

> **Setup:** Copy your screenshot files from the `IT-Project-1` folder into `assets/screenshots/`
> matching the filenames below. The subdirectory structure mirrors the folders you already have:
> `Linux-Setup-pics/` → `assets/screenshots/linux-setup-pics/`,
> `Verification-Test/` → `assets/screenshots/verification-test/`,
> `Windows-setup-pics/` → `assets/screenshots/windows-setup-pics/`.

### Linux Setup

| Screenshot | Description |
|-----------|-------------|
| [`linux-setup-pics/dns-resolution-check-1.png`](assets/screenshots/linux-setup-pics/dns-resolution-check-1.png) | DNS resolution from Samba DC — forward lookup |
| [`linux-setup-pics/dns-resolution-check-2.png`](assets/screenshots/linux-setup-pics/dns-resolution-check-2.png) | DNS resolution from Samba DC — SRV record |
| [`linux-setup-pics/domain-info.png`](assets/screenshots/linux-setup-pics/domain-info.png) | `samba-tool domain info` output confirming DC role |
| [`linux-setup-pics/smb-test-connectivity.png`](assets/screenshots/linux-setup-pics/smb-test-connectivity.png) | `smbclient -L localhost` showing SYSVOL/NETLOGON |
| [`linux-setup-pics/user-list.png`](assets/screenshots/linux-setup-pics/user-list.png) | `samba-tool user list` output |

### Verification Tests

| Screenshot | Description |
|-----------|-------------|
| [`verification-test/AD-Tree-Struct.png`](assets/screenshots/verification-test/AD-Tree-Struct.png) | ADUC showing full OU hierarchy |
| [`verification-test/After-Failover-Setup.png`](assets/screenshots/verification-test/After-Failover-Setup.png) | CLIENT01 receiving IP from DC02 after DC01 shutdown |
| [`verification-test/ComputerAccounts-And-GPO.png`](assets/screenshots/verification-test/ComputerAccounts-And-GPO.png) | Computer accounts and GPO links in ADUC |
| [`verification-test/gp-result.png`](assets/screenshots/verification-test/gp-result.png) | `gpresult /r` on CLIENT01 showing applied GPOs |
| [`verification-test/IP-lease.png`](assets/screenshots/verification-test/IP-lease.png) | CLIENT01 DHCP lease from DC01 scope |
| [`verification-test/IP-Lease-v2.png`](assets/screenshots/verification-test/IP-Lease-v2.png) | DHCP Manager showing active leases |
| [`verification-test/Kerneros-auth.png`](assets/screenshots/verification-test/Kerneros-auth.png) | `klist` showing Kerberos TGT on CLIENT01 |
| [`verification-test/mapped-drive.png`](assets/screenshots/verification-test/mapped-drive.png) | H: drive mapped via GPO Preferences |
| [`verification-test/No-ctrl-panel.png`](assets/screenshots/verification-test/No-ctrl-panel.png) | HR user blocked from accessing Control Panel |
| [`verification-test/nslookup-res.png`](assets/screenshots/verification-test/nslookup-res.png) | DNS name resolution from CLIENT01 |
| [`verification-test/Pre-FailoverDHCP.png`](assets/screenshots/verification-test/Pre-FailoverDHCP.png) | DHCP failover configuration state |
| [`verification-test/UsersIDs.png`](assets/screenshots/verification-test/UsersIDs.png) | All domain user accounts in ADUC |

### Windows Setup

| Screenshot | Description |
|-----------|-------------|
| [`windows-setup-pics/dc-diag.png`](assets/screenshots/windows-setup-pics/dc-diag.png) | `dcdiag` passing all tests on DC01 |
| [`windows-setup-pics/DNS-verification.png`](assets/screenshots/windows-setup-pics/DNS-verification.png) | DNS Manager showing zones and records |
| [`windows-setup-pics/get-addomain-filter.png`](assets/screenshots/windows-setup-pics/get-addomain-filter.png) | `Get-ADDomain` PowerShell output |
| [`windows-setup-pics/get-addomain.png`](assets/screenshots/windows-setup-pics/get-addomain.png) | Domain properties confirmation |
| [`windows-setup-pics/get-share-get-service-NTDS.png`](assets/screenshots/windows-setup-pics/get-share-get-service-NTDS.png) | SYSVOL/NETLOGON shares + NTDS service running |

---

## Resume Bullets

```
• Deployed dual-domain-controller Active Directory environment on Proxmox (Windows Server 2022),
  configured AD replication between DC01 and DC02, verified health via repadmin and dcdiag

• Engineered DHCP failover cluster in Hot Standby mode across two domain controllers,
  serving a 101-address scope with automatic failover validated by simulated DC failure

• Automated user lifecycle management via PowerShell: provisioned 10 domain accounts with
  role-based OU placement across IT, HR, and Development departments

• Authored Group Policy Objects enforcing 12-character password complexity, account lockout
  after 5 attempts, Control Panel restrictions for HR, and network drive mapping via GP Preferences

• Deployed Linux-equivalent domain controller using Samba 4 on Ubuntu 22.04, including
  Kerberos configuration and LDAP/DNS validation

• Documented three operational incident runbooks (AD replication failure, GPO not applying,
  DHCP exhaustion) following structured detect/diagnose/resolve/prevent format
```

---

## Interview Preparation

See [`docs/development/interview-prep.md`](docs/development/interview-prep.md) for full Q&A on:

- Kerberos authentication flow
- FSMO roles and their purpose
- AD replication (USN, KCC, intra-site vs inter-site)
- Troubleshooting replication error 1722
- GPO processing order (LSDOU)
- DHCP Hot Standby vs Load Balance modes
- What SYSVOL is and why it's critical

---

## Repository Structure

```
project-01-active-directory/
├── README.md
├── .github/
│   ├── workflows/
│   │   └── validate-scripts.yml
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
├── scripts/
│   ├── New-BulkUsers.ps1
│   ├── Create-OUs.ps1
│   ├── Create-GPOs.ps1
│   ├── Get-ReplicationStatus.ps1
│   ├── Configure-DHCP.ps1
│   └── samba-ad-setup.sh
├── runbooks/
│   ├── ad-replication-failure.md
│   ├── gpo-not-applying.md
│   └── dhcp-scope-exhaustion.md
├── tests/
│   └── Test-ADEnvironment.ps1
├── docs/
│   ├── adr/
│   │   ├── ADR-001-windows-server-2022.md
│   │   ├── ADR-002-samba-linux-dc.md
│   │   └── ADR-003-dhcp-hot-standby.md
│   ├── architecture/
│   │   └── overview.md
│   ├── security/
│   │   └── hardening.md
│   ├── monitoring/
│   │   └── ad-monitoring.md
│   ├── operations/
│   │   └── dhcp-setup.md
│   ├── troubleshooting/
│   │   └── common-issues.md
│   └── development/
│       └── interview-prep.md
├── config/
│   └── netplan-lnx-dc01.yaml
└── assets/
    ├── screenshots/
    │   ├── linux-setup-pics/
    │   ├── verification-test/
    │   └── windows-setup-pics/
    └── diagrams/
        └── architecture.md
```

---

## Acknowledgements / References

- [Microsoft AD DS Documentation](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview)
- [Samba AD DC Setup Guide](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Windows Server 2022 Evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022)
- [Ubuntu Server 22.04 LTS](https://ubuntu.com/download/server)
