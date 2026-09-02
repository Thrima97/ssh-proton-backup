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

DATE="$(date +"%Y-%m-%d_%H-%M-%S")"
HOSTNAME_SHORT="$(hostname -s)"
BACKUP_NAME="${HOSTNAME_SHORT}_ssh_${DATE}.tar.gz.gpg"
BACKUP_FILE="${WORK_DIR}/${BACKUP_NAME}"
PASS_TMP=""

cleanup() {
    if [ -n "${PASS_TMP:-}" ] && [ -f "$PASS_TMP" ]; then
        rm -f "$PASS_TMP"
    fi
}
trap cleanup EXIT

FORCE=0

usage() {
    cat <<'EOF'
Usage: ssh-proton-backup.sh [--force]

Create an encrypted backup of ~/.ssh and upload it to Proton Drive
only when the SSH directory has changed (or when --force is set).

Configuration is read from ~/.config/ssh-backup/.env (or SSH_BACKUP_ENV).
EOF
}

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: ${arg}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

ssh_fingerprint() {
    local dir="$1"
    find "$dir" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}'
}

if [ ! -d "$SSH_DIR" ]; then
    echo "ERROR: ${SSH_DIR} does not exist." >&2
    exit 1
fi

command -v gpg >/dev/null || {
    echo "ERROR: gpg is not installed." >&2
    exit 1
}

command -v proton-drive >/dev/null || {
    echo "ERROR: proton-drive is not installed." >&2
    exit 1
}

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

CURRENT_FINGERPRINT="$(ssh_fingerprint "$SSH_DIR")"

if [ "$FORCE" -eq 0 ] && [ -f "$FINGERPRINT_FILE" ]; then
    LAST_FINGERPRINT="$(tr -d '[:space:]' < "$FINGERPRINT_FILE")"
    if [ "$CURRENT_FINGERPRINT" = "$LAST_FINGERPRINT" ]; then
        echo "No SSH changes; skipping upload."
        exit 0
    fi
fi

echo "Creating encrypted SSH backup..."

if [ -n "${GPG_PASSPHRASE_FILE:-}" ] && [ -f "$GPG_PASSPHRASE_FILE" ]; then
    GPG_PASS_FILE="$GPG_PASSPHRASE_FILE"
else
    PASS_TMP="$(with_gpg_passphrase_file)"
    GPG_PASS_FILE="$PASS_TMP"
fi

tar -C "$(dirname "$SSH_DIR")" -czf - "$(basename "$SSH_DIR")" | \
gpg \
    --batch \
    --yes \
    --pinentry-mode loopback \
    --passphrase-file "$GPG_PASS_FILE" \
    --symmetric \
    --cipher-algo "$GPG_CIPHER" \
    --output "$BACKUP_FILE"

chmod 600 "$BACKUP_FILE"

echo "Encrypted backup created:"
echo "$BACKUP_FILE"

echo "Uploading to Proton Drive..."

proton-drive filesystem upload \
    --conflict-strategy skip \
    "$BACKUP_FILE" \
    "$PROTON_DIR"

echo "Checking Proton Drive..."

if proton-drive filesystem list -j "$PROTON_DIR" \
    | grep -Fq "$BACKUP_NAME"
then
    echo "Upload verified successfully."
else
    echo "ERROR: Could not verify Proton Drive backup." >&2
    exit 1
fi

printf '%s\n' "$CURRENT_FINGERPRINT" > "$FINGERPRINT_FILE"
chmod 600 "$FINGERPRINT_FILE"

find "$WORK_DIR" \
    -type f \
    -name "*.tar.gz.gpg" \
    -mtime "+${LOCAL_RETENTION_DAYS}" \
    -delete

echo "-------------------------------------"
echo "SSH backup completed successfully."
echo "Backup: ${BACKUP_NAME}"
echo "-------------------------------------"
