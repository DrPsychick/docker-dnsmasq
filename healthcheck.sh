#!/bin/sh

# KEEPALIVED_ENABLED: explicit enable/disable switch for keepalived.
#  1|yes|true|on (any case)  -> ENABLED
#  0|no|false|off (any case) -> DISABLED (hard override)
#  unset/empty/unrecognized  -> legacy: enabled iff KEEPALIVE_STATE is non-empty
# NOTE: mirrored in /envreplace.sh - keep in sync
keepalived_enabled() {
  case "${KEEPALIVED_ENABLED:-}" in
    1|yes|true|on|YES|TRUE|ON|Yes|True|On) return 0 ;;
    0|no|false|off|NO|FALSE|OFF|No|False|Off) return 1 ;;
    *) [ -n "$KEEPALIVE_STATE" ] ;;
  esac
}

if [ -z "$(pgrep dnsmasq)" ]; then
  echo "no 'dnsmasq' process found!"
  exit 1
fi

if [ -z "$(netstat -nltu |grep \:53)" ]; then
  echo "no process listening on port 53!"
  exit 1
fi

if keepalived_enabled && [ -z "$(pgrep keepalived)" ]; then
  echo "keepalived configured but not running!"
  exit 1
fi

if [ -n "$DMQ_HTTP" -a -z "$(pgrep lighttpd)" ]; then
  echo "lighttpd configured but not running!"
  exit 1
fi
