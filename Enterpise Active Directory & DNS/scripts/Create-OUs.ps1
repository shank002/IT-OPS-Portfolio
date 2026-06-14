<#
.SYNOPSIS
    Creates the TechCorp OU hierarchy in corp.local

.DESCRIPTION
    Builds the full Organizational Unit structure:
      corp.local
      └── TechCorp
          ├── IT
          ├── HR
          ├── Development
          └── Servers

.NOTES
    Run on DC01 as CORP\Administrator before New-BulkUsers.ps1
#>

#Requires -Module ActiveDirectory

$ErrorActionPreference = "Stop"
$base = "DC=corp,DC=local"

Write-Host "`n=== Creating TechCorp OU Structure ===" -ForegroundColor Cyan

$ous = @(
    @{ Name="TechCorp";    Path=$base;                              Desc="Root OU for TechCorp Pvt. Ltd." },
    @{ Name="IT";          Path="OU=TechCorp,$base";               Desc="Information Technology department" },
    @{ Name="HR";          Path="OU=TechCorp,$base";               Desc="Human Resources department" },
    @{ Name="Development"; Path="OU=TechCorp,$base";               Desc="Software Development department" },
    @{ Name="Servers";     Path="OU=TechCorp,$base";               Desc="Server computer accounts" }
)

foreach ($ou in $ous) {
    $fullPath = "OU=$($ou.Name),$($ou.Path)"
    try {
        # Check if OU already exists
        if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullPath'" -ErrorAction SilentlyContinue) {
            Write-Host "  [SKIP] OU=$($ou.Name) already exists" -ForegroundColor Yellow
            continue
        }
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -Description $ou.Desc
        Write-Host "  [OK]   Created OU=$($ou.Name) under $($ou.Path)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERR]  Failed to create OU=$($ou.Name): $_" -ForegroundColor Red
    }
}

Write-Host "`n=== OU Structure ===" -ForegroundColor Cyan
Get-ADOrganizationalUnit -Filter * -SearchBase $base `
    | Select DistinguishedName `
    | Sort-Object DistinguishedName `
    | Format-Table -AutoSize

Write-Host "Done.`n" -ForegroundColor Green
