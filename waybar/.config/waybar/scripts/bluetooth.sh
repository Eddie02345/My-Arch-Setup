#!/bin/bash

# Cache file for last status
CACHE_FILE="/tmp/bluetooth_status.cache"

# Check Bluetooth power status
power_status=$(bluetoothctl show | grep "Powered" | awk '{print $2}')
icon="󰂲"  # Default icon: off
status="off"

# If powered on, check connection status
if [[ "$power_status" == "yes" ]]; then
    connected=$(bluetoothctl info | grep "Connected: yes")
    if [[ -n "$connected" ]]; then
        icon="󰂱"  # Connected
        status="connected"
    else
        icon="󰂯"  # On but not connected
        status="on"
    fi
fi

# Update cache (optional, for future optimization)
echo "$status" > "$CACHE_FILE"

# Always output the icon (so Waybar shows the module)
echo "$icon"

