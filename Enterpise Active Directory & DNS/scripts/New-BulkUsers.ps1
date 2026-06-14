<#
.SYNOPSIS
    Bulk Active Directory user provisioning script for TechCorp Pvt. Ltd.

.DESCRIPTION
    Creates 10 domain users across IT, HR, and Development OUs.
    Also creates security groups and assigns group memberships.
    Run on DC01 as CORP\Administrator.

.NOTES
    Domain:  corp.local
    Author:  Shank (IT Portfolio Project 01)
    Version: 1.0
#>

#Requires -Module ActiveDirectory

$ErrorActionPreference = "Stop"
$base = "DC=corp,DC=local"
$pass = ConvertTo-SecureString "P@ssw0rd2024!" -AsPlainText -Force

Write-Host "`n=== TechCorp AD User Provisioning ===" -ForegroundColor Cyan

# ─── Define Users ────────────────────────────────────────────
$users = @(
    @{ Name="Rahul Sharma";  SAM="rahul.sharma";  OU="IT";          Title="IT Administrator" },
    @{ Name="Priya Patel";   SAM="priya.patel";   OU="IT";          Title="Systems Engineer" },
    @{ Name="Meena Iyer";    SAM="meena.iyer";    OU="IT";          Title="Network Engineer" },
    @{ Name="Ankit Mehta";   SAM="ankit.mehta";   OU="HR";          Title="HR Manager" },
    @{ Name="Sunita Rao";    SAM="sunita.rao";    OU="HR";          Title="HR Specialist" },
    @{ Name="Sanjay Kumar";  SAM="sanjay.kumar";  OU="HR";          Title="Recruitment Lead" },
    @{ Name="Karan Singh";   SAM="karan.singh";   OU="Development"; Title="Senior Developer" },
    @{ Name="Deepa Nair";    SAM="deepa.nair";    OU="Development"; Title="Backend Developer" },
    @{ Name="Vikram Joshi";  SAM="vikram.joshi";  OU="Development"; Title="Frontend Developer" },
    @{ Name="Pooja Gupta";   SAM="pooja.gupta";   OU="Development"; Title="QA Engineer" }
)

# ─── Create Users ─────────────────────────────────────────────
$created = 0
$skipped = 0

foreach ($u in $users) {
    $ouPath = "OU=$($u.OU),OU=TechCorp,$base"
    try {
        # Check if user already exists
        if (Get-ADUser -Filter "SamAccountName -eq '$($u.SAM)'" -ErrorAction SilentlyContinue) {
            Write-Host "  [SKIP] $($u.Name) already exists" -ForegroundColor Yellow
            $skipped++
            continue
        }

        New-ADUser `
            -Name              $u.Name `
            -GivenName         ($u.Name.Split(" ")[0]) `
            -Surname           ($u.Name.Split(" ")[1]) `
            -SamAccountName    $u.SAM `
            -UserPrincipalName "$($u.SAM)@corp.local" `
            -Path              $ouPath `
            -AccountPassword   $pass `
            -Enabled           $true `
            -Title             $u.Title `
            -Company           "TechCorp Pvt. Ltd." `
            -Department        $u.OU `
            -PasswordNeverExpires      $false `
            -ChangePasswordAtLogon     $true

        Write-Host "  [OK]   Created: $($u.Name) → OU=$($u.OU)" -ForegroundColor Green
        $created++
    } catch {
        Write-Host "  [ERR]  Failed to create $($u.Name): $_" -ForegroundColor Red
    }
}

Write-Host "`nUsers: $created created, $skipped skipped`n" -ForegroundColor Cyan

# ─── Create Security Groups ───────────────────────────────────
Write-Host "=== Creating Security Groups ===" -ForegroundColor Cyan

$groups = @(
    @{ Name="IT-Admins"; OU="IT";          Desc="IT department administrators" },
    @{ Name="HR-Staff";  OU="HR";          Desc="Human Resources staff" },
    @{ Name="Dev-Team";  OU="Development"; Desc="Software development team" }
)

foreach ($g in $groups) {
    $ouPath = "OU=$($g.OU),OU=TechCorp,$base"
    try {
        if (Get-ADGroup -Filter "Name -eq '$($g.Name)'" -ErrorAction SilentlyContinue) {
            Write-Host "  [SKIP] Group $($g.Name) already exists" -ForegroundColor Yellow
            continue
        }
        New-ADGroup -Name $g.Name -GroupScope Global -GroupCategory Security `
            -Path $ouPath -Description $g.Desc
        Write-Host "  [OK]   Created group: $($g.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERR]  Failed to create group $($g.Name): $_" -ForegroundColor Red
    }
}

# ─── Add Members to Groups ────────────────────────────────────
Write-Host "`n=== Assigning Group Memberships ===" -ForegroundColor Cyan

$memberships = @(
    @{ Group="IT-Admins"; Members=@("rahul.sharma","priya.patel","meena.iyer") },
    @{ Group="HR-Staff";  Members=@("ankit.mehta","sunita.rao","sanjay.kumar") },
    @{ Group="Dev-Team";  Members=@("karan.singh","deepa.nair","vikram.joshi","pooja.gupta") }
)

foreach ($m in $memberships) {
    try {
        Add-ADGroupMember -Identity $m.Group -Members $m.Members
        Write-Host "  [OK]   Added $($m.Members.Count) members to $($m.Group)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERR]  $($m.Group): $_" -ForegroundColor Red
    }
}

# ─── Summary ──────────────────────────────────────────────────
Write-Host "`n=== Final Verification ===" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase "OU=TechCorp,$base" `
    | Select Name, SamAccountName, Enabled `
    | Sort-Object Name `
    | Format-Table -AutoSize

Write-Host "Done. Run 'Get-ADGroupMember -Identity IT-Admins' to verify group membership.`n" -ForegroundColor Green
