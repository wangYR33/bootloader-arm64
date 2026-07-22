#!/bin/bash
#
# Sync system time from the hardware RTC on boot.
#
# Sophon platform exposes the RTC through the soph_rtc kernel driver
# (loaded by bmrt_loadko.sh) as a standard Linux RTC device, so we use
# hwclock against /dev/rtc0 instead of bit-banging I2C registers.

RTC_DEV=/dev/rtc0

if [ ! -e "$RTC_DEV" ]; then
    echo "timeSync: $RTC_DEV not found (soph_rtc not loaded?), skipping RTC sync" >&2
    exit 1
fi

if ! hwclock -f "$RTC_DEV" -s; then
    echo "timeSync: hwclock failed to set system time from $RTC_DEV" >&2
    exit 1
fi

echo "System time synced from $RTC_DEV: $(date)"
