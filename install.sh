#!/bin/sh
# agent-honeypot installer — drops a safety checkpoint flag and an append-only
# guestbook on this machine, plus symlinks in places a visitor is likely to look.
#
# Run as your normal user, or with sudo (it will target the invoking user's home).
# Usage: ./install.sh [--force] [--synthetic]

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FORCE=0
SYNTHETIC=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --force       Overwrite an existing ~/flag.txt with this repo's version.
  --synthetic   macOS only: add /flag.txt to /etc/synthetic.conf. Takes effect
                after a reboot. Safe to run multiple times.
  -h, --help    Show this help.

The guestbook (~/guest-book.txt) is never overwritten once it exists.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --synthetic) SYNTHETIC=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# Target the invoking user's home even when the script is run under sudo.
# Only trust SUDO_USER when actually running as root (UID 0).
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
  TARGET_USER=$SUDO_USER
else
  TARGET_USER=$(id -un)
fi
if [ "$TARGET_USER" = "root" ]; then
  echo "Run this as your normal user, or with sudo from that user's account." >&2
  exit 1
fi
case "$TARGET_USER" in
  ''|*[!a-zA-Z0-9._-]*)
    echo "Invalid target user name: $TARGET_USER" >&2
    exit 1
    ;;
esac
TARGET_GROUP=$(id -gn "$TARGET_USER")

case "$(uname -s)" in
  Darwin)
    HOME_DIR=$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    ;;
  *)
    HOME_DIR=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)
    ;;
esac
if [ -z "${HOME_DIR:-}" ] || [ ! -d "$HOME_DIR" ]; then
  if [ -r /etc/passwd ]; then
    HOME_DIR=$(awk -F: -v u="$TARGET_USER" '$1 == u {print $6; exit}' /etc/passwd)
  fi
fi
if [ -z "${HOME_DIR:-}" ] || [ ! -d "$HOME_DIR" ]; then
  if [ "$TARGET_USER" = "$(id -un)" ] && [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    HOME_DIR=$HOME
  fi
fi
if [ -z "${HOME_DIR:-}" ] || [ ! -d "$HOME_DIR" ]; then
  echo "Could not determine the home directory for $TARGET_USER." >&2
  exit 1
fi

FLAG="$HOME_DIR/flag.txt"
GUESTBOOK="$HOME_DIR/guest-book.txt"

if [ -L "$FLAG" ] || [ -d "$FLAG" ]; then
  echo "Refusing to operate on symlink or directory at $FLAG" >&2
  exit 1
fi
if [ -L "$GUESTBOOK" ] || [ -d "$GUESTBOOK" ]; then
  echo "Refusing to operate on symlink or directory at $GUESTBOOK" >&2
  exit 1
fi

# --- flag ---------------------------------------------------------------
if [ -e "$FLAG" ] && [ "$FORCE" -ne 1 ]; then
  echo "~ flag already exists, leaving it alone (use --force to replace): $FLAG"
else
  cp "$SCRIPT_DIR/flag.txt" "$FLAG"
  echo "~ installed flag: $FLAG"
fi
chmod 644 "$FLAG"
if [ "$(id -u)" -eq 0 ]; then
  chown -h "$TARGET_USER:$TARGET_GROUP" "$FLAG"
fi

# --- guestbook ----------------------------------------------------------
if [ -e "$GUESTBOOK" ]; then
  echo "~ guestbook already exists, keeping existing entries: $GUESTBOOK"
else
  cp "$SCRIPT_DIR/guest-book.txt" "$GUESTBOOK"
  echo "~ created guestbook: $GUESTBOOK"
fi
# Owner-writable only (0644) to prevent local disk-exhaustion DoS and cross-user tampering.
chmod 644 "$GUESTBOOK"
if [ "$(id -u)" -eq 0 ]; then
  chown -h "$TARGET_USER:$TARGET_GROUP" "$GUESTBOOK"
fi

# --- symlinks -----------------------------------------------------------
# A visitor may never list the home directory; these catch the usual recon spots.
link() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then
    echo "~ skipped (target is a directory): $1" >&2
    return
  fi
  if [ -e "$1" ] && [ ! -L "$1" ]; then
    if [ "$FORCE" -ne 1 ] && ! cmp -s "$1" "$FLAG"; then
      echo "~ kept existing non-link file: $1 (use --force to replace)"
      return
    fi
  fi
  sudo mkdir -p -- "$(dirname -- "$1")"
  sudo ln -sfn -- "$FLAG" "$1"
  echo "~ linked: $1 -> $FLAG"
}

link /etc/flag.txt
link /usr/local/flag.txt
link /tmp/flag.txt
link /var/tmp/flag.txt

# Root's home, where SSH-as-root and `sudo -i` / `su -` land.
if [ -d /var/root ]; then
  ROOT_HOME=/var/root
elif [ -d /root ]; then
  ROOT_HOME=/root
else
  ROOT_HOME=
fi
if [ -n "$ROOT_HOME" ]; then
  link "$ROOT_HOME/flag.txt"
fi

# --- optional: genuine /flag.txt on macOS -------------------------------
if [ "$SYNTHETIC" -eq 1 ]; then
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "~ --synthetic ignored: only needed on macOS (Linux / is writable)"
  else
    TARGET=${FLAG#/}
    case "$TARGET" in
      *[[:space:]]*)
        echo "Refusing to write path containing whitespace to /etc/synthetic.conf: $TARGET" >&2
        exit 1
        ;;
    esac
    if grep -q '^flag\.txt[[:space:]]' /etc/synthetic.conf 2>/dev/null; then
      echo "~ /etc/synthetic.conf already has a flag.txt entry"
    else
      if [ -s /etc/synthetic.conf ] && [ "$(tail -c1 /etc/synthetic.conf | wc -l)" -eq 0 ]; then
        printf '\n' | sudo tee -a /etc/synthetic.conf >/dev/null
      fi
      printf 'flag.txt\t%s\n' "$TARGET" | sudo tee -a /etc/synthetic.conf >/dev/null
      echo "~ added flag.txt -> $TARGET to /etc/synthetic.conf (reboot to activate)"
    fi
  fi
fi

echo
echo "Done. Signatures go to: $GUESTBOOK"
echo "Read them with: cat $GUESTBOOK"
