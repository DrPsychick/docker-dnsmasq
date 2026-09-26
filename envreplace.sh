#!/bin/sh
set -e

. default.env

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

if [ -n "$KEEPALIVE_STATE" ]; then
  echo "Enabling keepalived"
  KEEPALIVE_PRIO=${KEEPALIVE_PRIO:-100}
  KEEPALIVE_ID=${KEEPALIVE_ID:-21}
  KEEPALIVE_INTERFACE=${KEEPALIVE_INTERFACE:-eth0}
  sed -i -e "s/KEEPALIVE_STATE/$KEEPALIVE_STATE/" -e "s/KEEPALIVE_PRIO/$KEEPALIVE_PRIO/" \
    -e "s/KEEPALIVE_PASS/$KEEPALIVE_PASS/" -e "s/KEEPALIVE_VIP/$KEEPALIVE_VIP/" \
    -e "s/KEEPALIVE_ID/$KEEPALIVE_ID/" -e "s/KEEPALIVE_INTERFACE/$KEEPALIVE_INTERFACE/" /etc/keepalived/keepalived.conf

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
server.document-root = "$HTTP_ROOT"
server.port = $DMQ_HTTP_PORT
server.bind = "$DMQ_HTTP_BIND"
server.dir-listing = "disable"
mimetype.assign = (".gz" => "application/gzip", ".efi" => "application/octet-stream", "" => "application/octet-stream")
EOF
    then
      if lighttpd -f /etc/lighttpd/lighttpd.conf; then
        echo "Starting optional TFTP-over-HTTP server on $DMQ_HTTP_BIND:$DMQ_HTTP_PORT serving $HTTP_ROOT"
      else
        echo "WARNING: failed to start lighttpd - continuing without HTTP server"
      fi
    else
      echo "WARNING: could not write /etc/lighttpd/lighttpd.conf - continuing without HTTP server"
    fi
  fi
fi

exec dnsmasq "$@"

