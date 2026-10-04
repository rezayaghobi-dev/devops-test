#!/usr/bin/env bash
# Restrict external access to this host and to Docker-published ports.
# Usage: sudo ./firewall.sh up | down | status
set -euo pipefail

[ "$EUID" -eq 0 ] || { echo "Run with sudo"; exit 1; }

EXT_IF="${EXT_IF:-$(ip route show default | awk '/default/ {print $5; exit}')}"
[ -n "$EXT_IF" ] || { echo "No default route found, set EXT_IF=<interface>"; exit 1; }
LAN="${LAN:-$(ip -o -4 addr show dev "$EXT_IF" | awk '{print $4; exit}')}"
APP_PORT=8000
CHAIN=DEVOPS-FW

down() {
  while iptables -D INPUT -j "$CHAIN" 2>/dev/null; do :; done
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
  iptables -F DOCKER-USER 2>/dev/null || true
  iptables -A DOCKER-USER -j RETURN 2>/dev/null || true
}

up() {
  down
  echo "External interface: $EXT_IF | LAN: $LAN"

  # Host traffic (INPUT): only packets arriving on the external interface are filtered
  iptables -N "$CHAIN"
  iptables -A "$CHAIN" ! -i "$EXT_IF" -j RETURN
  iptables -A "$CHAIN" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  iptables -A "$CHAIN" -p icmp -j ACCEPT
  iptables -A "$CHAIN" -p udp --sport 67 --dport 68 -j ACCEPT
  iptables -A "$CHAIN" -p tcp --dport 22 -s "$LAN" -j ACCEPT
  iptables -A "$CHAIN" -j DROP
  iptables -I INPUT 1 -j "$CHAIN"

  # Container ports (DOCKER-USER): after DNAT only the original destination port tells us what was requested
  iptables -F DOCKER-USER
  iptables -A DOCKER-USER -i "$EXT_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
  iptables -A DOCKER-USER -i "$EXT_IF" -s "$LAN" -p tcp -m conntrack --ctorigdstport "$APP_PORT" --ctdir ORIGINAL -j RETURN
  iptables -A DOCKER-USER -i "$EXT_IF" -j DROP
  iptables -A DOCKER-USER -j RETURN
}

status() {
  echo "== INPUT (top) =="; iptables -L INPUT -n -v --line-numbers | head -5
  echo "== $CHAIN =="; iptables -L "$CHAIN" -n -v --line-numbers 2>/dev/null || echo "not active"
  echo "== DOCKER-USER =="; iptables -L DOCKER-USER -n -v --line-numbers
}

case "${1:-}" in
  up) up; status ;;
  down) down; status ;;
  status) status ;;
  *) echo "Usage: sudo $0 up|down|status"; exit 1 ;;
esac
