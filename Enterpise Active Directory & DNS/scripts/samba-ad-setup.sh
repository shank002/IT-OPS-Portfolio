#!/usr/bin/env bash
# =============================================================================
# samba-ad-setup.sh — Deploy Samba 4 Active Directory DC on Ubuntu 22.04
# =============================================================================
# Domain:   LINUXCORP.LOCAL
# DC FQDN:  lnx-dc01.linuxcorp.local
# DC IP:    192.168.10.11
# Gateway:  192.168.10.1
# Admin pw: P@ssw0rd2024!
#
# Run as root or with sudo on a fresh Ubuntu 22.04 Server install.
# =============================================================================

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
REALM="LINUXCORP.LOCAL"
DOMAIN="LINUXCORP"
DC_IP="192.168.10.11"
DC_HOSTNAME="lnx-dc01"
DC_FQDN="lnx-dc01.linuxcorp.local"
GATEWAY="192.168.10.1"
ADMIN_PASS="P@ssw0rd2024!"
NIC="ens18"   # Change to your NIC name (run: ip a)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run as root: sudo bash samba-ad-setup.sh"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Samba AD DC Setup — linuxcorp.local            ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ─── Phase 1: Static IP ───────────────────────────────────────────────────────
info "Phase 1: Configuring static IP via Netplan"

cat > /etc/netplan/00-installer-config.yaml << EOF
network:
  version: 2
  ethernets:
    ${NIC}:
      dhcp4: false
      addresses:
        - ${DC_IP}/24
      nameservers:
        addresses: [127.0.0.1, 8.8.8.8]
        search: [${REALM,,}]
      routes:
        - to: default
          via: ${GATEWAY}
EOF

chmod 600 /etc/netplan/00-installer-config.yaml
netplan apply
success "Netplan configured: ${DC_IP}/24"

# ─── Phase 2: Hostname ────────────────────────────────────────────────────────
info "Phase 2: Setting hostname to ${DC_HOSTNAME}"
hostnamectl set-hostname "${DC_HOSTNAME}"

# /etc/hosts — critical for Samba provision
# Remove any existing entries for this hostname first
sed -i "/${DC_HOSTNAME}/d" /etc/hosts

cat >> /etc/hosts << EOF

# Samba AD DC
${DC_IP}   ${DC_FQDN}   ${DC_HOSTNAME}
EOF

success "Hostname set: ${DC_FQDN}"

# ─── Phase 3: Remove conflicting packages ─────────────────────────────────────
info "Phase 3: Removing conflicting Samba packages"
apt-get remove --purge -y samba* winbind* libnss-winbind* \
    libpam-winbind* libwbclient* 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
success "Conflicting packages removed"

# ─── Phase 4: Install Samba packages ──────────────────────────────────────────
info "Phase 4: Installing Samba and Kerberos packages"
export DEBIAN_FRONTEND=noninteractive

# Pre-answer debconf for Kerberos
debconf-set-selections << EOF
krb5-config krb5-config/default_realm string ${REALM}
krb5-config krb5-config/kerberos_servers string ${DC_FQDN}
krb5-config krb5-config/admin_server string ${DC_FQDN}
EOF

apt-get update -qq
apt-get install -y \
    samba \
    krb5-config \
    krb5-user \
    winbind \
    libpam-winbind \
    libnss-winbind \
    smbclient \
    dnsutils \
    net-tools

success "Packages installed"

# ─── Phase 5: Stop all Samba services ─────────────────────────────────────────
info "Phase 5: Stopping and disabling conflicting services"
systemctl stop smbd nmbd winbind samba-ad-dc 2>/dev/null || true
systemctl disable smbd nmbd winbind 2>/dev/null || true

# Backup existing smb.conf
[[ -f /etc/samba/smb.conf ]] && mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
success "Services stopped"

# ─── Phase 6: Provision Samba AD ──────────────────────────────────────────────
info "Phase 6: Provisioning Samba AD domain (${REALM})"
info "This may take 30–60 seconds..."

samba-tool domain provision \
    --use-rfc2307 \
    --realm="${REALM}" \
    --domain="${DOMAIN}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="${ADMIN_PASS}"

success "Domain provisioned: ${REALM}"

# ─── Phase 7: Kerberos config ─────────────────────────────────────────────────
info "Phase 7: Configuring Kerberos"
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
success "Kerberos config updated"

# ─── Phase 8: Enable and start Samba AD DC ────────────────────────────────────
info "Phase 8: Starting Samba AD DC service"
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc
systemctl start samba-ad-dc
sleep 3  # Allow service to initialize

if systemctl is-active --quiet samba-ad-dc; then
    success "samba-ad-dc is running"
else
    error "samba-ad-dc failed to start. Check: journalctl -u samba-ad-dc"
fi

# ─── Phase 9: Verification ────────────────────────────────────────────────────
echo ""
info "Phase 9: Running verification checks"
echo ""

echo "--- samba-tool domain info ---"
samba-tool domain info "${DC_IP}" || warn "domain info check failed"

echo ""
echo "--- User list ---"
samba-tool user list

echo ""
echo "--- DNS SRV records ---"
host -t SRV _ldap._tcp."${REALM,,}" 127.0.0.1 || warn "SRV lookup failed (DNS may need a moment)"
host -t SRV _kerberos._tcp."${REALM,,}" 127.0.0.1 || warn "Kerberos SRV lookup failed"

echo ""
echo "--- SMB connectivity ---"
smbclient -L localhost -U Administrator%"${ADMIN_PASS}" || warn "smbclient check failed"

echo ""
echo "--- Kerberos TGT ---"
echo "${ADMIN_PASS}" | kinit administrator@"${REALM}" 2>/dev/null && klist || warn "kinit failed (try manually)"

# ─── Phase 10: Add test users ─────────────────────────────────────────────────
info "Phase 10: Creating sample users"

declare -A USERS=(
    ["rahul.sharma"]="Rahul Sharma"
    ["priya.patel"]="Priya Patel"
    ["ankit.mehta"]="Ankit Mehta"
)

samba-tool ou create "OU=TechCorp,DC=linuxcorp,DC=local" 2>/dev/null || true
samba-tool ou create "OU=IT,OU=TechCorp,DC=linuxcorp,DC=local" 2>/dev/null || true
samba-tool ou create "OU=HR,OU=TechCorp,DC=linuxcorp,DC=local" 2>/dev/null || true

for SAM in "${!USERS[@]}"; do
    samba-tool user create "${SAM}" "${ADMIN_PASS}" \
        --given-name="${USERS[$SAM]% *}" \
        --surname="${USERS[$SAM]#* }" \
        --mail-address="${SAM}@${REALM,,}" 2>/dev/null && \
    success "Created user: ${SAM}" || warn "User ${SAM} may already exist"
done

samba-tool group add "IT-Admins" 2>/dev/null || true
samba-tool group addmembers "IT-Admins" rahul.sharma 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✓ Samba AD Setup Complete                      ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Domain:     ${REALM}"
echo "DC FQDN:    ${DC_FQDN}"
echo "DC IP:      ${DC_IP}"
echo "Admin:      administrator@${REALM}"
echo "Admin pass: ${ADMIN_PASS}"
echo ""
echo "Next steps:"
echo "  1. Verify DNS:   host -t A ${DC_FQDN} 127.0.0.1"
echo "  2. Test Kerberos: kinit administrator@${REALM}"
echo "  3. Test SMB:      smbclient //localhost/netlogon -U administrator"
echo ""
