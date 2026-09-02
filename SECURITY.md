# Security policy

## Reporting a vulnerability

Open a [GitHub issue](https://github.com/Thrima97/ssh-proton-backup/issues) for
non-sensitive bugs. For a vulnerability you do not want public immediately,
email the maintainer through GitHub (profile contact) rather than filing a
public issue.

Do **not** attach or paste:

- Private SSH keys or `~/.ssh` contents
- `GPG_PASSPHRASE` or a real `.env` file
- Proton session data, keyring dumps, or decrypted archives

Strip secrets from logs before sharing `journalctl` output.

## What this project does not do

- It never stores your Proton account password. Login is browser-based; the
  session lives in the Linux secret store (libsecret).
- It never overwrites live keys. Restore extracts to a new folder only.
- Lost `GPG_PASSPHRASE` means Proton copies of the archives cannot be decrypted.
