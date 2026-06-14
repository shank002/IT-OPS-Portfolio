# Screenshot Inventory

All screenshots captured during the lab build, organised by category.
Place actual screenshot files in the paths shown.

---

## Linux Setup (`assets/screenshots/linux-setup-pics/`)

| File | What It Shows | Component | Portfolio Value |
|------|--------------|-----------|----------------|
| `dns-resolution-check-1.png` | `host -t A` forward DNS resolution from Samba DC | Samba DNS | Proves DNS is working |
| `dns-resolution-check-2.png` | `host -t SRV _ldap._tcp.linuxcorp.local` SRV record | Samba DNS | DC discoverable by clients |
| `domain-info.png` | `samba-tool domain info 192.168.10.11` output | Samba AD | Confirms DC role and realm |
| `smb-test-connectivity.png` | `smbclient -L localhost` showing SYSVOL/NETLOGON shares | Samba SMB | SYSVOL accessible |
| `user-list.png` | `samba-tool user list` output with all users | Samba Users | Users created successfully |

---

## Verification Tests (`assets/screenshots/verification-test/`)

| File | What It Shows | Component | Portfolio Value |
|------|--------------|-----------|----------------|
| `AD-Tree-Struct.png` | ADUC showing OU hierarchy (TechCorp > IT/HR/Dev/Servers) | AD Structure | Visual OU design evidence |
| `After-Failover-Setup.png` | `ipconfig /all` on CLIENT01 showing DC02 as DHCP server | DHCP Failover | **Key evidence** — proves failover works |
| `ComputerAccounts-And-GPO.png` | ADUC computer accounts tab + GPMC GPO links | GPO + Computers | Domain join + policy coverage |
| `gp-result.png` | `gpresult /r` on CLIENT01 — applied GPOs listed | GPO Application | GPOs applying correctly |
| `IP-lease.png` | CLIENT01 `ipconfig /all` showing 192.168.10.1xx from DC01 | DHCP | Initial DHCP lease working |
| `IP-Lease-v2.png` | DHCP Manager on DC01 showing active leases table | DHCP Leases | Server-side lease confirmation |
| `Kerneros-auth.png` | `klist` output on CLIENT01 with TGT | Kerberos | Authentication working |
| `mapped-drive.png` | Explorer showing H: drive mapped via GPO | GPO Drive Map | GP Preferences working |
| `No-ctrl-panel.png` | Control Panel blocked for HR user | GPO Restriction | Security policy enforced |
| `nslookup-res.png` | `nslookup corp.local` from CLIENT01 resolving to DC01 | DNS Client | Client DNS working |
| `Pre-FailoverDHCP.png` | DHCP failover relationship configuration in DHCP Manager | DHCP Failover | Failover configured |
| `UsersIDs.png` | All 10 domain user accounts listed in ADUC | AD Users | Users provisioned |

---

## Windows Setup (`assets/screenshots/windows-setup-pics/`)

| File | What It Shows | Component | Portfolio Value |
|------|--------------|-----------|----------------|
| `dc-diag.png` | `dcdiag` output — all tests passing | DC Health | Core health verified |
| `DNS-verification.png` | DNS Manager showing corp.local forward zone + reverse zone | DNS | DNS infrastructure |
| `get-addomain-filter.png` | `Get-ADDomain` PowerShell output | AD Domain | Domain properties |
| `get-addomain.png` | Domain info confirmation | AD Domain | Domain configuration |
| `get-share-get-service-NTDS.png` | `net share` (SYSVOL/NETLOGON) + `Get-Service NTDS` Running | DC Services | Core services healthy |

---

## Missing Screenshots (Recommended to Capture)

These screenshots would strengthen the portfolio but weren't captured yet.

| Suggested File | What to Capture | How to Capture |
|---------------|----------------|----------------|
| `repadmin-replsummary.png` | `repadmin /replsummary` with 0 failures | Run on DC01 after DC02 promotion |
| `dhcp-failover-state-after.png` | `Get-DhcpServerv4Failover` after failover triggered | Run on DC02 while DC01 is down |
| `dc02-promoted.png` | Server Manager on DC02 showing AD DS and DNS roles | After DC02 promotion |
| `both-dcs-aduc.png` | ADUC → Domain Controllers OU showing DC01 and DC02 | Open ADUC on DC01 |
| `gpmc-full-view.png` | GPMC showing all three GPOs linked | Open Group Policy Management |
