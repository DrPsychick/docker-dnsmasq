#!/bin/sh
set -e

. default.env

# KEEPALIVED_ENABLED: explicit enable/disable switch for keepalived.
#  1|yes|true|on (any case)  -> ENABLED
#  0|no|false|off (any case) -> DISABLED (hard override)
#  unset/empty/unrecognized  -> legacy: enabled iff KEEPALIVE_STATE is non-empty
# NOTE: mirrored in /healthcheck.sh - keep in sync
keepalived_enabled() {
  case "${KEEPALIVED_ENABLED:-}" in
    1|yes|true|on|YES|TRUE|ON|Yes|True|On) return 0 ;;
    0|no|false|off|NO|FALSE|OFF|No|False|Off) return 1 ;;
    *) [ -n "$KEEPALIVE_STATE" ] ;;
  esac
}

# generate configuration files from templates
for tmpl in ${conf_templates}; do
  # do not generate config, if file or directory is mounted into the container
  if [ -n "$(mount | grep ${tmpl#*:})" -o -n "$(mount | grep $(basename ${tmpl#*:}))" ]; then
      echo "NOT overwriting mounted configuration file: ${tmpl#*:}"
      continue
  fi
  eval "$(cat ${tmpl%:*})" > ${tmpl#*:}
done

if [ "$1" = "--test" ]; then
  for tmpl in ${conf_templates}; do
    echo "${tmpl#*:}:"
    echo "=================="
    cat ${tmpl#*:}
    echo
  done

  echo "Variables:"
  echo "=========="
  for v in $(set |grep ^${conf_var_prefix}|sed -e 's/^\('${conf_var_prefix}'[^=]*\).*/\1/' |sort |tr '\n' ' ' ); do
    [ -z "$v" ] && continue
    value=$(eval echo -n \""\$$v"\")
    echo -e "$v=\"$value\""
  done

  if [ -n "$DMQ_HTTP" ]; then
    case "$DMQ_TFTP" in
      *enable-tftp*)
        root=${DMQ_HTTP_ROOT:-$(printf '%s\n' "$DMQ_TFTP" | sed -n 's/.*\(tftp-root=\)\([^\\]*\).*/\2/p')}
        echo "HTTP server enabled (DMQ_HTTP=$DMQ_HTTP, root=$root, bind=${DMQ_HTTP_BIND:-0.0.0.0}, port=${DMQ_HTTP_PORT:-8080})"
        ;;
      *)
        echo "DMQ_HTTP set but TFTP not enabled - HTTP server will be skipped"
        ;;
    esac
  fi
  exit 0
fi

# export variables suitable for input for --env-file
if [ "$1" = "--export" ]; then
  # fetch all defined ${conf_var_prefix} variables
  for v in $(set |grep ^${conf_var_prefix}|sed -e 's/^\('${conf_var_prefix}'[^=]*\).*/\1/' |sort |tr '\n' ' '); do
    [ -z "$v" ] && continue
    # get value and replace all newlines with \n (docker only supports single line variables)
    value=$(eval echo -n \""\$$v"\")
    echo "$v=$(echo -n "$value" | awk '{if (NR>1) {printf "%s\\n", $0}} END {print $0}')"
  done
  exit 0
fi

if [ -n "$CONFIG_DEBUG" ]; then
  echo "Compiled Configuration:"
  echo "===================="
  cat -n /etc/dnsmasq.conf
  echo "===================="
fi

if keepalived_enabled; then
  echo "Enabling keepalived"
  KEEPALIVE_PRIO=${KEEPALIVE_PRIO:-100}
  KEEPALIVE_ID=${KEEPALIVE_ID:-21}
  KEEPALIVE_INTERFACE=${KEEPALIVE_INTERFACE:-eth0}
  KEEPALIVE_CONF=${KEEPALIVE_CONF:-/etc/keepalived/keepalived.conf}
  if [ -n "$(mount | grep "$KEEPALIVE_CONF")" -o -n "$(mount | grep "$(basename "$KEEPALIVE_CONF")")" ]; then
    echo "NOT overwriting mounted configuration file: $KEEPALIVE_CONF"
  else
    sed -i -e "s/KEEPALIVE_STATE/$KEEPALIVE_STATE/" -e "s/KEEPALIVE_PRIO/$KEEPALIVE_PRIO/" \
      -e "s/KEEPALIVE_PASS/$KEEPALIVE_PASS/" -e "s/KEEPALIVE_VIP/$KEEPALIVE_VIP/" \
      -e "s/KEEPALIVE_ID/$KEEPALIVE_ID/" -e "s/KEEPALIVE_INTERFACE/$KEEPALIVE_INTERFACE/" "$KEEPALIVE_CONF"
  fi

  if ! keepalived -t -f "$KEEPALIVE_CONF" >&2; then
    echo "ERROR: keepalived configuration check failed - aborting ($KEEPALIVE_CONF)" >&2
    exit 1
  fi

  if [ -z "$(grep bind-dynamic /etc/dnsmasq.conf)" ]; then
    echo "WARNING: 'bind-dynamic' should be enabled when using keeplived, so that dnsmasq binds to the VIP dynamically."
  fi

  rm -f /run/keepalived/*.pid
  keepalived -P -n -l 2>&1 > /dev/stdout &
fi

# optional TFTP-over-HTTP server (lighttpd)
if [ -n "$DMQ_HTTP" ]; then
  case "$DMQ_TFTP" in
    *enable-tftp*) ;;
    *)
      echo "DMQ_HTTP set but TFTP not enabled - skipping HTTP server"
      DMQ_HTTP=""
      ;;
  esac
fi

if [ -n "$DMQ_HTTP" ]; then
  # determine document root: explicit override, or derive from tftp-root= in DMQ_TFTP
  HTTP_ROOT=$DMQ_HTTP_ROOT
  if [ -z "$HTTP_ROOT" ]; then
    HTTP_ROOT=$(printf '%s\n' "$DMQ_TFTP" | sed -n 's/.*\(tftp-root=\)\([^\\]*\).*/\2/p')
  fi

  if [ -z "$HTTP_ROOT" ]; then
    echo "could not determine HTTP root - skipping HTTP server"
  else
    if cat > /etc/lighttpd/lighttpd.conf <<EOF
server.modules = ("mod_access", "mod_accesslog")
server.document-root = "$HTTP_ROOT"
server.port = $DMQ_HTTP_PORT
server.bind = "$DMQ_HTTP_BIND"
accesslog.filename = "/dev/stderr"
server.errorlog = "/dev/stderr"
mimetype.assign = (".gz" => "application/gzip", ".efi" => "application/octet-stream", "" => "application/octet-stream")
EOF
    then
      lighttpd -D -f /etc/lighttpd/lighttpd.conf &
      HTTP_PID=$!
      sleep 1
      if kill -0 "$HTTP_PID" 2>/dev/null; then
        echo "Starting optional TFTP-over-HTTP server on $DMQ_HTTP_BIND:$DMQ_HTTP_PORT serving $HTTP_ROOT (pid $HTTP_PID)"
      else
        wait "$HTTP_PID" 2>/dev/null || true
        echo "WARNING: lighttpd failed to start - continuing without HTTP server"
      fi
    else
      echo "WARNING: could not write /etc/lighttpd/lighttpd.conf - continuing without HTTP server"
    fi
  fi
fi

exec dnsmasq "$@"

