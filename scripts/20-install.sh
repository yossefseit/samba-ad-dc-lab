#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command apt-get systemctl

log "Updating Ubuntu package indexes"
apt-get update

log "Installing the AD DC, DNS, Kerberos, SMB test, and time packages"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  samba-ad-dc \
  krb5-user \
  bind9-dnsutils \
  smbclient \
  chrony

log "Stopping and masking standalone Samba services"
systemctl disable --now smbd nmbd winbind 2>/dev/null || true
systemctl mask smbd nmbd winbind

log "Enabling the AD DC unit without starting it before provisioning"
systemctl unmask samba-ad-dc
systemctl enable samba-ad-dc

log "Package installation complete; the current DNS resolver was left intact"
