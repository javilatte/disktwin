#!/bin/bash
# disktwin - user part of the installation (no sudo): watch service, cron job,
# terminal alert banner and login notification.
set -euo pipefail
cd "$(dirname "$0")"
[[ $EUID -ne 0 ]] || { echo "Run this as your user, without sudo" >&2; exit 1; }
command -v disktwin-sync >/dev/null || { echo "First run: sudo ./install.sh" >&2; exit 1; }

echo "== User service disktwin-watch =="
mkdir -p ~/.config/systemd/user
install -m 644 systemd/disktwin-watch.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable disktwin-watch.service
systemctl --user restart disktwin-watch.service   # pick up new commands and config

echo "== Cron job: full sync every hour =="
LINE='0 * * * * /usr/local/bin/disktwin-sync --cron'
( crontab -l 2>/dev/null | grep -vF '/usr/local/bin/disktwin-sync' || true; echo "$LINE" ) | crontab -

echo "== Alert banner when a terminal opens (~/.bashrc) =="
if ! grep -q 'disktwin-alerts --summary' ~/.bashrc 2>/dev/null; then
  cat >> ~/.bashrc <<'EOF'

# disktwin: pending disk alerts (SMART / mirror)
if [[ $- == *i* ]] && command -v disktwin-alerts >/dev/null; then disktwin-alerts --summary; fi
EOF
fi

echo "== Notification at login =="
mkdir -p ~/.config/autostart
install -m 644 autostart/disktwin-alerts.desktop ~/.config/autostart/

systemctl --user --no-pager status disktwin-watch.service | head -5
echo "Done."
