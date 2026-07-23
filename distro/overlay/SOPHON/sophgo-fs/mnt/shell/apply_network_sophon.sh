#!/bin/sh
#
# Apply the complete Sophon primary/backup network configuration.
# eth1 is the platform default primary interface; eth0 is the default backup.
# This script writes complete eth0/eth1 netplan subtrees. It intentionally does
# not call bm_set_ip: that helper appends fixed-indentation YAML blocks which
# become invalid after netplan has normalized an existing document.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
  echo "apply_network_sophon.sh: cannot resolve script directory" >&2
  exit 1
}
NETWORK_ROOT="$SCRIPT_DIR"
NETPLAN_FILE=${NETPLAN_FILE:-/etc/netplan/01-netcfg.yaml}
NETPLAN_ORIGIN=${NETPLAN_ORIGIN:-$(basename "$NETPLAN_FILE" .yaml)}
NETWORK_CONF="$NETWORK_ROOT/network.conf"
LOCK_FILE=${NETWORK_LOCK_FILE:-/run/lock/nvrcore-network.lock}
LAST_GOOD_FILE=${NETPLAN_LAST_GOOD_FILE:-$NETPLAN_FILE.nvrcore.last-good}
APPLY_NETWORK_API_VERSION=nvrcore-apply-network-sophon/5
SYS_CLASS_NET_ROOT=${SYS_CLASS_NET_ROOT:-/sys/class/net}

temporary_file=
backup_file=
rollback_enabled=0

trim()
{
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

valid_ipv4()
{
  printf '%s\n' "$1" | awk -F. '
    NF != 4 { exit 1 }
    {
      for (i = 1; i <= 4; ++i) {
        if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255)
          exit 1
      }
    }
  '
}

valid_netmask()
{
  valid_ipv4 "$1" || return 1
  printf '%s\n' "$1" | awk -F. '
    BEGIN { partial = 0 }
    {
      for (i = 1; i <= 4; ++i) {
        value = $i + 0
        if (value != 255 && value != 254 && value != 252 &&
            value != 248 && value != 240 && value != 224 &&
            value != 192 && value != 128 && value != 0)
          exit 1
        if (partial && value != 0)
          exit 1
        if (value != 255)
          partial = 1
      }
    }
  '
}

netmask_to_prefix()
{
  printf '%s\n' "$1" | awk -F. '
    {
      prefix = 0
      for (i = 1; i <= 4; ++i) {
        if ($i == 255) prefix += 8
        else if ($i == 254) prefix += 7
        else if ($i == 252) prefix += 6
        else if ($i == 248) prefix += 5
        else if ($i == 240) prefix += 4
        else if ($i == 224) prefix += 3
        else if ($i == 192) prefix += 2
        else if ($i == 128) prefix += 1
      }
      print prefix
    }
  '
}

cleanup()
{
  [ -z "$temporary_file" ] || rm -f "$temporary_file"
  [ -z "$backup_file" ] || rm -f "$backup_file"
}

rollback()
{
  [ "$rollback_enabled" -eq 1 ] || return 0
  echo "apply_network_sophon.sh: restoring previous netplan configuration" >&2
  cp -p "$backup_file" "$NETPLAN_FILE" || return 1
  chmod 600 "$NETPLAN_FILE" || return 1
  netplan generate >/dev/null 2>&1 || return 1
  netplan apply >/dev/null 2>&1 || return 1
  rollback_enabled=0
}

fail()
{
  echo "apply_network_sophon.sh: $*" >&2
  if ! rollback; then
    echo "apply_network_sophon.sh: rollback failed" >&2
  fi
  cleanup
  exit 1
}

on_signal()
{
  fail "interrupted"
}

trap cleanup 0
trap on_signal HUP INT TERM

if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
  echo "$APPLY_NETWORK_API_VERSION"
  exit 0
fi
[ "$#" -eq 0 ] || fail "usage: $0 [--version]"

write_network_default()
{
  temporary_file=$(mktemp "$NETWORK_CONF.tmp.XXXXXX") ||
    fail "cannot create a temporary network.conf"
  {
    echo "default_interface=eth1"
    echo "allowed_default_interfaces=eth0,eth1"
    echo "nameserver1=8.8.8.8"
    echo "nameserver2="
    echo "primary_route_metric=100"
    echo "backup_route_metric=200"
  } > "$temporary_file" || fail "cannot write $temporary_file"
  chmod 600 "$temporary_file" || fail "cannot set permissions on $temporary_file"
  mv -f "$temporary_file" "$NETWORK_CONF" ||
    fail "cannot replace $NETWORK_CONF"
  temporary_file=
}

read_network_config()
{
  if [ ! -r "$NETWORK_CONF" ] || [ ! -s "$NETWORK_CONF" ]; then
    write_network_default
  fi

  default_interface=
  nameserver1=
  nameserver2=
  primary_route_metric=100
  backup_route_metric=200
  while IFS='=' read -r key value || [ -n "$key$value" ]; do
    key=$(trim "$key")
    value=$(trim "$value")
    case "$key" in
      default_interface) default_interface=$value ;;
      nameserver1) nameserver1=$value ;;
      nameserver2) nameserver2=$value ;;
      primary_route_metric) primary_route_metric=$value ;;
      backup_route_metric) backup_route_metric=$value ;;
    esac
  done < "$NETWORK_CONF" || fail "cannot read $NETWORK_CONF"

  case "$default_interface" in
    eth0|eth1) ;;
    *)
      echo "apply_network_sophon.sh: invalid default_interface; using eth1" >&2
      default_interface=eth1
      ;;
  esac

  case "$primary_route_metric:$backup_route_metric" in
    *[!0-9:]*|:*|*:) fail "invalid route metric" ;;
  esac
  [ "$primary_route_metric" -gt 0 ] || fail "primary route metric must be positive"
  [ "$backup_route_metric" -gt "$primary_route_metric" ] ||
    fail "backup route metric must be greater than primary route metric"

  if [ -n "$nameserver1" ]; then
    valid_ipv4 "$nameserver1" || fail "invalid nameserver1: $nameserver1"
  fi
  if [ -n "$nameserver2" ]; then
    valid_ipv4 "$nameserver2" || fail "invalid nameserver2: $nameserver2"
    [ "$nameserver1" != "$nameserver2" ] ||
      fail "nameserver1 and nameserver2 must differ"
  fi

  if [ "$default_interface" = eth1 ]; then
    primary_interface=eth1
    backup_interface=eth0
  else
    primary_interface=eth0
    backup_interface=eth1
  fi
}

read_interface_config()
{
  interface=$1
  file="$NETWORK_ROOT/$interface"
  [ -r "$file" ] && [ -s "$file" ] ||
    fail "missing interface configuration: $file"

  mode=
  ipaddr=
  netmask=
  gateway=
  while IFS='=' read -r key value || [ -n "$key$value" ]; do
    key=$(trim "$key")
    value=$(trim "$value")
    case "$key" in
      mode) mode=$value ;;
      ipaddr) ipaddr=$value ;;
      netmask) netmask=$value ;;
      gateway) gateway=$value ;;
    esac
  done < "$file" || fail "cannot read $file"

  [ -n "$mode" ] || mode=static
  case "$mode" in
    static)
      valid_ipv4 "$ipaddr" || fail "invalid IPv4 address in $file: $ipaddr"
      valid_netmask "$netmask" || fail "invalid netmask in $file: $netmask"
      if [ -n "$gateway" ]; then
        valid_ipv4 "$gateway" || fail "invalid gateway in $file: $gateway"
      fi
      ;;
    dhcp) ;;
    *) fail "unsupported mode in $file: $mode" ;;
  esac
}

netplan_set()
{
  netplan set --origin-hint="$NETPLAN_ORIGIN" "$1" ||
    fail "netplan set failed: $1"
}

dns_addresses()
{
  if [ -n "$nameserver1" ] && [ -n "$nameserver2" ]; then
    printf '[%s, %s]' "$nameserver1" "$nameserver2"
  elif [ -n "$nameserver1" ]; then
    printf '[%s]' "$nameserver1"
  else
    printf '[]'
  fi
}

configure_interface()
{
  interface=$1
  mode=$2
  ipaddr=$3
  netmask=$4
  gateway=$5
  metric=$6
  dns_list=$(dns_addresses)

  if [ "$mode" = dhcp ]; then
    if [ "$dns_list" = "[]" ]; then
      subtree="{dhcp4: true, addresses: [], optional: true, dhcp-identifier: mac, dhcp4-overrides: {route-metric: $metric}}"
    else
      subtree="{dhcp4: true, addresses: [], optional: true, dhcp-identifier: mac, nameservers: {addresses: $dns_list}, dhcp4-overrides: {route-metric: $metric, use-dns: false}}"
    fi
  else
    prefix=$(netmask_to_prefix "$netmask") ||
      fail "cannot convert netmask for $interface"
    if [ -n "$gateway" ]; then
      routes="[{to: default, via: $gateway, metric: $metric}]"
    else
      routes="[]"
    fi
    if [ "$dns_list" = "[]" ]; then
      subtree="{dhcp4: false, addresses: [$ipaddr/$prefix], routes: $routes, optional: true}"
    else
      subtree="{dhcp4: false, addresses: [$ipaddr/$prefix], nameservers: {addresses: $dns_list}, routes: $routes, optional: true}"
    fi
  fi

  # Netplan merges YAML sequences by default. Remove the complete interface
  # node first so old addresses, DNS entries and routes cannot be appended to
  # the new configuration.
  netplan_set "network.ethernets.$interface=null"
  netplan_set "network.ethernets.$interface=$subtree"
}

remove_stale_static_addresses()
{
  interface=$1
  mode=$2
  ipaddr=$3
  netmask=$4

  [ "$mode" = static ] || return 0
  prefix=$(netmask_to_prefix "$netmask") ||
    fail "cannot convert netmask while cleaning $interface"
  desired_address="$ipaddr/$prefix"
  current_addresses=$(ip -o -4 addr show dev "$interface" scope global |
    awk '{print $4}')

  for current_address in $current_addresses; do
    if [ "$current_address" != "$desired_address" ]; then
      echo "Removing stale address $current_address from $interface"
      ip -4 addr del "$current_address" dev "$interface" ||
        fail "cannot remove stale address $current_address from $interface"
    fi
  done
}

verify_static_address()
{
  interface=$1
  mode=$2
  ipaddr=$3
  netmask=$4

  [ "$mode" = static ] || return 0
  carrier_file="$SYS_CLASS_NET_ROOT/$interface/carrier"
  if [ ! -r "$carrier_file" ] || [ "$(cat "$carrier_file")" != 1 ]; then
    echo "Skipping address verification for $interface without carrier"
    return 0
  fi

  prefix=$(netmask_to_prefix "$netmask") ||
    fail "cannot convert netmask while verifying $interface"
  desired_address="$ipaddr/$prefix"
  attempt=0
  while [ "$attempt" -lt 10 ]; do
    current_addresses=$(ip -o -4 addr show dev "$interface" scope global |
      awk '{print $4}')
    if [ "$current_addresses" = "$desired_address" ]; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  fail "$interface address verification failed: expected $desired_address, got ${current_addresses:-none}"
}

command -v flock >/dev/null 2>&1 || fail "flock is not available"
command -v netplan >/dev/null 2>&1 || fail "netplan is not available"
command -v ip >/dev/null 2>&1 || fail "ip is not available"
[ -r "$NETPLAN_FILE" ] || fail "$NETPLAN_FILE is missing or unreadable"
netplan set --help 2>&1 | grep -q -- '--origin-hint' ||
  fail "netplan set does not support --origin-hint"

lock_directory=$(dirname "$LOCK_FILE")
[ -d "$lock_directory" ] || mkdir -p "$lock_directory" ||
  fail "cannot create lock directory: $lock_directory"
exec 9>"$LOCK_FILE" || fail "cannot open lock file: $LOCK_FILE"
flock -x 9 || fail "cannot acquire network lock"

read_network_config

# bm_set_ip cannot safely update a netplan document that is already invalid.
netplan generate ||
  fail "existing netplan configuration is invalid; repair $NETPLAN_FILE first"

read_interface_config eth0
eth0_mode=$mode
eth0_ipaddr=$ipaddr
eth0_netmask=$netmask
eth0_gateway=$gateway
read_interface_config eth1
eth1_mode=$mode
eth1_ipaddr=$ipaddr
eth1_netmask=$netmask
eth1_gateway=$gateway

backup_file=$(mktemp /tmp/nvrcore-netplan-backup.XXXXXX) ||
  fail "cannot create netplan backup"
cp -p "$NETPLAN_FILE" "$backup_file" || fail "cannot back up $NETPLAN_FILE"
rollback_enabled=1

if [ "$primary_interface" = eth1 ]; then
  configure_interface eth0 "$eth0_mode" "$eth0_ipaddr" "$eth0_netmask" "$eth0_gateway" "$backup_route_metric"
  configure_interface eth1 "$eth1_mode" "$eth1_ipaddr" "$eth1_netmask" "$eth1_gateway" "$primary_route_metric"
else
  configure_interface eth1 "$eth1_mode" "$eth1_ipaddr" "$eth1_netmask" "$eth1_gateway" "$backup_route_metric"
  configure_interface eth0 "$eth0_mode" "$eth0_ipaddr" "$eth0_netmask" "$eth0_gateway" "$primary_route_metric"
fi

chmod 600 "$NETPLAN_FILE" || fail "cannot set permissions on $NETPLAN_FILE"
netplan generate || fail "netplan generate failed"

# Addresses previously installed by bm_set_ip/ifconfig are not always owned by
# networkd, so netplan apply may leave them behind. Remove only addresses that
# differ from the desired static CIDR; the matching address stays online.
remove_stale_static_addresses eth0 "$eth0_mode" "$eth0_ipaddr" "$eth0_netmask"
remove_stale_static_addresses eth1 "$eth1_mode" "$eth1_ipaddr" "$eth1_netmask"

netplan apply || fail "netplan apply failed"

verify_static_address eth0 "$eth0_mode" "$eth0_ipaddr" "$eth0_netmask"
verify_static_address eth1 "$eth1_mode" "$eth1_ipaddr" "$eth1_netmask"

rollback_enabled=0
cp -p "$NETPLAN_FILE" "$LAST_GOOD_FILE" ||
  fail "cannot save last-good netplan configuration"
chmod 600 "$LAST_GOOD_FILE" ||
  fail "cannot set permissions on $LAST_GOOD_FILE"

echo "Sophon network applied: primary=$primary_interface metric=$primary_route_metric, backup=$backup_interface metric=$backup_route_metric"
ip -4 addr show eth0 || true
ip -4 addr show eth1 || true
ip -4 route show || true

exit 0
