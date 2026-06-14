# ADR-001 — Use Windows Server 2022 as Primary Domain Controller

**Date:** 2024  
**Status:** Accepted  
**Deciders:** Shank (IT Portfolio Project 01)

## Context

A domain controller OS must be chosen for the primary AD environment.

## Decision

Use **Windows Server 2022 Standard Evaluation (Desktop Experience)**.

## Rationale

| Factor | Reasoning |
|--------|-----------|
| Industry prevalence | Windows Server is the dominant AD platform in enterprise India |
| GUI for learning | Desktop Experience allows learning ADUC, GPMC, DNS Manager, DHCP Manager visually before moving to PowerShell-only |
| Free evaluation | 180-day fully-functional trial at zero cost |
| Interview relevance | Job descriptions explicitly ask for "Windows Server 2019/2022" experience |
| PowerShell parity | All operations done in both GUI and PowerShell for portfolio depth |

## Alternatives Considered

| Alternative | Rejected Because |
|-------------|-----------------|
| Windows Server 2019 | 2022 is current LTS; slightly higher resume value |
| Windows Server Core | No GUI makes learning harder for first lab |
| Azure AD (cloud-only) | Doesn't cover on-prem AD which most Indian enterprises still use |

## Consequences

- 180-day expiry requires reactivation or rebuild for longer labs
- Desktop Experience uses ~2 GB more RAM than Core
- Learning curve for GUI is appropriate for beginner portfolio
