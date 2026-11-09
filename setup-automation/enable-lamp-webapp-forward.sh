#!/bin/bash
# Enable buildhost:8080 -> lamp-vm:80 forwarding for the Showroom LAMP Application tab.
# Safe to re-run. Intended to be invoked as: sudo enable-lamp-webapp-forward
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo enable-lamp-webapp-forward)" >&2
  exit 1
fi

if ! command -v socat >/dev/null 2>&1; then
  echo "Installing socat..."
  dnf install -y socat
fi

if ! command -v virsh >/dev/null 2>&1; then
  echo "ERROR: virsh not found" >&2
  exit 1
fi

if ! virsh list --name | grep -qx 'lamp-vm'; then
  echo "ERROR: lamp-vm is not defined/running. Finish the Module 3 VM steps first." >&2
  virsh list --all >&2 || true
  exit 1
fi

VM_IP="$(virsh domifaddr lamp-vm | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -n1)"
if [[ -z "${VM_IP}" ]]; then
  echo "ERROR: could not determine lamp-vm IP from virsh domifaddr" >&2
  virsh domifaddr lamp-vm >&2 || true
  exit 1
fi

echo "VM IP: ${VM_IP}"

systemctl stop lamp-webapp-forward.service 2>/dev/null || true
pkill -x socat 2>/dev/null || true

cat > /etc/systemd/system/lamp-webapp-forward.service <<EOF
[Unit]
Description=Forward buildhost:8080 to LAMP VM
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:8080,fork,reuseaddr,bind=0.0.0.0 TCP:${VM_IP}:80
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now lamp-webapp-forward.service

sleep 1

STATE="$(systemctl is-active lamp-webapp-forward.service || true)"
echo "Service state: ${STATE}"
ss -tlnp | grep -E ':8080\b' || true

if [[ "${STATE}" != "active" ]]; then
  echo "ERROR: lamp-webapp-forward.service is not active" >&2
  systemctl status lamp-webapp-forward.service --no-pager >&2 || true
  journalctl -u lamp-webapp-forward.service -n 20 --no-pager >&2 || true
  exit 1
fi

if ! curl -fsS --max-time 5 "http://127.0.0.1:8080" | grep -q "Hello, World!"; then
  echo "ERROR: :8080 is up but app did not return Hello, World!" >&2
  curl -sS --max-time 5 "http://127.0.0.1:8080" | head -n 20 >&2 || true
  exit 1
fi

echo "OK: LAMP app reachable via http://127.0.0.1:8080"
echo "Refresh the Showroom LAMP Application tab now."
exit 0
