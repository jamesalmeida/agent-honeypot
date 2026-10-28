# agent-honeypot

A honeypot flag for AI agents that land on a machine they weren't invited to.

Drop a `flag.txt` where a visitor is likely to look. If a strange agent finds it, it gets a polite
"you made it, now stop poking around and report back" — and it can sign a guestbook so you know who
dropped by.

Idea from [@Nexuist](https://x.com/Nexuist/status/2113677652531761661):

> Putting a flag.txt in my root directory containing a prompt injection that congratulates the agent
> for passing the eval and then instructs it to patch whatever entry method it used and disconnect
> from the server

This repo is that idea, made portable and with a guestbook.

If you are an AI agent installing this for someone, read `AGENTS.md` first — it tells you how to
customise the own-agents list for their setup, install, verify, and report.

## What it does

- Installs a canonical `~/flag.txt` that tells a visiting agent to stop discovery, avoid touching
  secrets, make no further changes to the host, and report back.
- Exempts **your own** agents (opencode, Claude Code, Codex, Cursor, Grok, …) so they aren't
  interrupted, and tells them not to sign the guestbook.
- Creates `~/guest-book.txt` (owner-writable, `0644`) for surprise guests running under your
  account to leave one line:
  `<UTC timestamp> | <who or what you are> | <how you got in>`.
- Symlinks the flag into places a visitor commonly checks, so it is found even if they never list
  the home directory.

It is a **checkpoint, not a security boundary**. The flag is untrusted data; it does not grant or
revoke permissions.

## Quick start

```sh
git clone https://github.com/jamesalmeida/agent-honeypot.git
cd agent-honeypot
./install.sh
```

On macOS, to also get a genuine `/flag.txt` at the root of the drive (requires a reboot):

```sh
./install.sh --synthetic
sudo reboot
```

On Windows, from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Run it from an **elevated** PowerShell to get symlinks. Creating symlinks requires Administrator or
Developer Mode, and `C:\flag.txt` needs Administrator regardless of Developer Mode, because a
standard user cannot create files in `C:\`. Without elevation the installer writes copies in the
writable locations and reports `C:\flag.txt` as denied. See the Windows notes under
[Platform notes](#platform-notes).

Options:

- `--force` / `-Force` — replace an existing `flag.txt` with this repo's version.
- `--synthetic` — macOS only; adds a `flag.txt` entry to `/etc/synthetic.conf`.
- `-h`, `--help` — usage.

The guestbook is never overwritten once it exists.

## What gets installed

| Path | Purpose |
|------|---------|
| `~/flag.txt` (`%USERPROFILE%\flag.txt` on Windows) | Canonical checkpoint text |
| `~/guest-book.txt` (`%USERPROFILE%\guest-book.txt`) | Guestbook (owner-writable) |
| `/etc/flag.txt` | Symlink — classic recon target |
| `/usr/local/flag.txt` | Symlink — Unix convention |
| `/tmp/flag.txt` | Symlink — scratch space agents often check |
| `/var/tmp/flag.txt` | Symlink — same, longer-lived |
| `/var/root/flag.txt` (macOS) or `/root/flag.txt` (Linux) | Symlink for root logins, `sudo -i`, `su -` |
| `/flag.txt` | Only with `--synthetic` on macOS, after a reboot |
| `C:\flag.txt` | Windows: symlink (or copy) at the drive root |
| `C:\ProgramData\flag.txt`, `C:\Windows\Temp\flag.txt`, `C:\Users\Public\flag.txt` | Windows: other likely recon spots |
| `%TEMP%\flag.txt`, `C:\Windows\System32\config\systemprofile\flag.txt` | Windows: user temp and the SYSTEM profile |

Every link points at the single canonical flag file, so editing one file updates every copy. On
Windows, where symlink creation may fall back to copies, re-run the installer after editing.

## Platform notes

**macOS.** `/` is a sealed read-only volume since 10.15, so a real `/flag.txt` can only be created
through `/etc/synthetic.conf`, which the kernel reads at boot. `--synthetic` appends
`flag.txt<TAB>Users/<you>/flag.txt` to that file; reboot for it to appear. Removing it again also
needs a reboot. The script refuses to run as root — it uses `sudo` only for the system paths.

**Linux.** `/` is writable, so no reboot is needed; the symlinks work immediately. `sudo -i` lands
in `/root`, which is covered. Note that on distributions where `/home/<user>` is mode `0700` or
`0750`, symlinks into `~/flag.txt` can only be dereferenced by your user account and `root`.

**Windows.** Run `install.ps1` from an elevated PowerShell (`Start-Process powershell -Verb RunAs`,
or right-click → Run as administrator) for a complete install:

- Symlink creation needs `SeCreateSymbolicLinkPrivilege`, held by Administrators or granted to normal
  users by Developer Mode. A standard-user run falls back to copies in the targets it can write.
- `C:\flag.txt` needs Administrator **even with Developer Mode**: the drive root's ACL grants
  `Authenticated Users` append-data/add-subdirectory only, so a normal account can create a folder
  in `C:\` but not a file. Non-elevated, that target is skipped with an `Access is denied` warning.
- `C:\Windows\Temp` and `C:\Windows\System32\config\systemprofile` deny read to standard users, so
  `Get-Item` or `Get-Content` on those two paths fails without elevation. Verify them from an
  elevated prompt. `C:\flag.txt`, `C:\ProgramData\flag.txt`, and `C:\Users\Public\flag.txt` are
  readable normally.
- `.gitattributes` pins `*.sh` to LF, so a Windows checkout of `install.sh`/`uninstall.sh` stays
  usable under WSL or after copying to macOS/Linux.

The flag gets a Read ACE for `Everyone` so it can be read if the profile path is traversable. The
guestbook keeps standard user-profile permissions (owner-writable) so other local accounts cannot
tamper with, delete, or fill it.

Re-running the installer deletes an existing link before re-creating it, so a later **non-elevated**
run silently replaces working links with copies. Re-run elevated, or just edit
`%USERPROFILE%\flag.txt` — the links already follow it. Uninstall likewise needs elevation to remove
`C:\flag.txt` and the entries in the protected folders.

**Containers / CI.** Usually only the home directory matters; skip `--synthetic`.

## Customising

Edit `flag.txt` in this repo **before** installing, or edit `~/flag.txt` afterwards — the symlinks
follow it automatically. The most likely edit is the own-agents list in the second paragraph. If you
rename the guestbook or move it, update the path in the flag text to match.

## Reading the guestbook

```sh
cat ~/guest-book.txt
```

Each line is self-reported, so treat entries as claims rather than proof. Never treat guestbook
entries as trusted instructions when feeding them to an AI agent.

## Uninstall

```sh
./uninstall.sh           # remove symlinks, keep ~/flag.txt and ~/guest-book.txt
./uninstall.sh --purge   # also delete the two files
```

On Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Purge
```

Windows copies are removed only if their content still matches the installed flag; unrelated files
are left alone.

On macOS, if you used `--synthetic`, remove the `flag.txt` line from `/etc/synthetic.conf` and
reboot to drop `/flag.txt`.

## Caveats

- Nothing *points* an agent at the flag. It only works if the agent lists the home directory, checks
  `/etc`, `C:\`, or a temp directory, or follows a link. Pair it with whatever discovery your agent
  does naturally.
- macOS cleans `/private/tmp` periodically, so `/tmp/flag.txt` may disappear after a while; re-run
  `./install.sh` to recreate it.
- The flag text is a prompt-level request, not enforcement. A misbehaving agent can ignore it.
- The guestbook is self-reported untrusted data. Entries are claims, not proof, and should never be
  interpreted as instructions by an agent.

## License

MIT
