#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command awk grep install samba-tool systemctl
load_env

systemctl is-active --quiet samba-ad-dc || die "samba-ad-dc must be active before creating objects."
base_dn="$(realm_to_base_dn "$REALM")"
users_ou="OU=${OU_USERS_NAME},${base_dn}"
workstations_ou="OU=${OU_WORKSTATIONS_NAME},${base_dn}"
sample_user_marker="${SAMBA_LAB_STATE_DIR}/sample-user-${NEW_USER}.owned"

ensure_ou() {
  local ou_dn=$1
  local description=$2

  if samba-tool ou list --full-dn | grep -Fxi -- "$ou_dn" >/dev/null; then
    log "OU already exists: ${ou_dn}"
  else
    samba-tool ou add "$ou_dn" --description="$description"
  fi
}

ensure_ou "$users_ou" "Isolated lab user accounts"
ensure_ou "$workstations_ou" "Isolated lab workstation accounts"

if ! samba-tool user show "$NEW_USER" >/dev/null 2>&1; then
  printf 'Enter a unique lab password when prompted; it is never read from scripts/00-env.\n'
  samba-tool user add "$NEW_USER" \
    --given-name="$NEW_USER_GIVEN" \
    --surname="$NEW_USER_SURNAME" \
    --must-change-at-next-login
  install -d -m 0700 "$SAMBA_LAB_STATE_DIR"
  install -m 0600 /dev/null "$sample_user_marker"
fi

if [[ -e $sample_user_marker ]]; then
  user_dn="$(samba-tool user show "$NEW_USER" | awk 'tolower($1) == "dn:" {$1=""; sub(/^ /, ""); print; exit}')"
  if [[ ${user_dn,,} == *",${users_ou,,}" ]]; then
    log "Managed sample user already exists in ${users_ou}: ${NEW_USER}"
  else
    samba-tool user move "$NEW_USER" "$users_ou"
    log "Placed managed sample user in ${users_ou}: ${NEW_USER}"
  fi
else
  log "User already exists but was not created by this lab; leaving it unchanged: ${NEW_USER}"
fi
