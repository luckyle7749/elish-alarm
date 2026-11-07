#!/bin/sh
# Wait for iio-sensor-proxy to finish SSC enumeration (HasAccelerometer=true).
# If it wasn't ready when this unit started — meaning plasmashell built the
# quicksettings model too early and dropped the auto-rotate toggle — restart
# plasmashell once so the model is rebuilt with the sensor present.
needed_wait=0
i=0
while [ "$i" -lt 90 ]; do
    if gdbus call --system -d net.hadess.SensorProxy -o /net/hadess/SensorProxy \
        -m org.freedesktop.DBus.Properties.Get net.hadess.SensorProxy \
        HasAccelerometer 2>/dev/null | grep -q true; then
        break
    fi
    needed_wait=1
    i=$((i + 1))
    sleep 1
done
[ "$needed_wait" = 1 ] || exit 0
sleep 2
systemctl --user restart plasma-plasmashell.service
