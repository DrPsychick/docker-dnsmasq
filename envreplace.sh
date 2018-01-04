#!/bin/sh
set -e

# sane defaults for docker environment

DMQ_GLOBAL=${DMQ_GLOBAL:-""}
DMQ_DNS=${DMQ_DNS:-""}
DMQ_DNS_RESOLV=${DMQ_DNS_RESOLV:-"no-resolv"}
DMQ_DNS_HOST1=${DMQ_DNS_HOSTS:-"host-record=gateway,gateway.local,172.17.10.1"}
DMQ_DNS_SERVER=${DMQ_DNS_SERVER:-"server=8.8.8.8\nserver=8.8.4.4"}
DMQ_DNS_ADDRESS=${DMQ_DNS_ADDRESS:-""}
DMQ_DNS_LOCAL=${DMQ_DNS_LOCAL:-"local=/local/"}
DMQ_DNS_DOMAIN=${DMQ_DNS_DOMAIN:-"domain=local"}
DMQ_DNS_FLAGS=${DMQ_DNS_FLAGS:-"expand-hosts\ndomain-needed\nselfmx\ndns-loop-detect"}
DMQ_DNS_SRV=${DMQ_DNS_SRV:-""}
DMQ_DNS_TXT=${DMQ_DNS_TXT:-""}
DMQ_DNS_ALIAS=${DMQ_ALIAS:-""}
DMQ_DNS_CNAME=${DMQ_DNS_CNAME:-""}

DMQ_DHCP=${DMQ_DHCP:-""}
DMQ_DHCP_OPTIONS=${DMQ_DHCP_OPTIONS:-""}
DMQ_DHCP_GATEWAY=${DMQ_DHCP_GATEWAY:-"dhcp-option=3,172.17.10.1"}
DMQ_DHCP_DNS=${DMQ_DHCP_DNS:-"dhcp-option=6,172.17.10.1,8.8.8.8,8.8.4.4"}
DMQ_DHCP_WINS=${DMQ_DHCP_WINS:-"# dhcp-option=44,172.17.10.1"}
DMQ_DHCP_RANGES=${DMQ_DHCP_RANGES:-"dhcp-range=172.17.10.10,172.17.10.100,24h"}
DMQ_DHCP_HOST1=${DMQ_DHCP_HOST1:-"dhcp-host=00:00:00:00:00:00,myhost,172.17.10.2,infinite"}
DMQ_DHCP_HOST2=${DMQ_DHCP_HOST2:-"dhcp-host=myhost2,172.17.10.3,infinite"}

DMQ_DHCP_PXE=${DMQ_PXE:-""}
DMQ_DHCP_TFTP=${DMQ_TFTP:-""}

# generate configuration files from templates
eval "$(cat dnsmasq.conf.tmpl)" > /etc/dnsmasq.conf

if [ "$1" = "--test" ]; then
  echo "/etc/dnsmasq.conf:"
  echo "=================="
  cat /etc/dnsmasq.conf
  echo

  echo "Variables:"
  echo "=========="
  for v in $(set |grep ^DMQ|sed -e 's/^\(DMQ_[^=]*\).*/\1/' |sort -r |tr '\n' ' ' ); do
    [ -z "$v" ] && continue
    value=$(eval echo -n \""\$$v"\")
    echo -e "$v=\"$value\""
  done
  exit 0
fi

# export variables suitable for input for --env-file
if [ "$1" = "--export" ]; then
  # fetch all defined DMQ_ variables
  for v in $(set |grep ^DMQ|sed -e 's/^\(DMQ_[^=]*\).*/\1/' |sort -r |tr '\n' ' '); do
    [ -z "$v" ] && continue
    # get value and replace all newlines with \n (docker only supports single line variables)
    value=$(eval echo -n \""\$$v"\")
    echo "$v=$(echo -n "$value" | awk '{if (NR>1) {printf "%s\\n", $0}} END {print $0}')"
  done
  exit 0
fi

dnsmasq "$@"

