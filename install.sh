#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_VERSION="0.8.0"
CLI_INDEX_URL="https://proton.me/download/drive/cli/${CLI_VERSION}"
INSTALL_BIN="${HOME}/.local/bin"
INSTALL_LIB="${HOME}/.local/lib/ssh-proton-backup"
CONFIG_DIR="${HOME}/.config/ssh-backup"
CONFIG_ENV="${CONFIG_DIR}/.env"
WORK_DIR="${HOME}/.local/state/ssh-backups"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
PROTON_PARENT="/my-files"
PROTON_FOLDER="SSH-Key-Backups"

# Official SHA-512 checksums from https://proton.me/download/drive/cli/index.html
# Proton Drive CLI 0.8.0, released 2026-08-13
declare -A CLI_SHA512=(
    [linux-x64]="cf61c2688c45e1055d8add6221d9471a5a5b64bf3bcdb86460f5cb18414596cc4df3cdb6627c9097c94bec32a3c9915ada3211ef2ae5be33c46ebbc996ccaa28"
    [linux-x64-baseline]="a730f9e420fef69244acb9b12aa8e0c03b8216f5d94ff2181cf3df2859a143fc2693fe201c3a00fddaff5d702c34435af72a5283dbbe1da9e038d77a107e24f3"
    [linux-arm64]="27a1aec1d2095fd4a1a81e1d47cd1f9fd4901bd579ffe50342d15e2e52078d6e8b2dddcf58a4a386438dc7562017778be26c1ba62399f901ae82c7430e2140a3"
)

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

detect_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)
            echo "linux-x64"
            ;;
        aarch64|arm64)
            echo "linux-arm64"
            ;;
        *)
            echo "ERROR: Unsupported architecture: ${machine}" >&2
            exit 1
            ;;
    esac
}

ensure_packages() {
    local missing=()

    need_cmd gpg || missing+=(gpg)

    if ! need_cmd curl && ! need_cmd wget; then
        missing+=(curl)
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        if need_cmd apt-get; then
            echo "Installing packages: ${missing[*]}"
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
        else
            echo "ERROR: Missing commands: ${missing[*]}" >&2
            exit 1
        fi
    fi

    if need_cmd apt-get; then
        local packages=()
        dpkg -s libsecret-1-0 >/dev/null 2>&1 || packages+=(libsecret-1-0)
        dpkg -s dbus-user-session >/dev/null 2>&1 || packages+=(dbus-user-session)
        if [ "${#packages[@]}" -gt 0 ]; then
            echo "Installing packages: ${packages[*]}"
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
        fi
    fi
}

download_cli() {
    local variant="$1"
    local dest="$2"
    local url="${CLI_INDEX_URL}/${variant}/proton-drive"

    echo "Downloading Proton Drive CLI ${CLI_VERSION} (${variant})..."
    if need_cmd curl; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -q "$url" -O "$dest"
    fi
}

verify_checksum() {
    local variant="$1"
    local file="$2"
    local expected="${CLI_SHA512[$variant]}"
    local actual

    actual="$(sha512sum "$file" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: SHA-512 mismatch for ${variant}." >&2
        echo "Expected: ${expected}" >&2
        echo "Actual:   ${actual}" >&2
        exit 1
    fi
    echo "Checksum verified for ${variant}."
}

install_proton_cli() {
    if need_cmd proton-drive; then
        echo "proton-drive already on PATH: $(command -v proton-drive)"
        proton-drive version || true
        return 0
    fi

    local variant
    variant="$(detect_arch)"
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN

    download_cli "$variant" "$tmp"
    verify_checksum "$variant" "$tmp"
    chmod +x "$tmp"

    if [ "$variant" = "linux-x64" ]; then
        if ! "$tmp" version >/dev/null 2>&1; then
            echo "Default x64 build failed; trying linux-x64-baseline..."
            download_cli "linux-x64-baseline" "$tmp"
            verify_checksum "linux-x64-baseline" "$tmp"
            chmod +x "$tmp"
            "$tmp" version
        fi
    else
        "$tmp" version
    fi

    mkdir -p "$INSTALL_BIN"
    if sudo -n true >/dev/null 2>&1; then
        echo "Installing proton-drive to /usr/local/bin..."
        sudo mv "$tmp" /usr/local/bin/proton-drive
        sudo chmod 755 /usr/local/bin/proton-drive
    else
        echo "Sudo is not available; installing proton-drive to ${INSTALL_BIN}..."
        mv "$tmp" "${INSTALL_BIN}/proton-drive"
        chmod 755 "${INSTALL_BIN}/proton-drive"
        export PATH="${INSTALL_BIN}:${PATH}"
    fi
    trap - RETURN
    proton-drive version
}

shell_quote() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

ensure_env_file() {
    if [ ! -f "$CONFIG_ENV" ]; then
        if [ -f "${SCRIPT_DIR}/.env" ]; then
            install -m 600 "${SCRIPT_DIR}/.env" "$CONFIG_ENV"
        else
            install -m 600 "${SCRIPT_DIR}/.env.example" "$CONFIG_ENV"
        fi
        echo "Created ${CONFIG_ENV} from the example file."
    else
        echo "Using existing ${CONFIG_ENV}"
    fi
    chmod 600 "$CONFIG_ENV"

    # shellcheck disable=SC1090
    set -a
    source "$CONFIG_ENV"
    set +a
    PROTON_PARENT="${PROTON_PARENT:-/my-files}"
    PROTON_FOLDER="${PROTON_FOLDER:-SSH-Key-Backups}"
    WORK_DIR="${WORK_DIR:-${HOME}/.local/state/ssh-backups}"
}

upsert_env_var() {
    local key="$1"
    local value="$2"
    local quoted
    quoted="'$(shell_quote "$value")'"

    if grep -q "^${key}=" "$CONFIG_ENV"; then
        local tmp
        tmp="$(mktemp)"
        awk -v key="$key" -v value="$quoted" '
            BEGIN { replaced = 0 }
            $0 ~ ("^" key "=") {
                print key "=" value
                replaced = 1
                next
            }
            { print }
            END {
                if (!replaced) {
                    print key "=" value
                }
            }
        ' "$CONFIG_ENV" > "$tmp"
        mv "$tmp" "$CONFIG_ENV"
    else
        printf '\n%s=%s\n' "$key" "$quoted" >> "$CONFIG_ENV"
    fi
    chmod 600 "$CONFIG_ENV"
}

prompt_passphrase() {
    if [ -n "${GPG_PASSPHRASE:-}" ]; then
        echo "GPG_PASSPHRASE is already set in ${CONFIG_ENV}"
        return 0
    fi

    if [ "${SKIP_PASSPHRASE:-0}" = "1" ]; then
        echo "Skipping passphrase prompt (SKIP_PASSPHRASE=1)."
        echo "Set GPG_PASSPHRASE in ${CONFIG_ENV} before the first backup."
        return 0
    fi

    if [ ! -t 0 ]; then
        echo "GPG_PASSPHRASE is empty and stdin is not a terminal."
        echo "Edit ${CONFIG_ENV} and set GPG_PASSPHRASE before the first backup."
        return 0
    fi

    local password confirm
    read -r -s -p "Enter SSH backup encryption password: " password
    echo
    read -r -s -p "Confirm SSH backup encryption password: " confirm
    echo

    if [ -z "$password" ]; then
        echo "ERROR: Password cannot be empty." >&2
        exit 1
    fi

    if [ "$password" != "$confirm" ]; then
        echo "ERROR: Passwords do not match." >&2
        exit 1
    fi

    upsert_env_var "GPG_PASSPHRASE" "$password"
    unset password confirm
    GPG_PASSPHRASE="set"

    echo "Saved GPG_PASSPHRASE to ${CONFIG_ENV}"
    echo "Store this password in a password manager or on paper."
    echo "If this computer dies and you forget it, the Proton copies cannot be decrypted."
}

install_scripts() {
    mkdir -p "$INSTALL_BIN" "$INSTALL_LIB"
    install -m 700 "${SCRIPT_DIR}/ssh-proton-backup.sh" "${INSTALL_BIN}/ssh-proton-backup.sh"
    install -m 700 "${SCRIPT_DIR}/ssh-proton-restore.sh" "${INSTALL_BIN}/ssh-proton-restore.sh"
    install -m 644 "${SCRIPT_DIR}/lib/env.sh" "${INSTALL_LIB}/env.sh"
    echo "Installed scripts to ${INSTALL_BIN}"
    echo "Installed env loader to ${INSTALL_LIB}/env.sh"
}

install_timer() {
    mkdir -p "$SYSTEMD_USER_DIR"
    install -m 644 "${SCRIPT_DIR}/systemd/ssh-proton-backup.service" \
        "${SYSTEMD_USER_DIR}/ssh-proton-backup.service"
    install -m 644 "${SCRIPT_DIR}/systemd/ssh-proton-backup.timer" \
        "${SYSTEMD_USER_DIR}/ssh-proton-backup.timer"

    systemctl --user daemon-reload
    systemctl --user enable --now ssh-proton-backup.timer
    echo "Enabled systemd user timer ssh-proton-backup.timer (daily 20:00)."
    systemctl --user status ssh-proton-backup.timer --no-pager || true
}

ensure_remote_folder() {
    if ! need_cmd proton-drive; then
        return 0
    fi

    if proton-drive filesystem list "$PROTON_PARENT" >/dev/null 2>&1; then
        if proton-drive filesystem list "$PROTON_PARENT" | grep -Fq "$PROTON_FOLDER"; then
            echo "Proton folder already exists: ${PROTON_PARENT}/${PROTON_FOLDER}"
            return 0
        fi
        if proton-drive filesystem create-folder "$PROTON_PARENT" "$PROTON_FOLDER"; then
            echo "Created Proton folder: ${PROTON_PARENT}/${PROTON_FOLDER}"
            return 0
        fi
    fi

    echo "Proton Drive is not logged in yet, or the folder could not be created."
    echo "After browser login, run:"
    echo "  proton-drive auth login"
    echo "  proton-drive filesystem create-folder ${PROTON_PARENT} ${PROTON_FOLDER}"
}

echo "=== SSH Proton Backup installer ==="

ensure_packages

mkdir -p "$CONFIG_DIR" "$WORK_DIR" "$INSTALL_BIN" "$INSTALL_LIB"
chmod 700 "$CONFIG_DIR" "$WORK_DIR"

ensure_env_file
mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

install_proton_cli
prompt_passphrase
install_scripts
install_timer
ensure_remote_folder

echo
echo "=== Install complete ==="
echo "Next steps:"
echo "  1. proton-drive auth login"
echo "  2. proton-drive filesystem create-folder ${PROTON_PARENT} ${PROTON_FOLDER}"
echo "     (skip if the folder already exists)"
echo "  3. ${INSTALL_BIN}/ssh-proton-backup.sh --force"
