# SSH Proton Backup

Change-based encrypted backup of `~/.ssh` to Proton Drive, using the official Proton Drive CLI.

A backup is created only when an SSH key, config, or other file under `~/.ssh` actually changes.

```
~/.ssh
   ↓  (only if contents changed)
encrypted .tar.gz.gpg
   ↓
Official Proton Drive CLI
   ↓
Proton Drive / SSH-Key-Backups
   ↓
local archives older than 7 days are deleted
```

## What is already done on this machine

These steps completed during the first install:

- Proton Drive CLI **0.8.0** is installed at `~/.local/bin/proton-drive`
- Proton browser login succeeded (`proton-drive auth login`)
- Remote folder `/my-files/SSH-Key-Backups` exists
- systemd user timer `ssh-proton-backup.timer` is enabled (daily 20:00)
- Config directory `~/.config/ssh-backup/` exists

**Still required before the first real backup:** set `GPG_PASSPHRASE` in `.env`, then run a `--force` test.

## Configuration (`.env`)

All paths and the encryption password live in a `.env` file. The scripts never store your Proton password. Proton login stays in the Linux secret store (libsecret).

Live file (mode `600`):

```
~/.config/ssh-backup/.env
```

Search order:

1. `SSH_BACKUP_ENV` if you set that variable
2. `~/.config/ssh-backup/.env`
3. `.env` next to the script (useful when running from this repo)

`.env.example` is the committed template. A real `.env` is gitignored.

### Create or edit `.env`

If `~/.config/ssh-backup/.env` is missing:

```bash
mkdir -p ~/.config/ssh-backup
chmod 700 ~/.config/ssh-backup
cp .env.example ~/.config/ssh-backup/.env
chmod 600 ~/.config/ssh-backup/.env
```

Then set the encryption password:

```bash
nano ~/.config/ssh-backup/.env
```

Set:

```bash
GPG_PASSPHRASE='your-strong-password-here'
```

Quote the value if it contains spaces or special characters. Write that password in a password manager or on paper as well. If this computer dies and you forget it, the Proton copies cannot be decrypted.

### Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSH_DIR` | `$HOME/.ssh` | Directory to archive |
| `WORK_DIR` | `$HOME/.local/state/ssh-backups` | Local encrypted archives and last fingerprint |
| `PROTON_PARENT` | `/my-files` | Proton Drive parent path |
| `PROTON_FOLDER` | `SSH-Key-Backups` | Folder name under that parent |
| `PROTON_DIR` | `/my-files/SSH-Key-Backups` | Full upload destination |
| `LOCAL_RETENTION_DAYS` | `7` | Delete local archives older than this. Proton copies stay. |
| `GPG_CIPHER` | `AES256` | Symmetric cipher |
| `GPG_PASSPHRASE` | *(required)* | Password used to encrypt/decrypt archives |
| `GPG_PASSPHRASE_FILE` | unset | Optional 600 file instead of `GPG_PASSPHRASE` |
| `FINGERPRINT_FILE` | `$WORK_DIR/last-fingerprint` | Last successful content hash |

Override the file for one run:

```bash
SSH_BACKUP_ENV=/path/to/.env ~/.local/bin/ssh-proton-backup.sh --force
```

## Install

From this repository:

```bash
chmod +x install.sh ssh-proton-backup.sh ssh-proton-restore.sh
./install.sh
```

The installer:

1. Checks for `gpg`, `libsecret`, and D-Bus tools
2. Downloads Proton Drive CLI 0.8.0, verifies the published SHA-512, and installs it to `/usr/local/bin` or `~/.local/bin`
3. Creates `~/.config/ssh-backup/.env` from `.env.example` if needed
4. Prompts for `GPG_PASSPHRASE` when stdin is a terminal
5. Copies the backup/restore scripts to `~/.local/bin`
6. Copies `lib/env.sh` to `~/.local/lib/ssh-proton-backup/env.sh`
7. Enables the systemd user timer at 20:00
8. Creates `/my-files/SSH-Key-Backups` if you are already logged in

Non-interactive install (skip the password prompt):

```bash
SKIP_PASSPHRASE=1 ./install.sh
```

Then edit `~/.config/ssh-backup/.env` yourself.

## Proton login (once)

Sign-in is through the browser. The session is stored in libsecret, not in `.env`.

```bash
proton-drive auth login
proton-drive filesystem create-folder /my-files SSH-Key-Backups
proton-drive filesystem list /my-files
```

`create-folder` can be skipped if the folder already exists.

## First test

After `GPG_PASSPHRASE` is set:

```bash
~/.local/bin/ssh-proton-backup.sh --force
```

Expected result:

- Encrypted file under `~/.local/state/ssh-backups/`
- Same filename in Proton Drive `/my-files/SSH-Key-Backups`
- Later runs without `--force` print `No SSH changes; skipping upload` until `~/.ssh` changes

## Schedule

A systemd user timer checks daily at 20:00. It only uploads when `~/.ssh` changed.

```bash
systemctl --user status ssh-proton-backup.timer
journalctl --user -u ssh-proton-backup.service
```

The timer needs your user session and an unlocked keyring. `Persistent=true` means a missed run fires after you log in again.

Classic cron often cannot read libsecret. Prefer the systemd timer.

## Restore

Download an archive from Proton Drive, then extract it to a **new** folder. The restore script refuses to write into `~/.ssh`.

```bash
proton-drive filesystem download \
    /my-files/SSH-Key-Backups/HOSTNAME_ssh_DATE.tar.gz.gpg \
    ~/Downloads

~/.local/bin/ssh-proton-restore.sh \
    ~/Downloads/HOSTNAME_ssh_DATE.tar.gz.gpg \
    ~/ssh-restore
```

Review the extracted files, then copy selected keys into `~/.ssh` if needed.

## Paths

| Path | Purpose |
| --- | --- |
| `~/.ssh` | Source directory |
| `.env.example` | Committed template |
| `~/.config/ssh-backup/.env` | Live config and `GPG_PASSPHRASE` (mode 600) |
| `~/.local/state/ssh-backups/` | Temporary local archives and last fingerprint |
| `/my-files/SSH-Key-Backups` | Proton Drive destination |
| `~/.local/bin/ssh-proton-backup.sh` | Installed backup script |
| `~/.local/lib/ssh-proton-backup/env.sh` | Shared `.env` loader |

## Safety

- Do not commit `.env`, `~/.ssh`, archives, or Proton session data
- Proton Drive already encrypts files. GPG is a second layer so a downloaded archive is still useless without your passphrase
- If the passphrase is lost, those archives cannot be decrypted
- Restore always extracts to a new folder so live keys are not overwritten
- Proton fair-use guidance matches the change-based approach: do not re-upload identical archives every day
