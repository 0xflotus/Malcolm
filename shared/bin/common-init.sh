#!/bin/bash

# Copyright (c) 2019 Battelle Energy Alliance, LLC.  All rights reserved.

declare -A IFACES

# read all non-virtual interfaces and their speeds into an associative array
function PopulateInterfaces()
{
  IFACE_RESULT=""
  SPEED_MAX=0
  while IFS='' read -r -d ' ' IFACE_NAME && IFS='' read -r -d '' IFACE_LINK; do
    if [[ "${IFACE_LINK}" != *"virtual"* ]]; then
      IFACE_SPEED="$(cat /sys/class/net/$IFACE_NAME/speed 2>/dev/null)"
      if [[ -n $IFACE_SPEED ]]; then
        IFACES[$IFACE_NAME]+=$IFACE_SPEED
      else
        IFACES[$IFACE_NAME]+=0
      fi
    fi
  done < <(find /sys/class/net/ -mindepth 1 -maxdepth 1 -type l -printf '%P %l\0' 2>/dev/null)
}

# the capture interface is the one with the highest "speed"
function DetermineCaptureInterface()
{
  for IFACE_NAME in "${!IFACES[@]}"; do
    echo "$IFACE_NAME" "${IFACES["$IFACE_NAME"]}"
  done | sort -rn -k2 | head -n 1 | cut -d' ' -f1
}

# remove default accounts/groups we don't want, create/set directories for non-user users for stig to not complain
function CleanDefaultAccounts() {
  for systemuser in games gnats irc list lp news uucp www-data
  do
    deluser $systemuser 2>/dev/null || true
  done
  [ ! -d /var/lib/nobody ] && ((mkdir -p /var/lib/nobody && chown nobody:nogroup /var/lib/nobody && chmod 700 /var/lib/nobody && usermod -m -d /var/lib/nobody nobody) || true)
  [ ! -d /var/lib/_apt ] && ((mkdir -p /var/lib/_apt && chown _apt:nogroup /var/lib/_apt && chmod 700 /var/lib/_apt && usermod -m -d /var/lib/_apt _apt) || true)
  [ ! -d /run/systemd/resolve ] && ((mkdir -p /run/systemd/resolve && chown systemd-resolve:systemd-resolve /run/systemd/resolve && chmod 700 /run/systemd/resolve) || true)
  [ ! -d /var/lib/usbmux ] && ((mkdir -p /var/lib/usbmux && chown usbmux:plugdev /var/lib/usbmux && chmod 700 /var/lib/usbmux) || true)
}

# if the network configuration files for the interfaces haven't been set to come up on boot, configure that
function InitializeNetworking() {
  if [[ ! -f /etc/network/interfaces.d/sensor ]]; then
    # /etc/network/interfaces.d/sensor can be further configured by the system admin via configure-interfaces.py.
    echo "" >> /etc/network/interfaces
    echo "# sensor interfaces should be configured in \"/etc/network/interfaces.d/sensor\"" >> /etc/network/interfaces
    for IFACE_NAME in "${!IFACES[@]}"; do
      echo "auto $IFACE_NAME" >> /etc/network/interfaces.d/sensor
      echo "allow-hotplug $IFACE_NAME" >> /etc/network/interfaces.d/sensor
      echo "iface $IFACE_NAME inet manual" >> /etc/network/interfaces.d/sensor
      echo "  pre-up ip link set dev \$IFACE up" >> /etc/network/interfaces.d/sensor
      echo "  post-down ip link set dev \$IFACE down" >> /etc/network/interfaces.d/sensor
      echo "" >> /etc/network/interfaces.d/sensor
    done

    # only wait 1 minute during boot for network interfaces to come up
    sed -i 's/^\(TimeoutStartSec\)=.*/\1=1min/' /etc/systemd/system/network-online.target.wants/networking.service

    systemctl restart networking
  fi
}

# fix some permisions to make sure things belong to the right person
function FixPermissions() {
  if [ -n "$1" ]; then
    USER_TO_FIX="$1"
    [ -d /home/"$USER_TO_FIX" ] && find /home/"$USER_TO_FIX" \( -type d -o -type f \) -exec chmod o-rwx "{}" \;
    [ -d /home/"$USER_TO_FIX" ] && find /home/"$USER_TO_FIX" -type f -name ".*" -exec chmod g-wx "{}" \;
  fi
}

# chromium tries to call home despite my best efforts
function BadGoogle() {
  if ! grep -q google /etc/hosts; then
    echo >> /etc/hosts
    echo '127.0.0.1 _googlecast._tcp.local' >> /etc/hosts
    echo '127.0.0.1 accounts.google.com' >> /etc/hosts
    echo '127.0.0.1 clients.l.google.com' >> /etc/hosts
    echo '127.0.0.1 safebrowsing-cache.google.com' >> /etc/hosts
    echo '127.0.0.1 safebrowsing.clients.google.com' >> /etc/hosts
    echo '127.0.0.1 update.googleapis.com' >> /etc/hosts
    echo '127.0.0.1 www.google-analytics.com' >> /etc/hosts
    echo '127.0.0.1 www.gstatic.com' >> /etc/hosts
  fi
}
