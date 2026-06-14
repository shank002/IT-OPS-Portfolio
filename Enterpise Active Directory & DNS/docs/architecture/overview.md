# Architecture Overview

## High-Level Design

The corp.local AD environment simulates a small-to-medium enterprise identity infrastructure
with full redundancy at the directory, DNS, and DHCP layers.

---

## Component Diagram (Mermaid)

```mermaid
graph TB
    subgraph Hypervisor["Proxmox Hypervisor"]
        DC01["DC01<br/>Windows Server 2022<br/>192.168.10.10<br/>AD DS · DNS · DHCP Active"]
        DC02["DC02<br/>Windows Server 2022<br/>192.168.10.12<br/>AD DS · DNS · DHCP Standby"]
        LNXDC["LNX-DC01<br/>Ubuntu 22.04 + Samba 4<br/>192.168.10.11<br/>linuxcorp.local"]
        CLIENT["CLIENT01<br/>Windows 10/11<br/>192.168.10.50 (DHCP)<br/>Domain Member"]
    end

    DC01 <-->|"AD Replication<br/>SYSVOL/DFSR"| DC02
    DC01 <-->|"DHCP Failover<br/>Hot Standby"| DC02
    CLIENT -->|"Kerberos Auth<br/>DNS · DHCP"| DC01
    CLIENT -.->|"Failover path"| DC02

    style DC01 fill:#0C447C,color:#fff
    style DC02 fill:#1A5C9C,color:#fff
    style LNXDC fill:#27500A,color:#fff
    style CLIENT fill:#444,color:#fff
```

---

## Authentication Flow (Mermaid)

```mermaid
sequenceDiagram
    participant C as CLIENT01
    participant DC as DC01 (KDC)
    participant FS as \\DC01\HR-Share

    C->>DC: AS-REQ (username + timestamp encrypted with pw hash)
    DC->>C: AS-REP (TGT encrypted with KDC secret key)
    Note over C: klist shows TGT valid 10 hours

    C->>DC: TGS-REQ (TGT + request for cifs/DC01)
    DC->>C: TGS-REP (Service Ticket for HR-Share)

    C->>FS: AP-REQ (Service Ticket)
    FS->>C: AP-REP (access granted)
    Note over C,FS: H: drive mapped via GPO
```

---

## OU Structure

```
corp.local
└── Domain Controllers       (built-in — DC01, DC02)
└── TechCorp                 (root company OU)
    ├── IT                   (IT-Admins group, 3 users)
    │   ├── rahul.sharma
    │   ├── priya.patel
    │   └── meena.iyer
    ├── HR                   (HR-Staff group, 3 users)
    │   │   GPO: HR-Desktop-Policy (blocks Control Panel)
    │   │   GPO: Corp-DriveMap-Policy (H: drive)
    │   ├── ankit.mehta
    │   ├── sunita.rao
    │   └── sanjay.kumar
    ├── Development          (Dev-Team group, 4 users)
    │   │   GPO: Corp-DriveMap-Policy (H: drive)
    │   ├── karan.singh
    │   ├── deepa.nair
    │   ├── vikram.joshi
    │   └── pooja.gupta
    └── Servers              (computer accounts for servers)
```

---

## DHCP Failover Architecture

```mermaid
stateDiagram-v2
    [*] --> Normal: Boot

    Normal: DC01 Active\nDC02 Standby (monitoring)
    Normal --> DC01_Down: DC01 network loss

    DC01_Down: Transition state\nDC02 waiting 60 minutes
    DC01_Down --> DC02_Active: MaxClientLeadTime elapsed

    DC02_Active: DC02 serving all DHCP\nNew leases from .100-.200
    DC02_Active --> Resync: DC01 comes back online

    Resync: DC01 rejoins\nLease databases synchronise
    Resync --> Normal: Sync complete
```

---

## Network Zone Layout

```
Internet
    │
    ▼
Gateway / Router (192.168.10.1)
    │
    ▼
192.168.10.0/24 — corp.local LAN (single flat network for lab)
    │
    ├─ .10  DC01      (AD DS, DNS, DHCP Active)
    ├─ .11  LNX-DC01  (Samba AD, linuxcorp.local)
    ├─ .12  DC02      (AD DS, DNS, DHCP Standby)
    ├─ .20  webserver01  (static, DNS A record only)
    ├─ .21  fileserver01 (static, DNS A record only)
    │
    └─ .100–.200  DHCP dynamic pool
                  CLIENT01 = .50 (static) or from pool
```
