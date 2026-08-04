#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command cp getent hostname install samba-tool systemctl testparm
load_env

[[ $(hostname) == "$DC_HOST" ]] ||
  die "The short hostname is $(hostname), expected ${DC_HOST}. Run 10-prereqs.sh first."
[[ $(getent ahostsv4 "$DC_FQDN" | awk 'NR == 1 {print $1}') == "$DC_IP" ]] ||
  die "${DC_FQDN} does not resolve to ${DC_IP}. Run 10-prereqs.sh and check /etc/hosts."

if [[ -e /var/lib/samba/private/sam.ldb ]]; then
  assert_domain_config_matches
  log "A matching AD database already exists; provisioning was safely skipped"
  exit 0
fi

if systemctl is-active --quiet samba-ad-dc; then
  die "samba-ad-dc is running without a detected AD database; investigate before provisioning."
fi

backup_path_once /etc/samba/smb.conf
backup_path_once /etc/krb5.conf
backup_path_once /etc/resolv.conf

if [[ -e /etc/samba/smb.conf ]]; then
  initial_config="/etc/samba/smb.conf.pre-ad-dc.$(date -u +%Y%m%dT%H%M%SZ)"
  log "Moving the package configuration to ${initial_config}"
  mv -- /etc/samba/smb.conf "$initial_config"
fi

printf '\nThis creates the first DC for a NEW, isolated lab forest.\n'
printf 'Realm: %s | NetBIOS domain: %s | DC: %s (%s)\n' "$REALM" "$DOMAIN" "$DC_FQDN" "$DC_IP"
printf 'The interactive prompt keeps the Administrator password out of files, arguments, and shell history.\n\n'

log "Starting interactive domain provisioning"
samba-tool domain provision \
  --interactive \
  --use-rfc2307 \
  --realm="$REALM" \
  --domain="$DOMAIN" \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --host-ip="$DC_IP"

assert_domain_config_matches
[[ -r /var/lib/samba/private/krb5.conf ]] || die "Provisioning did not produce the expected Kerberos configuration."
install -o root -g root -m 0644 /var/lib/samba/private/krb5.conf /etc/krb5.conf

log "Provisioning completed; run 40-dns-forwarder.sh before starting the AD DC"
