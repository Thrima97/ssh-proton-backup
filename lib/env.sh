#!/usr/bin/env bash
# Shared .env loader for SSH Proton Backup scripts.

resolve_env_file() {
    local extra_dir="${1:-}"

    if [ -n "${SSH_BACKUP_ENV:-}" ] && [ -f "$SSH_BACKUP_ENV" ]; then
        printf '%s\n' "$SSH_BACKUP_ENV"
        return 0
    fi

    if [ -f "${HOME}/.config/ssh-backup/.env" ]; then
        printf '%s\n' "${HOME}/.config/ssh-backup/.env"
        return 0
    fi

    if [ -n "$extra_dir" ] && [ -f "${extra_dir}/.env" ]; then
        printf '%s\n' "${extra_dir}/.env"
        return 0
    fi

    return 1
}

load_backup_env() {
    local env_file
    if ! env_file="$(resolve_env_file "${1:-}")"; then
        echo "ERROR: No .env file found." >&2
        echo "Copy .env.example to ~/.config/ssh-backup/.env, set GPG_PASSPHRASE, and chmod 600." >&2
        echo "Or set SSH_BACKUP_ENV to the path of your .env file." >&2
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a

    SSH_DIR="${SSH_DIR:-${HOME}/.ssh}"
    WORK_DIR="${WORK_DIR:-${HOME}/.local/state/ssh-backups}"
    PROTON_PARENT="${PROTON_PARENT:-/my-files}"
    PROTON_FOLDER="${PROTON_FOLDER:-SSH-Key-Backups}"
    PROTON_DIR="${PROTON_DIR:-${PROTON_PARENT}/${PROTON_FOLDER}}"
    LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-7}"
    GPG_CIPHER="${GPG_CIPHER:-AES256}"
    FINGERPRINT_FILE="${FINGERPRINT_FILE:-${WORK_DIR}/last-fingerprint}"
    ENV_FILE="$env_file"
}

require_gpg_passphrase() {
    if [ -n "${GPG_PASSPHRASE_FILE:-}" ] && [ -f "$GPG_PASSPHRASE_FILE" ]; then
        return 0
    fi

    if [ -z "${GPG_PASSPHRASE:-}" ]; then
        echo "ERROR: GPG_PASSPHRASE is empty in ${ENV_FILE}." >&2
        echo "Set it in that file, or point GPG_PASSPHRASE_FILE at a 600 password file." >&2
        exit 1
    fi
}

with_gpg_passphrase_file() {
    if [ -n "${GPG_PASSPHRASE_FILE:-}" ] && [ -f "$GPG_PASSPHRASE_FILE" ]; then
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    chmod 600 "$tmp"
    printf '%s' "$GPG_PASSPHRASE" > "$tmp"
    printf '%s\n' "$tmp"
}
