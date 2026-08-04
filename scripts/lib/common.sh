#!/usr/bin/env bash

# Shared validation and host-configuration backup helpers.
# This file is sourced by the numbered scripts and intentionally has no side effects.

SAMBA_LAB_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SAMBA_LAB_SCRIPTS_DIR
readonly SAMBA_LAB_STATE_DIR="${SAMBA_LAB_STATE_DIR:-/var/lib/samba-ad-dc-lab}"

log() {
  printf '[+] %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if ((EUID != 0)); then
    die "Run this script as root (for example, sudo bash $0)."
  fi
}

require_command() {
  local command_name

  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || die "Required command not found: ${command_name}"
  done
}

require_ubuntu_2404() {
  local distro_id distro_version

  [[ -r /etc/os-release ]] || die "Cannot identify the operating system: /etc/os-release is missing."
  distro_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
  distro_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')"
  [[ $distro_id == "ubuntu" && $distro_version == "24.04" ]] ||
    die "This lab targets Ubuntu 24.04; detected ${distro_id:-unknown} ${distro_version:-unknown}."
}

validate_ipv4() {
  local value=$1
  local octet
  local -a octets

  [[ $value =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<<"$value"
  for octet in "${octets[@]}"; do
    ((10#$octet <= 255)) || return 1
  done
}

ipv4_to_integer() {
  local value=$1
  local a b c d

  validate_ipv4 "$value" || return 1
  IFS='.' read -r a b c d <<<"$value"
  printf '%u\n' "$(((10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d))"
}

validate_cidr_contains_ip() {
  local cidr=$1
  local ip=$2
  local network prefix ip_integer network_integer mask

  [[ $cidr == */* ]] || return 1
  network=${cidr%/*}
  prefix=${cidr#*/}
  validate_ipv4 "$network" || return 1
  [[ $prefix =~ ^[0-9]{1,2}$ ]] || return 1
  ((10#$prefix >= 8 && 10#$prefix <= 30)) || return 1
  ip_integer="$(ipv4_to_integer "$ip")" || return 1
  network_integer="$(ipv4_to_integer "$network")" || return 1
  mask=$(((0xFFFFFFFF << (32 - 10#$prefix)) & 0xFFFFFFFF))
  ((network_integer == (network_integer & mask))) || return 1
  ((ip_integer == (ip_integer & mask) || ip_integer == ((ip_integer & mask) | (0xFFFFFFFF ^ mask)))) &&
    return 1
  (((ip_integer & mask) == network_integer))
}

is_safe_dns_forwarder() {
  local value=$1
  local a b _c _d

  validate_ipv4 "$value" || return 1
  IFS='.' read -r a b _c _d <<<"$value"
  ((10#$a != 0 && 10#$a != 127 && 10#$a < 224)) || return 1
  ! ((10#$a == 169 && 10#$b == 254))
}

realm_to_base_dn() {
  local realm=$1
  local label base_dn=""
  local -a labels

  IFS='.' read -r -a labels <<<"${realm,,}"
  for label in "${labels[@]}"; do
    if [[ -n $base_dn ]]; then
      base_dn+=","
    fi
    base_dn+="DC=${label}"
  done
  printf '%s\n' "$base_dn"
}

render_smb_config_with_forwarder() {
  local input_file=$1
  local output_file=$2
  local forwarder=$3

  awk -v forwarder="$forwarder" '
    function section_name(line, value) {
      value = line
      sub(/^\[/, "", value)
      sub(/\][[:space:]]*$/, "", value)
      return tolower(value)
    }
    function emit_forwarder() {
      if (in_global && !inserted) {
        print "\tdns forwarder = " forwarder
        inserted = 1
      }
    }
    /^\[[^]]+\][[:space:]]*$/ {
      emit_forwarder()
      in_global = section_name($0) == "global"
      if (in_global) {
        found_global = 1
      }
      print
      next
    }
    {
      lowered = tolower($0)
      if (in_global && lowered ~ /^[[:space:]]*dns[[:space:]]+forwarder[[:space:]]*=/) {
        next
      }
      print
    }
    END {
      emit_forwarder()
      if (!found_global) {
        exit 42
      }
    }
  ' "$input_file" >"$output_file"
}

parse_config_value() {
  local raw=$1

  if [[ $raw =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ $raw =~ ^\'([^\']*)\'[[:space:]]*(#.*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ $raw =~ ^([^[:space:]#]+)[[:space:]]*(#.*)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

load_env() {
  local env_file=${1:-${SAMBA_LAB_SCRIPTS_DIR}/00-env}
  local line key raw value line_number=0
  local -A seen=()

  [[ -r $env_file ]] || die "Configuration file not found or unreadable: ${env_file}"

  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue

    if [[ $line =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      raw=${BASH_REMATCH[2]}
    else
      die "Invalid configuration syntax at ${env_file}:${line_number}. Use KEY=VALUE assignments only."
    fi

    case "$key" in
      DC_IP | DC_FQDN | DC_HOST | REALM | DOMAIN | DNS_FORWARDER | LAN_CIDR | \
        OU_USERS_NAME | OU_WORKSTATIONS_NAME | NEW_USER | NEW_USER_GIVEN | \
        NEW_USER_SURNAME | BACKUP_DIR) ;;
      *) die "Unknown configuration key ${key} at ${env_file}:${line_number}." ;;
    esac

    [[ -z ${seen[$key]:-} ]] || die "Duplicate configuration key ${key} at ${env_file}:${line_number}."
    seen[$key]=1
    value="$(parse_config_value "$raw")" ||
      die "Invalid value at ${env_file}:${line_number}; quote values that contain spaces."
    printf -v "$key" '%s' "$value"
  done <"$env_file"

  : "${OU_USERS_NAME:=Lab Users}"
  : "${OU_WORKSTATIONS_NAME:=Lab Workstations}"
  : "${NEW_USER:=lab.user}"
  : "${NEW_USER_GIVEN:=Lab}"
  : "${NEW_USER_SURNAME:=User}"
  : "${BACKUP_DIR:=/var/backups/samba-ad-dc}"

  validate_config
}

validate_config() {
  local dns_zone
  local ou_name_pattern='^[A-Za-z0-9][A-Za-z0-9_-]*( [A-Za-z0-9][A-Za-z0-9_-]*)*$'
  local person_name_pattern='^[A-Za-z]([- A-Za-z]{0,62}[A-Za-z])?$'

  : "${DC_IP:?DC_IP is required}"
  : "${DC_FQDN:?DC_FQDN is required}"
  : "${DC_HOST:?DC_HOST is required}"
  : "${REALM:?REALM is required}"
  : "${DOMAIN:?DOMAIN is required}"
  : "${DNS_FORWARDER:?DNS_FORWARDER is required}"
  : "${LAN_CIDR:?LAN_CIDR is required}"

  validate_ipv4 "$DC_IP" || die "DC_IP must be a valid IPv4 address."
  [[ $DC_FQDN == "${DC_FQDN,,}" ]] || die "DC_FQDN must be lowercase."
  [[ $DC_FQDN =~ ^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?(\.[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?)+$ ]] ||
    die "DC_FQDN is not a valid fully qualified DNS name."
  [[ $DC_HOST =~ ^[a-z0-9]([-a-z0-9]{0,13}[a-z0-9])?$ ]] ||
    die "DC_HOST must be a lowercase DNS label no longer than 15 characters."
  [[ ${DC_FQDN%%.*} == "$DC_HOST" ]] || die "DC_HOST must be the first label of DC_FQDN."

  [[ $REALM == "${REALM^^}" && $REALM == *.* ]] || die "REALM must be an uppercase DNS name."
  [[ $REALM != *.LOCAL ]] || die "Do not use .local; it conflicts with multicast DNS."
  dns_zone=${DC_FQDN#*.}
  [[ ${dns_zone^^} == "$REALM" ]] || die "REALM must match the DNS suffix of DC_FQDN."

  [[ $DOMAIN =~ ^[A-Z0-9]([A-Z0-9-]{0,13}[A-Z0-9])?$ ]] ||
    die "DOMAIN must be an uppercase NetBIOS name no longer than 15 characters."
  [[ $DOMAIN != "${DC_HOST^^}" ]] || die "DOMAIN must not be the domain controller hostname."

  is_safe_dns_forwarder "$DNS_FORWARDER" ||
    die "DNS_FORWARDER must be a unicast IPv4 resolver (not loopback, link-local, multicast, or unspecified)."
  [[ $DNS_FORWARDER != "$DC_IP" ]] || die "DNS_FORWARDER must not point back to the domain controller."
  validate_cidr_contains_ip "$LAN_CIDR" "$DC_IP" ||
    die "LAN_CIDR must be an IPv4 /8 through /30 that contains DC_IP."

  [[ $OU_USERS_NAME =~ $ou_name_pattern ]] ||
    die "OU_USERS_NAME contains unsupported DN characters."
  [[ $OU_WORKSTATIONS_NAME =~ $ou_name_pattern ]] ||
    die "OU_WORKSTATIONS_NAME contains unsupported DN characters."
  [[ $NEW_USER =~ ^[a-z][a-z0-9._-]{0,31}$ ]] || die "NEW_USER is not a safe lab account name."
  [[ $NEW_USER_GIVEN =~ $person_name_pattern ]] ||
    die "NEW_USER_GIVEN contains unsupported characters."
  [[ $NEW_USER_SURNAME =~ $person_name_pattern ]] ||
    die "NEW_USER_SURNAME contains unsupported characters."

  [[ $BACKUP_DIR == /* && $BACKUP_DIR != "/" && $BACKUP_DIR != "/var" && $BACKUP_DIR != "/etc" ]] ||
    die "BACKUP_DIR must be a specific absolute directory."
}

backup_path_once() {
  local target=$1
  local key status_file data_file

  key=${target#/}
  key=${key//\//__}
  status_file="${SAMBA_LAB_STATE_DIR}/original/${key}.status"
  data_file="${SAMBA_LAB_STATE_DIR}/original/${key}.data"
  [[ -e $status_file ]] && return 0

  install -d -m 0700 "${SAMBA_LAB_STATE_DIR}/original"
  if [[ -e $target || -L $target ]]; then
    cp -a --no-dereference -- "$target" "$data_file"
    printf 'present\n' >"$status_file"
  else
    printf 'absent\n' >"$status_file"
  fi
  chmod 0600 "$status_file"
}

samba_config_value() {
  local parameter=$1

  testparm -s --parameter-name="$parameter" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

assert_domain_config_matches() {
  local actual_realm actual_domain actual_role

  [[ -r /etc/samba/smb.conf ]] || die "The domain database exists but /etc/samba/smb.conf is missing."
  actual_realm="$(samba_config_value realm)"
  actual_domain="$(samba_config_value workgroup)"
  actual_role="$(samba_config_value 'server role')"

  [[ ${actual_realm^^} == "$REALM" ]] || die "Existing realm ${actual_realm:-unknown} does not match ${REALM}."
  [[ ${actual_domain^^} == "$DOMAIN" ]] || die "Existing NetBIOS domain ${actual_domain:-unknown} does not match ${DOMAIN}."
  [[ ${actual_role,,} == "active directory domain controller" ]] ||
    die "Existing Samba role is ${actual_role:-unknown}, not an AD domain controller."
}
