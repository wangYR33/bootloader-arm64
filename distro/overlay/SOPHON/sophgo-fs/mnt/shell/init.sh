#!/bin/bash

#Load drivers for SoC
# ./add_mods.sh

cd /mnt/shell/
./mount.sh
set -- "/mnt/dev" "/mnt/dev1"
for disk in "$@"; do

    pic_path="${disk}/pic"
    record_path="${disk}/record"
    echo "pic_path: ${pic_path}"

    if grep -qs "${disk}" /proc/mounts; then
        if [ ! -d "$pic_path" ]; then
            mkdir -p "$pic_path"
        fi
        if [ ! -d "$record_path" ]; then
            mkdir -p "$record_path"
        fi
    else
        echo "${disk} is not mounted."
    fi
done


# Disable SophonHDMI service if it's enabled, then make sure it's stopped
if systemctl is-enabled --quiet SophonHDMI; then
    systemctl disable SophonHDMI
    systemctl stop SophonHDMI
fi

cd /mnt/shell/
# time sync cost 1s , move to start service
# ./timeSync.sh
#config network move to netplan, it costs 7s

source /mnt/shell/aliases.sh

cd /mnt/app/
 
#Run appmon
# Qt 环境变量
export QTDIR=/mnt/qt515
# 设置平台插件路径
export QT_QPA_PLATFORM_PLUGIN_PATH=$QTDIR/plugins/platforms
# 设置Qt插件路径
export QT_PLUGIN_PATH=$QTDIR/plugins
export QT_QPA_PLATFORM=linuxfb
export PATH="$QTDIR/bin:$PATH"
export LD_LIBRARY_PATH="$QTDIR/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$QTDIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export QT_QPA_FONTDIR=$QTDIR/fonts
QML2_IMPORT_PATH=$QTDIR/qml

exec ./appmon.exe -c ./appmon.conf
