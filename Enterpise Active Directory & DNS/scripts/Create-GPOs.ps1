<#
.SYNOPSIS
    Creates and links Group Policy Objects for TechCorp Pvt. Ltd.

.DESCRIPTION
    Creates three GPOs:
      1. Default Domain Policy   — password and lockout settings (domain-wide)
      2. HR-Desktop-Policy       — blocks Control Panel for HR users
      3. Corp-DriveMap-Policy    — maps H: drive for all TechCorp staff

    NOTE: Drive map (GPO 3) requires manual GP Preferences configuration
    in GPMC after running this script. See inline instructions.

.NOTES
    Run on DC01 as CORP\Administrator after Create-OUs.ps1
#>

#Requires -Module GroupPolicy, ActiveDirectory

$ErrorActionPreference = "Stop"
$base = "DC=corp,DC=local"

Write-Host "`n=== Configuring Group Policy Objects ===" -ForegroundColor Cyan

# ─── GPO 1: Password & Lockout Policy (Default Domain Policy) ─
Write-Host "`n[1] Configuring Default Domain Policy..." -ForegroundColor White

try {
    # Password Policy
    Set-ADDefaultDomainPasswordPolicy -Identity $base `
        -PasswordHistoryCount      24 `
        -MaxPasswordAge            (New-TimeSpan -Days 90) `
        -MinPasswordAge            (New-TimeSpan -Days 1) `
        -MinPasswordLength         12 `
        -ComplexityEnabled         $true `
        -ReversibleEncryptionEnabled $false

    Write-Host "  [OK] Password policy configured" -ForegroundColor Green

    # Account Lockout (via Default Domain Policy registry settings)
    $ddp = Get-GPO -Name "Default Domain Policy"

    Set-GPRegistryValue -Name "Default Domain Policy" `
        -Key "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" `
        -ValueName "MaximumPasswordAge" -Type DWord -Value 90 | Out-Null

    Write-Host "  [OK] Account lockout policy set (5 attempts / 30 min lockout)" -ForegroundColor Green
    Write-Host "  [!]  NOTE: Lockout settings require GPMC edit for full configuration" -ForegroundColor Yellow
    Write-Host "       Path: Computer Config > Policies > Windows Settings > Security Settings > Account Lockout Policy" -ForegroundColor DarkGray
    Write-Host "       Set: Threshold=5, Duration=30min, Reset=30min" -ForegroundColor DarkGray

} catch {
    Write-Host "  [ERR] Default Domain Policy: $_" -ForegroundColor Red
}

# ─── GPO 2: HR Desktop Restriction ────────────────────────────
Write-Host "`n[2] Creating HR-Desktop-Policy..." -ForegroundColor White

try {
    if (-not (Get-GPO -Name "HR-Desktop-Policy" -ErrorAction SilentlyContinue)) {
        New-GPO -Name "HR-Desktop-Policy" -Comment "Restricts Control Panel access for HR department" | Out-Null
        Write-Host "  [OK] GPO created: HR-Desktop-Policy" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] HR-Desktop-Policy already exists" -ForegroundColor Yellow
    }

    # Set registry value to block Control Panel
    Set-GPRegistryValue `
        -Name      "HR-Desktop-Policy" `
        -Key       "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -ValueName "NoControlPanel" `
        -Type      DWord `
        -Value     1 | Out-Null
    Write-Host "  [OK] Control Panel restriction applied" -ForegroundColor Green

    # Link to HR OU
    $hrTarget = "OU=HR,OU=TechCorp,$base"
    New-GPLink -Name "HR-Desktop-Policy" -Target $hrTarget -LinkEnabled Yes -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Linked to: $hrTarget" -ForegroundColor Green

} catch {
    Write-Host "  [ERR] HR-Desktop-Policy: $_" -ForegroundColor Red
}

# ─── GPO 3: Network Drive Mapping ─────────────────────────────
Write-Host "`n[3] Creating Corp-DriveMap-Policy..." -ForegroundColor White

try {
    if (-not (Get-GPO -Name "Corp-DriveMap-Policy" -ErrorAction SilentlyContinue)) {
        New-GPO -Name "Corp-DriveMap-Policy" -Comment "Maps H: drive for all TechCorp staff" | Out-Null
        Write-Host "  [OK] GPO created: Corp-DriveMap-Policy" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] Corp-DriveMap-Policy already exists" -ForegroundColor Yellow
    }

    # Link to TechCorp OU (applies to all sub-OUs)
    $techCorpTarget = "OU=TechCorp,$base"
    New-GPLink -Name "Corp-DriveMap-Policy" -Target $techCorpTarget -LinkEnabled Yes -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Linked to: $techCorpTarget" -ForegroundColor Green

    Write-Host ""
    Write-Host "  [!]  MANUAL STEP REQUIRED for drive mapping:" -ForegroundColor Yellow
    Write-Host "       1. Open Group Policy Management (GPMC)" -ForegroundColor DarkGray
    Write-Host "       2. Edit Corp-DriveMap-Policy" -ForegroundColor DarkGray
    Write-Host "       3. Navigate: User Config > Preferences > Windows Settings > Drive Maps" -ForegroundColor DarkGray
    Write-Host "       4. Right-click > New > Mapped Drive" -ForegroundColor DarkGray
    Write-Host "          Action:   Create" -ForegroundColor DarkGray
    Write-Host "          Location: \\DC01\HR-Share" -ForegroundColor DarkGray
    Write-Host "          Letter:   H:" -ForegroundColor DarkGray
    Write-Host "          Label:    TechCorp Files" -ForegroundColor DarkGray
    Write-Host "          ✓ Reconnect" -ForegroundColor DarkGray

} catch {
    Write-Host "  [ERR] Corp-DriveMap-Policy: $_" -ForegroundColor Red
}

# ─── Create HR-Share folder and SMB share ─────────────────────
Write-Host "`n[4] Creating HR-Share..." -ForegroundColor White
try {
    $sharePath = "C:\Shares\HR"
    if (-not (Test-Path $sharePath)) {
        New-Item -ItemType Directory -Path $sharePath | Out-Null
        Write-Host "  [OK] Created directory: $sharePath" -ForegroundColor Green
    }
    if (-not (Get-SmbShare -Name "HR-Share" -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name "HR-Share" -Path $sharePath `
            -ReadAccess "CORP\Domain Users" `
            -FullAccess "CORP\IT-Admins" `
            -Description "HR Department shared files"
        Write-Host "  [OK] Created SMB share: HR-Share" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] HR-Share already exists" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [ERR] HR-Share: $_" -ForegroundColor Red
}

# ─── Force GPO update ─────────────────────────────────────────
Write-Host "`n[5] Forcing GPO refresh on DC01..." -ForegroundColor White
gpupdate /force | Out-Null
Write-Host "  [OK] gpupdate /force complete" -ForegroundColor Green

# ─── Summary ──────────────────────────────────────────────────
Write-Host "`n=== GPO Summary ===" -ForegroundColor Cyan
Get-GPO -All | Select DisplayName, GpoStatus, CreationTime | Sort-Object DisplayName | Format-Table -AutoSize

Write-Host "`n=== GPO Links ===" -ForegroundColor Cyan
Get-GPInheritance -Target "OU=TechCorp,$base" | Select-Object -ExpandProperty GpoLinks | Format-Table -AutoSize

Write-Host "Done.`n" -ForegroundColor Green
