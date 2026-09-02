# How to cut a GitHub Release

GitHub **Releases** are named versions on top of **git tags**. A tag such as
`v0.1.0` is the immutable snapshot. The **Releases** tab is the human page
(notes and download links). GitHub attaches a source zip and tar.gz automatically;
this project has no compiled binary.

## Version numbers

Follow [SemVer](https://semver.org/):

| Change | Example | When |
| --- | --- | --- |
| Patch | `0.1.1` | Bugfix, Proton CLI version or checksum bump |
| Minor | `0.2.0` | New Makefile target, new env var, extra docs-only can stay patch |
| Major | `1.0.0` | Breaking `.env` or install path changes |

## Flow

1. Update [CHANGELOG.md](../CHANGELOG.md) with the new version and date.
2. Commit on `main`.
3. Tag and push.
4. Create the Releases-tab entry with `gh`.

```bash
git tag -a v0.1.0 -m "ssh-proton-backup 0.1.0"
git push origin main
git push origin v0.1.0

gh release create v0.1.0 --title "v0.1.0" --notes-file CHANGELOG.md --latest
```

After that, the tag appears under **Releases** on GitHub.

## Install from a release

```bash
git clone --branch v0.1.0 https://github.com/Thrima97/ssh-proton-backup.git
cd ssh-proton-backup
make install
```

Or download **Source code (tar.gz)** from the Releases tab, unpack it, and run
`make install`.
