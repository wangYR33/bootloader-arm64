#!/bin/sh

NETWORK_ROOT=${NETWORK_ROOT:-/mnt/shell}
SYS_CLASS_NET_ROOT=${SYS_CLASS_NET_ROOT:-/sys/class/net}
NETWORK_CONF="$NETWORK_ROOT/network.conf"
temporary_file=

fail()
{
    [ -z "$temporary_file" ] || rm -f "$temporary_file"
    echo "network apply failed: $*" >&2
    exit 1
}

trim()
{
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

write_network_default()
{
    temporary_file="$NETWORK_CONF.tmp.$$"
    printf '%s\n' 'default_interface=eth0' > "$temporary_file" ||
        fail "cannot write $temporary_file"
    mv -f "$temporary_file" "$NETWORK_CONF" || fail "cannot replace $NETWORK_CONF"
    temporary_file=
}

read_network_config()
{
    if [ ! -r "$NETWORK_CONF" ] || [ ! -s "$NETWORK_CONF" ]; then
        write_network_default
    fi

    default_interface=
    while IFS='=' read -r key value || [ -n "$key$value" ]; do
        key=$(trim "$key")
        value=$(trim "$value")
        [ "$key" = default_interface ] && default_interface=$value
        :
    done < "$NETWORK_CONF" || fail "cannot read $NETWORK_CONF"

    case "$default_interface" in
        eth0|eth1) ;;
        *)
            write_network_default
            default_interface=eth0
            ;;
    esac
}

write_interface_default()
{
    interface=$1
    file="$NETWORK_ROOT/$interface"
    case "$interface" in
        eth0)
            ipaddr=192.168.1.20
            gateway=192.168.1.254
            ;;
        eth1)
            ipaddr=172.168.1.20
            gateway=172.168.1.254
            ;;
    esac

    temporary_file="$file.tmp.$$"
    {
        echo "ipaddr=$ipaddr"
        echo "gateway=$gateway"
        echo 'netmask=255.255.255.0'
        echo 'hostname=midnvrv2'
        echo "netdev=$interface"
        echo 'autoconf='
        echo 'bootp='
    } > "$temporary_file" || fail "cannot write $temporary_file"
    mv -f "$temporary_file" "$file" || fail "cannot replace $file"
    temporary_file=
}

read_interface_config()
{
    interface=$1
    file="$NETWORK_ROOT/$interface"
    if [ ! -r "$file" ] || [ ! -s "$file" ]; then
        write_interface_default "$interface"
    fi

    ipaddr=
    netmask=
    gateway=
    mac=
    while IFS='=' read -r key value || [ -n "$key$value" ]; do
        key=$(trim "$key")
        value=$(trim "$value")
        case "$key" in
            ipaddr) ipaddr=$value ;;
            netmask) netmask=$value ;;
            gateway) gateway=$value ;;
            mac) mac=$value ;;
        esac
    done < "$file" || fail "cannot read $file"

    [ -n "$ipaddr" ] || fail "$file has no ipaddr"
    [ -n "$netmask" ] || fail "$file has no netmask"
    [ -n "$gateway" ] || fail "$file has no gateway"
}

apply_interface()
{
    interface=$1
    ipaddr=$2
    netmask=$3
    mac=$4

    if [ -n "$mac" ]; then
        address_file="$SYS_CLASS_NET_ROOT/$interface/address"
        [ -r "$address_file" ] || fail "cannot read $address_file"
        current_mac=$(sed -n '1p' "$address_file") ||
            fail "cannot read $address_file"
        current_mac=$(printf '%s' "$current_mac" | tr 'A-F' 'a-f')
        target_mac=$(printf '%s' "$mac" | tr 'A-F' 'a-f')
        if [ "$current_mac" != "$target_mac" ]; then
            ifconfig "$interface" down || fail "cannot stop $interface"
            ifconfig "$interface" hw ether "$mac" || fail "cannot set $interface mac"
            ifconfig "$interface" up || fail "cannot start $interface"
        fi
    fi

    ifconfig "$interface" "$ipaddr" netmask "$netmask" up ||
        fail "cannot configure $interface"
}

read_network_config

read_interface_config eth0
eth0_ipaddr=$ipaddr
eth0_netmask=$netmask
eth0_gateway=$gateway
eth0_mac=$mac

read_interface_config eth1
eth1_ipaddr=$ipaddr
eth1_netmask=$netmask
eth1_gateway=$gateway
eth1_mac=$mac

ifconfig lo 127.0.0.1 up || fail 'cannot configure lo'
apply_interface eth0 "$eth0_ipaddr" "$eth0_netmask" "$eth0_mac"
apply_interface eth1 "$eth1_ipaddr" "$eth1_netmask" "$eth1_mac"

while ip route del default >/dev/null 2>&1; do
    :
done

case "$default_interface" in
    eth0) default_gateway=$eth0_gateway ;;
    eth1) default_gateway=$eth1_gateway ;;
esac
ip route add default via "$default_gateway" dev "$default_interface" ||
    fail 'cannot add default route'
