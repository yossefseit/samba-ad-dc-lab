#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command awk getent hostname hostnamectl ip install
load_env "${SAMBA_LAB_SCRIPTS_DIR}/00-env"

configured_ip_found=false
while IFS= read -r address; do
  if [[ ${address%/*} == "$DC_IP" ]]; then
    configured_ip_found=true
    break
  fi
done < <(ip -o -4 address show scope global | awk '{print $4}')

[[ $configured_ip_found == true ]] ||
  die "DC_IP ${DC_IP} is not assigned to a global interface. Configure a persistent static address first."

conflict="$(
  awk -v ip="$DC_IP" -v fqdn="$DC_FQDN" -v host="$DC_HOST" '
    {
      content = $0
      sub(/[[:space:]]*#.*/, "", content)
      sub(/^[[:space:]]+/, "", content)
      count = split(content, fields, /[[:space:]]+/)
      if (count < 2) {
        next
      }
      for (i = 2; i <= count; i++) {
        if ((fields[i] == fqdn || fields[i] == host) && fields[1] != ip) {
          print NR ":" $0
        }
      }
    }
  ' /etc/hosts
)"
[[ -z $conflict ]] || die "Resolve conflicting /etc/hosts entries before continuing: ${conflict}"

backup_path_once /etc/hostname
backup_path_once /etc/hosts

if [[ $(hostname) != "$DC_HOST" ]]; then
  log "Setting the static hostname to ${DC_HOST}"
  hostnamectl set-hostname "$DC_HOST"
else
  log "Hostname already set to ${DC_HOST}"
fi

if ! awk -v ip="$DC_IP" -v fqdn="$DC_FQDN" -v host="$DC_HOST" '
  {
    content = $0
    sub(/[[:space:]]*#.*/, "", content)
    sub(/^[[:space:]]+/, "", content)
    count = split(content, fields, /[[:space:]]+/)
    if (fields[1] == ip) {
      have_fqdn = 0
      have_host = 0
      for (i = 2; i <= count; i++) {
        have_fqdn = have_fqdn || fields[i] == fqdn
        have_host = have_host || fields[i] == host
      }
      if (have_fqdn && have_host) {
        found = 1
      }
    }
  }
  END { exit(found ? 0 : 1) }
' /etc/hosts; then
  log "Adding the domain controller mapping to /etc/hosts"
  printf '%s  %s %s\n' "$DC_IP" "$DC_FQDN" "$DC_HOST" >>/etc/hosts
else
  log "/etc/hosts already contains the expected mapping"
fi

resolved_ip="$(getent ahostsv4 "$DC_FQDN" | awk 'NR == 1 {print $1}')"
[[ $resolved_ip == "$DC_IP" ]] || die "${DC_FQDN} resolves to ${resolved_ip:-nothing}, not ${DC_IP}."

log "Host preflight passed"
hostnamectl --static
printf 'FQDN: %s\nAddress: %s\n' "$(hostname -f)" "$resolved_ip"
