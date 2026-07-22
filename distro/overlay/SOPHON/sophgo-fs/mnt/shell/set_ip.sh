#!/bin/sh
#
# set_ip.sh - configure a network interface (eth0/eth1) using bm_set_ip /
# bm_set_ip_auto, which handle the OS-specific (netplan/nmcli/interfaces.d)
# configuration. Legacy Hisilicon/netboot logic (parsing "ip=" from
# /proc/cmdline, setting the interface's MAC address) has been removed --
# this only handles static/DHCP configuration for eth0/eth1.
#
# Usage: ./set_ip.sh eth0
#        ./set_ip.sh eth1
#
# Reads (or creates, if missing) a flat key=value config file named after
# the interface (relative to cwd -- i.e. /mnt/shell/eth0 or /mnt/shell/eth1
# when invoked from init.sh) with the schema:
#
#   mode=static|dhcp
#   ipaddr=<ip>        (static only)
#   netmask=<netmask>  (static only)
#   gateway=<gw>       (static only, may be empty)
#   dns=<dns>          (static only, may be empty)

if [ $# -ne 1 ]; then
  echo "Usage: $0 <eth0|eth1>"
  exit 1
fi

file="$1"
netdev=$(basename "$file")
if [ "$netdev" != "eth0" ] && [ "$netdev" != "eth1" ]; then
  echo "The filename is not 'eth0' or 'eth1'. Exiting."
  exit 1
fi

if [ ! -r "$file" ]; then
  echo "Error: Cannot read the $file or it does not exist. We will use defaults.."
  mode="static"
  if [ "$netdev" = "eth1" ]; then
    ipaddr="172.168.1.20"
    gateway="172.168.1.254"
  else
    ipaddr="192.168.1.20"
    gateway="192.168.1.254"
  fi
  netmask="255.255.255.0"
  dns="8.8.8.8"

  echo "mode=$mode" > "$file"
  echo "ipaddr=$ipaddr" >> "$file"
  echo "netmask=$netmask" >> "$file"
  echo "gateway=$gateway" >> "$file"
  echo "dns=$dns" >> "$file"
else
  mode=""
  ipaddr=""
  netmask=""
  gateway=""
  dns=""
  # Read the file line by line and extract the required information
  while IFS='=' read -r key value; do
    case "$key" in
      mode)
        mode="$value"
        ;;
      ipaddr)
        ipaddr="$value"
        ;;
      netmask)
        netmask="$value"
        ;;
      gateway)
        gateway="$value"
        ;;
      dns)
        dns="$value"
        ;;
    esac
  done < "$file"
fi

# Display the extracted information
echo "netdev: $netdev"
echo "mode: $mode"
echo "ipaddr: $ipaddr"
echo "netmask: $netmask"
echo "gateway: $gateway"
echo "dns: $dns"

rc=0
if [ "$mode" = "dhcp" ]; then
  bm_set_ip_auto "$netdev"
  rc=$?
else
  if [ -z "$ipaddr" ] || [ -z "$netmask" ]; then
    echo "Error: mode=static requires ipaddr and netmask to be set in $file. Exiting."
    rc=1
  else
    bm_set_ip "$netdev" "$ipaddr" "$netmask" "$gateway" "$dns"
    rc=$?
  fi
fi

if [ $rc -ne 0 ]; then
  echo "Error: failed to configure $netdev (exit code $rc)."
fi

# Interface name to check
interface="lo"

# Check the status of the network interface
status=$(ifconfig "$interface" 2>&1 | grep -o "UP")

# If the interface is not active, enable it
if [ -z "$status" ]; then
  echo "Interface $interface is not active. Enabling it..."
  ifconfig "$interface" 127.0.0.1 up
  echo "Interface $interface has been enabled."
else
  echo "Interface $interface is already active."
fi

exit $rc
