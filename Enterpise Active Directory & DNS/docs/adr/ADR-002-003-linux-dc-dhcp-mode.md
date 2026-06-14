# ADR-002 — Deploy Samba 4 as Linux Domain Controller

**Date:** 2024  
**Status:** Accepted

## Context

Should the Linux DC component use Samba AD, OpenLDAP, or be skipped entirely?

## Decision

Use **Samba 4 on Ubuntu Server 22.04** as a separate domain (`linuxcorp.local`).

## Rationale

Samba 4 is a complete AD implementation (Kerberos KDC, LDAP, DNS, SMB). It demonstrates:
- Understanding of AD at the protocol level, not just Windows GUI
- Cross-platform identity management (relevant to hybrid environments)
- Linux server administration under realistic enterprise conditions

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| FreeIPA | Not AD-compatible; different skill set |
| OpenLDAP standalone | No Kerberos, no GP, not AD-equivalent |
| Skip Linux DC | Weaker portfolio — misses cross-platform differentiator |
| Join Samba to corp.local | More complex; separate domain better isolates Linux skills |

---

# ADR-003 — DHCP Hot Standby vs Load Balance Failover

**Date:** 2024  
**Status:** Accepted

## Context

Windows DHCP failover supports two modes. Which should be used?

## Decision

Use **Hot Standby** mode with DC01 as Active and DC02 as Standby.

## Rationale

| Factor | Hot Standby | Load Balance |
|--------|------------|--------------|
| Complexity | Simple — one server active | Moderate — both serve leases |
| Failover visibility | Clear: DC02 takes over completely | Harder to observe — leases split |
| Production usage | Branch office, simple environments | Most production environments |
| Lab suitability | ✅ Easy to test and demonstrate | Harder to verify without many clients |
| Interview value | Good — shows HA thinking | Slightly higher, but harder to demo |

Hot Standby is chosen because it produces clear, demonstrable failover evidence
(CLIENT01 visibly switching from DC01 to DC02), which is ideal for portfolio screenshots.

## Consequences

- In real production, Load Balance is preferred (both DCs active = better utilisation)
- Hot Standby means DC02 DHCP service is idle until DC01 fails
- MaxClientLeadTime of 60 minutes is aggressive for production but appropriate for lab testing
