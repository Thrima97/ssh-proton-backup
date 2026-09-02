#!/usr/bin/env bash

set -Eeuo pipefail

export PATH="/usr/local/bin:${HOME}/.local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LIB=""
for candidate in \
    "${SCRIPT_DIR}/lib/env.sh" \
    "${HOME}/.local/lib/ssh-proton-backup/env.sh"
do
    if [ -f "$candidate" ]; then
        ENV_LIB="$candidate"
        break
    fi
done

if [ -z "$ENV_LIB" ]; then
    echo "ERROR: Cannot find lib/env.sh" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_LIB"
load_backup_env "$SCRIPT_DIR"
require_gpg_passphrase

PASS_TMP=""
cleanup() {
    if [ -n "${PASS_TMP:-}" ] && [ -f "$PASS_TMP" ]; then
        rm -f "$PASS_TMP"
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
Usage: ssh-proton-restore.sh ARCHIVE [DEST_DIR]

Decrypt an SSH backup archive into DEST_DIR.
If DEST_DIR is omitted, a timestamped folder is created in $HOME.

This script never extracts into ~/.ssh.
Configuration is read from ~/.config/ssh-backup/.env (or SSH_BACKUP_ENV).
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage >&2
    exit 1
fi

ARCHIVE="$1"
DEST_DIR="${2:-${HOME}/ssh-restore-$(date +"%Y-%m-%d_%H-%M-%S")}"

if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: Archive not found: ${ARCHIVE}" >&2
    exit 1
fi

command -v gpg >/dev/null || {
    echo "ERROR: gpg is not installed." >&2
    exit 1
}

ABS_DEST="$(mkdir -p "$DEST_DIR" && cd "$DEST_DIR" && pwd)"
ABS_SSH="$(cd "$SSH_DIR" 2>/dev/null && pwd || true)"

if [ -n "$ABS_SSH" ] && [ "$ABS_DEST" = "$ABS_SSH" ]; then
    echo "ERROR: Refusing to extract into ${SSH_DIR}. Choose another destination." >&2
    exit 1
fi

chmod 700 "$ABS_DEST"

if [ -n "${GPG_PASSPHRASE_FILE:-}" ] && [ -f "$GPG_PASSPHRASE_FILE" ]; then
    GPG_PASS_FILE="$GPG_PASSPHRASE_FILE"
else
    PASS_TMP="$(with_gpg_passphrase_file)"
    GPG_PASS_FILE="$PASS_TMP"
fi

echo "Decrypting ${ARCHIVE} into ${ABS_DEST}..."

gpg \
    --batch \
    --yes \
    --pinentry-mode loopback \
    --passphrase-file "$GPG_PASS_FILE" \
    --decrypt \
    "$ARCHIVE" | tar -C "$ABS_DEST" -xzf -

echo "Restore complete."
echo "Extracted files are in: ${ABS_DEST}"
echo "Review them, then copy selected keys into ${SSH_DIR} if needed."
