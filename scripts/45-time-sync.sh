#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command chronyc chronyd getent grep install mktemp stat systemctl
load_env "${SAMBA_LAB_SCRIPTS_DIR}/00-env"

[[ -S /var/lib/samba/ntp_signd/socket ]] ||
  die "The Samba signed-time socket is missing. Start samba-ad-dc with 40-dns-forwarder.sh first."
getent group _chrony >/dev/null || die "The Ubuntu _chrony service group does not exist."

chrony_drop_in=/etc/chrony/conf.d/samba-ad-dc-lab.conf
backup_path_once "$chrony_drop_in"

if grep -R --exclude='samba-ad-dc-lab.conf' -E '^[[:space:]]*ntpsigndsocket[[:space:]]' \
  /etc/chrony/chrony.conf /etc/chrony/conf.d 2>/dev/null; then
  die "An unmanaged ntpsigndsocket directive already exists; reconcile it manually before continuing."
fi

runtime_dir="$(mktemp -d /run/samba-ad-dc-lab-time.XXXXXX)"
candidate="${runtime_dir}/samba-ad-dc-lab.conf"
previous_drop_in="${runtime_dir}/previous.conf"
drop_in_was_present=false
chrony_was_enabled=false
chrony_was_active=false
config_changed=false
socket_uid="$(stat -c '%u' /var/lib/samba/ntp_signd)"
socket_gid="$(stat -c '%g' /var/lib/samba/ntp_signd)"
socket_mode="$(stat -c '%a' /var/lib/samba/ntp_signd)"

if [[ -e $chrony_drop_in ]]; then
  cp -a --no-dereference -- "$chrony_drop_in" "$previous_drop_in"
  drop_in_was_present=true
fi
systemctl is-enabled --quiet chrony && chrony_was_enabled=true
systemctl is-active --quiet chrony && chrony_was_active=true

cleanup() {
  local exit_code=$?

  set +e
  if ((exit_code != 0)) && [[ $config_changed == true ]]; then
    warn "Chrony activation failed; restoring the configuration and service state from before this run"
    rm -f -- "$chrony_drop_in"
    if [[ $drop_in_was_present == true ]]; then
      cp -a --no-dereference -- "$previous_drop_in" "$chrony_drop_in"
    fi
    chown "${socket_uid}:${socket_gid}" /var/lib/samba/ntp_signd
    chmod "$socket_mode" /var/lib/samba/ntp_signd
    if [[ $chrony_was_enabled == true ]]; then
      systemctl enable chrony >/dev/null 2>&1 || true
    else
      systemctl disable chrony >/dev/null 2>&1 || true
    fi
    if [[ $chrony_was_active == true ]]; then
      systemctl restart chrony >/dev/null 2>&1 ||
        warn "The previous chrony service state could not be restored automatically"
    else
      systemctl stop chrony >/dev/null 2>&1 || true
    fi
  fi
  rm -f -- "$candidate" "$previous_drop_in"
  rmdir -- "$runtime_dir" 2>/dev/null || true
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

log "Restricting signed NTP service to ${LAN_CIDR}"
printf '# Managed by samba-ad-dc-lab.\nallow %s\nntpsigndsocket /var/lib/samba/ntp_signd\n' \
  "$LAN_CIDR" >"$candidate"
chronyd -p -f "$candidate" >/dev/null
install -o root -g root -m 0644 "$candidate" "$chrony_drop_in"
config_changed=true

chown root:_chrony /var/lib/samba/ntp_signd
chmod 0750 /var/lib/samba/ntp_signd
chronyd -p -f /etc/chrony/chrony.conf >/dev/null

systemctl enable --now chrony
systemctl restart chrony
systemctl is-active --quiet chrony || die "chrony did not become active."
chronyc tracking

config_changed=false
log "Chrony is active; restrict UDP/123 to the lab LAN in the host and network firewalls"
