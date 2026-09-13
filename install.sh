#!/bin/bash
# Installs the fan-profile-set helper (root-owned) + its scoped sudoers
# NOPASSWD rule, and the Omarchy bar plugin (user-owned). Run with sudo:
#
#   sudo ./install.sh
#
set -e

if [ -z "$SUDO_USER" ]; then
  echo "Run this with sudo, e.g.: sudo ./install.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

echo "==> Installing /usr/local/bin/fan-profile-set"
install -o root -g root -m 755 "$SCRIPT_DIR/bin/fan-profile-set" /usr/local/bin/fan-profile-set

echo "==> Writing scoped sudoers rule for $SUDO_USER"
cat > "/etc/sudoers.d/$SUDO_USER-fanprofile" <<EOF
$SUDO_USER ALL=(root) NOPASSWD: /usr/local/bin/fan-profile-set silent, /usr/local/bin/fan-profile-set quiet, /usr/local/bin/fan-profile-set balanced, /usr/local/bin/fan-profile-set performance
EOF
chmod 440 "/etc/sudoers.d/$SUDO_USER-fanprofile"
visudo -c

echo "==> Installing the Omarchy bar plugin for $SUDO_USER"
PLUGIN_DIR="$USER_HOME/.config/omarchy/plugins/community.temps-fan-panel"
mkdir -p "$PLUGIN_DIR"
cp "$SCRIPT_DIR/plugin/"* "$PLUGIN_DIR/"
chmod +x "$PLUGIN_DIR/read_temps.sh"
chown -R "$SUDO_USER:$SUDO_USER" "$USER_HOME/.config/omarchy/plugins"

echo "==> Setting an initial fan profile (quiet)"
/usr/local/bin/fan-profile-set quiet || echo "  (skipped — no it87/it8688 hwmon device found yet; run fan-profile-set manually once your driver is loaded)"

echo "==> Enabling the bar widget"
sudo -u "$SUDO_USER" omarchy plugin enable community.temps-fan-panel --section right || \
  echo "  (couldn't auto-enable — run: omarchy plugin enable community.temps-fan-panel --section right)"

cat <<'EOF'

Done. A couple of things worth checking:

1. This needs the it87 (or a patched fork like it87-dkms-git on the AUR)
   kernel driver loaded and bound to your Super I/O chip. See README.md
   "Hardware setup" if `sensors` doesn't show an it86xx/it87xx device yet.

2. fan-profile-set assumes pwm1 drives your primary/CPU fan and pwm3 drives
   a secondary fan, using temp3 as the driving sensor. That's common on
   Gigabyte AM4 boards using this driver, but NOT universal — check with
   `sensors` and edit the PWM_PRIMARY / PWM_SECONDARY / TEMP_SOURCE
   variables at the top of /usr/local/bin/fan-profile-set for your board.
EOF
