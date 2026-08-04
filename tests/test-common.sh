#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${repo_root}/scripts/lib/common.sh"

fail_test() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_success() {
  local label=$1
  shift

  "$@" || fail_test "$label"
}

assert_failure() {
  local label=$1
  shift

  if "$@"; then
    fail_test "$label"
  fi
}

assert_success "valid IPv4 rejected" validate_ipv4 10.20.30.10
assert_failure "out-of-range IPv4 accepted" validate_ipv4 10.20.30.999
assert_success "valid CIDR membership rejected" validate_cidr_contains_ip 10.20.30.0/24 10.20.30.10
assert_failure "out-of-range CIDR membership accepted" validate_cidr_contains_ip 10.20.31.0/24 10.20.30.10
assert_failure "host-form CIDR accepted as a network" validate_cidr_contains_ip 10.20.30.5/24 10.20.30.10
assert_failure "network address accepted as DC IP" validate_cidr_contains_ip 10.20.30.0/24 10.20.30.0
assert_failure "broadcast address accepted as DC IP" validate_cidr_contains_ip 10.20.30.0/24 10.20.30.255
assert_success "public DNS forwarder rejected" is_safe_dns_forwarder 9.9.9.9
assert_failure "loopback DNS forwarder accepted" is_safe_dns_forwarder 127.0.0.1
[[ $(realm_to_base_dn AD.EXAMPLE.TEST) == 'DC=ad,DC=example,DC=test' ]] || fail_test "realm-to-DN conversion"

test_tmp="$(mktemp -d)"
trap 'rm -rf -- "$test_tmp"' EXIT

valid_env="${test_tmp}/valid.env"
printf '%s\n' \
  'DC_IP="10.20.30.10"' \
  'DC_FQDN="dc1.ad.example.test"' \
  'DC_HOST="dc1"' \
  'REALM="AD.EXAMPLE.TEST"' \
  'DOMAIN="LAB"' \
  'DNS_FORWARDER="9.9.9.9"' \
  'LAN_CIDR="10.20.30.0/24"' \
  'OU_USERS_NAME="Lab Users"' >"$valid_env"

if ! (
  load_env "$valid_env"
  [[ $DC_IP == '10.20.30.10' ]]
  [[ $OU_USERS_NAME == 'Lab Users' ]]
  [[ $NEW_USER == 'lab.user' ]]
); then
  fail_test "valid configuration did not load with defaults"
fi

duplicate_env="${test_tmp}/duplicate.env"
cp "$valid_env" "$duplicate_env"
printf '%s\n' 'DC_IP="10.20.30.11"' >>"$duplicate_env"
if (load_env "$duplicate_env") >/dev/null 2>&1; then
  fail_test "duplicate key was accepted"
fi

wrong_realm_env="${test_tmp}/wrong-realm.env"
sed 's/REALM="AD.EXAMPLE.TEST"/REALM="OTHER.EXAMPLE.TEST"/' "$valid_env" >"$wrong_realm_env"
if (load_env "$wrong_realm_env") >/dev/null 2>&1; then
  fail_test "realm/FQDN mismatch was accepted"
fi

marker="${test_tmp}/executed"
malicious_env="${test_tmp}/malicious.env"
# The literal command substitution is the parser attack payload under test.
# shellcheck disable=SC2016
printf 'DC_IP="$(touch %s)"\n' "$marker" >"$malicious_env"
sed -n '2,$p' "$valid_env" >>"$malicious_env"
if (load_env "$malicious_env") >/dev/null 2>&1; then
  fail_test "shell expression was accepted as configuration"
fi
[[ ! -e $marker ]] || fail_test "configuration executed shell code"

smb_input="${test_tmp}/smb.conf"
smb_output="${test_tmp}/smb.rendered.conf"
printf '%s\n' \
  '[global]' \
  '  workgroup = LAB' \
  '  dns forwarder = 127.0.0.53' \
  '  dns forwarder = 1.1.1.1' \
  '[netlogon]' \
  '  path = /var/lib/samba/sysvol/ad.example.test/scripts' >"$smb_input"
render_smb_config_with_forwarder "$smb_input" "$smb_output" 9.9.9.9
[[ $(grep -Eic '^[[:space:]]*dns[[:space:]]+forwarder[[:space:]]*=' "$smb_output") == 1 ]] ||
  fail_test "duplicate DNS forwarders were not removed"
grep -Eq '^[[:space:]]*dns[[:space:]]+forwarder[[:space:]]*=[[:space:]]*9\.9\.9\.9$' "$smb_output" ||
  fail_test "expected DNS forwarder was not rendered"
grep -Fq '[netlogon]' "$smb_output" || fail_test "non-global Samba sections were not preserved"

printf '%s\n' '[netlogon]' '  path = /tmp' >"$smb_input"
if render_smb_config_with_forwarder "$smb_input" "$smb_output" 9.9.9.9; then
  fail_test "Samba configuration without [global] was accepted"
fi

printf 'PASS: configuration parser, network validators, and Samba config rendering\n'
