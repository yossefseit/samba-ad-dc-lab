#!/usr/bin/env bash
set -euo pipefail
umask 077

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "$0")/lib/common.sh"

require_root
require_ubuntu_2404
require_command awk find install mktemp samba-tool sha256sum sort systemctl
load_env "${SAMBA_LAB_SCRIPTS_DIR}/00-env"

systemctl is-active --quiet samba-ad-dc || die "samba-ad-dc must be active for an online backup."
install -d -o root -g root -m 0700 "$BACKUP_DIR"

samba-tool dbcheck --cross-ncs
samba-tool ntacl sysvolcheck

run_marker="$(mktemp "${BACKUP_DIR}/.samba-backup-run.XXXXXX")"
cleanup() {
  local exit_code=$?

  rm -f -- "$run_marker"
  trap - EXIT
  exit "$exit_code"
}
trap cleanup EXIT

printf 'This creates a secret-bearing online domain backup outside the repository.\n'
printf 'Authenticate as %s\\Administrator when prompted.\n' "$DOMAIN"
samba-tool domain backup online \
  --server="$DC_FQDN" \
  --targetdir="$BACKUP_DIR" \
  -U "${DOMAIN}\\Administrator"

new_backup="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'samba-backup-*.tar.bz2' -newer "$run_marker" -printf '%T@ %p\n' | sort -nr | awk 'NR == 1 {$1=""; sub(/^ /, ""); print}')"
[[ -n $new_backup ]] || die "The backup command returned success but created no new backup archive."
sha256sum "$new_backup" >"${new_backup}.sha256"
chmod 0600 "$new_backup" "${new_backup}.sha256"

log "Backup created by this run: ${new_backup}"
log "A backup is not recovery evidence until it is restored and tested on an isolated host"
