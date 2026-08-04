#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command chronyc getent host samba-tool systemctl testparm
load_env

failures=0
zone=${REALM,,}

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  ((failures += 1))
}

check_command() {
  local label=$1
  shift

  if "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_srv() {
  local label=$1
  local record=$2
  local port=$3
  local output

  if output="$(host -t SRV "${record}.${zone}" 127.0.0.1 2>&1)" &&
    grep -Eiq "[[:space:]]${port}[[:space:]]+${DC_FQDN//./\\.}\.?$" <<<"$output"; then
    pass "$label"
  else
    printf '%s\n' "$output" >&2
    fail "$label"
  fi
}

check_command "samba-ad-dc service is active" systemctl is-active --quiet samba-ad-dc
check_command "chrony service is active" systemctl is-active --quiet chrony
check_command "Samba configuration parses" testparm -s

if [[ $(getent ahostsv4 "$DC_FQDN" | awk 'NR == 1 {print $1}') == "$DC_IP" ]]; then
  pass "host resolver maps the DC FQDN to its LAN address"
else
  fail "host resolver maps the DC FQDN to its LAN address"
fi

if host -t A "$DC_FQDN" 127.0.0.1 2>/dev/null | grep -Fq "has address ${DC_IP}"; then
  pass "Samba DNS returns the DC A record"
else
  fail "Samba DNS returns the DC A record"
fi

check_srv "LDAP service discovery record" _ldap._tcp 389
check_srv "Kerberos TCP service discovery record" _kerberos._tcp 88
check_srv "Kerberos UDP service discovery record" _kerberos._udp 88
check_srv "Kerberos password-change service record" _kpasswd._udp 464

check_command "external DNS forwarding works" host -t A example.com 127.0.0.1
check_command "domain information is queryable" samba-tool domain info "$DC_IP"
check_command "directory database check passes" samba-tool dbcheck --cross-ncs
check_command "SYSVOL ACL check passes" samba-tool ntacl sysvolcheck
check_command "chrony reports tracking data" chronyc tracking
check_command "signed-time socket exists" test -S /var/lib/samba/ntp_signd/socket

printf '\nManual credential-backed checks (not run by this script):\n'
printf '  kinit Administrator@%s && klist\n' "$REALM"
printf '  smbclient //%s/netlogon -U Administrator -c ls\n' "$DC_FQDN"
printf '  smbclient //%s/sysvol -U Administrator -c ls\n' "$DC_FQDN"

if ((failures > 0)); then
  printf '\n%d required verification check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll non-interactive verification checks passed.\n'
