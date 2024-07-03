#!/bin/sh

if [ -z "$(pgrep dnsmasq)" ]; then
  echo "no 'dnsmasq' process found!"
  exit 1
fi

if [ -z "$(netstat -nltu |grep \:53)" ]; then
  echo "no process listening on port 53!"
  exit 1
fi

if [ -n "$KEEPALIVE_STATE" -a -z "$(pgrep keepalived)" ]; then
  echo "keepalived configured but not running!"
  exit 1
fi
