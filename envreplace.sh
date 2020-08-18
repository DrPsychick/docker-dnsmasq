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

dnsmasq "$@"

