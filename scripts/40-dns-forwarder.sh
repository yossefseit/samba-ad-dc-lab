#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command awk host install mktemp samba-tool systemctl testparm
load_env

[[ -e /var/lib/samba/private/sam.ldb ]] || die "No provisioned domain was found. Run 30-provision.sh first."
assert_domain_config_matches
backup_path_once /etc/samba/smb.conf
backup_path_once /etc/resolv.conf

runtime_dir="$(mktemp -d /run/samba-ad-dc-lab-dns.XXXXXX)"
config_tmp="$(mktemp /etc/samba/.smb.conf.samba-lab.XXXXXX)"
resolver_tmp="$(mktemp /etc/.resolv.conf.samba-lab.XXXXXX)"
previous_config="${runtime_dir}/smb.conf"
previous_resolver="${runtime_dir}/resolv.conf"
cp -a --no-dereference -- /etc/samba/smb.conf "$previous_config"
resolver_was_present=false
if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
  cp -a --no-dereference -- /etc/resolv.conf "$previous_resolver"
  resolver_was_present=true
fi

config_changed=false
resolver_changed=false
resolved_was_enabled=false
resolved_was_active=false
samba_was_active=false

systemctl is-enabled --quiet systemd-resolved && resolved_was_enabled=true
systemctl is-active --quiet systemd-resolved && resolved_was_active=true
systemctl is-active --quiet samba-ad-dc && samba_was_active=true

cleanup() {
  local exit_code=$?

  set +e
  rm -f -- "$config_tmp" "$resolver_tmp"
  if ((exit_code != 0)) && [[ $config_changed == true || $resolver_changed == true ]]; then
    warn "DNS activation failed; restoring the configuration and service state from before this run"
    systemctl stop samba-ad-dc >/dev/null 2>&1
    if [[ $config_changed == true ]]; then
      rm -f -- /etc/samba/smb.conf
      cp -a --no-dereference -- "$previous_config" /etc/samba/smb.conf
    fi
    if [[ $resolver_changed == true ]]; then
      rm -f -- /etc/resolv.conf
      if [[ $resolver_was_present == true ]]; then
        cp -a --no-dereference -- "$previous_resolver" /etc/resolv.conf
      fi
    fi
    if [[ $resolved_was_enabled == true ]]; then
      systemctl enable systemd-resolved >/dev/null 2>&1 || true
    else
      systemctl disable systemd-resolved >/dev/null 2>&1 || true
    fi
    if [[ $resolved_was_active == true ]]; then
      systemctl start systemd-resolved >/dev/null 2>&1 || true
    fi
    if [[ $samba_was_active == true ]]; then
      systemctl restart samba-ad-dc >/dev/null 2>&1 ||
        warn "The previous samba-ad-dc service state could not be restored automatically"
    fi
  fi
  rm -f -- "$previous_config" "$previous_resolver"
  rmdir -- "$runtime_dir" 2>/dev/null || true
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

log "Setting a single DNS forwarder in the [global] section"
if ! render_smb_config_with_forwarder /etc/samba/smb.conf "$config_tmp" "$DNS_FORWARDER"; then
  die "Could not update the [global] section in /etc/samba/smb.conf."
fi

testparm -s "$config_tmp" >/dev/null
chmod --reference=/etc/samba/smb.conf "$config_tmp"
chown --reference=/etc/samba/smb.conf "$config_tmp"
mv -- "$config_tmp" /etc/samba/smb.conf
config_changed=true

printf 'nameserver 127.0.0.1\nsearch %s\n' "${REALM,,}" >"$resolver_tmp"
chmod 0644 "$resolver_tmp"

log "Switching this dedicated DC from systemd-resolved to Samba internal DNS"
resolver_changed=true
systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
rm -f -- /etc/resolv.conf
mv -- "$resolver_tmp" /etc/resolv.conf

log "Starting samba-ad-dc"
systemctl restart samba-ad-dc

dns_ready=false
for ((attempt = 1; attempt <= 15; attempt += 1)); do
  if systemctl is-active --quiet samba-ad-dc &&
    host -t A "$DC_FQDN" 127.0.0.1 2>/dev/null | grep -F "has address ${DC_IP}" >/dev/null; then
    dns_ready=true
    break
  fi
  sleep 2
done
[[ $dns_ready == true ]] ||
  die "Samba DNS did not become ready or return ${DC_IP} for ${DC_FQDN} within 30 seconds."

resolver_changed=false
config_changed=false
log "Samba DNS is active and the local resolver check passed"
